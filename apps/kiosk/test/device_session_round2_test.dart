import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/main.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_activation.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _Wire implements SyncRpcTransport {
  int restores = 0, menus = 0;
  bool malformed = false;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'kiosk_menu') {
      menus++;
      return {'ok': false, 'error': 'invalid_session'};
    }
    restores++;
    if (malformed) return {'ok': true};
    return {
      'ok': true,
      'device_id': 'd',
      'device_session_id': 's',
      'organization_id': 'o',
      'restaurant_id': 'r',
      'branch_id': 'b',
      'device_type': 'kiosk',
    };
  }
}

class _Superseded
    implements DeviceSessionOutcomeManager, DevicePairingRepository {
  @override
  Future<DeviceContext?> restore({String? expectedDeviceType}) async => null;
  @override
  Future<void> unpair() async {}
  @override
  Future<DeviceRestoreOutcome> restoreOutcome({
    String? expectedDeviceType,
  }) async => const DeviceSessionRestoreSuperseded();
  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async => const Failure(PairingFailure(PairingFailureKind.unknown));
}

class _Menu extends ConsumerStatefulWidget {
  const _Menu();
  @override
  ConsumerState<_Menu> createState() => _MenuState();
}

class _MenuState extends ConsumerState<_Menu> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(kioskLiveProvider.notifier).loadMenu());
    });
  }

  @override
  Widget build(BuildContext context) => const Text('customer menu');
}

void main() {
  testWidgets(
    'H3 Kiosk ignores superseded cold restore without changing gate verdict',
    (tester) async {
      final repo = _Superseded();
      await tester.pumpWidget(
        ProviderScope(
          child: KioskApp(
            home: KioskPairingGate(
              outcomes: repo,
              pairing: repo,
              shellBuilder: (_) => const Text('customer menu'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(DeviceSessionUnavailableView), findsNothing);
      expect(find.byKey(const Key('kiosk-activation-code')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'H5 actual Kiosk local repair shows neutral notice on activation scaffold',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'd', sessionToken: 't'),
      );
      final wire = _Wire()..malformed = true;
      final repo = SupabaseDevicePairingRepository(
        transport: wire,
        secretStore: store,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        ProviderScope(
          child: KioskApp(
            heartbeatManager: repo,
            home: KioskPairingGate(
              outcomes: repo,
              pairing: repo,
              shellBuilder: (_) => const Text('customer menu'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(repo.consecutiveUnavailable, 3);
      expect(find.byKey(const Key('device-session-repair')), findsNothing);
      final title = find.byKey(const Key('device-session-unavailable-title'));
      final message = AppLocalizations.of(
        tester.element(title),
      ).deviceUnpairedSnack;
      final hold = await tester.startGesture(tester.getCenter(title));
      await tester.pump(const Duration(milliseconds: 5100));
      await hold.up();
      await tester.pump();
      await tester.tap(find.byKey(const Key('device-session-repair')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('kiosk-activation-code')), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(await store.read(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'G1 invalid kiosk menu after successful restore remains unavailable until Retry',
    (tester) async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'd', sessionToken: 't'),
      );
      final wire = _Wire();
      final repo = SupabaseDevicePairingRepository(
        transport: wire,
        secretStore: store,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kioskLiveReadsProvider.overrideWithValue(
              KioskLiveReads(transport: wire, secretStore: store),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: KioskPairingGate(
              outcomes: repo,
              pairing: repo,
              shellBuilder: (_) => const _Menu(),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(wire.restores, 1);
      expect(wire.menus, 1);
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KioskPairingGate)),
      );
      container.read(kioskDeviceContextProvider.notifier).state =
          repo.activeDevice;
      await tester.pump();
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      expect(wire.restores, 1);
      expect(wire.menus, 1);
      await tester.tap(find.byKey(const Key('device-session-retry')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(wire.restores, 2);
      expect(wire.menus, 2);
      expect(find.byType(DeviceSessionUnavailableView), findsOneWidget);
      expect(await store.read(), isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
