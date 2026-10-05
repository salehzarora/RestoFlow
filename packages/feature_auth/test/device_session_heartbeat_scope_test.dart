import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _device = DeviceContext(
  organizationId: 'org',
  branchId: 'branch',
  restaurantId: 'restaurant',
  deviceId: 'device',
  deviceType: 'pos',
  deviceSessionId: 'session',
);

class _Manager implements DeviceSessionHeartbeatManager {
  final changes = StreamController<DeviceSessionChange>.broadcast();
  @override
  DeviceContext? activeDevice;
  DeviceHeartbeatResult result = DeviceHeartbeatResult.active;
  int calls = 0;
  @override
  Stream<DeviceSessionChange> get sessionChanges => changes.stream;
  @override
  Future<DeviceHeartbeatResult> heartbeat() async {
    calls++;
    return result;
  }

  void change(DeviceContext? device, {bool invalid = false}) {
    activeDevice = device;
    changes.add(DeviceSessionChange(device, invalidSession: invalid));
  }
}

class _Cart extends StatefulWidget {
  const _Cart();
  @override
  State<_Cart> createState() => _CartState();
}

class _CartState extends State<_Cart> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      key: const Key('cart'),
      onPressed: () => setState(() => count++),
      child: Text('cart $count'),
    ),
  );
}

class _RestoreWire implements SyncRpcTransport {
  bool malformed = false;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (malformed && function == 'restore_device_session') return {'ok': true};
    return {
      'ok': true,
      'device_id': 'device',
      'device_session_id': 'session',
      'organization_id': 'org',
      'restaurant_id': 'restaurant',
      'branch_id': 'branch',
      'device_type': 'pos',
    };
  }
}

Widget _app(
  DeviceSessionHeartbeatManager manager, {
  VoidCallback? invalid,
  ValueChanged<DeviceContext>? restored,
}) => DeviceSessionAppHost(
  manager: manager,
  onInvalidSession: invalid ?? () {},
  onRestored: restored ?? (_) {},
  buildApp: (navigatorKey, sessionBuilder) => MaterialApp(
    navigatorKey: navigatorKey,
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const _Cart(),
    builder: sessionBuilder,
  ),
);
void main() {
  testWidgets(
    'unknown restore gates existing dialog and retries without replacing navigator or cart',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: 'device',
          sessionToken: 'token',
        ),
      );
      final wire = _RestoreWire();
      final repo = SupabaseDevicePairingRepository(
        transport: DeviceSessionGuardedTransport(wire),
        secretStore: store,
      );
      await repo.restoreOutcome(expectedDeviceType: 'pos');
      var restored = 0;
      await tester.pumpWidget(_app(repo, restored: (_) => restored++));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cart')));
      await tester.pump();
      final cart = tester.state(find.byType(_Cart));
      final cartContext = tester.element(find.byType(_Cart));
      unawaited(
        showDialog<void>(
          context: cartContext,
          builder: (_) => const AlertDialog(title: Text('protected dialog')),
        ),
      );
      await tester.pumpAndSettle();
      wire.malformed = true;
      await repo.restoreOutcome(expectedDeviceType: 'pos');
      await tester.pumpAndSettle();
      expect(find.text('protected dialog'), findsNothing);
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      wire.malformed = false;
      await tester.tap(find.byKey(const Key('device-session-retry')));
      await tester.pumpAndSettle();
      expect(restored, 1);
      expect(find.text('protected dialog'), findsOneWidget);
      Navigator.of(cartContext).pop();
      await tester.pumpAndSettle();
      expect(find.text('cart 1'), findsOneWidget);
      expect(identical(tester.state(find.byType(_Cart)), cart), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('explicit invalidation removes an actual Navigator modal route', (
    tester,
  ) async {
    final manager = _Manager()..activeDevice = _device;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_app(manager));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(_Cart));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('protected dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('protected dialog'), findsOneWidget);
    manager.change(null, invalid: true);
    await tester.pumpAndSettle();
    expect(find.text('protected dialog'), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await manager.changes.close();
  });
  testWidgets(
    'startup, restore, foreground cadence and resume cancel correctly',
    (tester) async {
      final manager = _Manager();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_app(manager));
      await tester.pumpAndSettle();
      expect(manager.calls, 0);
      manager.change(_device);
      await tester.pumpAndSettle();
      expect(manager.calls, 1);
      await tester.pump(const Duration(minutes: 15));
      expect(manager.calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 45));
      expect(manager.calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(manager.calls, 3);
      manager.change(null);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 30));
      expect(manager.calls, 3);
      await tester.pumpWidget(const SizedBox());
      await manager.changes.close();
    },
  );
  testWidgets(
    'unknown hides protected navigator including dialogs; retry preserves cart',
    (tester) async {
      final manager = _Manager()..activeDevice = _device;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_app(manager));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cart')));
      await tester.pump();
      final cartState = tester.state(find.byType(_Cart));
      final cartContext = tester.element(find.byType(_Cart));
      unawaited(
        showDialog<void>(
          context: cartContext,
          builder: (_) => const AlertDialog(title: Text('protected dialog')),
        ),
      );
      await tester.pumpAndSettle();
      manager.result = DeviceHeartbeatResult.unavailable;
      await tester.pump(const Duration(minutes: 15));
      await tester.pumpAndSettle();
      expect(find.text('protected dialog'), findsNothing);
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      expect(find.byType(DevicePairingScreen), findsNothing);
      manager.result = DeviceHeartbeatResult.active;
      await tester.tap(find.byKey(const Key('device-session-retry')));
      await tester.pumpAndSettle();
      expect(find.text('protected dialog'), findsOneWidget);
      Navigator.of(cartContext).pop();
      await tester.pumpAndSettle();
      expect(find.text('cart 1'), findsOneWidget);
      expect(identical(tester.state(find.byType(_Cart)), cartState), isTrue);
      await tester.pumpWidget(const SizedBox());
      await manager.changes.close();
    },
  );
  testWidgets(
    'unsupported RPC keeps existing usable app and still retries later',
    (tester) async {
      final manager = _Manager()
        ..activeDevice = _device
        ..result = DeviceHeartbeatResult.unsupported;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_app(manager));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cart')), findsOneWidget);
      expect(manager.calls, 1);
      await tester.pump(const Duration(minutes: 15));
      await tester.pumpAndSettle();
      expect(manager.calls, 2);
      expect(find.byType(DeviceSessionUnavailableView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await manager.changes.close();
    },
  );
  testWidgets(
    'explicit stream rejection ends the app session once and stops heartbeat',
    (tester) async {
      var invalid = 0;
      final manager = _Manager()..activeDevice = _device;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_app(manager, invalid: () => invalid++));
      await tester.pumpAndSettle();
      manager.change(null, invalid: true);
      await tester.pumpAndSettle();
      expect(invalid, 1);
      await tester.pump(const Duration(minutes: 30));
      expect(manager.calls, 1);
      await tester.pumpWidget(const SizedBox());
      await manager.changes.close();
    },
  );
}
