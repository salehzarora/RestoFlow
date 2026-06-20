import 'package:drift/drift.dart';

/// Thin local **inbox** / processed-pull dedupe ledger (RF-018).
///
/// Records which operations have already been applied locally so a re-delivered
/// inbound change (pull race, retry) is recognised and not re-applied
/// (docs/OFFLINE_SYNC_SPEC.md section 14, `processed_pull_log`). The dedupe
/// identity is the idempotency pair `(deviceId, localOperationId)`
/// (DECISION D-022), enforced by a UNIQUE constraint.
///
/// Scope: this is the *ledger table* only. The pull engine that writes it
/// (cursor tracking, conflict resolution, networking) is RF-057 — none of that
/// behavior lives here. No server networking, no conflict-resolution engine.
class ProcessedPullLog extends Table {
  /// Client-generated UUID primary key for this ledger entry.
  TextColumn get id => text()();

  /// Originating device of the applied operation (DECISION D-022).
  TextColumn get deviceId => text()();

  /// Local operation id of the applied operation (DECISION D-022).
  TextColumn get localOperationId => text()();

  /// When the operation was applied locally.
  DateTimeColumn get appliedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  /// Dedupe uniqueness (DECISION D-022): at most one ledger row per
  /// `(deviceId, localOperationId)`.
  @override
  List<Set<Column>> get uniqueKeys => [
    {deviceId, localOperationId},
  ];
}
