import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kiosk/main.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_activation.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';

const _valid = <String, Object>{
  'ok': true,
  'device_id': 'd',
  'device_session_id': 's',
  'organization_id': 'o',
  'restaurant_id': 'r',
  'branch_id': 'b',
  'device_type': 'kiosk',
};

class _Wire implements SyncRpcTransport {
  bool malformed = true;
  bool holdNextRestore = false;
  int restores = 0;
  int menus = 0;
  final slowRestore = Completer<Object?>();
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'kiosk_menu') {
      menus++;
      return {'ok': true, 'categories': <Object>[], 'items': <Object>[]};
    }
    if (function == 'restore_device_session') {
      restores++;
      if (holdNextRestore) {
        holdNextRestore = false;
        return slowRestore.future;
      }
    }
    return malformed ? {'ok': true} : _valid;
  }
}

class _LiveMenu extends ConsumerStatefulWidget {
  const _LiveMenu();
  @override
  ConsumerState<_LiveMenu> createState() => _LiveMenuState();
}

class _LiveMenuState extends ConsumerState<_LiveMenu> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(kioskLiveProvider.notifier).loadMenu());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kioskLiveProvider);
    return Text(state.menu != null ? 'live menu loaded' : 'loading live menu');
  }
}

Future<
  (
    ProviderContainer,
    SupabaseDevicePairingRepository,
    InMemoryDeviceSessionSecretStore,
  )
>
_mount(WidgetTester tester, _Wire wire, VoidCallback activated) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = InMemoryDeviceSessionSecretStore();
  await store.write(
    const DeviceSessionCredential(deviceId: 'd', sessionToken: 'token'),
  );
  final transport = DeviceSessionGuardedTransport(wire);
  final repo = SupabaseDevicePairingRepository(
    transport: transport,
    secretStore: store,
  );
  final container = ProviderContainer(
    overrides: [
      kioskLiveReadsProvider.overrideWithValue(
        KioskLiveReads(transport: transport, secretStore: store),
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: KioskApp(
        heartbeatManager: repo,
        home: KioskPairingGate(
          outcomes: repo,
          pairing: repo,
          shellBuilder: (_) => const _LiveMenu(),
          onActivated: (context) {
            activated();
            container.read(kioskDeviceContextProvider.notifier).state = context;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, repo, store);
}

void main() {
  testWidgets(
    'K1 real cold Retry superseded by heartbeat restore enters live menu before slow reply',
    (tester) async {
      final wire = _Wire();
      var activations = 0;
      final (container, repo, store) = await _mount(
        tester,
        wire,
        () => activations++,
      );
      expect(wire.restores, 2);
      expect(repo.activeDevice, isNull);
      expect(repo.protectedCallsBlocked, isTrue);
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      wire.holdNextRestore = true;
      await tester.tap(find.byKey(const Key('device-session-retry')));
      await tester.pump();
      await tester.pump();
      expect(wire.restores, 3);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      wire.malformed = false;
      await tester.pump(const Duration(seconds: 60));
      // Bounded pumps keep the original stuck-spinner defect a direct assertion
      // failure rather than a pumpAndSettle timeout.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(wire.restores, 4);
      expect(repo.protectedCallsBlocked, isFalse);
      expect(container.read(kioskDeviceContextProvider), isNotNull);
      expect(find.text('live menu loaded'), findsOneWidget);
      expect(wire.menus, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(activations, 1);
      wire.slowRestore.complete(_valid);
      await tester.pumpAndSettle();
      expect(
        wire.restores,
        4,
        reason: 'the older superseded reply cannot restart the gate',
      );
      expect(wire.menus, 1);
      expect(activations, 1);
      expect(find.text('live menu loaded'), findsOneWidget);
      expect(await store.read(), isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'K1 successful gate publication activates once without re-entering restoring listener',
    (tester) async {
      final wire = _Wire()..malformed = false;
      var activations = 0;
      await _mount(tester, wire, () => activations++);
      expect(activations, 1);
      expect(wire.menus, 1);
      expect(find.text('live menu loaded'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
