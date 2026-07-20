import 'package:drift/drift.dart';
// RF-071: brings PrintJobState/PrintJobType into the library scope so the
// generated `part` (local_database.g.dart) can reference the converter types.
import 'package:restoflow_printing/restoflow_printing.dart';

import 'converters.dart';
import 'sync_operation_state.dart';
import 'tables/item_sizes.dart';
import 'tables/item_variants.dart';
import 'tables/menu_categories.dart';
import 'tables/menu_items.dart';
import 'tables/modifier_options.dart';
import 'tables/modifiers.dart';
import 'tables/outbox_operations.dart';
import 'tables/print_jobs.dart';
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
///
/// RF-071 adds the durable LOCAL print spool ([PrintJobs]) — local-only, not
/// cross-device synced; the spool engine/state machine live in
/// `packages/printing`.
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
    PrintJobs,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  /// Opens the database on [executor] (e.g. `NativeDatabase.memory()` in tests).
  LocalDatabase(super.executor);

  /// v1 = RF-018 sync foundation; v2 = RF-030 menu catalog; v3 = RF-071 print
  /// spool (`print_jobs`); v4 = KITCHEN-MODE-001C2A briefly added
  /// `kitchen_spool_jobs` here; v5 = KITCHEN-MODE-001C2B moves the kitchen
  /// spool to its DEDICATED [KitchenSpoolDatabase] (Android backup-excluded
  /// path) and removes the table from this general database.
  ///
  /// CONTRACT: opening `kitchen_spool_jobs` through this general database is
  /// PROHIBITED — runtime kitchen-spool data must never live in a database
  /// that Android backup may restore without its matching Keystore key.
  @override
  int get schemaVersion => 5;

  /// Migration strategy.
  ///
  /// `onCreate` builds the full current schema. The v1 -> v2 upgrade ADDS the
  /// six menu tables; the v2 -> v3 upgrade ADDS the `print_jobs` table only.
  /// The v4 -> v5 upgrade REMOVES the (only-ever-empty) `kitchen_spool_jobs`
  /// table with a FAIL-CLOSED guard: any unexpected spool row ABORTS the
  /// migration (no version advance, nothing deleted) — spool rows are never
  /// silently dropped. Existing tables are never destructively recreated,
  /// and NOTHING here creates or reads crypto keys — opening the database
  /// performs no key provisioning of any kind (explicit-only, per the RF-021
  /// fail-closed policy).
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
      if (from < 3) {
        // RF-071: add the local print spool (no FK to other tables).
        await m.createTable(printJobs);
      }
      // (from < 4): the 001C2A spool-table creation step is deliberately
      // GONE — a pre-v4 database upgrading now never grows the table, and
      // the v5 guard below finds nothing to remove.
      if (from < 5) {
        // KITCHEN-MODE-001C2B: the kitchen spool moved to the DEDICATED
        // KitchenSpoolDatabase. Remove the general-DB copy ONLY when it is
        // provably empty; any row means something unexpected wrote spool
        // data here — ABORT (the thrown error rolls the migration back, so
        // user_version stays put and no row is lost).
        final exists = (await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'kitchen_spool_jobs'",
        ).get()).isNotEmpty;
        if (exists) {
          final row = await customSelect(
            'SELECT COUNT(*) AS c FROM kitchen_spool_jobs',
          ).getSingle();
          final count = row.data['c'] as int;
          if (count > 0) {
            throw StateError(
              'LocalDatabase v5 migration REFUSED: kitchen_spool_jobs holds '
              '$count row(s) in the general database. Kitchen-spool rows '
              'must never be dropped silently — move them to the dedicated '
              'KitchenSpoolDatabase before upgrading.',
            );
          }
          for (final index in const [
            'kitchen_spool_runnable_idx',
            'kitchen_spool_destination_idx',
            'kitchen_spool_unresolved_idx',
            'kitchen_spool_pending_ack_idx',
            'kitchen_spool_retention_idx',
            'kitchen_spool_order_sequence_idx',
          ]) {
            await customStatement('DROP INDEX IF EXISTS $index');
          }
          await customStatement('DROP TABLE kitchen_spool_jobs');
        }
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
