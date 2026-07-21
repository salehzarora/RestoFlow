/// KITCHEN-MODE-001C2A — the bounded, fail-closed kitchen-spool store.
///
/// Every mutation is a CONDITIONAL, scope-preserving transition inside the
/// closed [KitchenSpoolJobStatus] machine — there is deliberately NO generic
/// `updateStatus` writer anywhere. Invariants enforced here (and, where
/// SQLite can, by table CHECKs):
///
///  * `claimRunnableForQueued` is THE one atomic claim (001C2C LOCKED 1):
///    single-flight per job (a same-instant duplicate claim updates 0 rows)
///    AND per pinned destination (no other `queued`/`printing` row on the
///    same fingerprint). There is NO direct claim into `printing`; the
///    transport boundary is entered only through `markPrinting` (queued
///    only). Every print-state resolution writes its matching pending
///    server acknowledgement IN THE SAME UPDATE (`*WithAck`).
///  * `printing` recovery maps ONLY `printing -> possiblyPrinted`.
///  * `possiblyPrinted` and `superseded` can never become runnable again.
///  * `superseded` is SERVER EVIDENCE ONLY (`markSupersededFromServerEvidence`).
///  * `transportAccepted` never re-enters the runnable set — a failed server
///    acknowledgement retries the ACK, never the PRINT.
///  * pruning removes ONLY fully server-acknowledged `transportAccepted`
///    history; unresolved / possiblyPrinted / blocked rows are never pruned.
library;

import 'package:drift/drift.dart';

import '../kitchen_spool_database.dart';
import 'kitchen_spool_status.dart';

/// Canonical on-disk location for the kitchen-spool database, pinned NOW so
/// Android backup rules can exclude it by exact path (Auto Backup rules have
/// no wildcards, so the spool lives in its OWN directory — excluding the
/// directory also covers `-wal`/`-shm`/`-journal` side files).
///
/// ============================================================================
/// KITCHEN-MODE-001C2B HARD PRECONDITION (review-approved; NON-NEGOTIABLE):
///   1. The runtime kitchen spool MUST be opened as a DEDICATED database.
///   2. It MUST live under [kKitchenSpoolDatabaseDirectoryName].
///   3. It MUST use [kKitchenSpoolDatabaseFileName].
///   4. Opening `kitchen_spool_jobs` inside a backed-up general application
///      database is PROHIBITED (the Android backup exclusion covers ONLY
///      this directory; a general DB would restore into a mismatched
///      key/data state).
///   5. The existing v4 table/store/crypto model is reused as-is — no
///      plaintext fallback of any kind.
///   6. The backup-contract guard test
///      (apps/pos/test/kitchen_spool_backup_contract_test.dart) binds these
///      constants to the Android XML resources and MUST remain green.
/// If 001C2B cannot satisfy this, it must STOP before any runtime wiring.
/// ============================================================================
const String kKitchenSpoolDatabaseDirectoryName = 'restoflow_kitchen_spool';

/// The database file inside [kKitchenSpoolDatabaseDirectoryName].
const String kKitchenSpoolDatabaseFileName = 'kitchen_spool.sqlite';

/// Bounded persistence port for the encrypted kitchen spool. No background
/// worker exists in this phase; callers drive transitions explicitly.
abstract interface class KitchenSpoolStore {
  Future<KitchenSpoolJobRow> insertImportedJob(NewKitchenSpoolJob job);
  Future<KitchenSpoolJobRow?> findByDispatchId(String dispatchId);
  Future<KitchenSpoolJobRow?> getByLocalJobId(String localJobId);
  Future<List<KitchenSpoolJobRow>> listUnresolved({
    required String deviceId,
    required String branchId,
  });
  Future<List<KitchenSpoolJobRow>> listRunnable({
    required String deviceId,
    required String branchId,
    required DateTime now,
    int limit = 20,
  });

  /// KITCHEN-MODE-001C2C (LOCKED DECISION 1): THE one atomic claim. A
  /// runnable job (imported / queued / failedRetryable) moves to `queued`
  /// through a single conditional UPDATE that additionally requires the full
  /// scope tuple, the server-ack-complete gate, a DUE retry time, a NON-NULL
  /// destination fingerprint (executable jobs only), and destination
  /// single-flight: no OTHER row with the same fingerprint may be `queued`
  /// or `printing`. Increments `attemptCount` exactly once and stamps
  /// `lastAttemptAt`; a SAME-INSTANT duplicate claim updates zero rows (one
  /// winner), while a strictly LATER claim may re-adopt a stale `queued`
  /// row (restart recovery). There is deliberately NO direct claim into
  /// `printing`.
  Future<KitchenSpoolJobRow?> claimRunnableForQueued(
    String localJobId, {
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required DateTime now,
  });

  /// KITCHEN-MODE-001C2C (LOCKED DECISION 2): `queued` → `printing`,
  /// invoked IMMEDIATELY before the transport boundary. Source state is
  /// `queued` ONLY; re-verifies the ack-complete gate and destination
  /// single-flight (no other queued/printing row on the same fingerprint).
  Future<bool> markPrinting(String localJobId, DateTime now);

  /// Atomic `printing` → `transportAccepted` + pending `transport_accepted`
  /// acknowledgement in ONE conditional UPDATE (no crash window between the
  /// local transition and the owed server acknowledgement).
  Future<bool> markTransportAcceptedWithAck(String localJobId, DateTime now);

  /// Atomic `printing`/`queued` → `failedRetryable` + pending
  /// `failed_retryable` acknowledgement. ONLY for outcomes the transport
  /// proved DEFINITELY-NOT-SENT; the caller supplies the safe backoff time.
  Future<bool> markFailedRetryableWithAck(
    String localJobId, {
    required String errorCode,
    required DateTime nextAttemptAt,
    required DateTime now,
  });

  /// Atomic `printing` → `possiblyPrinted` + pending `possibly_printed`
  /// acknowledgement. No retry time (the hold is permanent until an
  /// operator acts); destination, encrypted payload, and any existing
  /// supersession link are preserved.
  Future<bool> markPossiblyPrintedWithAck(String localJobId, DateTime now);

  /// Atomic `queued` → `blockedConfiguration` + pending
  /// `blocked_configuration` acknowledgement (render/destination failure
  /// BEFORE the transport boundary — zero paper risk). The error code is a
  /// safe bounded token, never an endpoint or payload.
  Future<bool> markBlockedConfigurationWithAck(
    String localJobId, {
    required String errorCode,
    required DateTime now,
  });

  /// Startup crash recovery: every STALE `printing` row in scope becomes
  /// `possiblyPrinted` WITH its pending `possibly_printed` acknowledgement
  /// in the same UPDATE. Idempotent; `transportAccepted` rows are never
  /// touched; nothing ever maps back to a runnable state.
  Future<int> markPossiblyPrintedOnRecoveryWithAck({
    required String deviceId,
    required String branchId,
    required DateTime now,
  });
  Future<bool> markSupersededFromServerEvidence({
    required String dispatchId,
    required String supersededByDispatchId,
    required DateTime now,
  });
  Future<bool> setPendingServerAck(
    String localJobId,
    KitchenServerAckStatus ack,
    DateTime now,
  );
  Future<bool> markServerAcked(String localJobId, DateTime now);
  Future<bool> updateServerAckRetry(
    String localJobId, {
    required String errorCode,
    required DateTime nextAttemptAt,
    required DateTime now,
  });

  /// KITCHEN-MODE-001C2B: records a TERMINAL server verdict
  /// (`not_claim_owner` / `conflict` / `not_found` / `ambiguous_print_hold`):
  /// stops acknowledgement retries, preserves the encrypted job and its
  /// history, and makes the job permanently non-runnable.
  Future<bool> markServerAckTerminal(
    String localJobId, {
    required String terminalCode,
    required DateTime now,
  });

  /// KITCHEN-MODE-001C2B: links SERVER supersession evidence onto a
  /// `possiblyPrinted` row WITHOUT erasing its ambiguous state (paper may
  /// exist — the 001C2C operator flow needs both facts).
  Future<bool> linkSupersessionEvidence({
    required String dispatchId,
    required String supersededByDispatchId,
    required DateTime now,
  });

  /// Jobs still owing the server an acknowledgement, due for retry.
  Future<List<KitchenSpoolJobRow>> listPendingServerAcks({
    required String deviceId,
    required String branchId,
    required DateTime now,
    int limit = 20,
  });

  Future<int> countUnresolved({
    required String deviceId,
    required String branchId,
  });

  /// TOTAL rows across every scope (metadata count only — used by the key
  /// flow's missing-key policy; never decrypts anything).
  Future<int> countTotalRows();

  Future<int> pruneTransportAcceptedOlderThan(DateTime cutoff);
}

/// Insert-time value object: the imported dispatch's metadata plus the
/// ALREADY-ENCRYPTED payload envelope. Plaintext never crosses this API.
final class NewKitchenSpoolJob {
  NewKitchenSpoolJob({
    required this.localJobId,
    required this.dispatchId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.orderId,
    this.serviceRoundId,
    required this.dispatchType,
    required this.initialStatus,
    required this.encryptedPayloadBlob,
    required this.encryptionVersion,
    this.destinationFingerprint,
    this.destinationDisplayLabel,
    this.transportKind,
    this.paperWidth,
    this.lastErrorCode,
    required this.payloadVersion,
    required this.documentVersion,
    required this.rasterVersion,
    this.serverClaimExpiresAt,
    required this.createdAt,
  }) {
    if (initialStatus != KitchenSpoolJobStatus.imported &&
        initialStatus != KitchenSpoolJobStatus.blockedConfiguration) {
      throw ArgumentError.value(
        initialStatus,
        'initialStatus',
        'an import may only start as imported or blockedConfiguration',
      );
    }
    if (encryptedPayloadBlob.isEmpty) {
      throw ArgumentError('encryptedPayloadBlob must not be empty');
    }
  }

  final String localJobId;
  final String dispatchId;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;
  final String orderId;
  final String? serviceRoundId;
  final KitchenSpoolDispatchType dispatchType;
  final KitchenSpoolJobStatus initialStatus;
  final Uint8List encryptedPayloadBlob;
  final int encryptionVersion;
  final String? destinationFingerprint;
  final String? destinationDisplayLabel;
  final String? transportKind;
  final String? paperWidth;

  /// Safe typed reason for a blocked-configuration import (never endpoints).
  final String? lastErrorCode;
  final int payloadVersion;
  final int documentVersion;
  final int rasterVersion;
  final DateTime? serverClaimExpiresAt;
  final DateTime createdAt;
}

/// Normalizes a human display label so no endpoint data can leak into the
/// plaintext column: anything resembling an IPv4/IPv6 address, host:port,
/// MAC/BT address, URL or credentialed URL collapses to the safe generic
/// `kitchen-printer` label; control characters are stripped and the result is
/// length-capped. Ordinary human names ("Kitchen Printer", "Grill Station")
/// pass through untouched.
String? sanitizeDestinationDisplayLabel(String? label) {
  if (label == null) return null;
  final trimmed = label.trim().replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  if (trimmed.isEmpty) return null;
  final endpointish =
      // IPv4 (with or without :port).
      RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(trimmed) ||
      // MAC / Bluetooth addresses (colon- or dash-separated hex pairs).
      RegExp(r'([0-9A-Fa-f]{2}[:\-]){3,}[0-9A-Fa-f]{2}').hasMatch(trimmed) ||
      // CLEANUP 5 — IPv6 in every common shape: compressed (`::`), full
      // grouped hex (2+ hextet groups), bracketed-with-port, zone index.
      trimmed.contains('::') ||
      RegExp(r'([0-9A-Fa-f]{1,4}:){2,}[0-9A-Fa-f]{1,4}').hasMatch(trimmed) ||
      RegExp(r'\[[0-9A-Fa-f:.]+\]').hasMatch(trimmed) ||
      RegExp(r'%(eth|wlan|en|lo)\w*', caseSensitive: false).hasMatch(trimmed) ||
      // host:port (any host shape, incl. hostnames like printer.local:9100).
      RegExp(r':\d{2,5}(\D|$)').hasMatch(trimmed) ||
      // URLs, incl. credentialed https://user:pass@host forms.
      trimmed.contains('://') ||
      RegExp(r'\S+@\S+\.\S+').hasMatch(trimmed);
  if (endpointish) return 'kitchen-printer';
  return trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed;
}

/// Drift-backed implementation over the DEDICATED [KitchenSpoolDatabase]
/// (KITCHEN-MODE-001C2B: the general LocalDatabase no longer carries the
/// spool table — opening the spool through it is prohibited).
final class DriftKitchenSpoolStore implements KitchenSpoolStore {
  DriftKitchenSpoolStore(this._db);

  final KitchenSpoolDatabase _db;

  $KitchenSpoolJobsTable get _t => _db.kitchenSpoolJobs;

  @override
  Future<KitchenSpoolJobRow> insertImportedJob(NewKitchenSpoolJob job) {
    return _db.transaction(() async {
      // Idempotent by dispatchId: a duplicate import RETURNS the existing row
      // untouched (never re-inserts, never resets its state).
      final existing = await findByDispatchId(job.dispatchId);
      if (existing != null) return existing;
      await _db
          .into(_t)
          .insert(
            KitchenSpoolJobsCompanion.insert(
              localJobId: job.localJobId,
              dispatchId: job.dispatchId,
              organizationId: job.organizationId,
              restaurantId: job.restaurantId,
              branchId: job.branchId,
              deviceId: job.deviceId,
              orderId: job.orderId,
              serviceRoundId: Value(job.serviceRoundId),
              dispatchType: job.dispatchType,
              status: Value(job.initialStatus),
              encryptedPayloadBlob: job.encryptedPayloadBlob,
              encryptionVersion: job.encryptionVersion,
              destinationFingerprint: Value(job.destinationFingerprint),
              destinationDisplayLabel: Value(
                sanitizeDestinationDisplayLabel(job.destinationDisplayLabel),
              ),
              transportKind: Value(job.transportKind),
              paperWidth: Value(job.paperWidth),
              lastErrorCode: Value(job.lastErrorCode),
              payloadVersion: job.payloadVersion,
              documentVersion: job.documentVersion,
              rasterVersion: job.rasterVersion,
              serverClaimExpiresAt: Value(job.serverClaimExpiresAt),
              createdAt: job.createdAt,
              updatedAt: job.createdAt,
            ),
          );
      return (await findByDispatchId(job.dispatchId))!;
    });
  }

  @override
  Future<KitchenSpoolJobRow?> findByDispatchId(String dispatchId) {
    return (_db.select(
      _t,
    )..where((t) => t.dispatchId.equals(dispatchId))).getSingleOrNull();
  }

  @override
  Future<KitchenSpoolJobRow?> getByLocalJobId(String localJobId) {
    return (_db.select(
      _t,
    )..where((t) => t.localJobId.equals(localJobId))).getSingleOrNull();
  }

  @override
  Future<List<KitchenSpoolJobRow>> listUnresolved({
    required String deviceId,
    required String branchId,
  }) {
    return (_db.select(_t)
          ..where(
            (t) =>
                t.deviceId.equals(deviceId) &
                t.branchId.equals(branchId) &
                t.status.isInValues(KitchenSpoolJobStatus.unresolved.toList()),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.localJobId),
          ]))
        .get();
  }

  /// KITCHEN-MODE-001C2B PRINT-ELIGIBILITY INVARIANT: a job can only be
  /// runnable for the (future, 001C2C) worker when the SERVER successfully
  /// acknowledged the import — `server_acknowledged_at` set, no pending
  /// acknowledgement, and no terminal server verdict. An imported-but-
  /// unacknowledged job, a transient ack failure, and every terminal server
  /// rejection are all non-runnable.
  Expression<bool> _serverAckComplete($KitchenSpoolJobsTable t) =>
      t.serverAcknowledgedAt.isNotNull() &
      t.pendingServerAckStatus.isNull() &
      t.serverAckTerminalCode.isNull();

  @override
  Future<List<KitchenSpoolJobRow>> listRunnable({
    required String deviceId,
    required String branchId,
    required DateTime now,
    int limit = 20,
  }) {
    return (_db.select(_t)
          ..where(
            (t) =>
                t.deviceId.equals(deviceId) &
                t.branchId.equals(branchId) &
                t.status.isInValues(KitchenSpoolJobStatus.runnable.toList()) &
                _serverAckComplete(t) &
                (t.nextAttemptAt.isNull() |
                    t.nextAttemptAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.localJobId),
          ])
          ..limit(limit))
        .get();
  }

  /// Destination single-flight predicate (LOCKED DECISION 1): another row
  /// with the SAME non-null fingerprint in `queued` OR `printing` blocks a
  /// claim/print for this destination. The old printing-only predicate was
  /// insufficient — a second job could stage behind a queued holder.
  Future<bool> _destinationBusy(String fingerprint, String localJobId) async {
    final busy =
        await (_db.select(_t)..where(
              (t) =>
                  t.destinationFingerprint.equals(fingerprint) &
                  t.status.isInValues(const [
                    KitchenSpoolJobStatus.queued,
                    KitchenSpoolJobStatus.printing,
                  ]) &
                  t.localJobId.equals(localJobId).not(),
            ))
            .get();
    return busy.isNotEmpty;
  }

  @override
  Future<KitchenSpoolJobRow?> claimRunnableForQueued(
    String localJobId, {
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required DateTime now,
  }) {
    // Same shape as the RF071-B1 print-spool claim: one conditional UPDATE
    // in a transaction is the atomic duplicate-claim guard — PLUS the
    // widened destination single-flight guard. SQLite serializes writes, so
    // the pre-check inside the transaction is race-safe.
    return _db.transaction(() async {
      final row = await getByLocalJobId(localJobId);
      if (row == null) return null;
      final fingerprint = row.destinationFingerprint;
      // Executable jobs REQUIRE a pinned destination fingerprint; a
      // blocked-shaped row (null fingerprint) is never claimable.
      if (fingerprint == null) return null;
      if (await _destinationBusy(fingerprint, localJobId)) return null;
      final updated =
          await (_db.update(_t)..where(
                (t) =>
                    t.localJobId.equals(localJobId) &
                    t.organizationId.equals(organizationId) &
                    t.restaurantId.equals(restaurantId) &
                    t.branchId.equals(branchId) &
                    t.deviceId.equals(deviceId) &
                    t.status.isInValues(
                      KitchenSpoolJobStatus.runnable.toList(),
                    ) &
                    t.destinationFingerprint.isNotNull() &
                    _serverAckComplete(t) &
                    (t.nextAttemptAt.isNull() |
                        t.nextAttemptAt.isSmallerOrEqualValue(now)) &
                    // ONE WINNER per instant: a same-`now` duplicate claim
                    // updates 0 rows, while a genuinely LATER claim (the
                    // restart-reclaim of a stale queued row) proceeds.
                    (t.lastAttemptAt.isNull() |
                        t.lastAttemptAt.isSmallerThanValue(now)),
              ))
              .write(
                KitchenSpoolJobsCompanion.custom(
                  status: Constant(KitchenSpoolJobStatus.queued.wireName),
                  attemptCount: _t.attemptCount + const Constant(1),
                  lastAttemptAt: Constant<DateTime>(now),
                  updatedAt: Constant<DateTime>(now),
                ),
              );
      if (updated == 0) return null;
      return getByLocalJobId(localJobId);
    });
  }

  @override
  Future<bool> markPrinting(String localJobId, DateTime now) {
    // LOCKED DECISION 2: `queued` ONLY, immediately before the transport
    // boundary — with the ack gate and the destination single-flight both
    // re-verified (a superseded/blocked row is no longer `queued`, so
    // supersession evidence structurally refuses the print).
    return _db.transaction(() async {
      final row = await getByLocalJobId(localJobId);
      if (row == null) return false;
      final fingerprint = row.destinationFingerprint;
      if (fingerprint == null) return false;
      if (await _destinationBusy(fingerprint, localJobId)) return false;
      final updated =
          await (_db.update(_t)..where(
                (t) =>
                    t.localJobId.equals(localJobId) &
                    t.status.equalsValue(KitchenSpoolJobStatus.queued) &
                    _serverAckComplete(t),
              ))
              .write(
                KitchenSpoolJobsCompanion(
                  status: const Value(KitchenSpoolJobStatus.printing),
                  updatedAt: Value(now),
                ),
              );
      return updated > 0;
    });
  }

  @override
  Future<bool> markTransportAcceptedWithAck(String localJobId, DateTime now) {
    // ONE conditional UPDATE: local resolution + the owed server
    // acknowledgement are inseparable (the pending status ALWAYS describes
    // row.status — no crash window can leave a silent local acceptance).
    return _transition(
      localJobId,
      from: const {KitchenSpoolJobStatus.printing},
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.transportAccepted),
        transportAcceptedAt: Value(now),
        nextAttemptAt: const Value(null),
        lastErrorCode: const Value(null),
        pendingServerAckStatus: const Value(
          KitchenServerAckStatus.transportAccepted,
        ),
        serverAckNextAttemptAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<bool> markFailedRetryableWithAck(
    String localJobId, {
    required String errorCode,
    required DateTime nextAttemptAt,
    required DateTime now,
  }) {
    // ONLY for DEFINITELY-NOT-SENT transport outcomes (the caller proves
    // it); ambiguous outcomes must use markPossiblyPrintedWithAck instead.
    return _transition(
      localJobId,
      from: const {
        KitchenSpoolJobStatus.printing,
        KitchenSpoolJobStatus.queued,
      },
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.failedRetryable),
        lastErrorCode: Value(errorCode),
        nextAttemptAt: Value(nextAttemptAt),
        pendingServerAckStatus: const Value(
          KitchenServerAckStatus.failedRetryable,
        ),
        serverAckNextAttemptAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<bool> markPossiblyPrintedWithAck(String localJobId, DateTime now) {
    // Ambiguous transport result: paper MAY exist. Permanent hold (no retry
    // time); destination, encrypted payload, and any existing supersession
    // link are untouched. The table CHECK guarantees a transportAccepted
    // row can never be relabeled ambiguous.
    return _transition(
      localJobId,
      from: const {KitchenSpoolJobStatus.printing},
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.possiblyPrinted),
        nextAttemptAt: const Value(null),
        pendingServerAckStatus: const Value(
          KitchenServerAckStatus.possiblyPrinted,
        ),
        serverAckNextAttemptAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<bool> markBlockedConfigurationWithAck(
    String localJobId, {
    required String errorCode,
    required DateTime now,
  }) {
    // Pre-transport failure only (`queued`): decrypt/render/destination
    // decode failed BEFORE the boundary — zero paper risk, typed reason.
    return _transition(
      localJobId,
      from: const {KitchenSpoolJobStatus.queued},
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.blockedConfiguration),
        lastErrorCode: Value(errorCode),
        nextAttemptAt: const Value(null),
        pendingServerAckStatus: const Value(
          KitchenServerAckStatus.blockedConfiguration,
        ),
        serverAckNextAttemptAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<int> markPossiblyPrintedOnRecoveryWithAck({
    required String deviceId,
    required String branchId,
    required DateTime now,
  }) {
    // Startup crash recovery maps ONLY stale printing -> possiblyPrinted
    // (the transport may or may not have delivered bytes; paper MAY exist)
    // and sets the owed possibly_printed acknowledgement in the SAME
    // update. Idempotent (a second sweep finds no printing rows); the hold
    // is permanent: nothing maps possiblyPrinted back to a runnable state
    // anywhere in this API, and transportAccepted rows are never touched.
    return (_db.update(_t)..where(
          (t) =>
              t.deviceId.equals(deviceId) &
              t.branchId.equals(branchId) &
              t.status.equalsValue(KitchenSpoolJobStatus.printing),
        ))
        .write(
          KitchenSpoolJobsCompanion(
            status: const Value(KitchenSpoolJobStatus.possiblyPrinted),
            nextAttemptAt: const Value(null),
            pendingServerAckStatus: const Value(
              KitchenServerAckStatus.possiblyPrinted,
            ),
            serverAckNextAttemptAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  @override
  Future<bool> markSupersededFromServerEvidence({
    required String dispatchId,
    required String supersededByDispatchId,
    required DateTime now,
  }) async {
    // SERVER-DERIVED state only: keyed by the server dispatch identity and
    // carrying the superseding void's id. transportAccepted history and a
    // job that is PRINTING RIGHT NOW are left alone (the latter resolves
    // first; later evidence passes can supersede it then).
    // KITCHEN-MODE-001C2B: possiblyPrinted is deliberately EXCLUDED here —
    // its ambiguity must never be erased; use [linkSupersessionEvidence] to
    // attach the void link while KEEPING the possiblyPrinted state.
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.dispatchId.equals(dispatchId) &
                  t.status.isInValues(const [
                    KitchenSpoolJobStatus.imported,
                    KitchenSpoolJobStatus.queued,
                    KitchenSpoolJobStatus.failedRetryable,
                    KitchenSpoolJobStatus.blockedConfiguration,
                  ]),
            ))
            .write(
              KitchenSpoolJobsCompanion(
                status: const Value(KitchenSpoolJobStatus.superseded),
                supersededByDispatchId: Value(supersededByDispatchId),
                nextAttemptAt: const Value(null),
                updatedAt: Value(now),
              ),
            );
    return updated > 0;
  }

  @override
  Future<bool> linkSupersessionEvidence({
    required String dispatchId,
    required String supersededByDispatchId,
    required DateTime now,
  }) async {
    // possiblyPrinted keeps BOTH facts: the ambiguous state (paper may
    // exist) AND the server's void evidence. Idempotent: an existing link is
    // never overwritten.
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.dispatchId.equals(dispatchId) &
                  t.status.equalsValue(KitchenSpoolJobStatus.possiblyPrinted) &
                  t.supersededByDispatchId.isNull(),
            ))
            .write(
              KitchenSpoolJobsCompanion(
                supersededByDispatchId: Value(supersededByDispatchId),
                updatedAt: Value(now),
              ),
            );
    return updated > 0;
  }

  @override
  Future<bool> markServerAckTerminal(
    String localJobId, {
    required String terminalCode,
    required DateTime now,
  }) async {
    // A terminal verdict ENDS the retry loop (pending cleared, no next
    // attempt) and — because serverAcknowledgedAt stays NULL and the
    // terminal code is set — the job is permanently non-runnable, while the
    // encrypted job and its history stay intact.
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.localJobId.equals(localJobId) &
                  t.pendingServerAckStatus.isNotNull(),
            ))
            .write(
              KitchenSpoolJobsCompanion(
                pendingServerAckStatus: const Value(null),
                serverAckNextAttemptAt: const Value(null),
                serverAckTerminalCode: Value(terminalCode),
                updatedAt: Value(now),
              ),
            );
    return updated > 0;
  }

  @override
  Future<List<KitchenSpoolJobRow>> listPendingServerAcks({
    required String deviceId,
    required String branchId,
    required DateTime now,
    int limit = 20,
  }) {
    return (_db.select(_t)
          ..where(
            (t) =>
                t.deviceId.equals(deviceId) &
                t.branchId.equals(branchId) &
                t.pendingServerAckStatus.isNotNull() &
                (t.serverAckNextAttemptAt.isNull() |
                    t.serverAckNextAttemptAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.localJobId),
          ])
          ..limit(limit))
        .get();
  }

  @override
  Future<int> countTotalRows() async {
    final count = countAll();
    final query = _db.selectOnly(_t)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<bool> setPendingServerAck(
    String localJobId,
    KitchenServerAckStatus ack,
    DateTime now,
  ) async {
    final updated =
        await (_db.update(
          _t,
        )..where((t) => t.localJobId.equals(localJobId))).write(
          KitchenSpoolJobsCompanion(
            pendingServerAckStatus: Value(ack),
            serverAckNextAttemptAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return updated > 0;
  }

  @override
  Future<bool> markServerAcked(String localJobId, DateTime now) async {
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.localJobId.equals(localJobId) &
                  t.pendingServerAckStatus.isNotNull(),
            ))
            .write(
              KitchenSpoolJobsCompanion(
                pendingServerAckStatus: const Value(null),
                serverAckNextAttemptAt: const Value(null),
                serverAckLastErrorCode: const Value(null),
                serverAcknowledgedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
    return updated > 0;
  }

  @override
  Future<bool> updateServerAckRetry(
    String localJobId, {
    required String errorCode,
    required DateTime nextAttemptAt,
    required DateTime now,
  }) async {
    // The ack pipeline NEVER touches local print status: a transportAccepted
    // job whose acknowledgement keeps failing retries the ACK, not the print.
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.localJobId.equals(localJobId) &
                  t.pendingServerAckStatus.isNotNull(),
            ))
            .write(
              KitchenSpoolJobsCompanion.custom(
                serverAckAttemptCount:
                    _t.serverAckAttemptCount + const Constant(1),
                serverAckLastErrorCode: Constant(errorCode),
                serverAckNextAttemptAt: Constant<DateTime>(nextAttemptAt),
                updatedAt: Constant<DateTime>(now),
              ),
            );
    return updated > 0;
  }

  @override
  Future<int> countUnresolved({
    required String deviceId,
    required String branchId,
  }) async {
    final count = countAll();
    final query = _db.selectOnly(_t)
      ..addColumns([count])
      ..where(
        _t.deviceId.equals(deviceId) &
            _t.branchId.equals(branchId) &
            _t.status.isInValues(KitchenSpoolJobStatus.unresolved.toList()),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<int> pruneTransportAcceptedOlderThan(DateTime cutoff) {
    // ONLY fully-resolved history is prunable: transport accepted AND the
    // server acknowledgement completed (nothing pending). Unresolved,
    // possiblyPrinted, blocked and superseded rows are NEVER pruned here.
    return (_db.delete(_t)..where(
          (t) =>
              t.status.equalsValue(KitchenSpoolJobStatus.transportAccepted) &
              t.serverAcknowledgedAt.isNotNull() &
              t.pendingServerAckStatus.isNull() &
              t.transportAcceptedAt.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  Future<bool> _transition(
    String localJobId, {
    required Set<KitchenSpoolJobStatus> from,
    required KitchenSpoolJobsCompanion write,
    bool requireServerAckComplete = false,
  }) async {
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.localJobId.equals(localJobId) &
                  t.status.isInValues(from.toList()) &
                  (requireServerAckComplete
                      ? _serverAckComplete(t)
                      : const Constant(true)),
            ))
            .write(write);
    return updated > 0;
  }
}
