/// RestoFlow sync package - offline sync orchestration.
///
/// Owns (per docs/ARCHITECTURE.md section 3) the sync engine: cadence, cursors,
/// retry/backoff. RF-063 adds the PULL-ONLY KDS coordinator — polling-first
/// `app.sync_pull` consumption with in-memory `(updated_at, id)` cursors,
/// `has_more` page draining, exponential backoff on transient failure, and a
/// reauth-required hard stop on `42501`. There is NO push/outbox here yet and
/// NO realtime (DECISION D-010); the cursor store is behind an interface so a
/// later ticket can persist it (approved decision A3). Pure Dart.
library;

export 'src/backoff.dart';
export 'src/kds_sync_coordinator.dart';
export 'src/kds_sync_state.dart';
export 'src/sync_cursor_store.dart';
