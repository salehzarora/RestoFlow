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
// RF-071: durable Drift-backed print spool store + table.
export 'src/drift_print_spool_store.dart';
// KITCHEN-MODE-001C2A: encrypted kitchen spool foundation (field-level
// AES-256-GCM cipher + AAD, explicit key manager, closed payload models,
// bounded Drift store). DORMANT: no production composition uses this yet.
export 'src/kitchen_spool/drift_kitchen_spool_store.dart';
export 'src/kitchen_spool/kitchen_spool_aad.dart';
export 'src/kitchen_spool/kitchen_spool_cipher.dart';
export 'src/kitchen_spool/kitchen_spool_key_manager.dart';
export 'src/kitchen_spool/kitchen_spool_payload.dart';
export 'src/kitchen_spool/kitchen_spool_status.dart';
export 'src/local_database.dart';
// RF-030: local menu/catalog repository.
export 'src/menu_repository.dart';
// RF-021: fail-closed data-at-rest opening policy around the injected executor.
export 'src/protected_local_database.dart';
export 'src/sync_operation_state.dart';
// RF-030: local menu/catalog tables.
export 'src/tables/item_sizes.dart';
export 'src/tables/item_variants.dart';
// KITCHEN-MODE-001C2A: encrypted kitchen spool table.
export 'src/tables/kitchen_spool_jobs.dart';
export 'src/tables/menu_categories.dart';
export 'src/tables/menu_items.dart';
export 'src/tables/modifier_options.dart';
export 'src/tables/modifiers.dart';
export 'src/tables/outbox_operations.dart';
export 'src/tables/processed_pull_log.dart';
export 'src/tables/syncable_columns.dart';
