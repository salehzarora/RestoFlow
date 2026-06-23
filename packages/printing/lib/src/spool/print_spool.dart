import 'dart:math';

import '../print_result.dart';
import '../printer.dart';
import 'print_job.dart';
import 'print_job_state.dart';
import 'print_spool_store.dart';
import 'reprint_audit_sink.dart';

/// Retry/backoff policy for the print spool (RF-071, approved A6 — configurable,
/// not frozen). `maxRetries` lives on each [PrintJob] (default 12); this holds
/// the backoff schedule and the transient-vs-permanent classification.
class PrintRetryPolicy {
  const PrintRetryPolicy({
    this.baseDelay = const Duration(seconds: 2),
    this.multiplier = 2,
    this.maxDelay = const Duration(minutes: 5),
    this.jitter = true,
  });

  final Duration baseDelay;
  final num multiplier;
  final Duration maxDelay;
  final bool jitter;

  /// Only `unsupported` is permanent (never retried — it would loop forever).
  /// Everything else (`unreachable`/`paperOut`/`coverOpen`/`unknown`) is
  /// transient and bounded by the job's `maxRetries`.
  bool isPermanent(PrinterErrorCategory category) =>
      category == PrinterErrorCategory.unsupported;

  /// Delay before retry [attempt] (1-based): `base * multiplier^(attempt-1)`,
  /// capped at [maxDelay]; with full jitter the result is `random()*ceiling`.
  Duration backoffFor(int attempt, {double Function()? random}) {
    final exp = (attempt - 1).clamp(0, 30);
    final raw = baseDelay.inMicroseconds * pow(multiplier, exp).toDouble();
    final capped = raw > maxDelay.inMicroseconds
        ? maxDelay.inMicroseconds.toDouble()
        : raw;
    if (!jitter) return Duration(microseconds: capped.round());
    final r = (random ?? Random().nextDouble)();
    return Duration(microseconds: (capped * r).round());
  }
}

/// The durable print-job spool engine (RF-071).
///
/// Enqueues jobs (idempotent on `(deviceId, localOperationId)`, D-022), drains
/// runnable jobs FIFO through the RF-070 [Printer], and drives the state machine
/// with retry/backoff → `abandoned` after `maxRetries`. A job in `printing` is
/// never re-dispatched (single-flight); a crash leaves it `possiblyPrinted`
/// (never auto-reprinted). A reprint is an explicit NEW job (new idempotency
/// key + `reprintOf` + mandatory reason) that emits a [ReprintAuditEntry] to the
/// [ReprintAuditSink]. The engine holds no real transport — printing happens
/// through the injected [Printer] (RF-070 `AdapterPrinter` + `InMemoryPrintTransport`
/// in tests). Clock/random/id are injectable for deterministic tests.
class PrintSpool {
  PrintSpool({
    required PrintSpoolStore store,
    required Printer printer,
    required ReprintAuditSink auditSink,
    PrintRetryPolicy retryPolicy = const PrintRetryPolicy(),
    DateTime Function()? clock,
    double Function()? random,
    String Function()? newId,
  }) : _store = store,
       _printer = printer,
       _auditSink = auditSink,
       _retryPolicy = retryPolicy,
       _clock = clock ?? DateTime.now,
       _random = random,
       _newId = newId;

  final PrintSpoolStore _store;
  final Printer _printer;
  final ReprintAuditSink _auditSink;
  final PrintRetryPolicy _retryPolicy;
  final DateTime Function() _clock;
  final double Function()? _random;
  final String Function()? _newId;

  int _idSeq = 0;
  String _generateId() => _newId != null ? _newId() : 'printjob-${_idSeq++}';

  /// Enqueue [job], collapsing a duplicate `(deviceId, localOperationId)` to the
  /// existing job (returns it unchanged). Otherwise persists [job] and returns it.
  Future<PrintJob> enqueue(PrintJob job) async {
    final existing = await _store.findByIdempotencyKey(
      job.deviceId,
      job.localOperationId,
    );
    if (existing != null) return existing;
    await _store.save(job);
    return job;
  }

  /// Recover after a crash/restart: move interrupted `printing` jobs to
  /// `possiblyPrinted` (never auto-reprinted). Returns the count moved.
  Future<int> recover() => _store.markPossiblyPrintedOnRecovery(_clock());

  /// Process every currently-runnable job once (FIFO). Returns the resulting jobs.
  Future<List<PrintJob>> drainOnce() async {
    final runnable = await _store.listRunnable(_clock());
    final results = <PrintJob>[];
    for (final job in runnable) {
      results.add(await processJob(job));
    }
    return results;
  }

  /// Drive one job through `(created/queued/retrying)→printing→printed` or, on
  /// failure, `printing→failed→(retrying|abandoned)`.
  ///
  /// RF071-B1: the snapshot [job] is NOT trusted — the job is first ATOMICALLY
  /// claimed via [PrintSpoolStore.claimRunnableForPrinting]. If the claim fails
  /// (already printing/terminal/possiblyPrinted/not-due, or a concurrent drain
  /// already claimed it), nothing is printed and the current persisted row (or
  /// the snapshot) is returned. This is the single-flight, duplicate-dispatch
  /// guard — only the claimer prints.
  Future<PrintJob> processJob(PrintJob job) async {
    final claimed = await _store.claimRunnableForPrinting(job.id, _clock());
    if (claimed == null) {
      // Not runnable/due, or another drain already claimed it — never print.
      return await _store.getById(job.id) ?? job;
    }
    var j = claimed; // current row, status == printing (no stale fields)

    final PrintResult res = await _printer.printDocument(j.document);
    final now = _clock();

    if (res.ok) {
      j = j.copyWith(
        status: PrintJobState.printed,
        printedAt: now,
        updatedAt: now,
        nextAttemptAt: null,
        lastErrorCode: null,
        lastErrorMessage: null,
      );
      await _store.save(j);
      return j;
    }

    final category = res.category ?? PrinterErrorCategory.unknown;
    // printing -> failed (record the error).
    j = j.copyWith(
      status: PrintJobState.failed,
      lastErrorCode: category.name,
      lastErrorMessage: res.message,
      updatedAt: now,
    );
    await _store.save(j);

    // failed -> abandoned (permanent or retries exhausted) | retrying.
    if (_retryPolicy.isPermanent(category)) {
      j = j.copyWith(
        status: PrintJobState.abandoned,
        abandonedAt: now,
        updatedAt: now,
      );
    } else {
      final attempts = j.retryCount + 1;
      if (attempts >= j.maxRetries) {
        j = j.copyWith(
          status: PrintJobState.abandoned,
          retryCount: attempts,
          abandonedAt: now,
          updatedAt: now,
        );
      } else {
        final wait = _retryPolicy.backoffFor(attempts, random: _random);
        j = j.copyWith(
          status: PrintJobState.retrying,
          retryCount: attempts,
          nextAttemptAt: now.add(wait),
          updatedAt: now,
        );
      }
    }
    await _store.save(j);
    return j;
  }

  /// Create an explicit reprint of [originalJobId]: a NEW job (new idempotency
  /// key + `reprintOf` + mandatory [reason]) that renders the SAME document. The
  /// original is never modified. Emits a [ReprintAuditEntry] to the sink.
  /// Throws if [reason] is blank or the original is missing.
  ///
  /// REFUSES cash-drawer jobs ([PrintJobType.cashDrawer]) with a [StateError]
  /// (RF-58, for RF-074): reprinting a drawer kick would physically open the
  /// drawer a second time, breaking the at-most-once guarantee. The refusal
  /// happens before any new job is created and emits NO audit entry; the
  /// original job is left unchanged.
  Future<PrintJob> reprint(
    String originalJobId, {
    required String reason,
    String? actorId,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'a reprint reason is required',
      );
    }
    final original = await _store.getById(originalJobId);
    if (original == null) {
      throw StateError('print job $originalJobId not found');
    }
    if (original.jobType == PrintJobType.cashDrawer) {
      throw StateError(
        'cash drawer jobs cannot be reprinted: a re-issue would open the '
        'drawer again (job $originalJobId)',
      );
    }
    final now = _clock();
    final newJobId = _generateId();
    final newLocalOp = _generateId();
    final reprintJob = PrintJob(
      id: newJobId,
      organizationId: original.organizationId,
      branchId: original.branchId,
      deviceId: original.deviceId,
      stationId: original.stationId,
      localOperationId: newLocalOp,
      jobType: original.jobType,
      document: original.document,
      status: PrintJobState.created,
      maxRetries: original.maxRetries,
      reprintOf: originalJobId,
      reprintReason: trimmed,
      createdAt: now,
      updatedAt: now,
    );
    await _store.save(reprintJob);
    await _auditSink.record(
      ReprintAuditEntry(
        originalJobId: originalJobId,
        newJobId: newJobId,
        reason: trimmed,
        jobType: original.jobType,
        organizationId: original.organizationId,
        branchId: original.branchId,
        deviceId: original.deviceId,
        stationId: original.stationId,
        actorId: actorId,
      ),
    );
    return reprintJob;
  }
}
