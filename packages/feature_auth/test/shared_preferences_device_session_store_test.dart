import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LIVE-DEVICE-001 — the web device-session store must PERSIST the paired-device
/// credential across an app restart / browser refresh, so a paired POS/KDS tablet
/// stays paired. shared_preferences is web-durable (localStorage per origin); the
/// test proves a fresh store instance reads what a prior instance wrote (the
/// restart), plus clear() and honest fail-closed on a partial value.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const cred = DeviceSessionCredential(
    deviceId: 'device-123',
    sessionToken: 'raw-token-secret',
  );

  test('a written credential SURVIVES a restart (a fresh store instance reads '
      'it)', () async {
    // Instance 1 (this "run") writes.
    final prefs1 = await SharedPreferences.getInstance();
    await SharedPreferencesDeviceSessionSecretStore(prefs1).write(cred);

    // Instance 2 (a "refresh" — a new store over the persisted backing) reads.
    final prefs2 = await SharedPreferences.getInstance();
    final restored = await SharedPreferencesDeviceSessionSecretStore(
      prefs2,
    ).read();

    expect(restored, cred);
    expect(restored!.deviceId, 'device-123');
    expect(restored.sessionToken, 'raw-token-secret');
  });

  test('read() is null when nothing is stored (-> pairing screen)', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(
      await SharedPreferencesDeviceSessionSecretStore(prefs).read(),
      isNull,
    );
  });

  test(
    'clear() removes the credential (unpair) — a later read is null',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesDeviceSessionSecretStore(prefs);
      await store.write(cred);
      expect(await store.read(), isNotNull);

      await store.clear();
      expect(await store.read(), isNull);
      // Idempotent.
      await store.clear();
      expect(await store.read(), isNull);
    },
  );

  test(
    'a PARTIAL value (only device id, no token) fails closed to null — never '
    'a half-restored session',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'restoflow.device_session.v1.device_id',
        'device-123',
      );
      // token key intentionally absent
      expect(
        await SharedPreferencesDeviceSessionSecretStore(prefs).read(),
        isNull,
      );
    },
  );

  test('the token is never exposed by toString (redacted)', () {
    expect(cred.toString(), isNot(contains('raw-token-secret')));
    expect(cred.toString(), contains('device-123'));
    expect(cred.toString(), contains('***'));
  });
}
