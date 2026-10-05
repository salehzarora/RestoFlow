import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _credential = DeviceSessionCredential(
  deviceId: 'device',
  sessionToken: 'test-token',
);
Map<String, Object?> _ok({String device = 'device'}) => {
  'ok': true,
  'device_id': device,
  'device_session_id': 'session-$device',
  'organization_id': 'org',
  'restaurant_id': 'restaurant',
  'branch_id': 'branch',
  'device_type': 'pos',
};

class _SlowClearStore extends InMemoryDeviceSessionSecretStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> clear() async {
    entered.complete();
    await release.future;
    await super.clear();
  }
}

class _SlowReadStore extends InMemoryDeviceSessionSecretStore {
  Completer<void>? releaseRead;
  @override
  Future<DeviceSessionCredential?> read() async {
    await releaseRead?.future;
    return super.read();
  }
}

class _Transport implements SyncRpcTransport {
  _Transport(this.handler);
  FutureOr<Object?> Function(String, Map<String, dynamic>) handler;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return handler(function, params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a clear already in progress finishes before newer pairing is persisted',
    () async {
      final store = _SlowClearStore();
      await store.write(_credential);
      final transport = _Transport((_, _) => _ok());
      final repo = SupabaseDevicePairingRepository(
        transport: DeviceSessionGuardedTransport(transport),
        secretStore: store,
      );
      await repo.restoreOutcome(expectedDeviceType: 'pos');
      transport.handler = (fn, _) => fn == 'redeem_device_pairing'
          ? {..._ok(device: 'new-device'), 'session_token': 'new-token'}
          : {'ok': false, 'error': 'invalid_session'};
      final oldRestore = repo.restoreOutcome(expectedDeviceType: 'pos');
      await store.entered.future;
      final newPair = repo.pairWithCode(code: 'new-code', deviceType: 'pos');
      store.release.complete();
      expect(await oldRestore, isA<DeviceSessionRestoreUnavailable>());
      expect(await newPair, isA<Success<DeviceContext, PairingFailure>>());
      expect(
        await store.read(),
        const DeviceSessionCredential(
          deviceId: 'new-device',
          sessionToken: 'new-token',
        ),
      );
      expect(repo.activeDevice?.deviceId, 'new-device');
    },
  );
  test(
    'late unpair storage read cannot revoke replacement credential remotely',
    () async {
      final store = _SlowReadStore();
      await store.write(_credential);
      final transport = _Transport((_, _) => _ok());
      final repo = SupabaseDevicePairingRepository(
        transport: transport,
        secretStore: store,
      );
      await repo.restoreOutcome();
      store.releaseRead = Completer<void>();
      final oldUnpair = repo.unpair();
      transport.handler = (_, _) => {
        ..._ok(device: 'new-device'),
        'session_token': 'new-token',
      };
      await repo.pairWithCode(code: 'new-code', deviceType: 'pos');
      store.releaseRead!.complete();
      await oldUnpair;
      expect(
        transport.calls.where((call) => call.$1 == 'revoke_device_session'),
        isEmpty,
      );
      expect(
        await store.read(),
        const DeviceSessionCredential(
          deviceId: 'new-device',
          sessionToken: 'new-token',
        ),
      );
    },
  );
  for (final reply in <Object?>[
    null,
    [],
    {'ok': false},
    {'ok': false, 'error': 'unknown'},
    {'ok': true},
    _ok()..remove('restaurant_id'),
    {..._ok(), 'restaurant_id': ''},
  ]) {
    test(
      'BIZBOT malformed/unknown restore $reply preserves durable web credential',
      () async {
        SharedPreferences.setMockInitialValues({
          'outbox-sentinel': 'queued-order',
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPreferencesDeviceSessionSecretStore(prefs);
        await store.write(_credential);
        final guard = DeviceSessionGuardedTransport(
          _Transport((_, _) => reply),
        );
        final repo = SupabaseDevicePairingRepository(
          transport: guard,
          secretStore: store,
        );
        expect(
          await repo.restoreOutcome(expectedDeviceType: 'pos'),
          isA<DeviceSessionRestoreUnavailable>(),
        );
        expect(
          await SharedPreferencesDeviceSessionSecretStore(prefs).read(),
          _credential,
        );
        expect(guard.isBlocked, isFalse);
        await repo.restoreOutcome(expectedDeviceType: 'pos');
        expect(guard.isBlocked, isTrue);
        expect(prefs.getString('outbox-sentinel'), 'queued-order');
      },
    );
  }
  test('heartbeat proves persisted token without rotation', () async {
    final store = InMemoryDeviceSessionSecretStore();
    await store.write(_credential);
    final transport = _Transport((_, _) => _ok());
    final repo = SupabaseDevicePairingRepository(
      transport: transport,
      secretStore: store,
    );
    await repo.restoreOutcome(expectedDeviceType: 'pos');
    expect(await repo.heartbeat(), DeviceHeartbeatResult.active);
    expect(transport.calls.last.$1, 'heartbeat_device_session');
    expect(transport.calls.last.$2, {
      'p_device_id': 'device',
      'p_session_token': 'test-token',
    });
    expect(await store.read(), _credential);
    expect(repo.activeDevice?.deviceSessionId, 'session-device');
  });
  for (final reason in ['expired', 'revoked', 'invalid']) {
    test(
      'explicit heartbeat invalid_session $reason clears only pairing state',
      () async {
        SharedPreferences.setMockInitialValues({
          'outbox-sentinel': 'queued-order',
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPreferencesDeviceSessionSecretStore(prefs);
        await store.write(_credential);
        final transport = _Transport((_, _) => _ok());
        final guard = DeviceSessionGuardedTransport(transport);
        final repo = SupabaseDevicePairingRepository(
          transport: guard,
          secretStore: store,
        );
        await repo.restoreOutcome();
        transport.handler = (_, _) => {
          'ok': false,
          'error': 'invalid_session',
          'reason': reason,
        };
        final invalidation = repo.sessionChanges.firstWhere(
          (e) => e.invalidSession,
        );
        expect(await repo.heartbeat(), DeviceHeartbeatResult.invalidSession);
        expect((await invalidation).context, isNull);
        expect(await store.read(), isNull);
        expect(
          await store.readCachedContext(expectedDeviceId: 'device'),
          isNull,
        );
        expect(prefs.getString('outbox-sentinel'), 'queued-order');
        expect(guard.isBlocked, isTrue);
      },
    );
  }
  for (final code in ['PGRST202', '42883']) {
    test('missing heartbeat RPC $code is compatible and retried', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_credential);
      final transport = _Transport((_, _) => _ok());
      final guard = DeviceSessionGuardedTransport(transport);
      final repo = SupabaseDevicePairingRepository(
        transport: guard,
        secretStore: store,
      );
      await repo.restoreOutcome();
      transport.handler = (_, _) => throw SyncTransportException(
        SyncTransportErrorKind.server,
        code: code,
      );
      expect(await repo.heartbeat(), DeviceHeartbeatResult.unsupported);
      expect(await repo.heartbeat(), DeviceHeartbeatResult.unsupported);
      expect(
        transport.calls.where((e) => e.$1 == 'heartbeat_device_session'),
        hasLength(2),
      );
      expect(await store.read(), _credential);
      expect(guard.isBlocked, isFalse);
    });
  }
  test(
    'malformed heartbeat gates protected work until verified retry',
    () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_credential);
      final transport = _Transport((_, _) => _ok());
      final guard = DeviceSessionGuardedTransport(transport);
      final repo = SupabaseDevicePairingRepository(
        transport: guard,
        secretStore: store,
      );
      await repo.restoreOutcome();
      for (final reply in <Object?>[
        null,
        {'ok': false, 'error': 'unknown'},
        {'ok': true},
        {..._ok(), 'branch_id': 'other'},
      ]) {
        transport.handler = (_, _) => reply;
        expect(await repo.heartbeat(), DeviceHeartbeatResult.unavailable);
        await repo.heartbeat();
        expect(await store.read(), _credential);
        expect(guard.isBlocked, isTrue);
        await expectLater(
          guard.invoke('sync_push', {}),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.kind,
              'kind',
              SyncTransportErrorKind.transient,
            ),
          ),
        );
      }
      transport.handler = (_, _) =>
          throw const SyncTransportException(SyncTransportErrorKind.transient);
      expect(await repo.heartbeat(), DeviceHeartbeatResult.offline);
      expect(
        guard.isBlocked,
        isTrue,
        reason: 'offline cannot override an earlier unknown verdict',
      );
      transport.handler = (_, _) => throw const SyncTransportException(
        SyncTransportErrorKind.server,
        code: 'PGRST202',
      );
      expect(await repo.heartbeat(), DeviceHeartbeatResult.offline);
      expect(
        guard.isBlocked,
        isTrue,
        reason: 'missing RPC cannot reopen an unverified session',
      );
      transport.handler = (_, _) => _ok();
      expect(await repo.heartbeat(), DeviceHeartbeatResult.active);
      expect(guard.isBlocked, isFalse);
    },
  );
  test(
    'ordinary offline heartbeat preserves existing bounded offline path',
    () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_credential);
      final transport = _Transport((_, _) => _ok());
      final guard = DeviceSessionGuardedTransport(transport);
      final repo = SupabaseDevicePairingRepository(
        transport: guard,
        secretStore: store,
      );
      await repo.restoreOutcome();
      transport.handler = (_, _) =>
          throw const SyncTransportException(SyncTransportErrorKind.transient);
      expect(await repo.heartbeat(), DeviceHeartbeatResult.offline);
      expect(guard.isBlocked, isFalse);
      expect(await store.read(), _credential);
    },
  );
  for (final oldOperation in [
    'heartbeat_device_session',
    'restore_device_session',
  ]) {
    test('late $oldOperation rejection cannot erase newer pairing', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_credential);
      final transport = _Transport((_, _) => _ok());
      final guard = DeviceSessionGuardedTransport(transport);
      final repo = SupabaseDevicePairingRepository(
        transport: guard,
        secretStore: store,
      );
      await repo.restoreOutcome();
      final entered = Completer<void>();
      final oldReply = Completer<Object?>();
      transport.handler = (fn, _) {
        if (fn == oldOperation) {
          entered.complete();
          return oldReply.future;
        }
        return {..._ok(device: 'new-device'), 'session_token': 'new-token'};
      };
      final oldRequest = oldOperation == 'heartbeat_device_session'
          ? repo.heartbeat()
          : repo.restoreOutcome();
      await entered.future;
      expect(
        await repo.pairWithCode(code: 'new-code', deviceType: 'pos'),
        isA<Success<DeviceContext, PairingFailure>>(),
      );
      oldReply.complete({
        'ok': false,
        'error': 'invalid_session',
        'reason': 'revoked',
      });
      await oldRequest;
      expect(
        await store.read(),
        const DeviceSessionCredential(
          deviceId: 'new-device',
          sessionToken: 'new-token',
        ),
      );
      expect(repo.activeDevice?.deviceId, 'new-device');
      expect(guard.isBlocked, isFalse);
    });
  }
  test(
    'restore exposes safe rejection reasons and old-server fallback',
    () async {
      for (final entry in <String?, DeviceSessionRejectionReason>{
        'expired': DeviceSessionRejectionReason.expired,
        'revoked': DeviceSessionRejectionReason.revoked,
        null: DeviceSessionRejectionReason.invalid,
      }.entries) {
        final store = InMemoryDeviceSessionSecretStore();
        await store.write(_credential);
        final repo = SupabaseDevicePairingRepository(
          transport: _Transport(
            (_, _) => {
              'ok': false,
              'error': 'invalid_session',
              'reason': entry.key,
            },
          ),
          secretStore: store,
        );
        final outcome = await repo.restoreOutcome();
        expect((outcome as DeviceSessionRestoreRejected).reason, entry.value);
        expect(await store.read(), isNull);
      }
    },
  );
}
