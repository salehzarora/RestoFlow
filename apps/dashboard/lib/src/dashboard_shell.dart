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
import 'devices/device_pairing_panel.dart';
import 'activity/activity_log_screen.dart';
import 'orders/orders_screen.dart';
import 'printers/printers_repository.dart';
import 'printers/printers_screen.dart';
import 'setup/device_summary_card.dart';
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

  /// Dashboard "1c" responsive breakpoints (§9). Below [_railBreakpoint] the
  /// shell shows a phone bottom nav; from there the side rail stays on the
  /// reading-start side, icon-only in [_railBreakpoint.._fullRailBreakpoint) and
  /// full-labelled above, widening at [_desktopBreakpoint].
  static const double _railBreakpoint = 560;
  static const double _fullRailBreakpoint = 720;
  static const double _desktopBreakpoint = 1100;

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
        7 => _ordersSurface(),
        8 => _activityLogSurface(),
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

    // Dashboard V2: the persistent header bar lives INSIDE the content column
    // so the side rail runs the full viewport height (reference composition).
    // Everything on the bar (context, mode pill, language, sign-out) is
    // unchanged and stays visible on every tab at every width.
    final header = _ShellHeaderBar(
      membership: widget.membership,
      onSignOut: widget.onSignOut,
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Dashboard "1c" responsive rules (§9): the labelled/icon rail
          // stays on the reading-start side (right in RTL) for every
          // tablet+desktop width; the bottom nav is for phones (<560) ONLY.
          final width = constraints.maxWidth;
          if (width >= DashboardShell._railBreakpoint) {
            final compact = width < DashboardShell._fullRailBreakpoint;
            final railWidth = width >= DashboardShell._desktopBreakpoint
                ? 232.0
                : (compact ? 72.0 : 212.0);
            return Row(
              children: [
                _SideNav(
                  destinations: _destinations(l10n),
                  selectedIndex: _index,
                  onSelected: _select,
                  membership: widget.membership,
                  width: railWidth,
                  compact: compact,
                ),
                Expanded(
                  child: Column(
                    children: [
                      header,
                      const Divider(height: 1),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              header,
              const Divider(height: 1),
              Expanded(child: content),
              NavigationBar(
                key: const Key('dashboard-bottom-nav'),
                selectedIndex: _index,
                onDestinationSelected: _select,
                // RF-132 (Codex review): ten destinations at phone width
                // leave no room to render any label unclipped, so the bar
                // is deliberately ICON-ONLY. NavigationBar keeps each
                // destination's label + selected state in its semantics
                // ("<label>, Tab N of 10") even with the label hidden,
                // and the tooltip covers hover/long-press; selection
                // stays visible via the filled icon + indicator pill.
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                destinations: _destinations(l10n)
                    .map(
                      (d) => NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                        tooltip: d.label,
                      ),
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Overview: in real mode, the setup center (live readiness from the SAME real
  /// repositories the tabs use) sits high in the reports screen — which reads the
  /// REAL `sales_summary` through the scoped membership + authenticated transport.
  ///
  /// RF-127: the setup center is passed into [DashboardHomeScreen] via its
  /// presentation-only `setupPanel` slot (so it renders right after the calm page
  /// chrome), instead of a wrapping Column. Repository ownership, the menu params,
  /// the `_select` navigation callbacks, and the report ProviderScope overrides
  /// are all unchanged.
  Widget _overview() {
    final devices = _realDeviceRepo;
    // The direct null-check promotes `devices` to non-null inside the branch.
    final Widget? setupPanel;
    if (devices != null &&
        widget.printersRepository != null &&
        widget.staffRepository != null) {
      setupPanel = DashboardSetupCenter(
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
      );
    } else {
      setupPanel = null;
    }
    // Dashboard V2: the honest device readiness card for the operational row
    // — real devices repository only (same source as the Devices tab), with
    // the existing tab-navigation callback. Demo mode / tests: no card.
    final Widget? deviceSummary = devices == null
        ? null
        : DashboardDeviceSummaryCard(
            repository: devices,
            onOpenDevices: () => _select(2),
          );
    // Scope the report seam to the active membership + the session-carrying
    // transport (real mode). Demo mode keeps the defaults (demo repository).
    return ProviderScope(
      overrides: [
        dashboardMembershipProvider.overrideWithValue(widget.membership),
        dashboardAuthTransportProvider.overrideWithValue(
          widget.reportsTransport,
        ),
      ],
      child: DashboardHomeScreen(
        setupPanel: setupPanel,
        deviceSummary: deviceSummary,
      ),
    );
  }

  /// Orders: ONE destination holding the read-only ACTIVE-ORDERS operations
  /// centre (ACTIVE-ORDERS-001, `owner_active_orders`) and the order-history +
  /// reprint centre (ORDERS-HISTORY-001, `owner_order_history` /
  /// `owner_order_detail`). All three RPCs read through the scoped membership +
  /// authenticated transport (real mode); demo mode shows the computed demo
  /// dataset with an honest banner. Same ProviderScope wiring as the Overview so
  /// both order seams pick up the scope + transport.
  Widget _ordersSurface() {
    return ProviderScope(
      overrides: [
        dashboardMembershipProvider.overrideWithValue(widget.membership),
        dashboardAuthTransportProvider.overrideWithValue(
          widget.reportsTransport,
        ),
      ],
      child: const OrdersScreen(),
    );
  }

  /// The Activity-log tab (AUDIT-LOG-DASHBOARD-001). Reads the read-only
  /// `owner_audit_events` RPC through the scoped membership + authenticated
  /// transport (real mode); demo mode shows the in-memory timeline with an
  /// honest banner. Same ProviderScope wiring as the Orders surface.
  Widget _activityLogSurface() {
    return ProviderScope(
      overrides: [
        dashboardMembershipProvider.overrideWithValue(widget.membership),
        dashboardAuthTransportProvider.overrideWithValue(
          widget.reportsTransport,
        ),
      ],
      child: const ActivityLogScreen(),
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
            overrides: [
              ...adminFeatureOverrides(
                scope: _adminScope,
                repository: repository,
              ),
              // LIVE-OPS-001: the Dashboard provides the QR pairing panel (it owns
              // the qr_flutter dependency); feature_admin stays QR-free.
              devicePairingPanelProvider.overrideWithValue(
                showDevicePairingPanel,
              ),
            ],
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
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: l10n.dashboardNavOrders,
    ),
    _NavItem(
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      label: l10n.dashboardNavActivity,
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
      // Dashboard "1c": a clean white top bar over the warm canvas.
      color: scheme.surface,
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
            // Long organization / branch names truncate safely to one line; the
            // tooltip reveals the full active-context label (no new string).
            child: Tooltip(
              message: contextLabel,
              child: Text(
                contextLabel,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
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

/// The Dashboard "1c" LIGHT side rail: a white panel with an end hairline, a
/// gradient brand lockup on top, one tappable destination per row (active =
/// brand-green fill + white foreground + soft shadow; inactive = muted ink with
/// a warm hover), and a footer workspace card. Collapses to icon-only ([compact])
/// on small tablets. RTL-safe (Rows + directional padding/borders); it stays on
/// the reading-start side, so it sits on the right under Arabic/Hebrew.
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.membership,
    required this.width,
    required this.compact,
  });

  final List<_NavItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final MembershipContext? membership;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final member = membership;
    final side = compact ? RestoflowSpacing.sm : RestoflowSpacing.lg;
    // Dashboard V2: the rail is a full-height floating panel (rounded, hairline
    // outline, soft shadow) on the warm canvas rather than a flush column.
    return Container(
      key: const Key('dashboard-side-rail'),
      width: width,
      margin: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.md,
        RestoflowSpacing.md,
        0,
        RestoflowSpacing.md,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        border: Border.all(color: kRestoflowHairline),
        boxShadow: RestoflowShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // RF-132: a stronger, never-truncated brand area — the short product
          // wordmark with the surface tagline beneath it (the previous long
          // app title ellipsized inside the rail), and a touch more air above
          // the navigation.
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              side,
              RestoflowSpacing.xl,
              side,
              RestoflowSpacing.xl,
            ),
            child: compact
                ? const Center(child: RestoflowBrandMark(size: 40))
                : RestoflowBrandMark(
                    size: 42,
                    title: l10n.dashboardBrandName,
                    tagline: l10n.dashboardBrandTagline,
                  ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
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
                    compact: compact,
                    onTap: () => onSelected(i),
                  ),
              ],
            ),
          ),
          if (member != null) _RailFooter(membership: member, compact: compact),
        ],
      ),
    );
  }
}

/// One rail destination: brand-green fill + white foreground when selected,
/// muted ink otherwise, with a warm hover on inactive rows. Icon-only when
/// [compact] (label moves to a tooltip). The Row fills the rail width so the
/// active fill spans it and the icon centres in compact mode.
///
/// Accessibility (RF-125): each tile is one merged semantic node — a selectable
/// button carrying the destination [item.label] even when the visual is
/// icon-only ([compact]) — so selection is announced (not conveyed by colour
/// alone; the icon also switches to its filled variant) and screen readers read
/// a label for every destination. Keyboard focus is visible via [InkWell]'s
/// focus highlight.
class _SideNavTile extends StatelessWidget {
  const _SideNavTile({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(RestoflowRadii.md);
    final iconColor = selected ? Colors.white : kRestoflowInk3;
    final labelColor = selected ? Colors.white : kRestoflowInk2;

    final row = Row(
      mainAxisAlignment: compact
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(
          selected ? item.selectedIcon : item.icon,
          size: RestoflowIconSizes.md,
          color: iconColor,
        ),
        if (!compact) ...[
          const SizedBox(width: RestoflowSpacing.md),
          Expanded(
            child: Text(
              item.label,
              style: theme.textTheme.labelLarge?.copyWith(color: labelColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    final tile = AnimatedContainer(
      duration: RestoflowDurations.fast,
      decoration: BoxDecoration(
        color: selected ? kRestoflowSeedColor : Colors.transparent,
        borderRadius: radius,
        // RF-132: the active pill's soft shadow is brand-green tinted (the
        // reference's restrained glow) rather than the neutral card shadow.
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x521B7A52),
                  offset: Offset(0, 4),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? RestoflowSpacing.sm : RestoflowSpacing.md,
        vertical: RestoflowSpacing.md,
      ),
      child: row,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.xs),
      // One merged, selectable button node with an explicit label — so compact
      // icon-only tiles still expose their destination name and the selected
      // state is announced (never colour-only). The visual subtree's own
      // semantics are excluded to avoid a duplicate/empty node.
      child: MergeSemantics(
        child: Semantics(
          selected: selected,
          button: true,
          label: item.label,
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              // Inactive rows show a warm hover; the active row's opaque green
              // fill sits above the ink so it stays solid.
              hoverColor: kRestoflowCanvas,
              // Visible keyboard focus on the white rail — a light brand tint,
              // distinct from the warm hover.
              focusColor: kRestoflowSeedColor.withValues(alpha: 0.12),
              child: ExcludeSemantics(
                child: compact
                    ? Tooltip(message: item.label, child: tile)
                    : tile,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rail footer workspace card: a gradient avatar (org initial) + the
/// organization name and the localized membership role. No user display name is
/// available in [MembershipContext], so it honestly shows the workspace + role,
/// never a fabricated person. Collapses to the avatar alone when [compact].
class _RailFooter extends StatelessWidget {
  const _RailFooter({required this.membership, required this.compact});

  final MembershipContext membership;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic =
        theme.extension<RestoflowSemanticColors>() ??
        RestoflowSemanticColors.of(theme.brightness);
    final org = membership.organizationName;
    final initial = org.isNotEmpty ? org.substring(0, 1).toUpperCase() : '?';
    final avatar = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [theme.colorScheme.primary, semantic.accent],
        ),
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Text(
        initial,
        style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
      ),
    );
    final side = compact ? RestoflowSpacing.sm : RestoflowSpacing.md;
    return Container(
      margin: EdgeInsetsDirectional.fromSTEB(
        side,
        0,
        side,
        RestoflowSpacing.md,
      ),
      padding: EdgeInsets.all(
        compact ? RestoflowSpacing.xs : RestoflowSpacing.md,
      ),
      // RF-132: the reference's account card — the warm surface gains a
      // hairline outline so it reads as a deliberate card, not a tint.
      decoration: BoxDecoration(
        color: kRestoflowCanvas,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: kRestoflowHairline),
      ),
      child: compact
          ? Center(child: avatar)
          : Row(
              children: [
                avatar,
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        org,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _roleLabel(l10n, membership.role),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kRestoflowInk3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// The localized label for a membership [role] (the six D-004 role keys).
String _roleLabel(AppLocalizations l10n, MembershipRole role) => switch (role) {
  MembershipRole.orgOwner => l10n.authRoleOwner,
  MembershipRole.restaurantOwner => l10n.authRoleRestaurantOwner,
  MembershipRole.manager => l10n.authRoleManager,
  MembershipRole.cashier => l10n.authRoleCashier,
  MembershipRole.kitchenStaff => l10n.authRoleKitchenStaff,
  MembershipRole.accountant => l10n.authRoleAccountant,
};
