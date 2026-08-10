/// GLOBAL-BRAND-DASHBOARD-V2-1 — navigation smoothness, measured.
///
/// The claim under test is a COUNT, not a feeling: how many times the Overview's
/// setup surfaces hit their repositories. Before this slice the Setup Center
/// loaded from a State field initializer and the device summary card loaded in
/// `initState`, and both were handed the SAME `AdminRepository` — so one mount
/// cost TWO `loadDevices()` calls, and the shell's `KeyedSubtree` teardown made
/// the whole set repeat on every return to Overview.
///
/// Counting fakes are the only honest evidence here. A widget test that merely
/// renders the panel would pass in both architectures.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/printers/printers_repository.dart';
import 'package:restoflow_dashboard/src/printers/printers_screen.dart';
import 'package:restoflow_dashboard/src/setup/device_summary_card.dart';
import 'package:restoflow_dashboard/src/setup/setup_center.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/setup_device_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Counts every call. One instance stands in for the single repository the
/// shell hands to both surfaces.
class _CountingDevices extends DemoAdminStore {
  _CountingDevices() : super(scope: AdminScope.demo);

  int loadDevicesCalls = 0;

  /// What the backend would return NOW. Mutable so a test can stand in for a
  /// device created on the Devices tab — the exact situation the leave-writer
  /// invalidation exists for.
  List<AdminDevice> devices = const [
    AdminDevice(
      id: 'd-1',
      label: 'Counter POS',
      deviceType: 'pos',
      branchLabel: 'Main',
      status: DeviceLifecycleStatus.active,
    ),
  ];

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async {
    loadDevicesCalls++;
    return Success(List.of(devices));
  }
}

Widget _host(_CountingDevices devices, {required Widget child}) =>
    ProviderScope(
      overrides: [setupDevicesRepositoryProvider.overrideWithValue(devices)],
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('A. the device list is loaded ONCE for both surfaces', () {
    testWidgets('Setup Center + device summary share one canonical load', (
      tester,
    ) async {
      final devices = _CountingDevices();
      await tester.pumpWidget(
        _host(
          devices,
          child: Column(
            children: [
              DashboardSetupCenter(
                onOpenMenu: () {},
                onOpenDevices: () {},
                onOpenPrinters: () {},
                onOpenStaff: () {},
              ),
              const DashboardDeviceSummaryCard(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        devices.loadDevicesCalls,
        1,
        reason: 'two widgets asking the same question must cost one request',
      );
    });

    testWidgets('the summary card alone still loads exactly once', (
      tester,
    ) async {
      final devices = _CountingDevices();
      await tester.pumpWidget(
        _host(devices, child: const DashboardDeviceSummaryCard()),
      );
      await tester.pumpAndSettle();

      expect(devices.loadDevicesCalls, 1);
    });
  });

  group('B. rebuilding the widget does not refetch', () {
    testWidgets('tearing the subtree down and rebuilding it costs nothing', (
      tester,
    ) async {
      final devices = _CountingDevices();
      final container = ProviderContainer(
        overrides: [setupDevicesRepositoryProvider.overrideWithValue(devices)],
      );
      addTearDown(container.dispose);

      Widget app({required bool showCard}) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: showCard
                  ? const DashboardDeviceSummaryCard()
                  : const SizedBox(key: Key('other-destination')),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(showCard: true));
      await tester.pumpAndSettle();
      expect(devices.loadDevicesCalls, 1);

      // Navigate away: the shell really does destroy the subtree.
      await tester.pumpWidget(app(showCard: false));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardDeviceSummaryCard), findsNothing);

      // ...and back. The provider entry outlived the widget.
      await tester.pumpWidget(app(showCard: true));
      await tester.pumpAndSettle();
      expect(
        devices.loadDevicesCalls,
        1,
        reason: 'a remount must not re-issue the request',
      );
    });
  });

  group('C. the key is value-based, never the repository instance', () {
    const base = SetupScopeKey(
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
      isDemoMode: false,
    );

    test('identical values are the same entry', () {
      expect(
        base,
        const SetupScopeKey(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          isDemoMode: false,
        ),
      );
      expect(base.hashCode, isNotNull);
    });

    test('a different branch, restaurant or organization is a NEW entry', () {
      expect(
        base ==
            const SetupScopeKey(
              organizationId: 'org-1',
              restaurantId: 'rest-1',
              branchId: 'branch-2',
              isDemoMode: false,
            ),
        isFalse,
      );
      expect(
        base ==
            const SetupScopeKey(
              organizationId: 'org-1',
              restaurantId: 'rest-2',
              branchId: 'branch-1',
              isDemoMode: false,
            ),
        isFalse,
      );
      expect(
        base ==
            const SetupScopeKey(
              organizationId: 'org-2',
              restaurantId: 'rest-1',
              branchId: 'branch-1',
              isDemoMode: false,
            ),
        isFalse,
      );
    });

    test('demo and real are different sources, so different entries', () {
      expect(
        base ==
            const SetupScopeKey(
              organizationId: 'org-1',
              restaurantId: 'rest-1',
              branchId: 'branch-1',
              isDemoMode: true,
            ),
        isFalse,
      );
    });
  });

  group('D. a new scope loads afresh and never serves the old answer', () {
    testWidgets('switching key issues a new load', (tester) async {
      final devices = _CountingDevices();
      final container = ProviderContainer(
        overrides: [setupDevicesRepositoryProvider.overrideWithValue(devices)],
      );
      addTearDown(container.dispose);

      const keyA = SetupScopeKey(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        isDemoMode: false,
      );
      const keyB = SetupScopeKey(
        organizationId: 'org-2',
        restaurantId: 'rest-2',
        branchId: 'branch-2',
        isDemoMode: false,
      );

      await container.read(setupDevicesProvider(keyA).future);
      expect(devices.loadDevicesCalls, 1);

      await container.read(setupDevicesProvider(keyB).future);
      expect(
        devices.loadDevicesCalls,
        2,
        reason: 'a new scope must not be answered from the old scope entry',
      );

      // The first entry is still cached in its own right.
      await container.read(setupDevicesProvider(keyA).future);
      expect(devices.loadDevicesCalls, 2);
    });
  });

  group('E. invalidation refetches exactly once, for the current key only', () {
    test('invalidating one key leaves other scopes cached', () async {
      final devices = _CountingDevices();
      final container = ProviderContainer(
        overrides: [setupDevicesRepositoryProvider.overrideWithValue(devices)],
      );
      addTearDown(container.dispose);

      const keyA = SetupScopeKey(
        organizationId: 'org-1',
        restaurantId: null,
        branchId: 'branch-1',
        isDemoMode: false,
      );
      const keyB = SetupScopeKey(
        organizationId: 'org-1',
        restaurantId: null,
        branchId: 'branch-2',
        isDemoMode: false,
      );

      await container.read(setupDevicesProvider(keyA).future);
      await container.read(setupDevicesProvider(keyB).future);
      expect(devices.loadDevicesCalls, 2);

      container.invalidate(setupDevicesProvider(keyA));
      await container.read(setupDevicesProvider(keyA).future);
      expect(
        devices.loadDevicesCalls,
        3,
        reason: 'the refreshed key reloads exactly once',
      );

      await container.read(setupDevicesProvider(keyB).future);
      expect(
        devices.loadDevicesCalls,
        3,
        reason: 'the other branch must still be served from cache',
      );
    });
  });

  group('F. an unwired repository is honest, not empty', () {
    test('no repository yields null — the "unavailable" answer', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const key = SetupScopeKey(
        organizationId: 'org-1',
        restaurantId: null,
        branchId: null,
        isDemoMode: false,
      );
      expect(await container.read(setupDevicesProvider(key).future), isNull);
    });
  });

  group('G. the shell identity key rebuilds scope-bearing State', () {
    MembershipContext member({
      String id = 'm-1',
      String org = 'org-1',
      String? restaurant = 'rest-1',
      String? branch = 'branch-1',
      MembershipRole role = MembershipRole.orgOwner,
    }) => MembershipContext(
      id: id,
      organizationId: org,
      organizationName: 'Org',
      restaurantId: restaurant,
      restaurantName: 'Rest',
      branchId: branch,
      branchName: 'Main',
      role: role,
      status: 'active',
    );

    test('identity changes with every field that scopes a repository', () {
      final base = dashboardShellIdentity(member(), currencyCode: 'ILS');

      // Same everything => same State may be reused.
      expect(dashboardShellIdentity(member(), currencyCode: 'ILS'), base);

      // Each of these builds a DIFFERENT AdminScope or a different authority,
      // so each must dispose the old State and its late-final repositories.
      expect(
        dashboardShellIdentity(member(id: 'm-2'), currencyCode: 'ILS'),
        isNot(base),
      );
      expect(
        dashboardShellIdentity(member(org: 'org-2'), currencyCode: 'ILS'),
        isNot(base),
      );
      expect(
        dashboardShellIdentity(
          member(restaurant: 'rest-2'),
          currencyCode: 'ILS',
        ),
        isNot(base),
      );
      expect(
        dashboardShellIdentity(member(branch: 'branch-2'), currencyCode: 'ILS'),
        isNot(base),
      );
      expect(
        dashboardShellIdentity(
          member(role: MembershipRole.cashier),
          currencyCode: 'ILS',
        ),
        isNot(base),
        reason: 'a downgraded role must not keep repositories built for owner',
      );
      expect(
        dashboardShellIdentity(member(), currencyCode: 'USD'),
        isNot(base),
        reason: 'AdminScope embeds the currency',
      );
    });

    test('demo mode has its own stable identity', () {
      expect(dashboardShellIdentity(null), 'demo');
      expect(dashboardShellIdentity(null), dashboardShellIdentity(null));
      expect(
        dashboardShellIdentity(null),
        isNot(dashboardShellIdentity(member())),
      );
    });

    testWidgets('a changed identity DISPOSES the old State and rebuilds its '
        'scope-bearing fields', (tester) async {
      // The property that matters is not the string — it is that Flutter
      // actually tears the State down. A StatefulWidget whose State records
      // its construction stands in for the shell's `late final` repositories:
      // if the State survives, so would a stale repository.
      final built = <String>[];

      Widget app(String identity) => MaterialApp(
        home: _ScopeProbe(
          key: ValueKey(identity),
          onInit: built.add,
          identity: identity,
        ),
      );

      await tester.pumpWidget(app('org-1|owner'));
      await tester.pumpAndSettle();
      expect(built, ['org-1|owner']);

      // Same identity, rebuilt widget: the State (and its repositories) are
      // reused, which is exactly what we want for ordinary rebuilds.
      await tester.pumpWidget(app('org-1|owner'));
      await tester.pumpAndSettle();
      expect(built, ['org-1|owner'], reason: 'no needless teardown');

      // Different membership identity: the State must be recreated.
      await tester.pumpWidget(app('org-2|owner'));
      await tester.pumpAndSettle();
      expect(built, [
        'org-1|owner',
        'org-2|owner',
      ], reason: 'a membership change must rebuild the scope-bearing State');
    });
  });
  group('H. leaving a WRITING tab refreshes only what that tab writes', () {
    Future<_CountingDevices> pumpShell(WidgetTester tester) async {
      final devices = _CountingDevices();
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // The SHELL overrides the repository seam from its own `late final`
      // field, so a test must supply the repository the way the shell really
      // gets it — an outer override would simply be shadowed.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: DashboardShell(
              membership: const MembershipContext(
                id: 'm-1',
                organizationId: 'org-1',
                organizationName: 'Org',
                restaurantId: 'rest-1',
                restaurantName: 'Rest',
                branchId: 'branch-1',
                branchName: 'Main',
                role: MembershipRole.orgOwner,
                status: 'active',
              ),
              deviceRepositoryFor: (_) => devices,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return devices;
    }

    Future<void> goTo(WidgetTester tester, DashboardDestination d) async {
      tester
          .widget<NavigationBar>(find.byKey(const Key('dashboard-bottom-nav')))
          .onDestinationSelected!(d.tabIndex);
      await tester.pumpAndSettle();
    }

    // NOTE: there is deliberately no "Devices -> Overview reloads" test in THIS
    // group. The obvious one is CONFOUNDED: the Devices screen calls
    // loadDevices() itself, so this repository counter rises whether or not the
    // Overview's cached entry was invalidated, and such a test passes with the
    // fix reverted. Groups K/L/M below close that gap with counters only the
    // canonical setup PROVIDERS can move.

    testWidgets('Overview -> Orders -> Overview reloads NOTHING', (
      tester,
    ) async {
      final devices = await pumpShell(tester);
      final afterFirstMount = devices.loadDevicesCalls;

      await goTo(tester, DashboardDestination.orders);
      // Prove the switch really happened before asserting about caching.
      expect(find.byKey(const Key('reports-heading')), findsNothing);
      await goTo(tester, DashboardDestination.overview);
      expect(find.byKey(const Key('reports-heading')), findsOneWidget);

      expect(
        devices.loadDevicesCalls,
        afterFirstMount,
        reason: 'Orders cannot write setup data, so the count stays cached',
      );
    });
  });

  // =========================================================================
  // I. PERMISSION DOWNGRADE — the ValueKey, not just the SetupScopeKey
  // =========================================================================
  group('I. a membership change rebuilds the scope-bearing repositories', () {
    MembershipContext member({
      String id = 'm-1',
      String org = 'org-1',
      MembershipRole role = MembershipRole.orgOwner,
    }) => MembershipContext(
      id: id,
      organizationId: org,
      organizationName: 'Org',
      restaurantId: 'rest-1',
      restaurantName: 'Rest',
      branchId: 'branch-1',
      branchName: 'Main',
      role: role,
      status: 'active',
    );

    /// Mirrors what main.dart does: the shell carries a membership-derived key.
    Widget app(
      MembershipContext membership,
      List<AdminScope> built,
      _CountingDevices devices, {
      bool withKey = true,
    }) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        theme: restoflowBaseTheme(),
        home: DashboardShell(
          key: withKey
              ? ValueKey(dashboardShellIdentity(membership))
              : const ValueKey('fixed'),
          membership: membership,
          deviceRepositoryFor: (scope) {
            built.add(scope);
            return devices;
          },
        ),
      ),
    );

    testWidgets('a downgraded role rebuilds the repository for the new scope', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final built = <AdminScope>[];
      final devices = _CountingDevices();

      await tester.pumpWidget(app(member(), built, devices));
      await tester.pumpAndSettle();
      expect(built, hasLength(1), reason: 'the owner scope was built once');

      // A rebuild with the SAME membership must not churn.
      await tester.pumpWidget(app(member(), built, devices));
      await tester.pumpAndSettle();
      expect(built, hasLength(1), reason: 'no needless repository rebuild');

      // Downgrade the role: the repository was constructed for the OLD
      // authority, so the State must be disposed and it must be rebuilt.
      await tester.pumpWidget(
        app(member(role: MembershipRole.cashier), built, devices),
      );
      await tester.pumpAndSettle();
      expect(
        built,
        hasLength(2),
        reason: 'a weaker membership must not keep owner-scoped repositories',
      );
    });

    testWidgets('a different organization rebuilds the repository', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final built = <AdminScope>[];
      final devices = _CountingDevices();

      await tester.pumpWidget(app(member(), built, devices));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(member(org: 'org-2'), built, devices));
      await tester.pumpAndSettle();

      expect(built, hasLength(2));
      expect(
        built.last.organizationId,
        'org-2',
        reason: 'the new repository must be scoped to the NEW tenant',
      );
    });
  });

  // =========================================================================
  // J. NO DESTINATION RETENTION WAS INTRODUCED
  // =========================================================================
  group('J. the destination lifecycle is unchanged', () {
    testWidgets('leaving a destination really does destroy its subtree', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: const DashboardShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reports-heading')), findsOneWidget);

      tester
          .widget<NavigationBar>(find.byKey(const Key('dashboard-bottom-nav')))
          .onDestinationSelected!(DashboardDestination.orders.tabIndex);
      await tester.pumpAndSettle();

      // If V2.1 had introduced Offstage/IndexedStack retention, the Overview
      // heading would still be in the tree. It must not be: the poller and
      // drill-down contracts both depend on destinations really going away.
      expect(
        find.byKey(const Key('reports-heading')),
        findsNothing,
        reason: 'no destination retention may have been introduced',
      );
      // Deliberately NOT asserting on Offstage/IndexedStack types: Material's
      // own NavigationBar builds both, so those assertions would be about
      // Flutter rather than about us (they fail on an untouched tree). The
      // destroyed subtree above IS the evidence — a retained destination could
      // not satisfy it, and the poller and drill-down contracts both rest on
      // exactly that teardown.
    });
  });

  // =========================================================================
  // K/L/M. THE LEAVE-WRITER INVALIDATION, MEASURED ON THE PROVIDER
  //
  // The first attempt at leave-writer invalidation resolved its container with
  // `ProviderScope.containerOf` on the SHELL STATE's context. The shell's
  // override ProviderScope is something `build` RETURNS, so that context sits
  // ABOVE it: the lookup found the ROOT container, where the repository seams
  // are null, the membership is null, and the computed SetupScopeKey is a
  // different (all-null) key. Every invalidation landed on an entry no surface
  // watches. It ran, it threw nothing, and it did nothing.
  //
  // Nothing in group H could see that, because the only counter available
  // there is the repository's — and the Devices screen calls the very same
  // repository on the very same instance. These groups measure the CANONICAL
  // PROVIDER instead, which only the Overview's read model touches.
  // =========================================================================

  /// Counts COMPLETED evaluations of ONE canonical setup provider.
  ///
  /// Deliberately not a repository counter. `loadDevices()` is called by the
  /// Devices screen as well as by the setup provider, on the same instance, so
  /// its count rises on any visit to that tab and cannot distinguish a working
  /// invalidation from an inert one. This subscribes to the provider entry the
  /// Overview reads, in the container the shell built, and counts the settled
  /// values it produces: one per completed evaluation.
  ///
  /// SETTLED, not merely `AsyncData`. Riverpod re-emits the PREVIOUS value as
  /// an `AsyncData` carrying `isLoading: true` the moment an entry is
  /// invalidated — that is what keeps a refreshing card showing its old figure
  /// instead of flashing a skeleton. Counting those would double every
  /// refetch and turn "exactly one reload" into an unfalsifiable number.
  int Function() countEvaluations<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
  ) {
    var count = 0;
    final sub = container.listen<AsyncValue<T>>(provider, (_, next) {
      if (next is AsyncData<T> && !next.isLoading) count++;
    }, fireImmediately: true);
    addTearDown(sub.close);
    return () => count;
  }

  group('K. the invalidation path runs INSIDE the overridden scope', () {
    testWidgets('it resolves the shell\'s repositories, membership and key — '
        'not the root container\'s', (tester) async {
      final devices = _CountingDevices();
      final printers = InMemoryPrintersStore();
      final staff = InMemoryStaffStore();
      WidgetRef? used;

      await _pumpShell(
        tester,
        devices: devices,
        printers: printers,
        staff: staff,
        onInvalidation: (ref) => used = ref,
      );

      final overviewKey = _shellContainer(
        tester,
      ).read(currentSetupScopeKeyProvider);

      // Any navigation exercises the path; leaving Overview invalidates
      // nothing, which is exactly why this test asks WHERE it ran rather than
      // what it invalidated.
      await _goTo(tester, DashboardDestination.devices);

      expect(used, isNotNull, reason: 'the invalidation path must have run');
      final ref = used!;
      expect(
        ref.read(setupDevicesRepositoryProvider),
        same(devices),
        reason: 'the path must see the SHELL-injected repository, not null',
      );
      expect(
        ref.read(setupPrintersRepositoryProvider),
        same(printers),
        reason: 'every setup seam resolves through the same overrides',
      );
      expect(ref.read(setupStaffRepositoryProvider), same(staff));
      expect(
        ref.read(dashboardMembershipProvider)?.id,
        'm-1',
        reason: 'the membership the shell published, not the root default',
      );
      expect(
        ref.read(currentSetupScopeKeyProvider),
        overviewKey,
        reason: 'the invalidated key must be the key Overview watches',
      );

      // And, for the record, what the OLD lookup found. `containerOf` on the
      // shell element resolves above the shell's own ProviderScope, so the
      // previous implementation read every one of these instead.
      final rootContainer = ProviderScope.containerOf(
        tester.element(find.byType(DashboardShell)),
      );
      expect(
        rootContainer.read(setupDevicesRepositoryProvider),
        isNull,
        reason: 'documents the inert lookup: the root has no repository',
      );
      expect(rootContainer.read(dashboardMembershipProvider), isNull);
      expect(
        rootContainer.read(currentSetupScopeKeyProvider),
        isNot(overviewKey),
        reason: 'the root key is a scope nothing on screen is watching',
      );
    });
  });

  group('L. leaving Devices refetches the canonical device read model', () {
    testWidgets('exactly one extra evaluation, and the Overview shows it', (
      tester,
    ) async {
      final devices = _CountingDevices();
      await _pumpShell(
        tester,
        devices: devices,
        printers: InMemoryPrintersStore(),
        staff: InMemoryStaffStore(),
      );

      final container = _shellContainer(tester);
      final key = container.read(currentSetupScopeKeyProvider);
      final deviceEvals = countEvaluations(
        container,
        setupDevicesProvider(key),
      );

      // 1-2. The Overview is up and the canonical entry has resolved once.
      expect(deviceEvals(), 1, reason: 'first mount evaluates it once');
      expect(
        find.descendant(
          of: find.byKey(const Key('setup-stat-devices')),
          matching: find.text('1/1'),
        ),
        findsOneWidget,
      );

      // 3-4. Go to Devices, and prove the destination really changed.
      await _goTo(tester, DashboardDestination.devices);
      expect(find.byKey(const Key('reports-heading')), findsNothing);
      expect(find.byType(AdminDevicesScreen), findsOneWidget);
      expect(
        deviceEvals(),
        1,
        reason: 'ARRIVING at a writer must not refetch the read model',
      );

      // A device is created on that tab. The read model is now stale, and the
      // whole point of the invalidation is that the owner is never shown it.
      devices.devices = const [
        AdminDevice(
          id: 'd-1',
          label: 'Counter POS',
          deviceType: 'pos',
          branchLabel: 'Main',
          status: DeviceLifecycleStatus.active,
        ),
        AdminDevice(
          id: 'd-2',
          label: 'Kitchen display',
          deviceType: 'kds',
          branchLabel: 'Main',
          status: DeviceLifecycleStatus.active,
        ),
      ];

      // 5-6. Leave the writer.
      await _goTo(tester, DashboardDestination.overview);
      expect(find.byKey(const Key('reports-heading')), findsOneWidget);
      expect(
        deviceEvals(),
        2,
        reason: 'leaving the Devices tab costs exactly ONE refetch',
      );

      // 7. And the Overview renders the refreshed value, which is the whole
      // reason the refetch exists.
      expect(
        find.descendant(
          of: find.byKey(const Key('setup-stat-devices')),
          matching: find.text('2/2'),
        ),
        findsOneWidget,
        reason: 'the readiness strip must show the device that was just added',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('setup-stat-devices')),
          matching: find.text('1/1'),
        ),
        findsNothing,
        reason: 'the stale count must be gone, not merely joined',
      );
    });
  });

  group('M. leaving Printers refetches ONLY the printer read model', () {
    testWidgets(
      'the matching provider evaluates once more; the others do not',
      (tester) async {
        await _pumpShell(
          tester,
          devices: _CountingDevices(),
          printers: InMemoryPrintersStore(),
          staff: InMemoryStaffStore(),
        );

        final container = _shellContainer(tester);
        final key = container.read(currentSetupScopeKeyProvider);
        final printerEvals = countEvaluations(
          container,
          setupPrintersProvider(key),
        );
        final deviceEvals = countEvaluations(
          container,
          setupDevicesProvider(key),
        );
        final staffEvals = countEvaluations(container, setupStaffProvider(key));
        final menuEvals = countEvaluations(container, setupMenuProvider(key));

        expect(printerEvals(), 1);
        expect(deviceEvals(), 1);
        expect(staffEvals(), 1);
        expect(menuEvals(), 1);

        await _goTo(tester, DashboardDestination.printers);
        expect(find.byKey(const Key('reports-heading')), findsNothing);
        expect(find.byType(PrintersScreen), findsOneWidget);

        await _goTo(tester, DashboardDestination.overview);
        expect(find.byKey(const Key('reports-heading')), findsOneWidget);

        expect(
          printerEvals(),
          2,
          reason: 'the printer read model refreshes exactly once',
        );
        expect(
          deviceEvals(),
          1,
          reason: 'a printer edit cannot change the device counts',
        );
        expect(staffEvals(), 1);
        expect(
          menuEvals(),
          1,
          reason: 'invalidation is per-source, never a wipe of the whole panel',
        );
      },
    );
  });
}

/// Pumps the shell the way `main.dart` does — the repositories go in through
/// the constructor, so the ProviderScope under test is the shell's OWN.
Future<void> _pumpShell(
  WidgetTester tester, {
  required _CountingDevices devices,
  required PrintersRepository printers,
  required StaffRepository staff,
  void Function(WidgetRef ref)? onInvalidation,
}) async {
  // DESKTOP rail width, not the phone width the older groups use. These are
  // the only V2.1 tests that actually OPEN the Devices and Printers
  // destinations, and both of those screens have long-standing horizontal
  // overflows below ~560 that have nothing to do with navigation caching.
  // Measuring the invalidation is the wrong place to discover an unrelated
  // layout defect, and a worse place to absorb one; 1280 is also the width the
  // manual pass drives.
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        theme: restoflowBaseTheme(),
        home: DashboardShell(
          membership: const MembershipContext(
            id: 'm-1',
            organizationId: 'org-1',
            organizationName: 'Org',
            restaurantId: 'rest-1',
            restaurantName: 'Rest',
            branchId: 'branch-1',
            branchName: 'Main',
            role: MembershipRole.orgOwner,
            status: 'active',
          ),
          deviceRepositoryFor: (_) => devices,
          printersRepository: printers,
          staffRepository: staff,
          debugOnSetupInvalidation: onInvalidation,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The container the SHELL built, reached from a widget below its
/// ProviderScope. This is where the Overview's read models live — and it is
/// the container the previous invalidation never found.
ProviderContainer _shellContainer(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byKey(const Key('dashboard-side-rail'))),
    );

/// Navigates by TAPPING the rail rather than by invoking the shell's callback
/// directly, so the route under test is the one an owner actually takes.
///
/// Found by icon within the rail: the target destination is by definition not
/// the selected one, so it is showing its OUTLINED variant — and an icon does
/// not move when a translation does.
Future<void> _goTo(
  WidgetTester tester,
  DashboardDestination destination,
) async {
  const icons = {
    DashboardDestination.overview: Icons.dashboard_outlined,
    DashboardDestination.menu: Icons.restaurant_menu_outlined,
    DashboardDestination.devices: Icons.devices_outlined,
    DashboardDestination.printers: Icons.print_outlined,
    DashboardDestination.staff: Icons.badge_outlined,
  };
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('dashboard-side-rail')),
      matching: find.byIcon(icons[destination]!),
    ),
  );
  await tester.pumpAndSettle();
}

/// Stands in for the shell's scope-bearing State: it records every time its
/// State is constructed, which is precisely when `late final` repositories
/// would be rebuilt.
class _ScopeProbe extends StatefulWidget {
  const _ScopeProbe({required this.identity, required this.onInit, super.key});

  final String identity;
  final void Function(String) onInit;

  @override
  State<_ScopeProbe> createState() => _ScopeProbeState();
}

class _ScopeProbeState extends State<_ScopeProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit(widget.identity);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
