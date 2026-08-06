// [POS-OFFLINE-OPERATIONS-002] Pass A — the cached pairing-scope record.
//
// Pins the codec's fail-closed rules (unreadable / unknown version /
// mismatched device id / missing tenant scope -> ABSENT) and the in-memory
// store facet the repository tests ride on. The token is never part of the
// record and never touched by cache operations.
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

const _context = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  stationId: 'station-1',
  stationType: 'pos',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
  displayName: 'Till 1',
);

void main() {
  group('codec round-trip', () {
    test('every field the offline boot consumes survives encode+decode', () {
      final raw = encodeCachedDeviceContext(_context);
      final decoded = decodeCachedDeviceContext(raw, expectedDeviceId: 'dev-1');
      expect(decoded, isNotNull);
      expect(decoded!.organizationId, 'org-1');
      expect(decoded.branchId, 'branch-1');
      expect(decoded.restaurantId, 'rest-1');
      expect(decoded.stationId, 'station-1');
      expect(decoded.stationType, 'pos');
      expect(decoded.deviceId, 'dev-1');
      expect(decoded.deviceType, 'pos');
      expect(decoded.deviceSessionId, 'ds-1');
      expect(decoded.displayName, 'Till 1');
      expect(decoded.isPaired, isTrue);
    });

    test('pairedAt round-trips as UTC ISO-8601', () {
      final withTime = DeviceContext(
        organizationId: 'org-1',
        branchId: 'branch-1',
        deviceId: 'dev-1',
        pairedAt: DateTime.utc(2026, 8, 6, 9, 30),
      );
      final decoded = decodeCachedDeviceContext(
        encodeCachedDeviceContext(withTime),
        expectedDeviceId: 'dev-1',
      );
      expect(decoded!.pairedAt, DateTime.utc(2026, 8, 6, 9, 30));
    });

    test('the record NEVER carries a token-looking field', () {
      final raw = encodeCachedDeviceContext(_context);
      expect(raw.contains('token'), isFalse);
      expect(raw.contains('pin'), isFalse);
    });
  });

  group('fail-closed decode', () {
    test('unreadable JSON is absent', () {
      expect(
        decodeCachedDeviceContext('{not json', expectedDeviceId: 'dev-1'),
        isNull,
      );
      expect(
        decodeCachedDeviceContext('42', expectedDeviceId: 'dev-1'),
        isNull,
      );
    });

    test('an unknown schema version is refused, not guessed at', () {
      final raw = encodeCachedDeviceContext(
        _context,
      ).replaceFirst('"v":$kCachedDeviceContextVersion', '"v":99');
      expect(decodeCachedDeviceContext(raw, expectedDeviceId: 'dev-1'), isNull);
    });

    test('a record naming ANOTHER device than the stored secret is absent '
        '(scope mismatch fails closed)', () {
      final raw = encodeCachedDeviceContext(_context);
      expect(
        decodeCachedDeviceContext(raw, expectedDeviceId: 'dev-OTHER'),
        isNull,
      );
      expect(decodeCachedDeviceContext(raw, expectedDeviceId: ''), isNull);
    });

    test('a record missing its tenant scope is absent', () {
      expect(
        decodeCachedDeviceContext(
          '{"v":1,"device_id":"dev-1","branch_id":"branch-1"}',
          expectedDeviceId: 'dev-1',
        ),
        isNull,
        reason: 'no organization_id',
      );
      expect(
        decodeCachedDeviceContext(
          '{"v":1,"device_id":"dev-1","organization_id":"org-1"}',
          expectedDeviceId: 'dev-1',
        ),
        isNull,
        reason: 'no branch_id',
      );
    });
  });

  group('InMemoryDeviceSessionSecretStore cache facet', () {
    test('round-trip through the REAL codec', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.writeCachedContext(_context);
      final read = await store.readCachedContext(expectedDeviceId: 'dev-1');
      expect(read?.organizationId, 'org-1');
      expect(read?.deviceSessionId, 'ds-1');
    });

    test('a mismatched device id reads as absent — and the credential is '
        'untouched', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
      );
      await store.writeCachedContext(_context);
      expect(
        await store.readCachedContext(expectedDeviceId: 'dev-OTHER'),
        isNull,
      );
      expect(await store.read(), isNotNull, reason: 'token preserved');
    });

    test(
      'clearCachedContext clears ONLY the cache, never the secret',
      () async {
        final store = InMemoryDeviceSessionSecretStore();
        await store.write(
          const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
        );
        await store.writeCachedContext(_context);
        await store.clearCachedContext();
        expect(
          await store.readCachedContext(expectedDeviceId: 'dev-1'),
          isNull,
        );
        expect(await store.read(), isNotNull);
      },
    );
  });
}
