import 'package:drift/drift.dart';

import 'converters.dart';
import 'sync_operation_state.dart';
import 'tables/item_sizes.dart';
import 'tables/item_variants.dart';
import 'tables/menu_categories.dart';
import 'tables/menu_items.dart';
import 'tables/modifier_options.dart';
import 'tables/modifiers.dart';
import 'tables/outbox_operations.dart';
import 'tables/processed_pull_log.dart';

part 'local_database.g.dart';

/// The RestoFlow local SQLite/Drift database.
///
/// Contains the RF-018 sync foundation — the [OutboxOperations] outbox and the
/// [ProcessedPullLog] inbox/dedupe ledger — plus the RF-030 local **menu**
/// catalog ([MenuCategories], [MenuItems], [ItemSizes], [ItemVariants],
/// [Modifiers], [ModifierOptions]). Menu rows carry the `SyncableColumns`
/// contract (incl. the `deleted_at` tombstone) and integer `_minor` money only
/// (DECISION D-007). No money engine / totals / order logic lives here.
///
/// The sync engine (push RF-056 / pull RF-057), encryption at rest (RF-021),
/// auth/JWT (RF-050) and conflict resolution are all OUT of scope here.
@DriftDatabase(
  tables: [
    OutboxOperations,
    ProcessedPullLog,
    MenuCategories,
    MenuItems,
    ItemSizes,
    ItemVariants,
    Modifiers,
    ModifierOptions,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  /// Opens the database on [executor] (e.g. `NativeDatabase.memory()` in tests).
  LocalDatabase(super.executor);

  /// v1 = RF-018 sync foundation; v2 = RF-030 menu catalog tables.
  @override
  int get schemaVersion => 2;

  /// Migration strategy (RF-030).
  ///
  /// `onCreate` builds the full current schema. The v1 -> v2 upgrade ADDS the
  /// six menu tables only — it never drops or recreates the RF-018 tables
  /// (`outbox_operations`, `processed_pull_log`). Foreign keys are enabled so
  /// the menu FK relationships (item->category, size/variant/modifier->item,
  /// option->modifier) are enforced.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Parent-first so FK references resolve. Existing RF-018 tables are
        // left untouched.
        await m.createTable(menuCategories);
        await m.createTable(menuItems);
        await m.createTable(itemSizes);
        await m.createTable(itemVariants);
        await m.createTable(modifiers);
        await m.createTable(modifierOptions);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Store timestamps as UTC ISO-8601 text (drift's recommendation for new
  /// databases): timestamps are unambiguous across devices/time zones, which a
  /// multi-device offline sync foundation depends on. No floating point is
  /// involved (DECISION D-007).
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  /// Enqueue a mutating operation into the outbox. A duplicate
  /// `(deviceId, localOperationId)` is rejected by the UNIQUE constraint
  /// (DECISION D-022).
  Future<void> enqueueOperation(OutboxOperationsCompanion op) =>
      into(outboxOperations).insert(op);

  /// Record that an operation has been applied locally (inbox dedupe ledger).
  /// A duplicate `(deviceId, localOperationId)` is rejected by the UNIQUE
  /// constraint (DECISION D-022).
  Future<void> recordProcessedPull(ProcessedPullLogCompanion entry) =>
      into(processedPullLog).insert(entry);
}
