// [POS-OFFLINE-OPERATIONS-002] Pass A — the cached pairing-scope facet of the
// two PRODUCTION secret stores (native secure storage + web prefs).
//
// Pins: round-trip through the real backing, unreadable record -> absent with
// the token PRESERVED, mismatched device id -> absent, and cache clears that
// never touch the credential.
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _context = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
  displayName: 'Till 1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterSecureDeviceSessionStore cache facet', () {
    late Map<String, String> secure;

    setUp(() {
      secure = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            final args = (call.arguments as Map?)?.cast<String, Object?>();
            final key = args?['key'] as String?;
            switch (call.method) {
              case 'read':
                return secure[key];
              case 'write':
                secure[key!] = args!['value']! as String;
                return null;
              case 'delete':
                secure.remove(key);
                return null;
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('round-trip through the platform channel', () async {
      final store = FlutterSecureDeviceSessionStore();
      await store.writeCachedContext(_context);
      final read = await store.readCachedContext(expectedDeviceId: 'dev-1');
      expect(read?.organizationId, 'org-1');
      expect(read?.deviceSessionId, 'ds-1');
      // The record lives under its own key — never in the token keys.
      expect(secure.containsKey('restoflow.device_context_cache'), isTrue);
      expect(secure.containsKey('restoflow.device_session_token'), isFalse);
    });

    test('an unreadable record is ABSENT — and the credential (token) is '
        'preserved, never auto-deleted', () async {
      final store = FlutterSecureDeviceSessionStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
      );
      secure['restoflow.device_context_cache'] = '{not json at all';
      expect(await store.readCachedContext(expectedDeviceId: 'dev-1'), isNull);
      expect(
        secure['restoflow.device_context_cache'],
        '{not json at all',
        reason: 'a record we cannot read is not a record we may destroy',
      );
      expect(await store.read(), isNotNull, reason: 'token untouched');
    });

    test('a mismatched device id is ABSENT (fail closed)', () async {
      final store = FlutterSecureDeviceSessionStore();
      await store.writeCachedContext(_context);
      expect(
        await store.readCachedContext(expectedDeviceId: 'dev-OTHER'),
        isNull,
      );
    });

    test('clearCachedContext leaves the credential untouched', () async {
      final store = FlutterSecureDeviceSessionStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
      );
      await store.writeCachedContext(_context);
      await store.clearCachedContext();
      expect(await store.readCachedContext(expectedDeviceId: 'dev-1'), isNull);
      expect(await store.read(), isNotNull);
    });
  });

  group('SharedPreferencesDeviceSessionSecretStore cache facet', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('round-trip under the surface-specific prefix', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesDeviceSessionSecretStore(
        prefs,
        keyPrefix: kPosDeviceSessionPrefix,
      );
      await store.writeCachedContext(_context);
      final read = await store.readCachedContext(expectedDeviceId: 'dev-1');
      expect(read?.branchId, 'branch-1');
      expect(
        prefs.getString('$kPosDeviceSessionPrefix.context_cache'),
        isNotNull,
      );
      // The KDS prefix cannot see (or clear) the POS record.
      final kdsStore = SharedPreferencesDeviceSessionSecretStore(
        prefs,
        keyPrefix: kKdsDeviceSessionPrefix,
      );
      expect(
        await kdsStore.readCachedContext(expectedDeviceId: 'dev-1'),
        isNull,
      );
    });

    test('corrupt bytes read as absent and are preserved; the credential '
        'keys are untouched', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesDeviceSessionSecretStore(
        prefs,
        keyPrefix: kPosDeviceSessionPrefix,
      );
      await store.write(
        const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
      );
      await prefs.setString(
        '$kPosDeviceSessionPrefix.context_cache',
        '{broken',
      );
      expect(await store.readCachedContext(expectedDeviceId: 'dev-1'), isNull);
      expect(
        prefs.getString('$kPosDeviceSessionPrefix.context_cache'),
        '{broken',
      );
      expect(await store.read(), isNotNull);
    });
  });
}
