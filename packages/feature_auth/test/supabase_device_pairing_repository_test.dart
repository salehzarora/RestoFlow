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

Map<String, dynamic> _redeemOk() => {
  'ok': true,
  'entity': 'device_session',
  'device_session_id': 'sess-1',
  'session_token': 'raw-token-xyz',
  'organization_id': 'org-1',
  'restaurant_id': 'rest-1',
  'branch_id': 'branch-1',
  'device_id': 'dev-1',
  'device_type': 'pos',
};

void main() {
  group('pairWithCode', () {
    test('redeems, persists the secret, returns the server context', () async {
      final store = InMemoryDeviceSessionSecretStore();
      final t = _FakeTransport((fn, p) => _redeemOk());
      final repo = SupabaseDevicePairingRepository(
        transport: t,
        secretStore: store,
      );

      final result = await repo.pairWithCode(
        code: '  CODE ',
        deviceType: 'pos',
      );

      expect(t.calls.single.$1, 'redeem_device_pairing');
      expect(t.calls.single.$2, {
        'p_enrollment_code': 'CODE',
        'p_device_type': 'pos',
      });
      final ctx = (result as Success<DeviceContext, PairingFailure>).value;
      expect(ctx.isPaired, isTrue);
      expect(ctx.deviceId, 'dev-1');
      expect(ctx.organizationId, 'org-1');
      expect(ctx.branchId, 'branch-1');
      expect(ctx.deviceType, 'pos');
      // the raw token is persisted to secure storage, never returned in the context.
      expect(
        await store.read(),
        equals(
          const DeviceSessionCredential(
            deviceId: 'dev-1',
            sessionToken: 'raw-token-xyz',
          ),
        ),
      );
    });

    test('maps backend error codes to safe PairingFailure kinds', () async {
      final cases = {
        'invalid_code': PairingFailureKind.invalidCode,
        'expired': PairingFailureKind.expired,
        'wrong_type': PairingFailureKind.wrongScope,
        'permission_denied': PairingFailureKind.denied,
      };
      for (final entry in cases.entries) {
        final store = InMemoryDeviceSessionSecretStore();
        final t = _FakeTransport((fn, p) => {'ok': false, 'error': entry.key});
        final repo = SupabaseDevicePairingRepository(
          transport: t,
          secretStore: store,
        );
        final r = await repo.pairWithCode(code: 'x', deviceType: 'pos');
        r.fold(
          (_) => fail('expected failure for ${entry.key}'),
          (f) => expect(f.kind, entry.value, reason: entry.key),
        );
        // a failed pairing never writes a secret.
        expect(await store.read(), isNull, reason: entry.key);
      }
    });

    test('a transient transport error maps to network', () async {
      final store = InMemoryDeviceSessionSecretStore();
      final t = _FakeTransport((fn, p) {
        throw const SyncTransportException(SyncTransportErrorKind.transient);
      });
      final repo = SupabaseDevicePairingRepository(
        transport: t,
        secretStore: store,
      );
      final r = await repo.pairWithCode(code: 'x', deviceType: 'pos');
      r.fold(
        (_) => fail('expected failure'),
        (f) => expect(f.kind, PairingFailureKind.network),
      );
    });
  });

  group('restore', () {
    test('returns null when nothing is stored', () async {
      final repo = SupabaseDevicePairingRepository(
        transport: _FakeTransport((fn, p) => fail('should not call')),
        secretStore: InMemoryDeviceSessionSecretStore(),
      );
      expect(await repo.restore(), isNull);
    });

    test('restores the context from a valid stored token', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
      );
      final t = _FakeTransport(
        (fn, p) => {
          'ok': true,
          'device_session_id': 'sess-1',
          'organization_id': 'org-1',
          'restaurant_id': 'rest-1',
          'branch_id': 'branch-1',
          'device_id': 'dev-1',
          'device_type': 'kds',
        },
      );
      final repo = SupabaseDevicePairingRepository(
        transport: t,
        secretStore: store,
      );
      final ctx = await repo.restore();
      expect(t.calls.single.$1, 'restore_device_session');
      expect(t.calls.single.$2, {
        'p_device_id': 'dev-1',
        'p_session_token': 'tok',
      });
      expect(ctx?.isPaired, isTrue);
      expect(ctx?.deviceType, 'kds');
    });

    test(
      'a revoked/invalid session clears the stale secret (fail-closed)',
      () async {
        final store = InMemoryDeviceSessionSecretStore();
        await store.write(
          const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
        );
        final t = _FakeTransport(
          (fn, p) => {'ok': false, 'error': 'invalid_session'},
        );
        final repo = SupabaseDevicePairingRepository(
          transport: t,
          secretStore: store,
        );
        expect(await repo.restore(), isNull);
        expect(await store.read(), isNull); // cleared
      },
    );

    test('a transient error keeps the secret for a later retry', () async {
      final store = InMemoryDeviceSessionSecretStore();
      const cred = DeviceSessionCredential(
        deviceId: 'dev-1',
        sessionToken: 'tok',
      );
      await store.write(cred);
      final t = _FakeTransport((fn, p) {
        throw const SyncTransportException(SyncTransportErrorKind.transient);
      });
      final repo = SupabaseDevicePairingRepository(
        transport: t,
        secretStore: store,
      );
      expect(await repo.restore(), isNull);
      expect(await store.read(), equals(cred)); // NOT cleared
    });
  });

  group('unpair', () {
    test('revokes the session and clears the secret', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
      );
      final t = _FakeTransport((fn, p) => {'ok': true, 'revoked': 1});
      final repo = SupabaseDevicePairingRepository(
        transport: t,
        secretStore: store,
      );
      await repo.unpair();
      expect(t.calls.single.$1, 'revoke_device_session');
      expect(await store.read(), isNull);
    });

    test(
      'with no stored session, clears locally without a backend call',
      () async {
        final store = InMemoryDeviceSessionSecretStore();
        final t = _FakeTransport((fn, p) => fail('should not call'));
        final repo = SupabaseDevicePairingRepository(
          transport: t,
          secretStore: store,
        );
        await repo.unpair();
        expect(t.calls, isEmpty);
        expect(await store.read(), isNull);
      },
    );
  });
}
