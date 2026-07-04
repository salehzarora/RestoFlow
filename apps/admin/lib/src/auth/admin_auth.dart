/// RF-119-b — the platform-operator auth + MFA seam for the Admin app.
///
/// This is the ONLY interface the sign-in / MFA UI depends on, and the ONLY
/// place that (in its Supabase implementation) touches GoTrue. It is PURE Dart —
/// no Supabase import — so every widget/flow test drives it with an in-memory
/// fake and never contacts a backend.
///
/// SECURITY: implementations use the PUBLIC anon key only (DECISION D-011 — never
/// a service-role key), NEVER auto-grant platform-admin (a grant is a manual DBA
/// action, D-026), NEVER fake an aal2 session, and NEVER store the TOTP secret or
/// any token in app storage. Platform data reads remain gated server-side by
/// `app.platform_admin_guard` (grant + aal2 + reason); the assurance reported
/// here is a UX signal only.
library;

/// A safe, generic sign-in failure (no raw provider message ever surfaced).
enum AdminSignInError {
  /// Wrong email/password (or no session returned).
  invalidCredentials,

  /// A transient network/backend problem — safe to retry.
  network,

  /// Anything else, unclassified.
  unknown,
}

/// A safe, generic MFA verification failure.
enum AdminMfaVerifyError {
  /// The 6-digit code was rejected (wrong / expired).
  invalidCode,

  /// A transient network/backend problem — safe to retry.
  network,

  /// Anything else, unclassified.
  unknown,
}

/// A snapshot of the current session's MFA assurance (from GoTrue's
/// `getAuthenticatorAssuranceLevel` + `listFactors`). Drives the MFA screen:
/// - [isAal2] true  -> already MFA-verified (enter after the server confirms).
/// - [isAal2] false + [hasVerifiedFactor] true  -> CHALLENGE an enrolled factor.
/// - [isAal2] false + [hasVerifiedFactor] false -> ENROLL a new TOTP factor.
class AdminMfaAssurance {
  const AdminMfaAssurance({
    required this.isAal2,
    required this.hasVerifiedFactor,
    this.verifiedFactorId,
  });

  /// The current session assurance level is aal2.
  final bool isAal2;

  /// An ENROLLED + VERIFIED TOTP factor exists (so a challenge is possible).
  final bool hasVerifiedFactor;

  /// The id of a verified TOTP factor to challenge (null when none).
  final String? verifiedFactorId;
}

/// The one-time result of starting a TOTP enrollment. The [secret] and [uri] are
/// shown to the operator ONCE during enrolment (to add to an authenticator app)
/// and are NEVER persisted or logged.
class AdminTotpEnrollment {
  const AdminTotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
  });

  /// The new (unverified) factor id — passed to verify to complete enrolment.
  final String factorId;

  /// The manual-entry setup key (Base32). Shown once; never stored.
  final String secret;

  /// The `otpauth://` provisioning URI (for a QR code). Shown once; never stored.
  final String uri;
}

/// Platform-operator sign-in + TOTP MFA. See the library doc for the security
/// contract. All methods are safe to call with no session (fail-closed).
///
/// The valueless methods follow the codebase's `PinLoginError?` idiom: a `null`
/// return means SUCCESS; a non-null enum is a safe, localizable failure.
abstract interface class AdminAuthService {
  /// Whether a GoTrue session currently exists (any assurance level).
  bool get hasSession;

  /// The signed-in email of the current session, or null. NON-secret; shown so
  /// the operator can confirm which account is signed in.
  String? get currentEmail;

  /// Emits true when a session exists, false when signed out. Lets the gate
  /// re-evaluate after sign-in / sign-out without a manual refresh.
  Stream<bool> get sessionChanges;

  /// Signs in with email + password (PUBLIC anon key). Returns null on success
  /// (an aal1 session), or a safe [AdminSignInError]. NEVER grants platform-admin.
  Future<AdminSignInError?> signInWithPassword({
    required String email,
    required String password,
  });

  /// Signs the operator out and clears the local session.
  Future<void> signOut();

  /// The current session's MFA assurance snapshot (see [AdminMfaAssurance]).
  Future<AdminMfaAssurance> assurance();

  /// Begins a TOTP enrolment: returns the one-time [AdminTotpEnrollment]. The
  /// secret/URI must be shown only during enrolment and never stored. Throws
  /// [AdminMfaException] on failure (mapped to a safe UI message by the caller).
  Future<AdminTotpEnrollment> enrollTotp();

  /// Verifies a 6-digit TOTP [code] for [factorId] (a fresh enrolment factor OR
  /// an existing verified factor). On success the session is upgraded to aal2 and
  /// saved by the client; the caller then RE-FETCHES `get_my_context` so entry is
  /// gated on the SERVER-derived assurance, not this call. Returns null on
  /// success or a safe [AdminMfaVerifyError] (wrong code -> invalidCode).
  Future<AdminMfaVerifyError?> verifyTotp({
    required String factorId,
    required String code,
  });
}

/// Thrown by [AdminAuthService.enrollTotp] on failure. Carries only a safe,
/// developer-facing message (never a raw provider error / secret).
class AdminMfaException implements Exception {
  const AdminMfaException([this.message = 'mfa enrolment failed']);

  final String message;

  @override
  String toString() => 'AdminMfaException: $message';
}
