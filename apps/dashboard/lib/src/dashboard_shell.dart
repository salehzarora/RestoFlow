import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'admin/branch_kitchen_workflow_repository.dart';
import 'admin/branch_shift_close_policy_repository.dart';
import 'admin/real_admin_views.dart';
import 'admin/supabase_settings_repository.dart';
import 'branding/receipt_logo_url_resolver.dart';
import 'branding/restaurant_logo_repository.dart';
import 'branding/restaurant_logo_storage.dart';
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
import 'state/setup_device_providers.dart';
import 'analytics/dashboard_destination.dart';
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

/// GLOBAL-BRAND-DASHBOARD-V2-1 — the identity that must recreate the shell.
///
/// [DashboardShell] builds its admin scope and its real repositories ONCE, in
/// `late final` fields, so they live exactly as long as the State does. That is
/// the right lifetime for a session — and the wrong one across a membership
/// change, because Flutter will happily reuse the State when only the widget's
/// arguments change. The repositories would then still be scoped, and
/// authorized, to the PREVIOUS membership.
///
/// Value-based provider keys defend the CACHE against that; they cannot defend
/// the repository objects. Putting this string in a [ValueKey] closes the gap:
/// a different identity is a different widget, the old State is disposed, and
/// every `late final` is rebuilt for the membership actually signed in.
///
/// WHAT IS IN IT, and why each field earns its place:
///   * membership id + org / restaurant / branch — the scope the repositories
///     are constructed from (`dashboardAdminScopeFor`);
///   * role — authorization. A downgrade must not keep a State whose
///     repositories were built for the stronger role;
///   * currencyCode — `AdminScope` embeds it, so a resolved currency change
///     produces a genuinely different scope.
///
/// What is deliberately NOT in it: display labels, the selected analytics
/// range, and the repository instances themselves. Those change for cosmetic
/// or local reasons, and rebuilding the whole shell for them would throw away
/// scroll positions and in-flight work for nothing.
String dashboardShellIdentity(
  MembershipContext? membership, {
  String? currencyCode,
}) {
  if (membership == null) return 'demo';
  return [
    membership.id,
    membership.organizationId,
    membership.restaurantId ?? '-',
    membership.branchId ?? '-',
    membership.role.name,
    currencyCode ?? '-',
  ].join('|');
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
    this.brandingLogoStorage,
    this.printersRepository,
    this.staffRepository,
    this.tablesRepository,
    this.reportsTransport,
    this.onSignOut,
    this.debugOnSetupInvalidation,
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

  /// PRINT-BRANDING-LOGO-001: the restaurant-logo blob store (real mode only;
  /// null in demo -> the branding card shows an honest note).
  final RestaurantLogoStorage? brandingLogoStorage;

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

  /// V2.1 FINAL — the leave-writer invalidation's OWN [WidgetRef], published
  /// for tests. Null in production, where nothing reads it.
  ///
  /// It exists because the defect it guards against was invisible to every
  /// count-based test: the invalidation ran, on the wrong container, and looked
  /// exactly like a working one from the outside. Publishing the ref the path
  /// actually uses lets a test assert the ONE property that was violated — that
  /// this code resolves through the overrides below, not past them.
  @visibleForTesting
  final void Function(WidgetRef ref)? debugOnSetupInvalidation;

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

  /// DASHBOARD-PRINTER-ONLY-MODE-TOGGLE-010: the per-branch kitchen-workflow
  /// seam, built once on the same preconditions as the RF-113 policy seam — an
  /// authenticated transport AND a concrete restaurant+branch in scope.
  /// Otherwise null and the Settings section is omitted.
  late final BranchKitchenWorkflowRepository? _kitchenWorkflowRepo =
      _buildKitchenWorkflowRepo();

  BranchKitchenWorkflowRepository? _buildKitchenWorkflowRepo() {
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
    return SupabaseBranchKitchenWorkflowRepository(
      transport: transport,
      organizationId: membership.organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  }

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

  /// PRINT-BRANDING-LOGO-001: the receipt-branding read/write seam, built once.
  /// Null unless there is an authenticated transport AND a concrete restaurant
  /// in scope (branch is not required — branding is restaurant-level) -> the
  /// branding card then shows an honest "unavailable" note.
  late final RestaurantLogoRepository? _brandingRepo = _buildBrandingRepo();

  RestaurantLogoRepository? _buildBrandingRepo() {
    final transport = widget.reportsTransport;
    final membership = widget.membership;
    final restaurantId = membership?.restaurantId;
    if (transport == null || membership == null || restaurantId == null) {
      return null;
    }
    return SupabaseRestaurantLogoRepository(
      transport: transport,
      organizationId: membership.organizationId,
      restaurantId: restaurantId,
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

  /// V2.1 — leaving a destination where the user could have CHANGED setup data
  /// invalidates exactly the read model that destination writes to.
  ///
  /// Caching the Overview's setup counts bought a free return trip, but it also
  /// meant a device created on the Devices tab would not show up in the
  /// readiness checklist until a manual refresh — the counts would sit there
  /// looking authoritative and be wrong. This is the smallest truthful
  /// correction: not a global wipe, not a reload on every navigation, and not a
  /// reload for destinations that cannot write setup data at all (Overview,
  /// Orders, Activity, Users, Tables, Settings all leave the counts untouched).
  ///
  /// It is coarser than invalidating at each mutation call site, which lives in
  /// the shared admin package. The trade is deliberate: at most one reload per
  /// visit to a writing tab, in exchange for never showing a stale count.
  ///
  /// V2.1 FINAL — WHY THIS TAKES A [WidgetRef] INSTEAD OF LOOKING ONE UP.
  ///
  /// The first attempt at this method resolved its container itself, with
  /// `ProviderScope.containerOf(context)`. That `context` is the State's own —
  /// the shell element — and the ProviderScope carrying the setup overrides is
  /// something `build` RETURNS, so it is a descendant. The lookup therefore
  /// walked straight past every override and found the ROOT container, where
  /// `setupDevicesRepositoryProvider` is null, `dashboardMembershipProvider` is
  /// null, and [currentSetupScopeKeyProvider] is consequently an all-null key
  /// that no surface watches. Every invalidation landed on an entry nobody
  /// reads, so the whole leave-writer refresh was inert while looking, from any
  /// count of repository calls, exactly like a working one.
  ///
  /// [ref] comes from a `Consumer` placed immediately BELOW that ProviderScope,
  /// so it resolves THROUGH the overrides: the same container the Overview
  /// reads, the same repositories the tabs use, the same key. No second
  /// container is created and no repository is built twice — the point is to
  /// reach the one that already exists rather than to make another.
  void _invalidateSetupSourcesFor(int leavingIndex, WidgetRef ref) {
    widget.debugOnSetupInvalidation?.call(ref);
    final key = ref.read(currentSetupScopeKeyProvider);
    switch (DashboardDestination.fromIndex(leavingIndex)) {
      case DashboardDestination.devices:
        ref.invalidate(setupDevicesProvider(key));
      case DashboardDestination.printers:
        ref.invalidate(setupPrintersProvider(key));
      case DashboardDestination.staff:
        ref.invalidate(setupStaffProvider(key));
      case DashboardDestination.menu:
        ref.invalidate(setupMenuProvider(key));
      default:
        break;
    }
  }

  void _select(int value, WidgetRef ref) {
    if (value == _index) return;
    _invalidateSetupSourcesFor(_index, ref);
    setState(() => _index = value);
  }

  /// F0.3 — the ONE named navigation seam.
  ///
  /// Call sites say where they want to go by name instead of by magic number,
  /// so inserting a destination can no longer silently re-point an existing
  /// jump at the wrong surface.
  void _goTo(DashboardDestination destination, WidgetRef ref) =>
      _select(destination.tabIndex, ref);

  /// V2.1 FINAL — the override scope, and immediately beneath it the [Consumer]
  /// that gives every navigating callback a ref INSIDE it.
  ///
  /// The whole shell body is built in that builder deliberately: navigation is
  /// triggered from the rail, from the bottom bar, from the Setup Center's
  /// stats and from the Overview's KPI drill-downs, and a ref that only some of
  /// those could reach would be a fix that holds for some routes and not
  /// others.
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ProviderScope(
      overrides: [
        dashboardMembershipProvider.overrideWithValue(widget.membership),
        dashboardAuthTransportProvider.overrideWithValue(
          widget.reportsTransport,
        ),
        // V2.1 — the setup/device repositories reach their providers HERE,
        // above the KeyedSubtree, so the loads survive the destination
        // teardown. These are the SAME instances the Devices / Printers /
        // Staff tabs use; nothing is constructed twice.
        setupDevicesRepositoryProvider.overrideWithValue(_realDeviceRepo),
        setupPrintersRepositoryProvider.overrideWithValue(_printersRepo),
        setupStaffRepositoryProvider.overrideWithValue(_staffRepo),
        setupMenuSourceProvider.overrideWithValue(widget.menuReadSource),
        setupMenuScopeProvider.overrideWithValue(_menuScope),
      ],
      child: Consumer(builder: (context, ref, _) => _body(context, l10n, ref)),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, WidgetRef ref) {
    // KeyedSubtree: each tab gets a FRESH subtree, so the per-surface
    // ProviderScopes are recreated instead of reused with different override
    // types across tabs (Riverpod forbids changing an override's type in
    // place).
    // F0.6 — THE STABLE SHARED SCOPE.
    //
    // These two overrides used to be repeated inside Overview, Orders and
    // Activity with IDENTICAL values. Because each surface built its own
    // ProviderScope INSIDE the KeyedSubtree below, switching tabs destroyed
    // that container and everything it held - including the loaded owner
    // report, which then refetched on every return.
    //
    // Hoisting them gives those providers ONE container that outlives
    // tab changes. Surface-specific overrides (Orders' receipt-logo
    // resolver, the menu feature scopes) deliberately stay local - only the
    // genuinely shared ones move.
    //
    // CODEX F-1B-3-R1B — the scope is now ABOVE the LayoutBuilder, not inside
    // it. It used to wrap this subtree, which the responsive builder places in
    // two structurally different trees: `Row > Expanded > Column` at rail
    // widths, `Column` at phone widths. Crossing ~560px therefore gave the
    // ProviderScope a different ancestor chain, so its element could not be
    // reused — the container was disposed and rebuilt, taking the loaded report
    // AND the remembered branch answer with it. An owner who had already been
    // told branch B was gone would be back to "never answered" purely because
    // the window was resized, and the raw selection would apply again.
    //
    // Layout may change what is on screen; it must not change which container
    // owns the membership, the transport, or what the dashboard has learned.
    final content = KeyedSubtree(
      key: ValueKey('dashboard-tab-$_index'),
      child: switch (_index) {
        0 => _overview(ref),
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
                  kitchenWorkflowRepository: _kitchenWorkflowRepo,
                  settingsRepository: _settingsRepo,
                  brandingRepository: _brandingRepo,
                  brandingStorage: widget.brandingLogoStorage,
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
                  onSelected: (value) => _select(value, ref),
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
                onDestinationSelected: (value) => _select(value, ref),
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
  Widget _overview(WidgetRef ref) {
    final devices = _realDeviceRepo;
    // The direct null-check promotes `devices` to non-null inside the branch.
    final Widget? setupPanel;
    if (devices != null &&
        widget.printersRepository != null &&
        widget.staffRepository != null) {
      setupPanel = DashboardSetupCenter(
        // V2.1 — no repositories here any more: the panel reads the four
        // provider entries keyed by the current setup scope, so returning to
        // Overview costs nothing.
        onOpenMenu: () => _goTo(DashboardDestination.menu, ref),
        onOpenDevices: () => _goTo(DashboardDestination.devices, ref),
        onOpenPrinters: () => _goTo(DashboardDestination.printers, ref),
        onOpenStaff: () => _goTo(DashboardDestination.staff, ref),
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
            onOpenDevices: () => _goTo(DashboardDestination.devices, ref),
          );
    // Scope the report seam to the active membership + the session-carrying
    // transport (real mode). Demo mode keeps the defaults (demo repository).
    // F0.6: NO local ProviderScope here any more. The membership +
    // transport overrides moved to ONE stable scope above the tab-switch
    // KeyedSubtree. This scope was recreated on every return to Overview,
    // which destroyed the report container and forced a refetch.
    return DashboardHomeScreen(
      setupPanel: setupPanel,
      deviceSummary: deviceSummary,
      // F0.4: the shell owns tab state, so it supplies the NAMED navigation
      // seam. The Overview binds it to a WidgetRef and executes typed
      // drill-downs; the shell learns nothing about filters, and no magic
      // number crosses this boundary.
      onNavigate: (destination) => _goTo(destination, ref),
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
    // CODEX F-1B-3-R2 — the membership + transport overrides are GONE from
    // here, and that is the fix rather than a tidy-up.
    //
    // They were repeated with values identical to the stable scope above, and
    // an override is what decides WHERE a provider lives: Riverpod places a
    // provider in the deepest container overriding any of its transitive
    // dependencies. Branch options depend on both, so Overview and Orders each
    // built their OWN branch-options chain — two enumerations, and worse, two
    // independent memories of what the last successful answer said. Overview
    // could learn that branch B is gone and move to the parent scope while
    // Orders, mounting fresh, had never been told and issued an
    // `owner_order_history` request for B.
    //
    // With the duplicates removed both surfaces resolve in the ONE hoisted
    // container, so there is a single answer and a single scope. Only the
    // genuinely Orders-local override stays.
    return ProviderScope(
      overrides: [
        // PRINT-BRANDING-LOGO-001: the current-logo URL resolver for the order
        // reprint preview (null -> text-only).
        receiptLogoUrlResolverProvider.overrideWithValue(
          _receiptLogoUrlResolver(),
        ),
      ],
      child: const OrdersScreen(),
    );
  }

  /// Builds a transient current-logo signed-URL resolver from the branding
  /// repository + storage, or null when either is unavailable (text-only).
  /// EGRESS-REMEDIATION-001: the branding READ still runs per preview (live
  /// truth — a just-replaced logo is picked up immediately via its new
  /// versioned path), but the signed URL itself is reused per path from the
  /// shared cache, so repeated previews inside the validity window stop
  /// minting fresh tokens and re-downloading the unchanged logo.
  ReceiptLogoUrlResolver? _receiptLogoUrlResolver() {
    final repo = _brandingRepo;
    final storage = widget.brandingLogoStorage;
    if (repo == null || storage == null) return null;
    return () async {
      final settings = await repo.read();
      if (settings == null || !settings.enabled || !settings.hasLogo) {
        return null;
      }
      try {
        final url = await signedUrlCacheFor(storage).resolve(
          settings.path!,
          validity: kSignedUrlValidity,
          sign: () => storage.createSignedUrl(
            settings.path!,
            expiresIn: kSignedUrlValidity,
          ),
        );
        return url.toString();
      } catch (_) {
        return null;
      }
    };
  }

  /// The Activity-log tab (AUDIT-LOG-DASHBOARD-001). Reads the read-only
  /// `owner_audit_events` RPC through the scoped membership + authenticated
  /// transport (real mode); demo mode shows the in-memory timeline with an
  /// honest banner. Same ProviderScope wiring as the Orders surface.
  Widget _activityLogSurface() {
    // CODEX F-1B-3-R2 — same duplicate overrides, same effect: Activity was
    // enumerating branches into a container of its own. It inherits the stable
    // scope above, which is where those values already are.
    return const ActivityLogScreen();
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
          // Flexible, because this Row is the one place a hardened pill still
          // cannot save itself. A non-flex child of a horizontal RenderFlex is
          // laid out with an UNBOUNDED width, so the pill keeps its full
          // intrinsic size, starves the Expanded context label beside it, and
          // the HEADER overflows rather than the pill. Arabic and Hebrew reach
          // that point at 390px / 2x where English does not. Giving the pill a
          // finite share is the call-site half of the fix; the component owns
          // the other half.
          Flexible(
            child: RestoflowStatusPill(
              // DESIGN-002: user-facing data-source wording (was the developer
              // "Demo" / "Real" jargon).
              label: isReal
                  ? l10n.dashboardModeLiveData
                  : l10n.dashboardModeDemoData,
              tone: isReal ? RestoflowTone.success : RestoflowTone.info,
              icon: isReal ? Icons.cloud_done_outlined : Icons.science_outlined,
            ),
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

/// One rail destination: a navy fill + white foreground when selected, muted ink
/// otherwise, with a cool brand hover on every row. Icon-only when [compact]
/// (label moves to a tooltip). The Row fills the rail width so the active fill
/// spans it and the icon centres in compact mode.
///
/// Accessibility (RF-125): each tile is one merged semantic node — a selectable
/// button carrying the destination [item.label] even when the visual is
/// icon-only ([compact]) — so selection is announced (not conveyed by colour
/// alone; the icon also switches to its filled variant) and screen readers read
/// a label for every destination.
///
/// V2.2 — WHY THE FILL MOVED, AND WHY FOCUS IS A RING.
///
/// The selected fill used to be painted by an [AnimatedContainer] that was the
/// InkWell's CHILD. Material draws ink — hover, focus and splash overlays —
/// between its own surface and that child, so on a selected tile every one of
/// those overlays was painted UNDERNEATH an opaque navy rectangle. The result
/// was a destination that gave no hover feedback and, worse, showed no keyboard
/// focus at all: a keyboard user tabbing along the rail could not see where they
/// were. The fill is now the [Material]'s own colour, which puts the ink layer
/// back on top of it where the whole feedback system expects to be.
///
/// Focus is a RING rather than a wash, and that is deliberate: a wash is a
/// colour-only signal, and on the navy bed there is no wash light enough to read
/// reliably at a glance. The ring is drawn as a non-participating overlay, so
/// gaining focus changes nothing about the tile's size or position — a focus
/// indicator that nudges the layout is its own bug.
class _SideNavTile extends StatefulWidget {
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
  State<_SideNavTile> createState() => _SideNavTileState();
}

class _SideNavTileState extends State<_SideNavTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final compact = widget.compact;
    final radius = BorderRadius.circular(RestoflowRadii.md);
    final iconColor = selected ? Colors.white : kRestoflowInk3;
    final labelColor = selected ? Colors.white : kRestoflowInk2;

    // Hover/focus overlays, each read against the bed they actually land on.
    // On the navy pill only a light film is legible; on the white rail the quiet
    // brand tint is a real step (the previous hover was the page canvas, barely
    // 3% off white, which is why the rail felt inert under the mouse).
    final hoverColor = selected
        ? Colors.white.withValues(alpha: 0.14)
        : kRestoflowNavyContainer;
    final focusWash = selected
        ? Colors.white.withValues(alpha: 0.20)
        : kRestoflowNavyContainer;
    final focusRing = selected ? Colors.white : kRestoflowSeedColor;

    final row = Row(
      mainAxisAlignment: compact
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(
          selected ? widget.item.selectedIcon : widget.item.icon,
          size: RestoflowIconSizes.md,
          color: iconColor,
        ),
        if (!compact) ...[
          const SizedBox(width: RestoflowSpacing.md),
          Expanded(
            child: Text(
              widget.item.label,
              style: theme.textTheme.labelLarge?.copyWith(color: labelColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    final body = Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? RestoflowSpacing.sm : RestoflowSpacing.md,
        vertical: RestoflowSpacing.md,
      ),
      child: row,
    );

    final interactive = Material(
      // THE FILL. Being the Material's colour rather than a child decoration is
      // the whole fix — the ink layer now sits above it.
      color: selected ? kRestoflowSeedColor : Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (value) {
          if (value != _focused) setState(() => _focused = value);
        },
        borderRadius: radius,
        hoverColor: hoverColor,
        focusColor: focusWash,
        child: ExcludeSemantics(
          child: compact
              ? Tooltip(message: widget.item.label, child: body)
              : body,
        ),
      ),
    );

    final tile = AnimatedContainer(
      duration: RestoflowDurations.fast,
      decoration: BoxDecoration(
        borderRadius: radius,
        // RF-132: the active pill's soft shadow is BRAND tinted (the reference's
        // restrained glow) rather than the neutral card shadow.
        //
        // V1: derived from the painted brand colour instead of a hardcoded
        // green alpha, so the glow follows the identity instead of outliving it.
        boxShadow: selected
            ? [
                BoxShadow(
                  color: kRestoflowSeedColor.withValues(alpha: 0.32),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          interactive,
          // UI-ORANGE-BALANCE-POLISH-001: a narrow orange marker on the
          // selected tile's leading edge.
          //
          // The rail stays navy — that is the structure — but navy-on-navy made
          // "which page am I on" a brightness comparison. The marker adds a
          // second, non-colour signal (an edge that is either there or not), so
          // selection no longer depends on telling two navies apart. Directional
          // start, so it mirrors to the right edge under RTL.
          //
          // It rides INSIDE the tile bounds like the focus ring, taking part in
          // neither layout nor hit testing, so nothing shifts when selection
          // moves.
          if (widget.selected)
            PositionedDirectional(
              start: 0,
              top: RestoflowSpacing.sm,
              bottom: RestoflowSpacing.sm,
              child: IgnorePointer(
                child: Container(
                  key: const Key('rail-active-marker'),
                  width: 3,
                  decoration: BoxDecoration(
                    color: RestoflowBrandPalette.of(
                      Brightness.light,
                    ).accentOrange,
                    borderRadius: BorderRadius.circular(RestoflowRadii.pill),
                  ),
                ),
              ),
            ),
          if (_focused)
            // Positioned.fill + IgnorePointer: the ring is painted INSIDE the
            // tile's existing bounds and takes part in neither layout nor hit
            // testing, so focus cannot move anything or steal a tap.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('rail-focus-ring'),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: focusRing, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
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
          label: widget.item.label,
          child: tile,
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
