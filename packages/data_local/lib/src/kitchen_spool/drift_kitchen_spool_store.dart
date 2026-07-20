/// KITCHEN-MODE-001C2A — the bounded, fail-closed kitchen-spool store.
///
/// Every mutation is a CONDITIONAL, scope-preserving transition inside the
/// closed [KitchenSpoolJobStatus] machine — there is deliberately NO generic
/// `updateStatus` writer anywhere. Invariants enforced here (and, where
/// SQLite can, by table CHECKs):
///
///  * `claimRunnableForPrinting` is single-flight per job AND per pinned
///    destination (a second concurrent claim updates 0 rows / is refused).
///  * `printing` recovery maps ONLY `printing -> possiblyPrinted`.
///  * `possiblyPrinted` and `superseded` can never become runnable again.
///  * `superseded` is SERVER EVIDENCE ONLY (`markSupersededFromServerEvidence`).
///  * `transportAccepted` never re-enters the runnable set — a failed server
///    acknowledgement retries the ACK, never the PRINT.
///  * pruning removes ONLY fully server-acknowledged `transportAccepted`
///    history; unresolved / possiblyPrinted / blocked rows are never pruned.
library;

import 'package:drift/drift.dart';

import '../local_database.dart';
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
  Future<KitchenSpoolJobRow?> claimRunnableForPrinting(
    String localJobId,
    DateTime now,
  );
  Future<bool> markQueued(String localJobId, DateTime now);
  Future<bool> markPrinting(String localJobId, DateTime now);
  Future<bool> markTransportAccepted(String localJobId, DateTime now);
  Future<bool> markFailedRetryable(
    String localJobId, {
    required String errorCode,
    required DateTime nextAttemptAt,
    required DateTime now,
  });
  Future<bool> markBlockedConfiguration(
    String localJobId, {
    required String errorCode,
    required DateTime now,
  });
  Future<int> markPossiblyPrintedOnRecovery(DateTime now);
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
  Future<int> countUnresolved({
    required String deviceId,
    required String branchId,
  });
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

/// Drift-backed implementation over [LocalDatabase].
final class DriftKitchenSpoolStore implements KitchenSpoolStore {
  DriftKitchenSpoolStore(this._db);

  final LocalDatabase _db;

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

  @override
  Future<KitchenSpoolJobRow?> claimRunnableForPrinting(
    String localJobId,
    DateTime now,
  ) {
    // Same shape as the RF071-B1 print-spool claim: one conditional UPDATE in
    // a transaction is the atomic duplicate-dispatch guard — PLUS the
    // destination single-flight guard (never two `printing` jobs on the same
    // pinned destination; SQLite serializes writes, so the check inside the
    // transaction is race-safe).
    return _db.transaction(() async {
      final row = await getByLocalJobId(localJobId);
      if (row == null) return null;
      final fingerprint = row.destinationFingerprint;
      if (fingerprint != null) {
        final busy =
            await (_db.select(_t)..where(
                  (t) =>
                      t.destinationFingerprint.equals(fingerprint) &
                      t.status.equalsValue(KitchenSpoolJobStatus.printing) &
                      t.localJobId.equals(localJobId).not(),
                ))
                .get();
        if (busy.isNotEmpty) return null;
      }
      final updated =
          await (_db.update(_t)..where(
                (t) =>
                    t.localJobId.equals(localJobId) &
                    t.status.isInValues(
                      KitchenSpoolJobStatus.runnable.toList(),
                    ) &
                    (t.nextAttemptAt.isNull() |
                        t.nextAttemptAt.isSmallerOrEqualValue(now)),
              ))
              .write(
                KitchenSpoolJobsCompanion.custom(
                  status: Constant(KitchenSpoolJobStatus.printing.wireName),
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
  Future<bool> markQueued(String localJobId, DateTime now) {
    return _transition(
      localJobId,
      from: const {KitchenSpoolJobStatus.imported},
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.queued),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<bool> markPrinting(String localJobId, DateTime now) {
    // Explicit transition variant of the claim (no attempt bookkeeping, no
    // due-time gate) — still single-flight via the conditional WHERE.
    return _transition(
      localJobId,
      from: KitchenSpoolJobStatus.runnable,
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.printing),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<bool> markTransportAccepted(String localJobId, DateTime now) {
    return _transition(
      localJobId,
      from: const {KitchenSpoolJobStatus.printing},
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.transportAccepted),
        transportAcceptedAt: Value(now),
        nextAttemptAt: const Value(null),
        lastErrorCode: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<bool> markFailedRetryable(
    String localJobId, {
    required String errorCode,
    required DateTime nextAttemptAt,
    required DateTime now,
  }) {
    return _transition(
      localJobId,
      from: const {
        KitchenSpoolJobStatus.printing,
        KitchenSpoolJobStatus.queued,
        KitchenSpoolJobStatus.imported,
      },
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.failedRetryable),
        lastErrorCode: Value(errorCode),
        nextAttemptAt: Value(nextAttemptAt),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<bool> markBlockedConfiguration(
    String localJobId, {
    required String errorCode,
    required DateTime now,
  }) {
    return _transition(
      localJobId,
      from: const {
        KitchenSpoolJobStatus.imported,
        KitchenSpoolJobStatus.queued,
        KitchenSpoolJobStatus.printing,
        KitchenSpoolJobStatus.failedRetryable,
      },
      write: KitchenSpoolJobsCompanion(
        status: const Value(KitchenSpoolJobStatus.blockedConfiguration),
        lastErrorCode: Value(errorCode),
        nextAttemptAt: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<int> markPossiblyPrintedOnRecovery(DateTime now) {
    // Startup crash recovery maps ONLY printing -> possiblyPrinted (the
    // transport may or may not have delivered bytes; paper MAY exist). The
    // hold is permanent: nothing maps possiblyPrinted back to a runnable
    // state anywhere in this API.
    return (_db.update(_t)
          ..where((t) => t.status.equalsValue(KitchenSpoolJobStatus.printing)))
        .write(
          KitchenSpoolJobsCompanion(
            status: const Value(KitchenSpoolJobStatus.possiblyPrinted),
            nextAttemptAt: const Value(null),
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
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.dispatchId.equals(dispatchId) &
                  t.status.isInValues(const [
                    KitchenSpoolJobStatus.imported,
                    KitchenSpoolJobStatus.queued,
                    KitchenSpoolJobStatus.failedRetryable,
                    KitchenSpoolJobStatus.blockedConfiguration,
                    KitchenSpoolJobStatus.possiblyPrinted,
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
  }) async {
    final updated =
        await (_db.update(_t)..where(
              (t) =>
                  t.localJobId.equals(localJobId) &
                  t.status.isInValues(from.toList()),
            ))
            .write(write);
    return updated > 0;
  }
}
