/// The dashboard's real auth (sign-in / sign-up / sign-out) seam (RF-151).
///
/// A pure-Dart interface so the login/sign-up UI and the auth flow are unit- and
/// widget-testable with a fake; the real Supabase GoTrue implementation lives in
/// `supabase_dashboard_auth.dart` (the ONLY file that imports the `supabase`
/// SDK). SECURITY: implementations use the PUBLIC anon key only (DECISION D-011),
/// never a service-role key; outcomes NEVER carry the raw provider error text, a
/// token, or the password — only a safe [AuthErrorKind] the UI localizes.
library;

/// Whether the dashboard currently holds an authenticated Supabase session.
/// [unknown] is the brief startup state before the first auth event resolves.
enum AuthSessionStatus { unknown, signedOut, signedIn }

/// A user-safe classification of an auth failure. The UI maps each to a
/// localized message; the raw provider message is never surfaced.
///
/// AUTH-FLOW-256 widened this. Sign-in used to map EVERY provider exception to
/// [invalidCredentials], so a rate-limited, suspended or unreachable project all
/// told the operator their password was wrong — the one explanation guaranteed
/// to waste their time. Each value below is a distinct thing we can honestly
/// say; the classification itself lives in `auth_failure_classifier.dart`.
enum AuthErrorKind {
  /// Wrong email/password (or an otherwise rejected credential).
  invalidCredentials,

  /// The account exists and the password was accepted, but the email address
  /// has not been confirmed yet.
  emailNotConfirmed,

  /// The account cannot be used (banned/suspended). Deliberately vague to the
  /// user; it is never presented as a credential problem.
  accountUnavailable,

  /// Too many attempts, or too many emails requested, in a short window.
  rateLimited,

  /// The auth service itself is unavailable — 402 (project suspended/over quota)
  /// or 5xx. NEVER a credential problem.
  serviceUnavailable,

  /// A new password was rejected as too weak by the server's policy.
  weakPassword,

  /// The new password is the same as the current one.
  samePassword,

  /// A confirmation/recovery link is expired, already used, or was opened where
  /// the flow that created it cannot be completed (PKCE verifier absent).
  linkExpired,

  /// The backend could not be reached.
  network,

  /// Anything else (unclassified) — shown as a generic safe error.
  unknown,
}

/// The result of a sign-in / sign-up attempt. User-safe by construction.
sealed class AuthOutcome {
  const AuthOutcome();
}

/// Credentials accepted and a session is now active.
class AuthSignedIn extends AuthOutcome {
  const AuthSignedIn();
}

/// Sign-up succeeded but Supabase requires email confirmation, so there is no
/// session yet — the UI shows an honest "check your email" state.
class AuthConfirmationRequired extends AuthOutcome {
  const AuthConfirmationRequired();
}

/// A password-reset email request was accepted.
///
/// AUTH-FLOW-256: this is returned for a well-formed request whether or not the
/// address belongs to an account. Reporting "no such user" here would turn the
/// reset form into an account-existence oracle, so the caller cannot distinguish
/// the two and neither can an attacker.
class AuthPasswordResetRequested extends AuthOutcome {
  const AuthPasswordResetRequested();
}

/// A recovery session's password was replaced. The session is now an ordinary
/// authenticated session and the normal context gate takes over.
class AuthPasswordUpdated extends AuthOutcome {
  const AuthPasswordUpdated();
}

/// The attempt failed; [kind] is a safe, localizable classification.
class AuthError extends AuthOutcome {
  const AuthError(this.kind);

  final AuthErrorKind kind;
}

/// The dashboard real-auth seam. Demo mode never touches this (the demo path
/// bypasses auth entirely); real mode drives the login/sign-up/onboarding flow.
abstract interface class DashboardAuthRepository {
  /// The current session status (synchronous snapshot).
  AuthSessionStatus get status;

  /// Emits whenever the session status changes (sign-in, sign-out, expiry).
  Stream<AuthSessionStatus> get statusChanges;

  /// Signs in with email + password. Fails closed: a wrong credential yields
  /// [AuthError]; a missing session is never treated as success.
  Future<AuthOutcome> signIn({required String email, required String password});

  /// Creates an account with email + password. Returns [AuthSignedIn] when a
  /// session is immediately available, or [AuthConfirmationRequired] when the
  /// project requires email confirmation first.
  Future<AuthOutcome> signUp({required String email, required String password});

  /// Clears the session (and any cached auth state).
  Future<void> signOut();

  // -- AUTH-FLOW-256: password recovery ------------------------------------

  /// Emits `true` once the provider reports that this session arrived through a
  /// PASSWORD-RECOVERY link, and `false` once recovery is finished or abandoned.
  ///
  /// A recovery session is authenticated, which is exactly why it needs its own
  /// signal: without one the Dashboard would treat "clicked the reset link" as
  /// "signed in", drop the operator on a dashboard, and never offer them the new
  /// password they came for. That is the bug this stream exists to prevent.
  Stream<bool> get passwordRecoveryChanges;

  /// True when the current session is a recovery session awaiting a new
  /// password (synchronous snapshot of [passwordRecoveryChanges]).
  bool get isPasswordRecovery;

  /// Sends a password-reset email. Returns [AuthPasswordResetRequested] for any
  /// well-formed address — see that class for why it does not disclose whether
  /// the account exists. Genuine transport/rate-limit failures still surface as
  /// [AuthError].
  Future<AuthOutcome> requestPasswordReset({required String email});

  /// Replaces the password of the CURRENT recovery session. Returns
  /// [AuthPasswordUpdated] on success.
  Future<AuthOutcome> completePasswordRecovery({required String newPassword});

  /// Abandons an in-progress recovery without changing the password: the
  /// recovery session is signed out so it can never be replayed as an ordinary
  /// session, and the operator is returned to sign-in.
  Future<void> cancelPasswordRecovery();
}
