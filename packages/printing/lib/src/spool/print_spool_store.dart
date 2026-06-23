import 'print_job.dart';
import 'print_job_state.dart';

/// The durable spool store port (RF-071). `packages/printing` defines the port +
/// an in-memory impl; `packages/data_local` provides the Drift-backed durable
/// impl (A2). The store persists [PrintJob]s and enforces the idempotency key
/// `(deviceId, localOperationId)` (D-022).
abstract class PrintSpoolStore {
  /// Insert or update [job] (upsert by id). MUST reject a different id reusing
  /// an existing `(deviceId, localOperationId)` (the D-022 uniqueness backstop).
  Future<void> save(PrintJob job);

  /// The job with [id], or null.
  Future<PrintJob?> getById(String id);

  /// The job matching the idempotency key, or null.
  Future<PrintJob?> findByIdempotencyKey(
    String deviceId,
    String localOperationId,
  );

  /// Jobs eligible to run now (status `created`/`queued`/`retrying` with
  /// `nextAttemptAt == null || nextAttemptAt <= now`), in creation order
  /// (FIFO). Excludes `printing` (single-flight), terminals, and
  /// `possiblyPrinted`.
  Future<List<PrintJob>> listRunnable(DateTime now);

  /// Atomically CLAIM [jobId] for printing (RF071-B1 — duplicate-dispatch guard).
  ///
  /// Reloads the current row and transitions it `created`/`queued`/`retrying` ->
  /// `printing` (persisting `updatedAt`) ONLY IF it is still runnable AND due
  /// (`nextAttemptAt` null or `<= now`). Returns the claimed current job (status
  /// `printing`), or null when the job is missing, already `printing`, terminal
  /// (`printed`/`cancelled`/`abandoned`), `possiblyPrinted`, `failed` (not
  /// retrying), or `retrying` but not yet due. The check+transition is atomic —
  /// callers MUST claim before printing and never trust a stale snapshot.
  Future<PrintJob?> claimRunnableForPrinting(String jobId, DateTime now);

  /// Crash recovery: move every job left in `printing` to `possiblyPrinted`
  /// (outcome unknown — never auto-reprinted, §8.3). Returns the count moved.
  Future<int> markPossiblyPrintedOnRecovery(DateTime now);
}

/// The statuses from which a job may be claimed for printing (RF071-B1).
const Set<PrintJobState> kRunnablePrintStates = {
  PrintJobState.created,
  PrintJobState.queued,
  PrintJobState.retrying,
};

/// Thrown when [PrintSpoolStore.save] would violate the `(deviceId,
/// localOperationId)` uniqueness with a different job id (D-022).
class DuplicatePrintJobException implements Exception {
  const DuplicatePrintJobException(
    this.deviceId,
    this.localOperationId,
    this.existingId,
  );
  final String deviceId;
  final String localOperationId;
  final String existingId;
  @override
  String toString() =>
      'DuplicatePrintJobException(($deviceId,$localOperationId) already used by $existingId)';
}

/// An in-memory [PrintSpoolStore] for tests (RF-071): mirrors the Drift store's
/// upsert + idempotency-uniqueness semantics, with no persistence.
class InMemoryPrintSpoolStore implements PrintSpoolStore {
  final Map<String, PrintJob> _byId = {};

  @override
  Future<void> save(PrintJob job) async {
    // Enforce the (deviceId, localOperationId) uniqueness backstop (D-022).
    for (final existing in _byId.values) {
      if (existing.id != job.id &&
          existing.deviceId == job.deviceId &&
          existing.localOperationId == job.localOperationId) {
        throw DuplicatePrintJobException(
          job.deviceId,
          job.localOperationId,
          existing.id,
        );
      }
    }
    _byId[job.id] = job;
  }

  @override
  Future<PrintJob?> getById(String id) async => _byId[id];

  @override
  Future<PrintJob?> findByIdempotencyKey(
    String deviceId,
    String localOperationId,
  ) async {
    for (final j in _byId.values) {
      if (j.deviceId == deviceId && j.localOperationId == localOperationId) {
        return j;
      }
    }
    return null;
  }

  @override
  Future<List<PrintJob>> listRunnable(DateTime now) async {
    final jobs =
        _byId.values
            .where(
              (j) =>
                  kRunnablePrintStates.contains(j.status) &&
                  (j.nextAttemptAt == null || !j.nextAttemptAt!.isAfter(now)),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return jobs;
  }

  @override
  Future<PrintJob?> claimRunnableForPrinting(String jobId, DateTime now) async {
    // Atomic in a single isolate: there is NO `await` between the read and the
    // write below, so two concurrent claims cannot interleave — the first wins
    // and the second sees `printing` (RF071-B1).
    final job = _byId[jobId];
    if (job == null) return null;
    if (!kRunnablePrintStates.contains(job.status)) return null;
    if (job.nextAttemptAt != null && job.nextAttemptAt!.isAfter(now)) {
      return null; // not yet due (retrying backoff not elapsed)
    }
    final claimed = job.copyWith(
      status: PrintJobState.printing,
      updatedAt: now,
    );
    _byId[jobId] = claimed;
    return claimed;
  }

  @override
  Future<int> markPossiblyPrintedOnRecovery(DateTime now) async {
    var moved = 0;
    for (final j in _byId.values.toList()) {
      if (j.status == PrintJobState.printing) {
        _byId[j.id] = j.copyWith(
          status: PrintJobState.possiblyPrinted,
          updatedAt: now,
        );
        moved++;
      }
    }
    return moved;
  }
}
