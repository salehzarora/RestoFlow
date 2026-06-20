import 'package:drift/drift.dart';

import 'converters.dart';
import 'sync_operation_state.dart';
import 'tables/outbox_operations.dart';
import 'tables/processed_pull_log.dart';

part 'local_database.g.dart';

/// The RestoFlow local SQLite/Drift database — sync foundation only (RF-018).
///
/// Contains the [OutboxOperations] outbox and the [ProcessedPullLog] inbox/
/// dedupe ledger. It intentionally contains **no business entity tables**
/// (orders/menu/payments/shifts) and **no money columns** — those are RF-030+.
/// The reusable syncable column-set/tombstone contract lives in
/// `SyncableColumns` for future tables to mix in.
///
/// The sync engine (push RF-056 / pull RF-057), encryption at rest (RF-021),
/// auth/JWT (RF-050) and conflict resolution are all OUT of scope here.
@DriftDatabase(tables: [OutboxOperations, ProcessedPullLog])
class LocalDatabase extends _$LocalDatabase {
  /// Opens the database on [executor] (e.g. `NativeDatabase.memory()` in tests).
  LocalDatabase(super.executor);

  @override
  int get schemaVersion => 1;

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
