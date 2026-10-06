import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _device = DeviceContext(
  organizationId: 'o',
  restaurantId: 'r',
  branchId: 'b',
  deviceId: 'd',
  deviceSessionId: 's',
  deviceType: 'pos',
);

class _Manager
    implements
        DeviceSessionHeartbeatManager,
        DeviceSessionLocalRepairManager,
        DeviceSessionRecoveryManager {
  final changes = StreamController<DeviceSessionChange>.broadcast();
  final blocks = StreamController<bool>.broadcast();
  @override
  DeviceContext? activeDevice = _device;
  @override
  bool protectedCallsBlocked = true;
  @override
  int consecutiveUnavailable = 3;
  DeviceHeartbeatResult result = DeviceHeartbeatResult.unavailable;
  Completer<void>? clearing;
  bool failClear = false;
  int clears = 0;
  @override
  Stream<DeviceSessionChange> get sessionChanges => changes.stream;
  @override
  Stream<bool> get protectedCallBlockChanges => blocks.stream;
  @override
  Future<DeviceHeartbeatResult> heartbeat() async {
    if (result == DeviceHeartbeatResult.active) {
      consecutiveUnavailable = 0;
      block(false);
    } else if (result == DeviceHeartbeatResult.offline) {
      consecutiveUnavailable = 0;
    }
    return result;
  }

  void block(bool value) {
    if (value == protectedCallsBlocked) return;
    protectedCallsBlocked = value;
    blocks.add(value);
  }

  @override
  Future<void> clearLocalPairing() async {
    clears++;
    activeDevice = null;
    changes.add(const DeviceSessionChange(null));
    if (clearing != null) await clearing!.future;
    if (failClear) {
      activeDevice = _device;
      changes.add(const DeviceSessionChange(_device, unavailable: true));
      throw StateError('local storage unavailable');
    }
  }

  Future<void> dispose() async {
    await changes.close();
    await blocks.close();
  }
}

Widget _app(
  _Manager manager, {
  bool kiosk = false,
  VoidCallback? repaired,
  VoidCallback? invalid,
  VoidCallback? recovered,
}) => DeviceSessionAppHost(
  manager: manager,
  staffOnlyRepair: kiosk,
  onInvalidSession: invalid ?? () {},
  onLocalUnpair: repaired,
  onRecovered: recovered,
  onRestored: (_) {},
  buildApp: (key, builder) => MaterialApp(
    navigatorKey: key,
    builder: builder,
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: Text('live app')),
  ),
);
Future<void> _openRepair(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('device-session-repair')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('H5 mounted confirmation rechecks current unavailable counter', (
    tester,
  ) async {
    final manager = _Manager();
    var repaired = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: DeviceSessionUnavailableView(
          onRetry: () {},
          repairManager: manager,
          onRepaired: () => repaired++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openRepair(tester);
    manager.consecutiveUnavailable = 0;
    await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
    await tester.pumpAndSettle();
    expect(manager.clears, 0);
    expect(repaired, 0);
    await tester.pumpWidget(const SizedBox());
    await manager.dispose();
  });

  testWidgets(
    'H1 Kiosk repair remains hidden until full five second title hold',
    (tester) async {
      final manager = _Manager();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var repaired = 0;
      var invalid = 0;
      await tester.pumpWidget(
        _app(
          manager,
          kiosk: true,
          repaired: () => repaired++,
          invalid: () => invalid++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-session-repair')), findsNothing);
      final hold = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('device-session-unavailable-title')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 4900));
      expect(find.byKey(const Key('device-session-repair')), findsNothing);
      await tester.pump(const Duration(milliseconds: 101));
      await hold.up();
      await tester.pump();
      expect(find.byKey(const Key('device-session-repair')), findsOneWidget);
      await _openRepair(tester);
      expect(manager.clears, 0);
      await tester.tap(find.byKey(const Key('device-session-repair-cancel')));
      await tester.pumpAndSettle();
      expect(manager.clears, 0);
      await _openRepair(tester);
      await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
      await tester.pumpAndSettle();
      expect(manager.clears, 1);
      expect(repaired, 1);
      expect(invalid, 0, reason: 'local repair is not server rejection');
      expect(find.text('Device unpaired.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await manager.dispose();
    },
  );
  testWidgets(
    'H2 blocked offline keeps notice and recovery fires once for same session',
    (tester) async {
      final manager = _Manager();
      var recovered = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_app(manager, recovered: () => recovered++));
      await tester.pumpAndSettle();
      manager.result = DeviceHeartbeatResult.offline;
      await tester.tap(find.byKey(const Key('device-session-retry')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      expect(manager.protectedCallsBlocked, isTrue);
      expect(find.byKey(const Key('device-session-repair')), findsNothing);
      manager.result = DeviceHeartbeatResult.active;
      await tester.tap(find.byKey(const Key('device-session-retry')));
      await tester.pumpAndSettle();
      expect(recovered, 1);
      expect(find.byType(DeviceSessionUnavailableView), findsNothing);
      manager.changes.add(const DeviceSessionChange(_device));
      await tester.pumpAndSettle();
      expect(recovered, 1);
      manager.block(true);
      await tester.pump();
      manager.activeDevice = null;
      manager.changes.add(const DeviceSessionChange(null));
      manager.block(false);
      await tester.pumpAndSettle();
      expect(recovered, 1, reason: 'unpair is not recovery');
      await tester.pumpWidget(const SizedBox());
      await manager.dispose();
    },
  );
  testWidgets('H5 confirmation aborts if session recovered while dialog open', (
    tester,
  ) async {
    final manager = _Manager();
    var repaired = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_app(manager, repaired: () => repaired++));
    await tester.pumpAndSettle();
    await _openRepair(tester);
    manager.result = DeviceHeartbeatResult.active;
    await tester.tap(find.byKey(const Key('device-session-retry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
    await tester.pumpAndSettle();
    expect(manager.clears, 0);
    expect(repaired, 0);
    expect(find.text('live app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await manager.dispose();
  });
  testWidgets(
    'H5 clear failure stays visible and next valid heartbeat recovers',
    (tester) async {
      final manager = _Manager()
        ..failClear = true
        ..clearing = Completer<void>();
      var repaired = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_app(manager, repaired: () => repaired++));
      await tester.pumpAndSettle();
      await _openRepair(tester);
      await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
      await tester.pump();
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      manager.clearing!.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('device-session-repair-error')),
        findsOneWidget,
      );
      expect(repaired, 0);
      expect(manager.activeDevice, _device);
      expect(tester.takeException(), isNull);
      manager.result = DeviceHeartbeatResult.active;
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceSessionUnavailableView), findsNothing);
      expect(find.text('live app'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await manager.dispose();
    },
  );
  testWidgets('H5 clearing completion after unmount has no UI callback', (
    tester,
  ) async {
    final manager = _Manager()..clearing = Completer<void>();
    var repaired = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: DeviceSessionUnavailableView(
          onRetry: () {},
          repairManager: manager,
          onRepaired: () => repaired++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openRepair(tester);
    await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    manager.clearing!.complete();
    await tester.pump();
    expect(repaired, 0);
    expect(tester.takeException(), isNull);
    await manager.dispose();
  });
}
