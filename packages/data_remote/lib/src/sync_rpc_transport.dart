/// The neutral transport seam for the `sync_pull` RPC (RF-063).
///
/// `SyncPullApi` depends on this abstraction, not on the Supabase SDK, so it is
/// unit-testable with a fake transport and free of any client/secret concerns
/// (approved decisions A1/A2). The Supabase-backed implementation lives in
/// `supabase_sync_rpc_transport.dart` and is the only file that imports the SDK.
library;

/// How a transport-level failure should be classified by the caller.
enum SyncTransportErrorKind {
  /// A SESSION-CLASS refusal -> reauth required.
  ///
  /// [POS-OFFLINE-OPERATIONS-002 Pass B] This is NO LONGER "any SQLSTATE
  /// 42501". Our RPCs raise 42501 for many different things — batch-shape
  /// validation, permission denials, RLS refusals — and only the SESSION-CLASS
  /// subset is fixed by signing in again. The POS outbox turns a batch-level
  /// `auth` failure into the durable AUTH_HOLD state, released ONLY by a fresh
  /// ONLINE sign-in; classifying a non-session 42501 as `auth` therefore
  /// parked queued orders behind a hold that a re-auth could never release
  /// (the re-auth replays the identical refusal, or — for a PostgREST
  /// `permission denied for function sync_push` — cannot even run, because the
  /// PIN sign-in dies on the same dead transport).
  ///
  /// A 42501 maps here ONLY when its MESSAGE matches one of the session-class
  /// refusals `app.sync_push` raises from its preamble (source of truth:
  /// `supabase/migrations/20260803090000_kitchen_dispatch_enforce_001_server_guard.sql`):
  ///
  ///   * 'PIN session not found'
  ///   * 'PIN session is not valid (inactive/ended/expired)'
  ///   * 'backing device session not found'
  ///   * 'device_id does not match the PIN session device'
  ///
  /// Every other 42501 maps to [server] — the safe direction: the operation
  /// stays visible, sweepable and retryable instead of stuck behind a hold.
  /// An unknown FUTURE session-class message degrades the same way
  /// (retryable-visible), never into an unreleasable hold. A server
  /// error-contract ticket could replace this string matching with a typed
  /// discriminator later.
  auth,

  /// Network / timeout / 5xx / rate-limited -> retry with backoff.
  transient,

  /// A non-transient server-side error response.
  server,

  /// Could not be classified.
  unknown,
}

/// A transport error raised by [SyncRpcTransport.invoke].
class SyncTransportException implements Exception {
  const SyncTransportException(this.kind, {this.code, this.message});

  final SyncTransportErrorKind kind;
  final String? code;
  final String? message;

  @override
  String toString() => 'SyncTransportException($kind, code=$code, $message)';
}

/// A minimal RPC transport: invoke a Postgres function by name with a JSON
/// params map, returning the decoded JSON result, or throwing a
/// [SyncTransportException].
abstract class SyncRpcTransport {
  Future<Object?> invoke(String function, Map<String, dynamic> params);
}

/// [POS-OFFLINE-OPERATIONS-002 Pass B] The stable, lower-cased fragments of
/// OUR OWN session-class 42501 raise messages (see [SyncTransportErrorKind.auth]
/// for the full rationale and the owning migration file). Matched with a
/// case-insensitive CONTAINS so the `sync_push:` / `sync_pull:` / `pos_menu:`
/// function prefix and any trailing detail never defeat the match. Kept
/// deliberately NARROW: a fragment must be specific enough that no
/// validation/permission/RLS message can contain it.
const List<String> _sessionClass42501Fragments = [
  'pin session not found',
  'pin session is not valid',
  'backing device session not found',
  'does not match the pin session device',
];

/// Pure classification of a Postgres/PostgREST error `code` (+ its `message`)
/// into a [SyncTransportErrorKind] (no SDK import, so it is directly
/// unit-testable).
///
/// `42501` (insufficient_privilege) is NOT a single-meaning signal: our RPCs
/// raise it for session refusals AND for batch-shape validation, permission
/// denials and RLS refusals. Only the session-class subset is re-authenticatable,
/// so `42501` maps to [SyncTransportErrorKind.auth] ONLY when [message] matches
/// the allowlist in [_sessionClass42501Fragments]; every other `42501`
/// (including a missing message) maps to `server` — retryable-visible, never a
/// stuck AUTH_HOLD. A throttling code maps to transient; anything else
/// server-side maps to server.
SyncTransportErrorKind classifyPostgrestCode(String? code, {String? message}) {
  if (code == null) return SyncTransportErrorKind.server;
  if (code == '42501') {
    final normalized = message?.toLowerCase() ?? '';
    for (final fragment in _sessionClass42501Fragments) {
      if (normalized.contains(fragment)) return SyncTransportErrorKind.auth;
    }
    return SyncTransportErrorKind.server;
  }
  // PostgREST/HTTP throttling -> retryable.
  if (code == '429' || code == '503' || code == '504') {
    return SyncTransportErrorKind.transient;
  }
  return SyncTransportErrorKind.server;
}
