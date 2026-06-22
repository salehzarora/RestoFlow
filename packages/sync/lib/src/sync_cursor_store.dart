import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// A per-entity pull-cursor store (RF-063).
///
/// RF-063 uses in-memory state only (approved decision A3 — no Drift schema, no
/// migration). The interface exists so a later ticket can persist cursors (e.g.
/// to a `data_local` `sync_cursor` table, OFFLINE_SYNC §2.2) without touching
/// callers.
abstract class SyncCursorStore {
  /// The cursor last stored for [entity], or null if none.
  SyncCursor? cursorFor(String entity);

  /// Replace the cursor for [entity].
  void setCursor(String entity, SyncCursor cursor);

  /// A snapshot of every stored cursor, keyed by entity (for building a request).
  Map<String, SyncCursor> snapshot();

  /// Forget all cursors (e.g. on a forced re-sync).
  void clear();
}

/// The RF-063 in-memory implementation. Volatile by design: on app restart the
/// coordinator simply re-pulls from empty cursors (`sync_pull` is idempotent).
class InMemorySyncCursorStore implements SyncCursorStore {
  final Map<String, SyncCursor> _cursors = {};

  @override
  SyncCursor? cursorFor(String entity) => _cursors[entity];

  @override
  void setCursor(String entity, SyncCursor cursor) => _cursors[entity] = cursor;

  @override
  Map<String, SyncCursor> snapshot() => Map.unmodifiable(_cursors);

  @override
  void clear() => _cursors.clear();
}
