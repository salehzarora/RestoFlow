import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A `shared_preferences`-backed [DeviceSessionSecretStore] (LIVE-DEVICE-001) —
/// used ON WEB so a paired POS/KDS tablet stays paired across an F5 / browser
/// restart, which the `flutter_secure_storage` web backing does NOT reliably do
/// in the hosted build. It mirrors the exact `{deviceId, sessionToken}` contract
/// of [FlutterSecureDeviceSessionStore]; `restore_device_session` is token-proven
/// server-side (no principal binding), so persisting these two values is all that
/// is needed to survive refresh.
///
/// SECURITY: this deliberately DIVERGES from the "device token lives only in
/// flutter_secure_storage" rule **for web only**. On the web there is no OS
/// keychain — `flutter_secure_storage` there is itself just AES-in-`localStorage`
/// with the AES key ALSO kept in the same-origin `localStorage` (readable, and so
/// decryptable, by any same-origin script). So on web this is NO LESS protected
/// than that plugin, while being reliably durable (the same `localStorage` the
/// RF-114 outbox + RF-118 PIN store already use). On NATIVE, the OS-backed
/// [FlutterSecureDeviceSessionStore] MUST still be used (a real Keychain/Keystore)
/// — the app selects this store only under `kIsWeb`. The token is still NEVER
/// logged or shown, and is cleared on unpair / server-side revocation.
class SharedPreferencesDeviceSessionSecretStore
    implements DeviceSessionSecretStore {
  SharedPreferencesDeviceSessionSecretStore(
    this._prefs, {
    String keyPrefix = _defaultPrefix,
  }) : _prefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _prefix;

  static const String _defaultPrefix = 'restoflow.device_session.v1';

  String get _deviceIdKey => '$_prefix.device_id';
  String get _tokenKey => '$_prefix.session_token';

  @override
  Future<DeviceSessionCredential?> read() async {
    final deviceId = _prefs.getString(_deviceIdKey);
    final token = _prefs.getString(_tokenKey);
    // Both must be present + non-empty; a partial value is treated as absent
    // (fail closed to the pairing screen), never a half-restored session.
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
    await _prefs.setString(_deviceIdKey, credential.deviceId);
    await _prefs.setString(_tokenKey, credential.sessionToken);
  }

  @override
  Future<void> clear() async {
    // Remove the token first so a partial failure never leaves a usable secret.
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_deviceIdKey);
  }
}
