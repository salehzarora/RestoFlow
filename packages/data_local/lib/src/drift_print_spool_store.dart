import 'package:drift/drift.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

import 'local_database.dart';

/// The durable Drift-backed [PrintSpoolStore] (RF-071, approved A2).
///
/// Persists [PrintJob]s in the local `print_jobs` table, serializing the
/// render-neutral document via [PrintDocumentCodec] (A4 — no raw bytes/money).
/// The `(deviceId, localOperationId)` UNIQUE constraint (D-022) is the
/// duplicate-print backstop; the engine de-dups before saving.
class DriftPrintSpoolStore implements PrintSpoolStore {
  DriftPrintSpoolStore(
    this._db, {
    PrintDocumentCodec codec = const PrintDocumentCodec(),
  }) : _codec = codec;

  final LocalDatabase _db;
  final PrintDocumentCodec _codec;

  static const _runnable = {
    PrintJobState.created,
    PrintJobState.queued,
    PrintJobState.retrying,
  };

  @override
  Future<void> save(PrintJob job) =>
      _db.into(_db.printJobs).insertOnConflictUpdate(_toCompanion(job));

  @override
  Future<PrintJob?> getById(String id) async {
    final row = await (_db.select(
      _db.printJobs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<PrintJob?> findByIdempotencyKey(
    String deviceId,
    String localOperationId,
  ) async {
    final row =
        await (_db.select(_db.printJobs)..where(
              (t) =>
                  t.deviceId.equals(deviceId) &
                  t.localOperationId.equals(localOperationId),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<PrintJob>> listRunnable(DateTime now) async {
    final rows =
        await (_db.select(_db.printJobs)
              ..where(
                (t) =>
                    t.status.isInValues(_runnable.toList()) &
                    (t.nextAttemptAt.isNull() |
                        t.nextAttemptAt.isSmallerOrEqualValue(now)),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<PrintJob?> claimRunnableForPrinting(String jobId, DateTime now) {
    // RF071-B1: a single conditional UPDATE in a transaction is the atomic
    // duplicate-dispatch guard. The WHERE matches only a still-runnable, due
    // job; SQLite serializes writes, so a second concurrent claim updates 0
    // rows (status is already `printing`) and returns null.
    return _db.transaction(() async {
      final updated =
          await (_db.update(_db.printJobs)..where(
                (t) =>
                    t.id.equals(jobId) &
                    t.status.isInValues(_runnable.toList()) &
                    (t.nextAttemptAt.isNull() |
                        t.nextAttemptAt.isSmallerOrEqualValue(now)),
              ))
              .write(
                PrintJobsCompanion(
                  status: const Value(PrintJobState.printing),
                  updatedAt: Value(now),
                ),
              );
      if (updated == 0) return null;
      final row = await (_db.select(
        _db.printJobs,
      )..where((t) => t.id.equals(jobId))).getSingle();
      return _fromRow(row);
    });
  }

  @override
  Future<int> markPossiblyPrintedOnRecovery(DateTime now) {
    return (_db.update(
      _db.printJobs,
    )..where((t) => t.status.equalsValue(PrintJobState.printing))).write(
      PrintJobsCompanion(
        status: const Value(PrintJobState.possiblyPrinted),
        updatedAt: Value(now),
      ),
    );
  }

  PrintJobsCompanion _toCompanion(PrintJob job) => PrintJobsCompanion(
    id: Value(job.id),
    organizationId: Value(job.organizationId),
    branchId: Value(job.branchId),
    deviceId: Value(job.deviceId),
    stationId: Value(job.stationId),
    localOperationId: Value(job.localOperationId),
    jobType: Value(job.jobType),
    status: Value(job.status),
    payloadJson: Value(_codec.encode(job.document)),
    retryCount: Value(job.retryCount),
    maxRetries: Value(job.maxRetries),
    nextAttemptAt: Value(job.nextAttemptAt),
    lastErrorCode: Value(job.lastErrorCode),
    lastErrorMessage: Value(job.lastErrorMessage),
    reprintOf: Value(job.reprintOf),
    reprintReason: Value(job.reprintReason),
    createdAt: Value(job.createdAt),
    updatedAt: Value(job.updatedAt),
    printedAt: Value(job.printedAt),
    abandonedAt: Value(job.abandonedAt),
  );

  PrintJob _fromRow(PrintJobRow row) => PrintJob(
    id: row.id,
    organizationId: row.organizationId,
    branchId: row.branchId,
    deviceId: row.deviceId,
    stationId: row.stationId,
    localOperationId: row.localOperationId,
    jobType: row.jobType,
    status: row.status,
    document: _codec.decode(row.payloadJson),
    retryCount: row.retryCount,
    maxRetries: row.maxRetries,
    nextAttemptAt: row.nextAttemptAt,
    lastErrorCode: row.lastErrorCode,
    lastErrorMessage: row.lastErrorMessage,
    reprintOf: row.reprintOf,
    reprintReason: row.reprintReason,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    printedAt: row.printedAt,
    abandonedAt: row.abandonedAt,
  );
}
