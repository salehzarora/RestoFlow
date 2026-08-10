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
import 'package:restoflow_dashboard/src/setup/device_summary_card.dart';
import 'package:restoflow_dashboard/src/setup/setup_center.dart';
import 'package:restoflow_dashboard/src/state/setup_device_providers.dart';
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
}
