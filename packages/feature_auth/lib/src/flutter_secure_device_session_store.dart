import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The OS-backed [DeviceSessionSecretStore] (RF-161): stores the raw device-session
/// token in the platform Keychain / Keystore via `flutter_secure_storage` — NEVER in
/// `SharedPreferences`, and it is never logged or surfaced.
///
/// The concrete plugin is injected (default: a standard [FlutterSecureStorage]) so the
/// class stays swappable; unit-level tests use `InMemoryDeviceSessionSecretStore`
/// instead (the plugin needs a real platform channel).
///
/// [POS-OFFLINE-OPERATIONS-002] Pass A: it also holds the schema-versioned
/// cached pairing-scope record ([DeviceContextCacheStore]) under its own key —
/// ids + the device-session HANDLE + display fields, never the token — so an
/// offline cold boot can prove a prior server-verified pairing. Cache reads
/// fail closed to `null` (unreadable / mismatched device id) WITHOUT touching
/// the token, and cache clears never delete the credential.
class FlutterSecureDeviceSessionStore
    implements DeviceSessionSecretStore, DeviceContextCacheStore {
  FlutterSecureDeviceSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _deviceIdKey = 'restoflow.device_id';
  static const _tokenKey = 'restoflow.device_session_token';
  static const _contextCacheKey = 'restoflow.device_context_cache';

  @override
  Future<DeviceSessionCredential?> read() async {
    final deviceId = await _storage.read(key: _deviceIdKey);
    final token = await _storage.read(key: _tokenKey);
    if (deviceId == null ||
        deviceId.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }
    return DeviceSessionCredential(deviceId: deviceId, sessionToken: token);
  }

  @override
  Future<void> write(DeviceSessionCredential credential) async {
    await _storage.write(key: _deviceIdKey, value: credential.deviceId);
    await _storage.write(key: _tokenKey, value: credential.sessionToken);
  }

  @override
  Future<void> clear() async {
    // Delete the token first so a partial failure never leaves a usable secret.
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _deviceIdKey);
  }

  @override
  Future<void> writeCachedContext(DeviceContext context) async {
    await _storage.write(
      key: _contextCacheKey,
      value: encodeCachedDeviceContext(context),
    );
  }

  @override
  Future<DeviceContext?> readCachedContext({
    required String expectedDeviceId,
  }) async {
    final String? raw;
    try {
      raw = await _storage.read(key: _contextCacheKey);
    } catch (_) {
      // An unreadable cache is ABSENT evidence — never a crash, never a
      // deletion, and the token keys are not touched.
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    return decodeCachedDeviceContext(raw, expectedDeviceId: expectedDeviceId);
  }

  @override
  Future<void> clearCachedContext() async {
    await _storage.delete(key: _contextCacheKey);
  }
}
