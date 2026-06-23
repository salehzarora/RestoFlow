import 'package:drift/drift.dart';

import '../converters.dart';

/// The durable LOCAL print spool (RF-071, PRINTERS spec §7), one row per print
/// job. Local-only: print jobs are NOT cross-device synced (approved A3) — a
/// paper artifact belongs to the device that produced it — so this table does
/// NOT use the `SyncableColumns` contract. It carries the idempotency key
/// `(deviceId, localOperationId)` (DECISION D-022) for crash-recovery
/// de-duplication, the serialized render-neutral document (A4 — never raw
/// ESC/POS bytes, never money), and retry/reprint bookkeeping.
///
/// The state machine that drives [status] lives in `packages/printing`
/// ([PrintJobState]); this table only persists it via [PrintJobStateConverter].
///
/// The generated row class is named `PrintJobRow` (not the default `PrintJob`)
/// to avoid colliding with the `packages/printing` domain model `PrintJob`.
@DataClassName('PrintJobRow')
class PrintJobs extends Table {
  /// Client-generated UUID primary key.
  TextColumn get id => text()();

  /// Tenant scope (DECISION D-001).
  TextColumn get organizationId => text()();
  TextColumn get branchId => text()();
  TextColumn get deviceId => text()();

  /// nullable station scope (kitchen-station tickets).
  TextColumn get stationId => text().nullable()();

  /// Idempotency key part (DECISION D-022); UNIQUE with [deviceId].
  TextColumn get localOperationId => text()();

  /// `receipt` / `kitchen_ticket` / `drawer_kick` (PrintJobType wire value).
  TextColumn get jobType => text().map(const PrintJobTypeConverter())();

  /// Lifecycle state (DECISION D-018); stored as wire text.
  TextColumn get status => text()
      .map(const PrintJobStateConverter())
      .withDefault(const Constant('created'))();

  /// The render-neutral [PrintDocument] serialized as JSON (A4). No raw bytes,
  /// no money — text is caller-pre-formatted (D-007/D-008).
  TextColumn get payloadJson => text()();

  /// Retry bookkeeping (policy/limits configurable, Q-018; defaults in engine).
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get maxRetries => integer().withDefault(const Constant(12))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorMessage => text().nullable()();

  /// Reprint linkage (PRINTERS §8.4): the original job id + mandatory reason.
  TextColumn get reprintOf => text().nullable()();
  TextColumn get reprintReason => text().nullable()();

  /// Lifecycle timestamps (stored as UTC ISO-8601 text — DB option).
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get printedAt => dateTime().nullable()();
  DateTimeColumn get abandonedAt => dateTime().nullable()();

  /// Tombstone for local pruning (matches the local convention; not synced).
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  /// Idempotency uniqueness (DECISION D-022): at most one job per
  /// `(deviceId, localOperationId)`.
  @override
  List<Set<Column>> get uniqueKeys => [
    {deviceId, localOperationId},
  ];
}
