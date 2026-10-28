import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/secure_session_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/media/background_order_alert_bridge.dart';
import 'package:restoflow_pos/src/state/background_alert_delegation.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';

const _device = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'device-session-1',
  deviceType: 'pos',
);

class _Transport implements SyncRpcTransport {
  Future<Object?> Function()? nextSignIn;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') {
      return nextSignIn == null ? 'pin-session-1' : nextSignIn!();
    }
    return null; // No shift/order operation applies in this synthetic harness.
  }
}

class _Store extends PosSecureSessionStore {
  final records = <PosSyncScope, PosStoredPinSession>{};
  @override
  Future<void> save(PosSyncScope scope, PosStoredPinSession record) async =>
      records[scope] = record;
  @override
  Future<PosStoredPinSession?> read(PosSyncScope scope) async => records[scope];
  @override
  Future<void> clear(PosSyncScope scope) async => records.remove(scope);
}

class _Bridge
    implements
        BackgroundOrderAlertBridge,
        BackgroundOrderAlertInactivityRetention,
        BackgroundOrderAlertReasonedRevocation {
  final retained = <String>[];
  final revoked = <BackgroundAlertRevocationReason>[];
  Completer<bool>? retention;
  bool retainResult = true;
  String? boundIdentity;

  @override
  Future<bool> retainForInactivity(String identity) {
    retained.add(identity);
    return retention?.future ?? Future.value(retainResult);
  }

  @override
  Future<bool> revokeForReason(
    BackgroundAlertRevocationReason reason, {
    bool suspend = false,
    bool retainOptIn = false,
  }) async {
    revoked.add(reason);
    boundIdentity = null;
    return true;
  }

  @override
  Future<void> disable() async =>
      revoked.add(BackgroundAlertRevocationReason.securityFailure);
  @override
  Future<void> suspend({bool retainOptIn = false}) async {}
  @override
  Future<Map<String, dynamic>> prepare({
    bool requestPermission = false,
  }) async => const {};
  @override
  Future<bool> bind(Map<String, dynamic> binding) async {
    boundIdentity = binding['identity'] as String?;
    return true;
  }

  @override
  Future<void> pending(Map<String, dynamic> snapshot) async {}
  @override
  Future<bool> consumeInboxTap() async => false;
  @override
  void setHints({
    required VoidCallback tokenChanged,
    required VoidCallback pendingHint,
  }) {}
  @override
  Future<void> dispose() async {}
}

Future<
  ({
    ProviderContainer container,
    PosSessionController session,
    _Bridge bridge,
    _Transport transport,
    _Store store,
  })
>
_signedIn(DateTime t0) async {
  final transport = _Transport();
  final bridge = _Bridge();
  final store = _Store();
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posRealSessionConfigProvider.overrideWithValue(null),
      posAuthTransportProvider.overrideWithValue(transport),
      backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
      posSecureSessionStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  container.read(posDeviceContextProvider.notifier).set(_device);
  final session = container.read(posSessionControllerProvider.notifier);
  await container.read(posSessionControllerProvider.future);
  session.clock = () => t0;
  expect(
    await session.signInWithPin(
      device: _device,
      deviceId: _device.deviceId!,
      deviceSessionId: _device.deviceSessionId!,
      employeeProfileId: 'employee-1',
      pin: 'synthetic',
    ),
    isNull,
  );
  container.read(backgroundOrderAlertBridgeProvider);
  await pumpEventQueue();
  bridge.revoked.clear();
  return (
    container: container,
    session: session,
    bridge: bridge,
    transport: transport,
    store: store,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime.utc(2026, 10, 28, 12);
  const policy = PinSessionExpiryPolicy();

  test('29:59 inactivity leaves UI session and delegation unchanged', () async {
    final h = await _signedIn(t0);
    h.session.noteAppPaused();
    h.session.clock = () => t0.add(const Duration(minutes: 29, seconds: 59));
    expect(h.session.endSessionIfExpired(policy), isFalse);
    expect(h.container.read(posSyncSessionProvider), isNotNull);
    expect(h.bridge.retained, isEmpty);
    expect(h.bridge.revoked, isEmpty);
    expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
  });

  test('30:00 resume locks synchronously, retaining only exact existing '
      'native delegation without a PIN or operational scope', () async {
    final h = await _signedIn(t0);
    final oldIdentity = h.container.read(onlineOrderInboxIdentityProvider);
    h.bridge.retention = Completer<bool>();
    h.session.noteAppPaused();
    h.session.clock = () => t0.add(const Duration(minutes: 30));
    expect(h.session.endSessionIfExpired(policy), isTrue);
    expect(h.container.read(posSyncSessionProvider), isNull);
    expect(h.container.read(posPinSessionBindingProvider), isNull);
    expect(h.container.read(posSyncScopeProvider), isNull);
    expect(h.container.read(onlineOrderInboxIdentityProvider), isNull);
    expect(h.container.read(posSignedInEmployeeProfileIdProvider), isNull);
    final pending = h.container.read(backgroundAlertInactivityLockProvider)!;
    expect(pending.identity, oldIdentity);
    expect(pending.nativeConfirmed, isFalse);
    expect(pending.validUntil, t0.add(const Duration(hours: 8)));
    expect(h.bridge.retained, [oldIdentity]);
    h.bridge.retention!.complete(true);
    await pumpEventQueue();
    expect(
      h.container.read(backgroundAlertInactivityLockProvider)!.nativeConfirmed,
      isTrue,
    );
    expect(h.bridge.revoked, isEmpty);
  });

  for (final paused in [false, true]) {
    test('8-hour absolute expiry wins with paused=$paused', () async {
      final h = await _signedIn(t0);
      if (paused) h.session.noteAppPaused();
      h.session.clock = () => t0.add(const Duration(hours: 8));
      expect(h.session.endSessionIfExpired(policy), isTrue);
      expect(h.container.read(posSyncSessionProvider), isNull);
      expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
      expect(h.bridge.retained, isEmpty);
      expect(h.bridge.revoked, [
        BackgroundAlertRevocationReason.authorityExpired,
      ]);
    });
  }

  test(
    'native refusal locks UI but fails closed without retained proof',
    () async {
      final h = await _signedIn(t0);
      h.bridge.retainResult = false;
      h.session.noteAppPaused();
      h.session.clock = () => t0.add(const Duration(minutes: 30));
      h.session.endSessionIfExpired(policy);
      await pumpEventQueue();
      expect(h.container.read(posSyncSessionProvider), isNull);
      expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
      expect(h.bridge.revoked, [
        BackgroundAlertRevocationReason.securityFailure,
      ]);
    },
  );

  test('explicit logout during retention prevents a delayed native response '
      'from reviving consent', () async {
    final h = await _signedIn(t0);
    h.bridge.retention = Completer<bool>();
    h.session.noteAppPaused();
    h.session.clock = () => t0.add(const Duration(minutes: 30));
    h.session.endSessionIfExpired(policy);
    h.session.endSession();
    h.bridge.retention!.complete(true);
    await pumpEventQueue();
    expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
    expect(h.bridge.revoked, [BackgroundAlertRevocationReason.explicitSignOut]);
    expect(h.container.read(posSyncSessionProvider), isNull);
  });

  test('disposed idle owner cannot revoke a fresh container binding when its '
      'older retention response arrives', () async {
    final h = await _signedIn(t0);
    h.bridge.retention = Completer<bool>();
    h.session.noteAppPaused();
    h.session.clock = () => t0.add(const Duration(minutes: 30));
    h.session.endSessionIfExpired(policy);
    expect(h.container.read(backgroundAlertInactivityLockProvider), isNotNull);
    h.container.dispose();

    // Both Dart containers share the same process-wide native bridge owner.
    // New authorized binding is synthetic here; the old continuation has no
    // authority over it after its own provider container has been destroyed.
    final replacement = ProviderContainer(
      overrides: [
        backgroundOrderAlertBridgeProvider.overrideWithValue(h.bridge),
      ],
    );
    addTearDown(replacement.dispose);
    expect(
      await replacement.read(backgroundOrderAlertBridgeProvider).bind({
        'identity': 'fresh-authorized-container-binding',
      }),
      isTrue,
    );
    h.bridge.retention!.complete(true);
    await pumpEventQueue();
    expect(h.bridge.boundIdentity, 'fresh-authorized-container-binding');
    expect(h.bridge.revoked, isEmpty);
  });

  test(
    'arbitrary caller cannot manufacture idle retention by reason enum',
    () async {
      final h = await _signedIn(t0);
      h.session.endSession(
        reason: BackgroundAlertRevocationReason.inactivityUiLock,
      );
      await pumpEventQueue();
      expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
      expect(h.bridge.retained, isEmpty);
      expect(h.bridge.revoked, [
        BackgroundAlertRevocationReason.securityFailure,
      ]);
    },
  );

  test(
    'new employee failed PIN clears old idle grant before authentication',
    () async {
      final h = await _signedIn(t0);
      h.session.noteAppPaused();
      h.session.clock = () => t0.add(const Duration(minutes: 30));
      h.session.endSessionIfExpired(policy);
      await pumpEventQueue();
      h.transport.nextSignIn = () async => null;
      expect(
        await h.session.signInWithPin(
          device: _device,
          deviceId: _device.deviceId!,
          deviceSessionId: _device.deviceSessionId!,
          employeeProfileId: 'different-employee',
          pin: 'wrong-synthetic',
        ),
        PinLoginError.wrongPin,
      );
      expect(h.container.read(posSyncSessionProvider), isNull);
      expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
      expect(h.bridge.revoked, [
        BackgroundAlertRevocationReason.identityOrPairingChanged,
      ]);
    },
  );

  test(
    'server auth refusal while PIN-locked still revokes retained grant',
    () async {
      final h = await _signedIn(t0);
      h.session.noteAppPaused();
      h.session.clock = () => t0.add(const Duration(minutes: 30));
      h.session.endSessionIfExpired(policy);
      await pumpEventQueue();
      h.session.handleServerAuthRefusal();
      expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
      expect(h.bridge.revoked, [
        BackgroundAlertRevocationReason.serverAuthRevoked,
      ]);
    },
  );

  test(
    'branch change removes proof and cannot confirm delayed retention',
    () async {
      final h = await _signedIn(t0);
      h.bridge.retention = Completer<bool>();
      h.session.noteAppPaused();
      h.session.clock = () => t0.add(const Duration(minutes: 30));
      h.session.endSessionIfExpired(policy);
      h.container
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org-1',
              restaurantId: 'rest-1',
              branchId: 'other-branch',
              deviceId: 'device-1',
              deviceSessionId: 'device-session-2',
              deviceType: 'pos',
            ),
          );
      h.bridge.retention!.complete(true);
      await pumpEventQueue();
      expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
      expect(
        h.bridge.revoked,
        contains(BackgroundAlertRevocationReason.identityOrPairingChanged),
      );
      expect(h.container.read(posSyncSessionProvider), isNull);
    },
  );

  test(
    'delayed PIN success after explicit logout cannot unlock the POS',
    () async {
      final h = await _signedIn(t0);
      h.session.endSession();
      final reply = Completer<Object?>();
      h.transport.nextSignIn = () => reply.future;
      final result = h.session.signInWithPin(
        device: _device,
        deviceId: _device.deviceId!,
        deviceSessionId: _device.deviceSessionId!,
        employeeProfileId: 'employee-1',
        pin: 'synthetic',
      );
      h.session.endSession();
      reply.complete('late-pin-session');
      expect(await result, PinLoginError.unavailable);
      expect(h.container.read(posSyncSessionProvider), isNull);
    },
  );

  test('explicit logout after idle lock still destroys the retained offline '
      'record even though privileged binding is already null', () async {
    final h = await _signedIn(t0);
    expect(h.store.records, hasLength(1));
    h.session.noteAppPaused();
    h.session.clock = () => t0.add(const Duration(minutes: 30));
    h.session.endSessionIfExpired(policy);
    await pumpEventQueue();
    expect(h.store.records, hasLength(1));
    expect(h.container.read(posPinSessionBindingProvider), isNull);
    h.session.endSession();
    await pumpEventQueue();
    expect(h.store.records, isEmpty);
  });

  test(
    'offline restoration alone cannot mint trusted native idle proof',
    () async {
      final h = await _signedIn(t0);
      h.session.endSession(clearStoredSession: false);
      expect(
        await h.session.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.restored,
      );
      h.bridge.revoked.clear();
      h.session.noteAppPaused();
      h.session.clock = () => t0.add(const Duration(minutes: 30));
      h.session.endSessionIfExpired(policy);
      await pumpEventQueue();
      expect(h.container.read(backgroundAlertInactivityLockProvider), isNull);
      expect(h.bridge.retained, isEmpty);
      expect(h.bridge.revoked, [
        BackgroundAlertRevocationReason.securityFailure,
      ]);
    },
  );

  test(
    'backward clock is a security failure rather than inferred inactivity',
    () async {
      final h = await _signedIn(t0);
      h.session.noteAppPaused();
      h.session.clock = () => t0.subtract(const Duration(seconds: 1));
      h.session.endSessionIfExpired(policy);
      await pumpEventQueue();
      expect(h.bridge.retained, isEmpty);
      expect(h.bridge.revoked, [
        BackgroundAlertRevocationReason.securityFailure,
      ]);
    },
  );
}
