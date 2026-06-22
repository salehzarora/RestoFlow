/// A per-entity pull cursor (RF-063), mirroring the server's `(updated_at, id)`
/// cursor shape (RF-057 decision A1 — there is NO global change_seq).
///
/// The raw server `updated_at` string is preserved verbatim (not parsed to a
/// `DateTime`) so the value round-trips back to the server without any
/// timezone/precision drift; `id` is the tie-breaker uuid.
class SyncCursor {
  const SyncCursor({required this.updatedAt, required this.id});

  /// The server-authoritative `updated_at` of the last returned row (raw ISO).
  final String updatedAt;

  /// The id of the last returned row (tie-breaker).
  final String id;

  /// Parse the server cursor object `{ "updated_at": ..., "id": ... }`.
  /// Returns null when the server sent `null` (no rows / end of page stream).
  static SyncCursor? fromJson(Object? json) {
    if (json == null) return null;
    if (json is! Map) return null;
    final updatedAt = json['updated_at'];
    final id = json['id'];
    if (updatedAt is! String || id is! String) return null;
    return SyncCursor(updatedAt: updatedAt, id: id);
  }

  /// The wire shape the server expects back in `p_cursors`.
  Map<String, dynamic> toJson() => {'updated_at': updatedAt, 'id': id};

  @override
  bool operator ==(Object other) =>
      other is SyncCursor && other.updatedAt == updatedAt && other.id == id;

  @override
  int get hashCode => Object.hash(updatedAt, id);

  @override
  String toString() => 'SyncCursor($updatedAt, $id)';
}
