/// RF-161 — the device-session SECRET store abstraction.
///
/// After a device redeems its one-time pairing code (`redeem_device_pairing`), the
/// backend returns a raw device-session token EXACTLY ONCE. That token is a bearer
/// secret: possession of it (with the device id) lets the device restore/operate.
///
/// STORAGE (platform-specific): NEVER logged, NEVER shown in the UI, and cleared
/// on unpair / server-side revocation.
///  * NATIVE (mobile/desktop): it MUST live only in OS-backed secure storage
///    (Keychain / Keystore / equivalent) — NEVER in `SharedPreferences`.
///  * HOSTED FLUTTER WEB (LIVE-DEVICE-001): an MVP compromise — it may live in
///    `localStorage` (via `shared_preferences`), because `flutter_secure_storage`
///    on the web is ITSELF just same-origin browser storage (AES-in-`localStorage`
///    with the key ALSO in `localStorage`), so it is no more protected there, and
///    its web backing was not reliably durable in the hosted build. The web token
///    is same-origin-JS-readable; the REAL controls remain **server-side**:
///    `restore_device_session` re-proves the token each launch (token-only, no
///    principal binding) and a lost device is **revoked** server-side (RF-160/161).
///    On a shared origin (POS `/pos` + KDS `/kds`) each surface uses a DISTINCT
///    storage key so they cannot read/clear each other's credential.
///
/// This is a pure-Dart seam so repositories depend on the abstraction and stay
/// testable with [InMemoryDeviceSessionSecretStore]; the OS-backed
/// (`flutter_secure_storage`) and web (`shared_preferences`) implementations live
/// in a Flutter package.
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

/// A single-slot store for the [DeviceSessionCredential] (RF-161). One device app
/// install holds at most one device-session secret. Native implementations MUST
/// use OS-backed secure storage; hosted Flutter Web may use `localStorage` /
/// `shared_preferences` (see the library note above). The token is cleared on
/// sign-out / unpair / server-side revocation (fail-closed).
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
