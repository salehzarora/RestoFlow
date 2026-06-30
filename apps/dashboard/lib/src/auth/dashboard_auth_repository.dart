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

/// A user-safe classification of a sign-in / sign-up failure. The UI maps each
/// to a localized message; the raw provider message is never surfaced.
enum AuthErrorKind {
  /// Wrong email/password (or an otherwise rejected credential).
  invalidCredentials,

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
}
