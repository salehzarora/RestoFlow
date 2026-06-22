/// The neutral transport seam for the `sync_pull` RPC (RF-063).
///
/// `SyncPullApi` depends on this abstraction, not on the Supabase SDK, so it is
/// unit-testable with a fake transport and free of any client/secret concerns
/// (approved decisions A1/A2). The Supabase-backed implementation lives in
/// `supabase_sync_rpc_transport.dart` and is the only file that imports the SDK.
library;

/// How a transport-level failure should be classified by the caller.
enum SyncTransportErrorKind {
  /// SQLSTATE 42501 — revoked/expired/invalid session -> reauth required.
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

/// Pure classification of a Postgres/PostgREST error `code` into a
/// [SyncTransportErrorKind] (no SDK import, so it is directly unit-testable).
///
/// `42501` (insufficient_privilege) is how `app.sync_pull` signals a revoked
/// device / revoked employee / expired PIN session (RF-057/RF-061). Because the
/// KDS coordinator only ever sends valid requests (approved decision A5), a
/// runtime `42501` is treated as the reauth signal. A throttling code maps to
/// transient; anything else server-side maps to server.
SyncTransportErrorKind classifyPostgrestCode(String? code) {
  if (code == null) return SyncTransportErrorKind.server;
  if (code == '42501') return SyncTransportErrorKind.auth;
  // PostgREST/HTTP throttling -> retryable.
  if (code == '429' || code == '503' || code == '504') {
    return SyncTransportErrorKind.transient;
  }
  return SyncTransportErrorKind.server;
}
