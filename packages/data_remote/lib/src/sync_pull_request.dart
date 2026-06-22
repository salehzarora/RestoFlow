import 'sync_cursor.dart';

/// A typed `app.sync_pull` request (RF-063).
///
/// Maps 1:1 to the RPC parameters. `entities` null lets the server return the
/// caller's full role-permitted set; the KDS coordinator passes the explicit
/// non-financial kitchen set so a financial entity is never even requested
/// (approved decision A5 — valid requests only).
class SyncPullRequest {
  const SyncPullRequest({
    this.entities,
    this.cursors = const {},
    this.limit = 500,
  });

  /// Requested entity names (`p_entities`), or null for the role-permitted set.
  final List<String>? entities;

  /// Per-entity `(updated_at, id)` cursors (`p_cursors`), keyed by entity name.
  final Map<String, SyncCursor> cursors;

  /// Page size (`p_limit`); server default 500, hard cap 1000.
  final int limit;

  /// The `params` map passed to `client.rpc('sync_pull', params: ...)`.
  ///
  /// `p_limit` is clamped to the server's accepted range [1, 1000] so an
  /// out-of-range limit never trips the server's `42501` validation (which the
  /// client would otherwise misread as a reauth signal) — only valid requests
  /// are ever sent (approved decision A5).
  Map<String, dynamic> toRpcParams({
    required String pinSessionId,
    required String deviceId,
  }) {
    return {
      'p_pin_session_id': pinSessionId,
      'p_device_id': deviceId,
      'p_entities': entities,
      'p_cursors': {
        for (final entry in cursors.entries) entry.key: entry.value.toJson(),
      },
      'p_limit': limit.clamp(1, 1000),
    };
  }
}
