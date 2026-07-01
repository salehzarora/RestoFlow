import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The OS-backed [DeviceSessionSecretStore] (RF-161): stores the raw device-session
/// token in the platform Keychain / Keystore via `flutter_secure_storage` — NEVER in
/// `SharedPreferences`, and it is never logged or surfaced.
///
/// The concrete plugin is injected (default: a standard [FlutterSecureStorage]) so the
/// class stays swappable; unit-level tests use `InMemoryDeviceSessionSecretStore`
/// instead (the plugin needs a real platform channel).
class FlutterSecureDeviceSessionStore implements DeviceSessionSecretStore {
  FlutterSecureDeviceSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _deviceIdKey = 'restoflow.device_id';
  static const _tokenKey = 'restoflow.device_session_token';

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
}
