import 'package:drift/drift.dart';

import '../converters.dart';

/// KITCHEN-MODE-001C2A — the encrypted kitchen print spool (dedicated table;
/// deliberately NOT a reuse of `print_jobs`, whose plaintext-JSON payload
/// contract is wrong for kitchen dispatches).
///
/// PLAINTEXT COLUMN CONTRACT: only IDs, closed enum/status wire values,
/// non-secret fingerprints, safe generic display labels, transport kind,
/// paper width, safe typed error codes and retry timestamps/counts may exist
/// outside the encrypted blob. The kitchen payload (item names, modifiers,
/// notes, customer display name), every printer endpoint (host, port,
/// Bluetooth address), receipt/ticket bytes, keys and credentials live ONLY
/// inside `encryptedPayloadBlob` (AES-256-GCM, AAD-bound to
/// dispatch/org/restaurant/branch/device/version).
@DataClassName('KitchenSpoolJobRow')
@TableIndex(
  name: 'kitchen_spool_runnable_idx',
  columns: {#deviceId, #branchId, #status, #nextAttemptAt, #createdAt},
)
@TableIndex(
  name: 'kitchen_spool_destination_idx',
  columns: {#destinationFingerprint, #status},
)
@TableIndex(
  name: 'kitchen_spool_unresolved_idx',
  columns: {#deviceId, #branchId, #status},
)
@TableIndex(
  name: 'kitchen_spool_pending_ack_idx',
  columns: {
    #deviceId,
    #branchId,
    #pendingServerAckStatus,
    #serverAckNextAttemptAt,
  },
)
@TableIndex(
  name: 'kitchen_spool_retention_idx',
  columns: {#transportAcceptedAt},
)
@TableIndex(
  name: 'kitchen_spool_order_sequence_idx',
  columns: {#orderId, #dispatchType, #createdAt},
)
class KitchenSpoolJobs extends Table {
  /// Client-generated UUID primary key.
  TextColumn get localJobId => text()();

  /// The server dispatch this job materializes; UNIQUE (idempotent import).
  TextColumn get dispatchId => text()();

  /// Tenant/device scope (DECISION D-001) — matches the AAD binding.
  TextColumn get organizationId => text()();
  TextColumn get restaurantId => text()();
  TextColumn get branchId => text()();
  TextColumn get deviceId => text()();

  /// Order linkage (IDs only — the order CONTENT is inside the blob).
  TextColumn get orderId => text()();
  TextColumn get serviceRoundId => text().nullable()();

  /// `initial_order` / `service_round` / `void` (closed).
  TextColumn get dispatchType =>
      text().map(const KitchenSpoolDispatchTypeConverter())();

  /// Closed local lifecycle; see [KitchenSpoolJobStatus].
  TextColumn get status => text()
      .map(const KitchenSpoolJobStatusConverter())
      .withDefault(const Constant('imported'))();

  /// The AES-256-GCM envelope (versioned binary format; AAD-bound).
  BlobColumn get encryptedPayloadBlob => blob()();

  /// The envelope/crypto version used for this row.
  IntColumn get encryptionVersion => integer()();

  /// NON-SECRET digest of the pinned destination (single-flight lookups);
  /// null while no destination is pinned (blocked configuration).
  TextColumn get destinationFingerprint => text().nullable()();

  /// SAFE, GENERIC display label only — the store normalizes anything that
  /// looks like an endpoint (IP/port/MAC) into a generic label before
  /// storage. Never host/port/address.
  TextColumn get destinationDisplayLabel => text().nullable()();

  /// `network` / `bluetooth`; null while blocked.
  TextColumn get transportKind => text().nullable()();

  /// `58mm` / `80mm`; null while blocked.
  TextColumn get paperWidth => text().nullable()();

  /// Version pins for later rendering (payload = server payload version).
  IntColumn get payloadVersion => integer()();
  IntColumn get documentVersion => integer()();
  IntColumn get rasterVersion => integer()();

  /// Local transport retry bookkeeping.
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();

  /// Mirror of the server claim lease this import rode on (metadata only).
  DateTimeColumn get serverClaimExpiresAt => dateTime().nullable()();

  /// The acknowledgement this device still owes the server — INDEPENDENT of
  /// local print state: ack retries never make a printed job runnable again.
  TextColumn get pendingServerAckStatus =>
      text().map(const KitchenServerAckStatusConverter()).nullable()();
  IntColumn get serverAckAttemptCount =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get serverAckNextAttemptAt => dateTime().nullable()();
  TextColumn get serverAckLastErrorCode => text().nullable()();

  /// Lifecycle timestamps (stored as UTC ISO-8601 text — DB option).
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get transportAcceptedAt => dateTime().nullable()();
  DateTimeColumn get serverAcknowledgedAt => dateTime().nullable()();

  /// Operator review of terminal ambiguity (001C4; column reserved now so
  /// the schema needs no second migration).
  DateTimeColumn get reviewedAt => dateTime().nullable()();

  /// Reprint linkage: the original local job (never itself — CHECK).
  TextColumn get reprintOfLocalJobId => text().nullable()();

  /// SERVER EVIDENCE ONLY: the void dispatch that superseded this one.
  TextColumn get supersededByDispatchId => text().nullable()();

  @override
  Set<Column> get primaryKey => {localJobId};

  /// Idempotent import: at most one local job per server dispatch.
  @override
  List<Set<Column>> get uniqueKeys => [
    {dispatchId},
  ];

  /// SQLite-enforceable status invariants (defence in depth below the
  /// bounded store API).
  @override
  List<String> get customConstraints => [
    'CHECK (attempt_count >= 0)',
    'CHECK (server_ack_attempt_count >= 0)',
    "CHECK (status <> 'transport_accepted' OR transport_accepted_at IS NOT NULL)",
    "CHECK (status <> 'possibly_printed' OR transport_accepted_at IS NULL)",
    "CHECK (status <> 'superseded' OR superseded_by_dispatch_id IS NOT NULL)",
    'CHECK (reprint_of_local_job_id IS NULL OR '
        'reprint_of_local_job_id <> local_job_id)',
    "CHECK (length(encrypted_payload_blob) > 0)",
  ];
}
