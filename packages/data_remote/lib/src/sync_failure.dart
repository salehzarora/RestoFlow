/// Typed failure outcomes of a `sync_pull` call (RF-063).
///
/// Returned as the `Failure` arm of `Result<SyncPullResponse, SyncFailure>` so
/// callers branch on an exhaustive sealed type rather than catching exceptions
/// across the layer boundary (ARCHITECTURE §9.2).
sealed class SyncFailure {
  const SyncFailure(this.message);

  /// A non-localized, developer-facing diagnostic message (never UI chrome).
  final String message;
}

/// The server rejected the session: a revoked device, revoked employee, or an
/// expired/invalid PIN session (`app.sync_pull` raises SQLSTATE `42501`).
///
/// The client MUST stop polling and surface a re-authentication state; it must
/// NOT silently retry (approved decision A5; SECURITY T-004/T-005).
class ReauthRequiredFailure extends SyncFailure {
  const ReauthRequiredFailure([super.message = 'reauth required (42501)']);
}

/// A transient failure (offline / timeout / 5xx / rate-limited). Safe to retry
/// with backoff while keeping the last successful data (OFFLINE_SYNC §6/§15).
class TransientFailure extends SyncFailure {
  const TransientFailure([super.message = 'transient sync failure']);
}

/// A non-transient server error that is not an auth/revocation signal.
class ServerFailure extends SyncFailure {
  const ServerFailure([super.message = 'server sync failure']);
}

/// The response envelope was missing/`ok != true`/malformed and could not be
/// parsed safely.
class InvalidResponseFailure extends SyncFailure {
  const InvalidResponseFailure([super.message = 'invalid sync_pull response']);
}
