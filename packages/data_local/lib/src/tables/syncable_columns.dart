import 'package:drift/drift.dart';

/// Reusable column-set contract for **syncable** local entities (RF-018).
///
/// This is the local-store realisation of the "standard sync column set"
/// (docs/DOMAIN_MODEL.md section 0; DECISION D-010 / D-020 / D-022). Future
/// offline-capable business tables (orders, payments, …) in RF-030+ mix this in
/// so every syncable row carries identity, tenant scope, an idempotency key, a
/// revision (optimistic-concurrency token) and the tombstone marker.
///
/// RF-018 intentionally ships **no business table** that uses this mixin — it is
/// the contract only. A test-only table exercises it (see the tombstone test).
///
/// Tombstone contract (DECISION D-020): syncable rows are NEVER hard-deleted.
/// Deletion is a soft delete that sets [deletedAt]; the row remains for sync
/// convergence and referential integrity. This foundation exposes no
/// row-removal API for syncable entities.
mixin SyncableColumns on Table {
  /// Client-generated UUID primary key (rows exist before any server round-trip).
  TextColumn get id => text()();

  /// Tenant isolation boundary (DECISION D-001).
  TextColumn get organizationId => text()();

  /// Originating device identity (DECISION D-022).
  TextColumn get deviceId => text()();

  /// Client-generated per-operation id; `(deviceId, localOperationId)` is the
  /// idempotency key (DECISION D-022).
  TextColumn get localOperationId => text()();

  /// Monotonic per-entity version; optimistic-concurrency token.
  IntColumn get revision => integer().withDefault(const Constant(1))();

  /// Wall-clock time the change was made on the device (advisory, not trusted).
  DateTimeColumn get clientUpdatedAt => dateTime()();

  /// Authoritative time set by the server on accept; null until first accepted.
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();

  /// Standard audit timestamps.
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Tombstone marker (DECISION D-020). Null = live; non-null = soft-deleted.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
