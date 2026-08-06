// [POS-OFFLINE-OPERATIONS-002] Pass A — the TYPED restore outcome + the
// cached pairing scope written at BOTH server-verified moments.
//
// Pins the new contract of SupabaseDevicePairingRepository:
//  * pair success and restore success WRITE the cached scope;
//  * `rejected` (server verdict / wrong surface type) clears secret + cache;
//  * `offline` preserves both — and surfaces the cached scope ONLY for the
//    TRANSIENT transport kind (genuine offline evidence), never for
//    auth/server/unknown transport failures;
//  * the legacy `restore()` mapping (restored -> context, everything else ->
//    null) is unchanged, so KDS and existing callers keep their behaviour.
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

Map<String, dynamic> _restoreOk({String deviceType = 'pos'}) => {
  'ok': true,
  'device_session_id': 'ds-1',
  'organization_id': 'org-1',
  'restaurant_id': 'rest-1',
  'branch_id': 'branch-1',
  'device_id': 'dev-1',
  'device_type': deviceType,
};

Map<String, dynamic> _redeemOk() => {
  ..._restoreOk(),
  'entity': 'device_session',
  'session_token': 'raw-token-xyz',
};

const _cred = DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok');

SupabaseDevicePairingRepository _repo(
  SyncRpcTransport transport,
  InMemoryDeviceSessionSecretStore store,
) => SupabaseDevicePairingRepository(transport: transport, secretStore: store);

void main() {
  group('cached scope writes at server-verified moments', () {
    test('pair success persists the cached scope next to the secret', () async {
      final store = InMemoryDeviceSessionSecretStore();
      final repo = _repo(_FakeTransport((fn, p) => _redeemOk()), store);
      final result = await repo.pairWithCode(code: 'CODE', deviceType: 'pos');
      expect(result, isA<Success<DeviceContext, PairingFailure>>());

      final cached = await store.readCachedContext(expectedDeviceId: 'dev-1');
      expect(cached, isNotNull);
      expect(cached!.organizationId, 'org-1');
      expect(cached.restaurantId, 'rest-1');
      expect(cached.branchId, 'branch-1');
      expect(cached.deviceType, 'pos');
      expect(cached.deviceSessionId, 'ds-1');
    });

    test('restore success (typed) returns DeviceSessionRestored and refreshes '
        'the cached scope', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_cred);
      final repo = _repo(_FakeTransport((fn, p) => _restoreOk()), store);

      final outcome = await repo.restoreOutcome(expectedDeviceType: 'pos');
      expect(outcome, isA<DeviceSessionRestored>());
      expect(
        (outcome as DeviceSessionRestored).context.deviceSessionId,
        'ds-1',
      );
      final cached = await store.readCachedContext(expectedDeviceId: 'dev-1');
      expect(cached?.branchId, 'branch-1');
    });
  });

  group('rejected clears secret AND cached scope', () {
    test('a server verdict (invalid/revoked session)', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_cred);
      await store.writeCachedContext(
        const DeviceContext(
          organizationId: 'org-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          deviceType: 'pos',
        ),
      );
      final repo = _repo(
        _FakeTransport((fn, p) => {'ok': false, 'error': 'invalid_session'}),
        store,
      );
      expect(
        await repo.restoreOutcome(expectedDeviceType: 'pos'),
        isA<DeviceSessionRestoreRejected>(),
      );
      expect(await store.read(), isNull);
      expect(await store.readCachedContext(expectedDeviceId: 'dev-1'), isNull);
    });

    test('a valid session of the WRONG surface type', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_cred);
      final t = _FakeTransport((fn, p) => _restoreOk(deviceType: 'kds'));
      final repo = _repo(t, store);
      expect(
        await repo.restoreOutcome(expectedDeviceType: 'pos'),
        isA<DeviceSessionRestoreRejected>(),
      );
      expect(await store.read(), isNull);
      expect(await store.readCachedContext(expectedDeviceId: 'dev-1'), isNull);
      // NOT revoked server-side (it may be the real KDS device's session).
      expect(t.calls.map((c) => c.$1), ['restore_device_session']);
    });

    test('nothing stored -> rejected, and an orphaned cached scope is '
        'removed', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.writeCachedContext(
        const DeviceContext(
          organizationId: 'org-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          deviceType: 'pos',
        ),
      );
      final repo = _repo(
        _FakeTransport((fn, p) => fail('no stored secret — must not call')),
        store,
      );
      expect(await repo.restoreOutcome(), isA<DeviceSessionRestoreRejected>());
      expect(await store.readCachedContext(expectedDeviceId: 'dev-1'), isNull);
    });
  });

  group('offline preserves secret + cached scope', () {
    Future<InMemoryDeviceSessionSecretStore> seededStore() async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_cred);
      await store.writeCachedContext(
        const DeviceContext(
          organizationId: 'org-1',
          branchId: 'branch-1',
          restaurantId: 'rest-1',
          deviceId: 'dev-1',
          deviceType: 'pos',
          deviceSessionId: 'ds-1',
        ),
      );
      return store;
    }

    test('a TRANSIENT transport failure surfaces the cached scope', () async {
      final store = await seededStore();
      final repo = _repo(
        _FakeTransport((fn, p) {
          throw const SyncTransportException(SyncTransportErrorKind.transient);
        }),
        store,
      );
      final outcome = await repo.restoreOutcome(expectedDeviceType: 'pos');
      expect(outcome, isA<DeviceSessionRestoreOffline>());
      final cached = (outcome as DeviceSessionRestoreOffline).cachedContext;
      expect(cached, isNotNull);
      expect(cached!.deviceSessionId, 'ds-1');
      // Both durable records survive for the later retry.
      expect(await store.read(), _cred);
      expect(
        await store.readCachedContext(expectedDeviceId: 'dev-1'),
        isNotNull,
      );
    });

    test('a transient failure with NO cached scope is offline WITHOUT '
        'evidence (null cache)', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_cred);
      final repo = _repo(
        _FakeTransport((fn, p) {
          throw const SyncTransportException(SyncTransportErrorKind.transient);
        }),
        store,
      );
      final outcome = await repo.restoreOutcome(expectedDeviceType: 'pos');
      expect((outcome as DeviceSessionRestoreOffline).cachedContext, isNull);
      expect(await store.read(), _cred);
    });

    test(
      'an AUTH-kind transport failure is offline WITHOUT evidence and '
      'clears nothing (matching the pre-existing keep-the-secret rule)',
      () async {
        final store = await seededStore();
        final repo = _repo(
          _FakeTransport((fn, p) {
            throw const SyncTransportException(
              SyncTransportErrorKind.auth,
              code: '42501',
            );
          }),
          store,
        );
        final outcome = await repo.restoreOutcome(expectedDeviceType: 'pos');
        expect(outcome, isA<DeviceSessionRestoreOffline>());
        expect((outcome as DeviceSessionRestoreOffline).cachedContext, isNull);
        expect(await store.read(), _cred);
        expect(
          await store.readCachedContext(expectedDeviceId: 'dev-1'),
          isNotNull,
        );
      },
    );

    test('a cached scope of the WRONG surface type is filtered to null '
        '(absent), with nothing destroyed', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_cred);
      await store.writeCachedContext(
        const DeviceContext(
          organizationId: 'org-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          deviceType: 'kds',
        ),
      );
      final repo = _repo(
        _FakeTransport((fn, p) {
          throw const SyncTransportException(SyncTransportErrorKind.transient);
        }),
        store,
      );
      final outcome = await repo.restoreOutcome(expectedDeviceType: 'pos');
      expect((outcome as DeviceSessionRestoreOffline).cachedContext, isNull);
      expect(await store.read(), _cred);
      expect(
        await store.readCachedContext(expectedDeviceId: 'dev-1'),
        isNotNull,
        reason: 'a cache read may never destroy the record',
      );
    });
  });

  group('legacy restore() mapping is unchanged', () {
    test('restored -> context; offline -> null; rejected -> null', () async {
      final restoredStore = InMemoryDeviceSessionSecretStore();
      await restoredStore.write(_cred);
      expect(
        await _repo(
          _FakeTransport((fn, p) => _restoreOk()),
          restoredStore,
        ).restore(expectedDeviceType: 'pos'),
        isNotNull,
      );

      final offlineStore = InMemoryDeviceSessionSecretStore();
      await offlineStore.write(_cred);
      expect(
        await _repo(
          _FakeTransport((fn, p) {
            throw const SyncTransportException(
              SyncTransportErrorKind.transient,
            );
          }),
          offlineStore,
        ).restore(expectedDeviceType: 'pos'),
        isNull,
      );
      expect(await offlineStore.read(), _cred, reason: 'secret preserved');

      final rejectedStore = InMemoryDeviceSessionSecretStore();
      await rejectedStore.write(_cred);
      expect(
        await _repo(
          _FakeTransport((fn, p) => {'ok': false}),
          rejectedStore,
        ).restore(expectedDeviceType: 'pos'),
        isNull,
      );
      expect(await rejectedStore.read(), isNull, reason: 'secret cleared');
    });
  });

  group('unpair', () {
    test('clears the cached scope with the secret', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(_cred);
      await store.writeCachedContext(
        const DeviceContext(
          organizationId: 'org-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          deviceType: 'pos',
        ),
      );
      final repo = _repo(_FakeTransport((fn, p) => {'ok': true}), store);
      await repo.unpair();
      expect(await store.read(), isNull);
      expect(await store.readCachedContext(expectedDeviceId: 'dev-1'), isNull);
    });
  });
}
