/// RF-161 — the device-session SECRET store abstraction.
///
/// After a device redeems its one-time pairing code (`redeem_device_pairing`), the
/// backend returns a raw device-session token EXACTLY ONCE. That token is a bearer
/// secret: possession of it (with the device id) lets the device restore/operate. It
/// therefore MUST live only in OS-backed secure storage (Keychain / Keystore /
/// equivalent) — NEVER in `SharedPreferences`, NEVER logged, NEVER shown in the UI.
///
/// This is a pure-Dart seam so repositories depend on the abstraction and stay
/// testable with [InMemoryDeviceSessionSecretStore]; the real OS-backed
/// implementation (`flutter_secure_storage`) lives in a Flutter package.
library;

/// The secret a paired device must keep: the raw session [sessionToken] (bearer
/// secret) plus its non-secret [deviceId] (needed to call `restore_device_session`,
/// which re-derives the server-validated scope). Stored together in secure storage.
class DeviceSessionCredential {
  const DeviceSessionCredential({
    required this.deviceId,
    required this.sessionToken,
  });

  /// The non-secret device id (needed to restore the session server-side).
  final String deviceId;

  /// The raw device-session token — a BEARER SECRET. Never log or display it.
  final String sessionToken;

  @override
  bool operator ==(Object other) =>
      other is DeviceSessionCredential &&
      other.deviceId == deviceId &&
      other.sessionToken == sessionToken;

  @override
  int get hashCode => Object.hash(deviceId, sessionToken);

  /// A redacted description — NEVER exposes the token.
  @override
  String toString() =>
      'DeviceSessionCredential(deviceId: $deviceId, token: ***)';
}

/// A secure, single-slot store for the [DeviceSessionCredential] (RF-161). One
/// device app install holds at most one device-session secret. Implementations MUST
/// use OS-backed secure storage; the token is cleared on sign-out / unpair /
/// server-side revocation (fail-closed).
abstract interface class DeviceSessionSecretStore {
  /// Persists (overwriting any prior) the device-session credential securely.
  Future<void> write(DeviceSessionCredential credential);

  /// Reads the stored credential, or null when none/absent (never throws).
  Future<DeviceSessionCredential?> read();

  /// Clears the stored credential (idempotent).
  Future<void> clear();
}

/// An in-memory [DeviceSessionSecretStore] for tests and dev/preview only — it does
/// NOT protect a real production secret on a device.
class InMemoryDeviceSessionSecretStore implements DeviceSessionSecretStore {
  DeviceSessionCredential? _value;

  @override
  Future<DeviceSessionCredential?> read() async => _value;

  @override
  Future<void> write(DeviceSessionCredential credential) async {
    _value = credential;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}
