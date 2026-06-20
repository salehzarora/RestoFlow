import 'package:drift/drift.dart';

import '../converters.dart';

/// The local **outbox** (RF-018): one row per mutating client operation, queued
/// for at-most-once delivery to the server (docs/OFFLINE_SYNC_SPEC.md section 3;
/// DECISION D-010 / D-022).
///
/// The idempotency key `(deviceId, localOperationId)` (DECISION D-022) is
/// enforced by a UNIQUE constraint: a duplicate enqueue of the same operation is
/// rejected at the DB layer.
///
/// The outbox is an operation log, NOT a syncable business entity, so it does
/// not use [SyncableColumns] / tombstones — applied rows are pruned by a future
/// retention job, never tombstoned.
///
/// Scope: this is the *table* only. The push/retry/backoff/poison engine that
/// drives [syncState] is RF-056; the retry/error columns below are placeholders
/// (no retry/backoff or poison-op policy is frozen here — see OPEN QUESTION
/// Q-018).
class OutboxOperations extends Table {
  /// Client-generated UUID primary key for this outbox entry.
  TextColumn get id => text()();

  /// Originating device identity (DECISION D-022).
  TextColumn get deviceId => text()();

  /// Monotonic-per-device local operation id (DECISION D-022).
  TextColumn get localOperationId => text()();

  /// Tenant scope carried with the operation (DECISION D-001).
  TextColumn get organizationId => text()();

  /// Operational scope (present where relevant).
  TextColumn get restaurantId => text().nullable()();
  TextColumn get branchId => text().nullable()();
  TextColumn get stationId => text().nullable()();

  /// e.g. `order.create`, `payment.create`. Maps to a server RPC (RF-056).
  TextColumn get operationType => text()();

  /// The entity and its client UUID this operation targets.
  TextColumn get targetEntity => text()();
  TextColumn get targetId => text()();

  /// Operation arguments as JSON text. Any money inside is integer minor units
  /// only (`*_minor`) — never floating point (DECISION D-007). RF-018 stores it
  /// opaquely; concrete business payload schemas are RF-030+.
  TextColumn get payload => text()();

  /// JSON array of `localOperationId`s that must be applied first; `[]` = none
  /// (OFFLINE_SYNC_SPEC section 5).
  TextColumn get dependsOn => text().withDefault(const Constant('[]'))();

  /// The entity revision this change was computed against (optimistic
  /// concurrency; OFFLINE_SYNC_SPEC section 9).
  IntColumn get baseRevision => integer()();

  /// Sync-operation lifecycle state (DECISION D-018); stored as wire text.
  TextColumn get syncState => text()
      .map(const SyncOperationStateConverter())
      .withDefault(const Constant('created'))();

  /// Device-clock timestamps.
  DateTimeColumn get clientCreatedAt => dateTime()();
  DateTimeColumn get clientUpdatedAt => dateTime()();

  // ---- Retry / error bookkeeping: PLACEHOLDERS ONLY (RF-056 / Q-018) --------
  /// Number of delivery attempts; policy/limits are RF-056 (not frozen here).
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  /// When the next attempt is due; engine-populated (RF-056).
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// Last error diagnostics (transient vs permanent classification is RF-056).
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorClass => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  /// Idempotency key uniqueness (DECISION D-022): at most one outbox row per
  /// `(deviceId, localOperationId)`.
  @override
  List<Set<Column>> get uniqueKeys => [
    {deviceId, localOperationId},
  ];
}
