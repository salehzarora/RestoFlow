import 'package:drift/drift.dart';
// RF-071: brings PrintJobState/PrintJobType into the library scope so the
// generated `part` (local_database.g.dart) can reference the converter types.
import 'package:restoflow_printing/restoflow_printing.dart';

import 'converters.dart';
// KITCHEN-MODE-001C2A: brings the closed kitchen-spool enums into the library
// scope so the generated `part` can reference the converter types.
import 'kitchen_spool/kitchen_spool_status.dart';
import 'sync_operation_state.dart';
import 'tables/item_sizes.dart';
import 'tables/item_variants.dart';
import 'tables/kitchen_spool_jobs.dart';
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
    KitchenSpoolJobs,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  /// Opens the database on [executor] (e.g. `NativeDatabase.memory()` in tests).
  LocalDatabase(super.executor);

  /// v1 = RF-018 sync foundation; v2 = RF-030 menu catalog; v3 = RF-071 print
  /// spool (`print_jobs`); v4 = KITCHEN-MODE-001C2A encrypted kitchen spool
  /// (`kitchen_spool_jobs`).
  @override
  int get schemaVersion => 4;

  /// Migration strategy.
  ///
  /// `onCreate` builds the full current schema. The v1 -> v2 upgrade ADDS the
  /// six menu tables; the v2 -> v3 upgrade ADDS the `print_jobs` table only;
  /// the v3 -> v4 upgrade ADDS `kitchen_spool_jobs` + its indexes only.
  /// Existing tables are never dropped or recreated, existing rows are
  /// preserved, and NOTHING here creates or reads crypto keys — opening the
  /// database performs no key provisioning of any kind (explicit-only, per
  /// the RF-021 fail-closed policy).
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
      if (from < 4) {
        // KITCHEN-MODE-001C2A: add the encrypted kitchen spool (additive; no
        // FK to other tables; no data rewrite; no crypto interaction).
        await m.createTable(kitchenSpoolJobs);
        await m.createIndex(kitchenSpoolRunnableIdx);
        await m.createIndex(kitchenSpoolDestinationIdx);
        await m.createIndex(kitchenSpoolUnresolvedIdx);
        await m.createIndex(kitchenSpoolPendingAckIdx);
        await m.createIndex(kitchenSpoolRetentionIdx);
        await m.createIndex(kitchenSpoolOrderSequenceIdx);
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
