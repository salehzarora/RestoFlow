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
import 'package:restoflow_dashboard/src/setup/device_summary_card.dart';
import 'package:restoflow_dashboard/src/setup/setup_center.dart';
import 'package:restoflow_dashboard/src/state/setup_device_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Counts every call. One instance stands in for the single repository the
/// shell hands to both surfaces.
class _CountingDevices extends DemoAdminStore {
  _CountingDevices() : super(scope: AdminScope.demo);

  int loadDevicesCalls = 0;

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async {
    loadDevicesCalls++;
    return Success(const [
      AdminDevice(
        id: 'd-1',
        label: 'Counter POS',
        deviceType: 'pos',
        branchLabel: 'Main',
        status: DeviceLifecycleStatus.active,
      ),
    ]);
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

    // NOTE: there is deliberately no "Devices -> Overview reloads" test here.
    // The obvious one is CONFOUNDED: the Devices screen calls loadDevices()
    // itself, so the counter rises whether or not the Overview's cached entry
    // was invalidated, and the test passes with the fix reverted. Proving the
    // invalidation needs a counter that only the setup provider increments —
    // written up as the remaining V2.1 gap rather than left here looking green.

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
