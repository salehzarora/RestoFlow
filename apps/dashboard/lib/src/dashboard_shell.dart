import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'admin/branch_shift_close_policy_repository.dart';
import 'admin/real_admin_views.dart';
import 'admin/supabase_settings_repository.dart';
import 'dashboard_home_screen.dart';
import 'printers/printers_repository.dart';
import 'printers/printers_screen.dart';
import 'setup/setup_center.dart';
import 'staff/staff_repository.dart';
import 'staff/staff_screen.dart';
import 'state/dashboard_providers.dart';
import 'widgets/language_selector.dart';
import 'tables/tables_repository.dart';
import 'tables/tables_screen.dart';

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
/// (Overview · Menu · Devices · Printers · Staff · Tables · Users · Settings)
/// with a persistent context bar (active restaurant/branch + an honest
/// Demo/Real mode pill + sign-out).
///
/// REAL vs DEMO per surface: Devices (RF-160), Printers, Staff, and Tables use
/// REAL repositories when injected (authenticated real mode); every demo-backed
/// surface keeps its clear demo banner. The real-mode Overview opens with the
/// setup center (live device/printer/staff-PIN readiness from the same real
/// repositories).
class DashboardShell extends StatefulWidget {
  const DashboardShell({
    this.membership,
    this.currencyCode,
    this.deviceRepositoryFor,
    this.usersRepositoryFor,
    this.menuReadSource,
    this.menuWriter,
    this.menuImageStorage,
    this.printersRepository,
    this.staffRepository,
    this.tablesRepository,
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

  /// Builds the REAL users repository for the active admin scope (RF-116).
  /// Null in demo mode / widget tests -> the Users tab keeps the demo store
  /// (demo) or the honest not-connected state (real mode without it).
  final AdminRepository Function(AdminScope scope)? usersRepositoryFor;

  /// The REAL menu read (`public.list_menu`) — with [menuWriter], the Menu tab
  /// manages the real backend menu; null => the labelled demo store.
  final MenuReadSource? menuReadSource;

  /// The REAL menu writer (`public.menu_upsert_*` / `menu_soft_delete`).
  final MenuWriter? menuWriter;

  /// The REAL item image storage (menu/media sprint — the RF-110 bucket over
  /// the authenticated client). Null in demo mode / tests: the demo surface
  /// gets a labelled in-memory fake; a real surface without it shows the image
  /// panel's honest "not connected" state.
  final MenuImageStorage? menuImageStorage;

  /// The REAL printers repository (null => labelled demo store).
  final PrintersRepository? printersRepository;

  /// The REAL staff repository (null => labelled demo store).
  final StaffRepository? staffRepository;

  /// The REAL tables repository (null => labelled demo store).
  final TablesAdminRepository? tablesRepository;

  /// The authenticated dashboard transport for the Overview's real
  /// sales-summary read (sprint). Null in demo mode / tests => the report
  /// seam fails closed to its existing states.
  final SyncRpcTransport? reportsTransport;

  /// Signs the current user out (real mode). Null => no sign-out affordance
  /// (demo mode / legacy tests).
  final Future<void> Function()? onSignOut;

  static const double _wideBreakpoint = RestoflowBreakpoints.wide;

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

  /// The demo image storage (menu/media sprint): picking + preview work, the
  /// upload is recorded in memory only, and the panel says so ("demo — not
  /// uploaded to a server"). One instance so it survives tab switches.
  late final FakeMenuImageStorage _demoMenuImageStorage =
      FakeMenuImageStorage();

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

  /// The real users repository for the active scope (RF-116), built once. Null in
  /// demo mode / tests -> the Users tab keeps the demo store (demo) or the honest
  /// not-connected state (real mode without it).
  late final AdminRepository? _realUsersRepo = widget.usersRepositoryFor?.call(
    _adminScope,
  );

  /// RF-113: the real per-branch shift-close policy read/write seam for the
  /// Settings tab, built once. Null unless there is an authenticated transport
  /// AND a concrete restaurant+branch in scope -> the toggle is then omitted.
  late final BranchShiftClosePolicyRepository? _shiftClosePolicyRepo =
      _buildShiftClosePolicyRepo();

  BranchShiftClosePolicyRepository? _buildShiftClosePolicyRepo() {
    final transport = widget.reportsTransport;
    final membership = widget.membership;
    final restaurantId = membership?.restaurantId;
    final branchId = membership?.branchId;
    if (transport == null ||
        membership == null ||
        restaurantId == null ||
        branchId == null) {
      return null;
    }
    return SupabaseBranchShiftClosePolicyRepository(
      transport: transport,
      organizationId: membership.organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  }

  /// RF-116: the settings read/write seam for the owner-only editable
  /// branch/restaurant fields, built once. Null unless there is an authenticated
  /// transport AND a concrete restaurant+branch in scope -> the editable section
  /// is then omitted (the honest read-only workspace view remains).
  late final SettingsRepository? _settingsRepo = _buildSettingsRepo();

  SettingsRepository? _buildSettingsRepo() {
    final transport = widget.reportsTransport;
    final membership = widget.membership;
    final restaurantId = membership?.restaurantId;
    final branchId = membership?.branchId;
    if (transport == null ||
        membership == null ||
        restaurantId == null ||
        branchId == null) {
      return null;
    }
    return SupabaseSettingsRepository(
      transport: transport,
      organizationId: membership.organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  }

  /// Printers/Staff/Tables: real repository when injected, else the labelled
  /// demo store.
  late final PrintersRepository _printersRepo =
      widget.printersRepository ?? InMemoryPrintersStore();
  late final StaffRepository _staffRepo =
      widget.staffRepository ?? InMemoryStaffStore();
  late final TablesAdminRepository _tablesRepo =
      widget.tablesRepository ?? InMemoryTablesStore();

  bool get _printersDemo => widget.printersRepository == null;
  bool get _staffDemo => widget.staffRepository == null;
  bool get _tablesDemo => widget.tablesRepository == null;

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
        5 => _demoBannerSurface(
          TablesScreen(repository: _tablesRepo),
          demo: _tablesDemo,
        ),
        // Users/Settings: REAL mode never renders the demo store's fabricated
        // people/values. When the real users repository is wired (RF-116), the
        // Users tab manages real memberships (list + change-role + revoke); a
        // real membership WITHOUT it falls back to the honest not-connected
        // state. Demo mode keeps the labelled demo surface.
        6 => _usersSurface(),
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
                  policyRepository: _shiftClosePolicyRepo,
                  settingsRepository: _settingsRepo,
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
                      _SideNav(
                        destinations: _destinations(l10n),
                        selectedIndex: _index,
                        onSelected: _select,
                      ),
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
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.lg,
              RestoflowSpacing.md,
              RestoflowSpacing.lg,
              0,
            ),
            child: DashboardSetupCenter(
              devicesRepository: devices,
              printersRepository: _printersRepo,
              staffRepository: _staffRepo,
              // The guided checklist counts the REAL menu when its seams are
              // wired (sprint); a null scope/read source just omits the card.
              menuReadSource: widget.menuReadSource,
              menuScope: _menuScope,
              onOpenMenu: () => _select(1),
              onOpenDevices: () => _select(2),
              onOpenPrinters: () => _select(3),
              onOpenStaff: () => _select(4),
            ),
          ),
        Expanded(child: report),
      ],
    );
  }

  /// The Users tab (RF-116). Demo mode: the labelled demo store. Real mode with
  /// the injected users repository: the SAME [AdminUsersScreen] over `list_members`
  /// / `update_role` / `revoke_membership` (a denied/failed list shows an honest
  /// state, never fabricated members). Real mode without it: the honest
  /// not-connected view.
  Widget _usersSurface() {
    if (widget.membership == null) {
      return _adminSurface(
        const AdminUsersScreen(),
        repository: _adminStore,
        demo: true,
      );
    }
    final real = _realUsersRepo;
    if (real == null) return const RealUsersUnavailableView();
    return _adminSurface(
      const AdminUsersScreen(),
      repository: real,
      demo: false,
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
            padding: EdgeInsetsDirectional.fromSTEB(
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
          padding: EdgeInsetsDirectional.fromSTEB(
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
    //
    // MenuManagementScreen renders its own page header (menuManagementTitle),
    // so this wrapper adds NO title of its own — exactly one title on the tab.
    final readSource = widget.menuReadSource;
    final writer = widget.menuWriter;
    final real = readSource != null && writer != null && scope != null;
    if (real) {
      final imageStorage = widget.menuImageStorage;
      return ProviderScope(
        overrides: menuFeatureOverrides(
          scope: scope,
          readSource: readSource,
          writer: writer,
          // Real image storage when wired; omitted => the image panel shows
          // its honest "not connected" state (never a fake uploader).
          imageStorage: imageStorage == null
              ? null
              : MenuImageStorageConfig(storage: imageStorage),
        ),
        child: const MenuManagementScreen(),
      );
    }
    if (scope == null || store == null) return const _MenuUnavailable();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            0,
          ),
          child: RestoflowNoticeBanner(
            icon: Icons.science_outlined,
            body: l10n.menuDemoBanner,
          ),
        ),
        Expanded(
          child: ProviderScope(
            overrides: menuFeatureOverrides(
              scope: scope,
              readSource: store,
              writer: store,
              // Demo: picking/preview work; the panel labels itself honestly
              // ("demo — not uploaded to a server").
              imageStorage: MenuImageStorageConfig(
                storage: _demoMenuImageStorage,
                isDemo: true,
              ),
            ),
            child: const MenuManagementScreen(),
          ),
        ),
      ],
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
      icon: Icons.table_restaurant_outlined,
      selectedIcon: Icons.table_restaurant,
      label: l10n.dashboardNavTables,
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
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: RestoflowSpacing.lg,
        vertical: RestoflowSpacing.sm,
      ),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            ),
            child: Icon(
              Icons.storefront_outlined,
              size: RestoflowIconSizes.sm,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              contextLabel,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          RestoflowStatusPill(
            // DESIGN-002: user-facing data-source wording (was the developer
            // "Demo" / "Real" jargon).
            label: isReal
                ? l10n.dashboardModeLiveData
                : l10n.dashboardModeDemoData,
            tone: isReal ? RestoflowTone.success : RestoflowTone.info,
            icon: isReal ? Icons.cloud_done_outlined : Icons.science_outlined,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          // Sprint (I): the language switcher lives on the persistent header,
          // so it is visible on EVERY dashboard page.
          const LanguageSelector(),
          if (onSignOut != null) ...[
            const SizedBox(width: RestoflowSpacing.xs),
            IconButton(
              tooltip: l10n.authSignOut,
              onPressed: () => onSignOut!(),
              // Icons.logout is NOT auto-mirrored by Flutter; flip it under
              // RTL so the exit arrow points out of the app chrome.
              icon: Transform.flip(
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: const Icon(Icons.logout, size: RestoflowIconSizes.md),
              ),
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
    return RestoflowStateView(
      icon: Icons.store_mall_directory_outlined,
      title: l10n.menuScopeUnavailableTitle,
      message: l10n.menuScopeUnavailableBody,
    );
  }
}

/// The premium dark side panel (wide layout): a brand lockup on top and one
/// tappable labelled row per destination. Colours come from the dark-sidebar
/// palette in [RestoflowSemanticColors]; the active item gets a rounded brand
/// fill, inactive items stay muted. RTL-safe (Rows + directional padding).
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_NavItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _width = 240;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic =
        theme.extension<RestoflowSemanticColors>() ??
        RestoflowSemanticColors.of(theme.brightness);
    return Material(
      color: semantic.sidebarSurface,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                RestoflowSpacing.lg,
                RestoflowSpacing.xl,
                RestoflowSpacing.lg,
                RestoflowSpacing.xl,
              ),
              child: Row(
                children: [
                  const RestoflowBrandMark(size: 40),
                  const SizedBox(width: RestoflowSpacing.md),
                  Expanded(
                    child: Text(
                      l10n.dashboardAppTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: semantic.sidebarOnSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  RestoflowSpacing.sm,
                  0,
                  RestoflowSpacing.sm,
                  RestoflowSpacing.lg,
                ),
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _SideNavTile(
                      item: destinations[i],
                      selected: i == selectedIndex,
                      semantic: semantic,
                      onTap: () => onSelected(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One sidebar destination: icon + a visible, tappable label Text.
class _SideNavTile extends StatelessWidget {
  const _SideNavTile({
    required this.item,
    required this.selected,
    required this.semantic,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final RestoflowSemanticColors semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? semantic.sidebarActiveForeground
        : semantic.sidebarMuted;
    final radius = BorderRadius.circular(RestoflowRadii.md);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.xs),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          // Subtle interaction polish: the active fill fades in/out (finite
          // implicit animation — settles under pumpAndSettle).
          child: AnimatedContainer(
            duration: RestoflowDurations.fast,
            decoration: BoxDecoration(
              color: selected
                  ? semantic.sidebarActiveBackground
                  : Colors.transparent,
              borderRadius: radius,
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.md,
              RestoflowSpacing.md,
              RestoflowSpacing.md,
              RestoflowSpacing.md,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: RestoflowIconSizes.md,
                  color: foreground,
                ),
                const SizedBox(width: RestoflowSpacing.md),
                Expanded(
                  child: Text(
                    item.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
