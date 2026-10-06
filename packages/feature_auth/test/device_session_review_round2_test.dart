import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

const _credential = DeviceSessionCredential(
  deviceId: 'device',
  sessionToken: 'token',
);
Map<String, Object?> _ok() => {
  'ok': true,
  'device_id': 'device',
  'device_session_id': 'session',
  'organization_id': 'org',
  'restaurant_id': 'restaurant',
  'branch_id': 'branch',
  'device_type': 'pos',
};

class _Store extends InMemoryDeviceSessionSecretStore {
  bool failClear = false;
  bool failAfterClear = false;
  bool failWrite = false;
  Completer<void>? clearCacheEntered;
  Completer<void>? clearCacheRelease;
  Completer<DeviceContext?>? cacheRead;
  Completer<void>? cacheEntered;
  @override
  Future<void> clear() async {
    if (failClear) throw StateError('local store temporarily unavailable');
    await super.clear();
    if (failAfterClear) throw StateError('partial local clear');
  }

  @override
  Future<void> write(DeviceSessionCredential value) async {
    if (failWrite) throw StateError('local write unavailable');
    await super.write(value);
  }

  @override
  Future<void> clearCachedContext() async {
    clearCacheEntered?.complete();
    await clearCacheRelease?.future;
    await super.clearCachedContext();
  }

  @override
  Future<DeviceContext?> readCachedContext({
    required String expectedDeviceId,
  }) async {
    final pending = cacheRead;
    if (pending != null) {
      cacheEntered?.complete();
      return pending.future;
    }
    return super.readCachedContext(expectedDeviceId: expectedDeviceId);
  }
}

class _Wire implements SyncRpcTransport {
  FutureOr<Object?> Function(String, Map<String, dynamic>) handler = (_, _) =>
      _ok();
  final calls = <String>[];
  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> params) async {
    calls.add(fn);
    return handler(fn, params);
  }
}

Future<
  ({
    SupabaseDevicePairingRepository repo,
    _Store store,
    _Wire wire,
    DeviceSessionGuardedTransport guard,
  })
>
_rig({bool restore = true}) async {
  final store = _Store();
  await store.write(_credential);
  final wire = _Wire();
  final guard = DeviceSessionGuardedTransport(wire);
  final repo = SupabaseDevicePairingRepository(
    transport: guard,
    secretStore: store,
  );
  if (restore) await repo.restoreOutcome(expectedDeviceType: 'pos');
  return (repo: repo, store: store, wire: wire, guard: guard);
}

Future<void> _flush() async => Future<void>.delayed(Duration.zero);
void main() {
  test(
    'H5 partial clear restores durable token before surfacing repair failure',
    () async {
      final h = await _rig();
      h.store.failAfterClear = true;
      await expectLater(h.repo.clearLocalPairing(), throwsStateError);
      expect(await h.store.read(), _credential);
      expect(h.repo.activeDevice?.deviceId, 'device');
    },
  );
  test(
    'H5 partially cleared credential survives write outage and recovers without pairing',
    () async {
      final h = await _rig();
      h.wire.handler = (_, _) => {'ok': true};
      await h.repo.heartbeat();
      await h.repo.heartbeat();
      await h.repo.heartbeat();
      h.store.failAfterClear = true;
      h.store.failWrite = true;
      await expectLater(h.repo.clearLocalPairing(), throwsStateError);
      expect(h.repo.activeDevice?.deviceId, 'device');
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.offline);
      expect(h.repo.activeDevice?.deviceId, 'device');
      h.store.failWrite = false;
      h.wire.handler = (_, _) => _ok();
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.active);
      expect(await h.store.read(), _credential);
      expect(h.guard.isBlocked, isFalse);
      expect(
        h.wire.calls.where((fn) => fn == 'redeem_device_pairing'),
        isEmpty,
      );
    },
  );
  test(
    'H3 empty-secret restore cannot reject a newer pairing after cache clear',
    () async {
      final h = await _rig(restore: false);
      await h.store.clear();
      h.store.clearCacheEntered = Completer<void>();
      h.store.clearCacheRelease = Completer<void>();
      final old = h.repo.restoreOutcome(expectedDeviceType: 'pos');
      await h.store.clearCacheEntered!.future;
      h.wire.handler = (_, _) => {..._ok(), 'session_token': 'new-token'};
      final paired = h.repo.pairWithCode(code: 'NEW', deviceType: 'pos');
      h.store.clearCacheRelease!.complete();
      await paired;
      expect(await old, isA<DeviceSessionRestoreSuperseded>());
      expect((await h.store.read())?.sessionToken, 'new-token');
    },
  );
  test(
    'H2 block transition remains visible through offline and recovery emits exactly once',
    () async {
      final h = await _rig();
      final transitions = <bool>[];
      final sub = h.repo.protectedCallBlockChanges.listen(transitions.add);
      addTearDown(sub.cancel);
      h.wire.handler = (_, _) => {'ok': true};
      await h.repo.heartbeat();
      await h.repo.heartbeat();
      await _flush();
      expect(h.repo.protectedCallsBlocked, isTrue);
      expect(transitions, [true]);
      h.wire.handler = (_, _) => throw StateError('offline');
      await h.repo.heartbeat();
      await _flush();
      expect(h.repo.protectedCallsBlocked, isTrue);
      expect(transitions, [true]);
      h.wire.handler = (_, _) => _ok();
      await h.repo.heartbeat();
      await h.repo.heartbeat();
      await _flush();
      expect(h.repo.protectedCallsBlocked, isFalse);
      expect(transitions, [true, false]);
    },
  );
  test(
    'H3 old server recovers malformed restore even before guard blocks',
    () async {
      final h = await _rig();
      h.wire.handler = (_, _) => {'ok': true};
      expect(
        await h.repo.restoreOutcome(expectedDeviceType: 'pos'),
        isA<DeviceSessionRestoreUnavailable>(),
      );
      expect(h.guard.isBlocked, isFalse);
      h.wire.handler = (fn, params) {
        if (fn == 'heartbeat_device_session')
          throw const SyncTransportException(
            SyncTransportErrorKind.server,
            code: 'PGRST202',
          );
        expect(params['p_session_token'], 'token');
        return _ok();
      };
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.active);
      expect(
        h.wire.calls.where((f) => f == 'restore_device_session'),
        hasLength(3),
      );
    },
  );
  test(
    'H3 superseded malformed cache read never returns stale scope after unpair',
    () async {
      final h = await _rig(restore: false);
      const cached = DeviceContext(
        organizationId: 'org',
        restaurantId: 'restaurant',
        branchId: 'branch',
        deviceId: 'device',
        deviceSessionId: 'session',
        deviceType: 'pos',
      );
      h.store.cacheRead = Completer<DeviceContext?>();
      h.store.cacheEntered = Completer<void>();
      h.wire.handler = (_, _) => {'ok': true};
      final restore = h.repo.restoreOutcome(expectedDeviceType: 'pos');
      await h.store.cacheEntered!.future;
      await h.repo.unpair();
      h.store.cacheRead!.complete(cached);
      expect(await restore, isA<DeviceSessionRestoreSuperseded>());
      expect(h.repo.activeDevice, isNull);
      expect(await h.store.read(), isNull);
    },
  );
  test('H3 late restore reply is superseded rather than unavailable', () async {
    final h = await _rig();
    final pending = Completer<Object?>();
    final entered = Completer<void>();
    h.wire.handler = (fn, _) {
      if (fn == 'restore_device_session') {
        entered.complete();
        return pending.future;
      }
      return _ok();
    };
    final restore = h.repo.restoreOutcome(expectedDeviceType: 'pos');
    await entered.future;
    await h.repo.unpair();
    pending.complete(_ok());
    expect(await restore, isA<DeviceSessionRestoreSuperseded>());
  });
  test(
    'H5 local clear failure retains context and recovery then successful verification allows calls',
    () async {
      final h = await _rig();
      h.wire.handler = (_, _) => {'ok': true};
      await h.repo.heartbeat();
      await h.repo.heartbeat();
      await h.repo.heartbeat();
      h.store.failClear = true;
      final changes = <DeviceSessionChange>[];
      final sub = h.repo.sessionChanges.listen(changes.add);
      addTearDown(sub.cancel);
      await expectLater(h.repo.clearLocalPairing(), throwsStateError);
      await _flush();
      expect(h.repo.activeDevice?.deviceId, 'device');
      expect(h.repo.consecutiveUnavailable, 3);
      expect(changes.last.context?.deviceId, 'device');
      expect(changes.last.unavailable, isTrue);
      expect(await h.store.read(), _credential);
      h.store.failClear = false;
      h.wire.handler = (_, _) => _ok();
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.active);
      expect(h.guard.isBlocked, isFalse);
    },
  );
}
