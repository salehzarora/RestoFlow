import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'admin/real_admin_views.dart';
import 'dashboard_home_screen.dart';
import 'printers/printers_repository.dart';
import 'printers/printers_screen.dart';
import 'setup/setup_center.dart';
import 'staff/staff_repository.dart';
import 'staff/staff_screen.dart';
import 'state/dashboard_providers.dart';

/// Derives the menu scope for the dashboard from the active RF-108 membership.
///
///  * Demo mode (`membership == null`) uses the demo scope.
///  * An auth-mode membership uses its EXACT org/restaurant/branch and the
///    resolved real [currencyCode] (falling back to the demo currency only
///    when no real currency was resolvable) — never the demo scope.
///  * An org-wide membership with no restaurant returns `null`: menu management
///    is restaurant-scoped, so the surface shows a blocked state instead of
///    silently falling back to the demo scope.
MenuScope? dashboardMenuScopeFor(
  MembershipContext? membership, {
  String? currencyCode,
}) {
  if (membership == null) return demoMenuScope;
  return MenuScope.fromMembership(
    membership,
    currencyCode: currencyCode ?? demoCurrencyCode,
  );
}

/// Derives the administration scope (RF-113) from the active membership. Unlike
/// the menu, the admin surfaces (settings/users/devices) work at ANY scope — an
/// org-wide membership is fine — so there is no blocked state.
AdminScope dashboardAdminScopeFor(
  MembershipContext? membership, {
  String? currencyCode,
}) {
  if (membership == null) return AdminScope.demo;
  return AdminScope.fromMembership(
    membership,
    currencyCode: currencyCode ?? demoCurrencyCode,
  );
}

/// The owner/manager dashboard shell: a branded navigation
/// (Overview · Menu · Devices · Printers · Staff · Users · Settings) with a
/// persistent context bar (active restaurant/branch + an honest Demo/Real mode
/// pill + sign-out).
///
/// REAL vs DEMO per surface: Devices (RF-160), Printers, and Staff use REAL
/// repositories when injected (authenticated real mode); every demo-backed
/// surface keeps its clear demo banner. The real-mode Overview opens with the
/// setup center (live device/printer/staff-PIN readiness from the same real
/// repositories).
class DashboardShell extends StatefulWidget {
  const DashboardShell({
    this.membership,
    this.currencyCode,
    this.deviceRepositoryFor,
    this.menuReadSource,
    this.menuWriter,
    this.printersRepository,
    this.staffRepository,
    this.reportsTransport,
    this.onSignOut,
    super.key,
  });

  /// The RF-108 active membership (null in demo mode).
  final MembershipContext? membership;

  /// The resolved REAL currency for money-bearing surfaces (menu item
  /// creation). Null in demo mode / when the structure read failed — the demo
  /// currency is used only for demo scopes, never silently for real writes.
  final String? currencyCode;

  /// Builds the REAL device repository for the active admin scope (RF-160).
  /// Null in demo mode / widget tests -> the Devices tab uses the demo store.
  final AdminRepository Function(AdminScope scope)? deviceRepositoryFor;

  /// The REAL menu read (`public.list_menu`) — with [menuWriter], the Menu tab
  /// manages the real backend menu; null => the labelled demo store.
  final MenuReadSource? menuReadSource;

  /// The REAL menu writer (`public.menu_upsert_*` / `menu_soft_delete`).
  final MenuWriter? menuWriter;

  /// The REAL printers repository (null => labelled demo store).
  final PrintersRepository? printersRepository;

  /// The REAL staff repository (null => labelled demo store).
  final StaffRepository? staffRepository;

  /// The authenticated dashboard transport for the Overview's real
  /// sales-summary read (sprint). Null in demo mode / tests => the report
  /// seam fails closed to its existing states.
  final SyncRpcTransport? reportsTransport;

  /// Signs the current user out (real mode). Null => no sign-out affordance
  /// (demo mode / legacy tests).
  final Future<void> Function()? onSignOut;

  static const double _wideBreakpoint = 900;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _index = 0;

  /// The active menu scope (null when the membership is org-wide / restaurant-less).
  late final MenuScope? _menuScope = dashboardMenuScopeFor(
    widget.membership,
    currencyCode: widget.currencyCode,
  );

  /// The demo menu store, seeded at the active scope (null when there is no
  /// scope). Used ONLY when no real menu seams are injected.
  late final InMemoryMenuStore? _menuStore = _menuScope == null
      ? null
      : buildDemoMenuStore(scope: _menuScope);

  /// The active administration scope + its demo store (shared by the demo admin
  /// surfaces, so edits persist across tab switches within a session).
  late final AdminScope _adminScope = dashboardAdminScopeFor(
    widget.membership,
    currencyCode: widget.currencyCode,
  );
  late final DemoAdminStore _adminStore = DemoAdminStore(scope: _adminScope);

  /// The real device repository for the active scope (RF-160), built once. Null in
  /// demo mode / tests -> the Devices tab falls back to the demo store.
  late final AdminRepository? _realDeviceRepo = widget.deviceRepositoryFor
      ?.call(_adminScope);

  /// Printers/Staff: real repository when injected, else the labelled demo store.
  late final PrintersRepository _printersRepo =
      widget.printersRepository ?? InMemoryPrintersStore();
  late final StaffRepository _staffRepo =
      widget.staffRepository ?? InMemoryStaffStore();

  bool get _printersDemo => widget.printersRepository == null;
  bool get _staffDemo => widget.staffRepository == null;

  void _select(int value) => setState(() => _index = value);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // KeyedSubtree: each tab gets a FRESH subtree, so the per-surface
    // ProviderScopes are recreated instead of reused with different override
    // types across tabs (Riverpod forbids changing an override's type in
    // place).
    final content = KeyedSubtree(
      key: ValueKey('dashboard-tab-$_index'),
      child: switch (_index) {
        0 => _overview(),
        1 => _menuSurface(context, l10n),
        2 => _adminSurface(
          const AdminDevicesScreen(),
          // Real device management in authenticated mode; demo store otherwise.
          repository: _realDeviceRepo ?? _adminStore,
          demo: _realDeviceRepo == null,
        ),
        3 => _demoBannerSurface(
          PrintersScreen(repository: _printersRepo),
          demo: _printersDemo,
        ),
        4 => _demoBannerSurface(
          StaffScreen(repository: _staffRepo),
          demo: _staffDemo,
        ),
        // Users/Settings (sprint): REAL mode never renders the demo store's
        // fabricated people/values — it shows the honest not-connected state
        // and the real workspace values instead. Demo mode keeps the labelled
        // demo surfaces.
        5 =>
          widget.membership == null
              ? _adminSurface(
                  const AdminUsersScreen(),
                  repository: _adminStore,
                  demo: true,
                )
              : const RealUsersUnavailableView(),
        _ =>
          widget.membership == null
              ? _adminSurface(
                  const AdminSettingsScreen(),
                  repository: _adminStore,
                  demo: true,
                )
              : RealSettingsView(
                  membership: widget.membership!,
                  currencyCode: widget.currencyCode,
                ),
      },
    );

    return Scaffold(
      body: Column(
        children: [
          _ShellHeaderBar(
            membership: widget.membership,
            onSignOut: widget.onSignOut,
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide =
                    constraints.maxWidth >= DashboardShell._wideBreakpoint;
                if (isWide) {
                  return Row(
                    children: [
                      _SideNav(selectedIndex: _index, onSelected: _select),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: content),
                    NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: _select,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.onlyShowSelected,
                      destinations: _destinations(l10n)
                          .map(
                            (d) => NavigationDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: d.label,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Overview: in real mode, the setup center (live readiness from the SAME real
  /// repositories the tabs use) above the reports screen — which reads the REAL
  /// `sales_summary` through the scoped membership + authenticated transport.
  Widget _overview() {
    final devices = _realDeviceRepo;
    final showSetup =
        devices != null &&
        widget.printersRepository != null &&
        widget.staffRepository != null;
    // Scope the report seam to the active membership + the session-carrying
    // transport (real mode). Demo mode keeps the defaults (demo repository).
    final report = ProviderScope(
      overrides: [
        dashboardMembershipProvider.overrideWithValue(widget.membership),
        dashboardAuthTransportProvider.overrideWithValue(
          widget.reportsTransport,
        ),
      ],
      child: const DashboardHomeScreen(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSetup)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RestoflowSpacing.lg,
              RestoflowSpacing.md,
              RestoflowSpacing.lg,
              0,
            ),
            child: DashboardSetupCenter(
              devicesRepository: devices,
              printersRepository: _printersRepo,
              staffRepository: _staffRepo,
              onOpenDevices: () => _select(2),
              onOpenPrinters: () => _select(3),
              onOpenStaff: () => _select(4),
            ),
          ),
        Expanded(child: report),
      ],
    );
  }

  /// Wraps an RF-113 admin screen with the feature [ProviderScope] overrides
  /// (scope + [repository]) and — only when [demo] — the demo banner.
  Widget _adminSurface(
    Widget screen, {
    required AdminRepository repository,
    required bool demo,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (demo)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              RestoflowSpacing.lg,
              RestoflowSpacing.md,
              RestoflowSpacing.lg,
              0,
            ),
            child: AdminDemoBanner(),
          ),
        Expanded(
          child: ProviderScope(
            overrides: adminFeatureOverrides(
              scope: _adminScope,
              repository: repository,
            ),
            child: screen,
          ),
        ),
      ],
    );
  }

  /// Wraps a dashboard-local surface (Printers/Staff) with the demo banner when
  /// it is backed by the in-memory store.
  Widget _demoBannerSurface(Widget screen, {required bool demo}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (demo)
        const Padding(
          padding: EdgeInsets.fromLTRB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            0,
          ),
          child: AdminDemoBanner(),
        ),
      Expanded(child: screen),
    ],
  );

  Widget _menuSurface(BuildContext context, AppLocalizations l10n) {
    final scope = _menuScope;
    final store = _menuStore;
    // REAL menu management (sprint): both real seams injected + a concrete
    // scope => `list_menu` + `menu_upsert_*` against the backend, no demo
    // banner. Otherwise: the labelled demo store (demo mode / tests), or the
    // blocked state when no restaurant scope could be resolved.
    final readSource = widget.menuReadSource;
    final writer = widget.menuWriter;
    final real = readSource != null && writer != null && scope != null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: RestoflowSpacing.lg,
        title: Text(l10n.menuManagementTitle),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (real)
            Expanded(
              child: ProviderScope(
                overrides: menuFeatureOverrides(
                  scope: scope,
                  readSource: readSource,
                  writer: writer,
                ),
                child: const MenuManagementScreen(),
              ),
            )
          else if (scope == null || store == null)
            const Expanded(child: _MenuUnavailable())
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RestoflowSpacing.lg,
                RestoflowSpacing.md,
                RestoflowSpacing.lg,
                0,
              ),
              child: _MenuDemoBanner(message: l10n.menuDemoBanner),
            ),
            Expanded(
              child: ProviderScope(
                overrides: menuFeatureOverrides(
                  scope: scope,
                  readSource: store,
                  writer: store,
                ),
                child: const MenuManagementScreen(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_NavItem> _destinations(AppLocalizations l10n) => [
    _NavItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: l10n.dashboardNavOverview,
    ),
    _NavItem(
      icon: Icons.restaurant_menu_outlined,
      selectedIcon: Icons.restaurant_menu,
      label: l10n.dashboardNavMenu,
    ),
    _NavItem(
      icon: Icons.devices_outlined,
      selectedIcon: Icons.devices,
      label: l10n.dashboardNavDevices,
    ),
    _NavItem(
      icon: Icons.print_outlined,
      selectedIcon: Icons.print,
      label: l10n.dashboardNavPrinters,
    ),
    _NavItem(
      icon: Icons.badge_outlined,
      selectedIcon: Icons.badge,
      label: l10n.dashboardNavStaff,
    ),
    _NavItem(
      icon: Icons.group_outlined,
      selectedIcon: Icons.group,
      label: l10n.dashboardNavUsers,
    ),
    _NavItem(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      label: l10n.dashboardNavSettings,
    ),
  ];
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The persistent shell header: the active scope (organization · branch), an
/// honest Demo/Real mode pill, and sign-out (real mode).
class _ShellHeaderBar extends StatelessWidget {
  const _ShellHeaderBar({required this.membership, required this.onSignOut});

  final MembershipContext? membership;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final m = membership;
    final isReal = m != null;
    final contextLabel = m == null
        ? l10n.dashboardAppTitle
        : '${m.organizationName} · ${m.branchName ?? m.restaurantName ?? m.organizationName}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.lg,
        vertical: RestoflowSpacing.sm,
      ),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              contextLabel,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          RestoflowStatusPill(
            label: isReal ? l10n.dashboardModeReal : l10n.dashboardModeDemo,
            tone: isReal ? RestoflowTone.success : RestoflowTone.info,
            icon: isReal ? Icons.cloud_done_outlined : Icons.science_outlined,
          ),
          if (onSignOut != null) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            IconButton(
              tooltip: l10n.authSignOut,
              onPressed: () => onSignOut!(),
              icon: const Icon(Icons.logout, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

/// The blocked state shown when the active membership is org-wide and has no
/// restaurant scope (menu management is restaurant-scoped).
class _MenuUnavailable extends StatelessWidget {
  const _MenuUnavailable();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.store_mall_directory_outlined,
                size: 30,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.lg),
            Text(
              l10n.menuScopeUnavailableTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                l10n.menuScopeUnavailableBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The branded wide-screen side navigation.
class _SideNav extends StatelessWidget {
  const _SideNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return NavigationRail(
      backgroundColor: scheme.surfaceContainer,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.9,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.lg),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: scheme.primary,
          child: Icon(Icons.restaurant, color: scheme.onPrimary),
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.dashboard_outlined),
          selectedIcon: const Icon(Icons.dashboard),
          label: Text(l10n.dashboardNavOverview),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.restaurant_menu_outlined),
          selectedIcon: const Icon(Icons.restaurant_menu),
          label: Text(l10n.dashboardNavMenu),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.devices_outlined),
          selectedIcon: const Icon(Icons.devices),
          label: Text(l10n.dashboardNavDevices),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.print_outlined),
          selectedIcon: const Icon(Icons.print),
          label: Text(l10n.dashboardNavPrinters),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.badge_outlined),
          selectedIcon: const Icon(Icons.badge),
          label: Text(l10n.dashboardNavStaff),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.group_outlined),
          selectedIcon: const Icon(Icons.group),
          label: Text(l10n.dashboardNavUsers),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.tune_outlined),
          selectedIcon: const Icon(Icons.tune),
          label: Text(l10n.dashboardNavSettings),
        ),
      ],
    );
  }
}

/// A professional demo banner: an accent bar, an icon, and the message.
class _MenuDemoBanner extends StatelessWidget {
  const _MenuDemoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: BorderDirectional(
          start: BorderSide(color: scheme.tertiary, width: 4),
        ),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.science_outlined,
            size: 20,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
