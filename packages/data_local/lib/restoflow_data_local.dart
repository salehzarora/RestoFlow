/// RestoFlow data_local package - local sync foundation (RF-018).
///
/// Owns (per docs/ARCHITECTURE.md section 3) the Drift/SQLite local store: the
/// outbox, the processed-pull/inbox dedupe ledger, idempotency keys
/// `(device_id, local_operation_id)`, the sync-operation state vocabulary, and
/// the reusable syncable column-set / tombstone-revision contract. Pure Dart
/// (no Flutter). Business entity tables and the push/pull sync engine are later
/// tickets (RF-030+ / RF-056 / RF-057).
library;

export 'src/converters.dart';
export 'src/local_database.dart';
// RF-030: local menu/catalog repository.
export 'src/menu_repository.dart';
// RF-021: fail-closed data-at-rest opening policy around the injected executor.
export 'src/protected_local_database.dart';
export 'src/sync_operation_state.dart';
// RF-030: local menu/catalog tables.
export 'src/tables/item_sizes.dart';
export 'src/tables/item_variants.dart';
export 'src/tables/menu_categories.dart';
export 'src/tables/menu_items.dart';
export 'src/tables/modifier_options.dart';
export 'src/tables/modifiers.dart';
export 'src/tables/outbox_operations.dart';
export 'src/tables/processed_pull_log.dart';
export 'src/tables/syncable_columns.dart';
