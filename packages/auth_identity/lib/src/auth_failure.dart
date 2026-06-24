/// Typed failure outcomes for auth/identity calls (RF-108), mirroring the
/// sealed-failure pattern of `data_remote`'s `SyncFailure`. Returned as the
/// `Failure` arm of `Result<T, AuthFailure>` so callers branch on an exhaustive
/// sealed type instead of catching exceptions across the layer boundary
/// (ARCHITECTURE section 9.2).
///
/// SECURITY: [message] is a developer-facing diagnostic only (never UI chrome)
/// and MUST NOT contain memberships, email, PINs, tokens, or any secret.
sealed class AuthFailure {
  const AuthFailure(this.message);

  /// A non-localized developer diagnostic. Never contains PII/secrets.
  final String message;
}

/// No authenticated session is present locally - show sign-in.
class AuthUnauthenticatedFailure extends AuthFailure {
  const AuthUnauthenticatedFailure([
    super.message = 'unauthenticated: no session',
  ]);
}

/// `get_my_context` raised SQLSTATE 42501: the principal is unauthenticated,
/// unlinked, or an inactive app user. Treat as auth-denied (sign out; NO retry).
class AuthDeniedFailure extends AuthFailure {
  const AuthDeniedFailure([super.message = 'auth denied (42501)']);
}

/// The RPC response was missing / `ok != true` / malformed and could not be
/// parsed safely.
class AuthInvalidResponseFailure extends AuthFailure {
  const AuthInvalidResponseFailure([
    super.message = 'invalid get_my_context response',
  ]);
}

/// A membership carried a role outside the six tenant keys (fail-closed: deny).
class AuthUnknownRoleFailure extends AuthFailure {
  const AuthUnknownRoleFailure(this.role, [String? message])
    : super(message ?? 'unknown membership role');

  /// The offending wire value (a role label - not PII or a secret).
  final String role;
}

/// `start_pin_session` returned NULL - the PIN verifier did not match.
class AuthWrongPinFailure extends AuthFailure {
  const AuthWrongPinFailure([super.message = 'wrong pin']);
}

/// `start_pin_session` raised SQLSTATE 42501 - locked, or a structural /
/// precondition failure (device session, employee, membership, or lockout).
class AuthLockedOrPreconditionFailure extends AuthFailure {
  const AuthLockedOrPreconditionFailure([
    super.message = 'pin session precondition failed (42501)',
  ]);
}

/// A transient transport failure (offline / timeout / 5xx / rate-limited). Safe
/// to retry with backoff.
class AuthNetworkFailure extends AuthFailure {
  const AuthNetworkFailure([super.message = 'transient network failure']);
}

/// An unclassified server-side or otherwise unexpected failure.
class AuthUnknownFailure extends AuthFailure {
  const AuthUnknownFailure([super.message = 'unknown auth failure']);
}
