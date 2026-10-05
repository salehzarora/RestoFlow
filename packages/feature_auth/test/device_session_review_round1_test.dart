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
  bool throwRead = false;
  @override
  Future<DeviceSessionCredential?> read() async {
    if (throwRead) throw StateError('storage unavailable');
    return super.read();
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
    _Wire wire,
    DeviceSessionGuardedTransport guard,
    _Store store,
  })
>
_rig() async {
  final store = _Store();
  await store.write(_credential);
  final wire = _Wire();
  final guard = DeviceSessionGuardedTransport(wire);
  final repo = SupabaseDevicePairingRepository(
    transport: guard,
    secretStore: store,
  );
  await repo.restoreOutcome(expectedDeviceType: 'pos');
  return (repo: repo, wire: wire, guard: guard, store: store);
}

void main() {
  test('F3 cold unknown recovery survives a thrown restore', () async {
    final store = _Store();
    await store.write(_credential);
    final wire = _Wire()..handler = (_, _) => {'ok': true};
    final repo = SupabaseDevicePairingRepository(
      transport: wire,
      secretStore: store,
    );
    await repo.restoreOutcome(expectedDeviceType: 'pos');
    await repo.heartbeat();
    wire.handler = (_, _) => throw StateError('offline');
    expect(await repo.heartbeat(), DeviceHeartbeatResult.offline);
    wire.handler = (_, _) => _ok();
    expect(await repo.heartbeat(), DeviceHeartbeatResult.active);
  });
  test(
    'S4 waiting restore cannot consume a newer pairing generation',
    () async {
      final h = await _rig();
      final revoking = Completer<void>();
      final revoked = Completer<void>();
      final redeeming = Completer<void>();
      final redeemed = Completer<Object?>();
      h.wire.handler = (fn, _) {
        if (fn == 'revoke_device_session') {
          revoking.complete();
          return revoked.future;
        }
        if (fn == 'redeem_device_pairing') {
          redeeming.complete();
          return redeemed.future;
        }
        return _ok();
      };
      final unpair = h.repo.unpair();
      await revoking.future;
      final restore = h.repo.restoreOutcome(expectedDeviceType: 'pos');
      final pair = h.repo.pairWithCode(code: 'NEW', deviceType: 'pos');
      await redeeming.future;
      revoked.complete();
      await unpair;
      await restore;
      redeemed.complete({..._ok(), 'session_token': 'new-token'});
      await pair;
      expect((await h.store.read())?.sessionToken, 'new-token');
      expect(h.repo.activeDevice?.deviceId, 'device');
    },
  );
  for (final code in [
    '500',
    '502',
    '520',
    'PGRST000',
    'PGRST001',
    'PGRST002',
    'PGRST003',
    '57014',
    '40P01',
    '53300',
  ]) {
    test(
      'F1 heartbeat thrown $code is offline without blocking or erasure',
      () async {
        final h = await _rig();
        h.wire.handler = (_, _) => throw SyncTransportException(
          SyncTransportErrorKind.server,
          code: code,
        );
        expect(await h.repo.heartbeat(), DeviceHeartbeatResult.offline);
        expect(h.guard.isBlocked, isFalse);
        expect(await h.store.read(), _credential);
      },
    );
  }
  test(
    'F1 arbitrary heartbeat exception and credential read throw stay offline',
    () async {
      final h = await _rig();
      h.wire.handler = (_, _) => throw StateError('wire unavailable');
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.offline);
      expect(h.guard.isBlocked, isFalse);
      h.store.throwRead = true;
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.offline);
      expect(h.guard.isBlocked, isFalse);
      h.store.throwRead = false;
      expect(await h.store.read(), _credential);
    },
  );
  test(
    'F1 two consecutive malformed replies gate transiently, success resets streak',
    () async {
      final h = await _rig();
      h.wire.handler = (_, _) => {'ok': true};
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.unavailable);
      expect(h.guard.isBlocked, isFalse);
      h.wire.handler = (_, _) => _ok();
      expect(await h.repo.heartbeat(), DeviceHeartbeatResult.active);
      h.wire.handler = (_, _) => {'ok': true};
      await h.repo.heartbeat();
      expect(h.guard.isBlocked, isFalse);
      await h.repo.heartbeat();
      expect(h.guard.isBlocked, isTrue);
      await expectLater(
        h.guard.invoke('sync_push', {}),
        throwsA(
          isA<SyncTransportException>()
              .having((e) => e.kind, 'kind', SyncTransportErrorKind.transient)
              .having((e) => e.code, 'code', 'device_session_unverified'),
        ),
      );
      expect(await h.store.read(), _credential);
    },
  );
  test('F1 thrown error breaks consecutive malformed reply streak', () async {
    final h = await _rig();
    h.wire.handler = (_, _) => {'ok': true};
    await h.repo.heartbeat();
    h.wire.handler = (_, _) => throw StateError('wire unavailable');
    await h.repo.heartbeat();
    h.wire.handler = (_, _) => {'ok': true};
    await h.repo.heartbeat();
    expect(h.guard.isBlocked, isFalse);
  });
  for (final code in ['PGRST202', '42883', '404']) {
    test(
      'F3 blocked old server $code re-verifies token on next heartbeat',
      () async {
        final h = await _rig();
        h.wire.handler = (_, _) => {'ok': true};
        await h.repo.heartbeat();
        await h.repo.heartbeat();
        expect(h.guard.isBlocked, isTrue);
        h.wire.handler = (fn, params) {
          if (fn == 'heartbeat_device_session')
            throw SyncTransportException(
              SyncTransportErrorKind.server,
              code: code,
            );
          expect(fn, 'restore_device_session');
          expect(params, {'p_device_id': 'device', 'p_session_token': 'token'});
          return _ok();
        };
        expect(await h.repo.heartbeat(), DeviceHeartbeatResult.active);
        expect(h.guard.isBlocked, isFalse);
        expect(
          h.wire.calls.where((fn) => fn == 'restore_device_session'),
          hasLength(2),
        );
        expect(await h.store.read(), _credential);
      },
    );
  }
  test('S4 concurrent restore cannot supersede an explicit unpair', () async {
    final h = await _rig();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.wire.handler = (fn, _) {
      if (fn == 'revoke_device_session') {
        entered.complete();
        return release.future;
      }
      return _ok();
    };
    final unpair = h.repo.unpair();
    await entered.future;
    final restore = h.repo.restoreOutcome(expectedDeviceType: 'pos');
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await unpair;
    final result = await restore;
    expect(await h.store.read(), isNull);
    expect(result, isA<DeviceSessionRestoreRejected>());
    expect(h.repo.activeDevice, isNull);
  });
}
