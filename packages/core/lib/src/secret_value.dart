/// Pure-Dart security primitives for handling secret material (RF-021).
///
/// [SecretRef] is a safe-to-log opaque handle; [SecretValue] wraps raw secret
/// material and never exposes it through `toString`, equality, or logging. Raw
/// access is only via the explicit, grep-auditable `revealFor*Boundary` methods.
/// See docs/SECURITY_AND_THREAT_MODEL.md section 12 (no plaintext, no secrets in
/// logs) and the RF-021 sections in the package READMEs.
library;

/// A safe-to-log, opaque reference to secret material stored elsewhere (e.g. a
/// key in platform secure storage). Contains NO raw secret material itself, so
/// it may appear in logs, errors, and persisted metadata.
///
/// Conventionally formatted as `ref:<name>`, e.g. `ref:local-db-key`,
/// `ref:device-session-token`.
final class SecretRef {
  /// Creates a reference. Rejects empty refs and refs that look like raw secret
  /// material (a defensive guard against accidentally passing a token as a ref).
  SecretRef(this.value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'value', 'SecretRef must not be empty');
    }
    if (_looksLikeRawSecret(value)) {
      // Do NOT echo the offending value (it may be sensitive); report opaquely.
      throw ArgumentError.value(
        '***',
        'value',
        'SecretRef must be an opaque reference (e.g. "ref:local-db-key"), '
            'not raw secret material',
      );
    }
  }

  /// The opaque reference string. Non-secret by contract; safe to log.
  final String value;

  static bool _looksLikeRawSecret(String v) {
    // JWT-shaped material, or implausibly long strings, are not valid refs.
    final looksJwt = RegExp(r'^eyJ[A-Za-z0-9_=-]+\.eyJ').hasMatch(v);
    if (looksJwt || v.length > 200) return true;
    // Best-effort: also reject the specific credential shapes the repo already
    // treats as secrets (mirrors tools/check_secrets.sh), so a token accidentally
    // passed where a SecretValue belongs is rejected rather than becoming a
    // safe-to-log ref. These are specific enough not to match opaque `ref:...`
    // values. High-entropy generic hex/base64 keys cannot be distinguished from
    // valid refs, so the primary protection remains the documented contract.
    const credentialShapes = <String>[
      r'sb_secret_[A-Za-z0-9]{16,}',
      r'sbp_[A-Za-z0-9]{20,}',
      r'AKIA[0-9A-Z]{16}',
      r'AIza[0-9A-Za-z_-]{35}',
      r'-----BEGIN [A-Z ]*PRIVATE KEY-----',
      r'xox[baprs]-[A-Za-z0-9-]{10,}',
    ];
    return credentialShapes.any((p) => RegExp(p).hasMatch(v));
  }

  @override
  String toString() => 'SecretRef($value)';

  @override
  bool operator ==(Object other) => other is SecretRef && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An opaque wrapper around raw secret material (a token, key, or credential).
///
/// Safety contract (RF-021):
/// - `toString()` is redacted and never reveals the raw value.
/// - Equality and `hashCode` are identity-based — they never compare or expose
///   the raw value (no content-based equality that could leak via collections).
/// - There is no serializer/getter that returns the raw value implicitly. Raw
///   access is ONLY through the explicit, grep-auditable `revealFor*Boundary`
///   methods, intended to be called at exactly one site each.
final class SecretValue {
  /// Wraps raw secret material. Most secrets (tokens, base64/hex keys) are
  /// strings; binary keys should be encoded (hex/base64) before wrapping.
  ///
  /// Rejects empty / whitespace-only values (almost always a mistake). The
  /// error never echoes the value.
  SecretValue(this._secret) {
    if (_secret.trim().isEmpty) {
      throw ArgumentError.value(
        '***',
        'value',
        'SecretValue must not be empty or whitespace-only',
      );
    }
  }

  final String _secret;

  /// Reveals the raw value ONLY for handing to platform secure storage.
  /// Grep this method name to audit every secure-storage write/read site.
  String revealForStorageBoundary() => _secret;

  /// Reveals the raw value ONLY for handing to a crypto/cipher boundary
  /// (e.g. a SQLCipher `PRAGMA key`). Grep this name to audit every crypto site.
  String revealForCryptoBoundary() => _secret;

  @override
  String toString() => 'SecretValue(***redacted***)';

  // Identity-based equality only: never compares or exposes the raw value.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}
