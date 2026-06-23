import 'dart:async';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// A scripted RF-070 [Printer] that returns canned results (repeats the last) —
/// no hardware, deterministic failure injection.
class _ScriptedPrinter implements Printer {
  _ScriptedPrinter(this._results);
  final List<PrintResult> _results;
  int calls = 0;

  @override
  Future<PrintResult> printDocument(PrintDocument document) async {
    final i = calls++;
    return i < _results.length ? _results[i] : _results.last;
  }
}

/// A [Printer] that counts calls and blocks on a gate before succeeding — so a
/// concurrent-drain race is realistic (the first print is in-flight while the
/// second drain runs).
class _CountingGatePrinter implements Printer {
  _CountingGatePrinter(this._gate);
  final Future<void> _gate;
  int calls = 0;

  @override
  Future<PrintResult> printDocument(PrintDocument document) async {
    calls++;
    await _gate;
    return const PrintResult.success();
  }
}

final _t0 = DateTime.utc(2026, 6, 23, 12);

PrintJob _job({String id = 'j1', String op = 'op1', int maxRetries = 12}) =>
    PrintJob(
      id: id,
      organizationId: 'org',
      branchId: 'b1',
      deviceId: 'dev1',
      localOperationId: op,
      jobType: PrintJobType.receipt,
      document: const PrintDocument([PrintTextLine('Hello')]),
      createdAt: _t0,
      updatedAt: _t0,
      maxRetries: maxRetries,
    );

void main() {
  group('enqueue + happy path', () {
    test(
      'drains a job to printed via a real AdapterPrinter + in-memory transport',
      () async {
        final store = InMemoryPrintSpoolStore();
        final transport = InMemoryPrintTransport();
        final spool = PrintSpool(
          store: store,
          printer: AdapterPrinter(
            adapter: const EscPosPrintAdapter(),
            profile: PrinterProfile.escPos80mm,
            transport: transport,
          ),
          auditSink: InMemoryReprintAuditSink(),
          clock: () => _t0,
        );

        await spool.enqueue(_job());
        final results = await spool.drainOnce();

        expect(results.single.status, PrintJobState.printed);
        expect(results.single.printedAt, isNotNull);
        expect(
          transport.lastBytes,
          isNotNull,
          reason: 'bytes were rendered + sent',
        );
      },
    );

    test(
      'dedups on (deviceId, localOperationId): same op enqueues once',
      () async {
        final store = InMemoryPrintSpoolStore();
        final spool = PrintSpool(
          store: store,
          printer: _ScriptedPrinter([const PrintResult.success()]),
          auditSink: InMemoryReprintAuditSink(),
          clock: () => _t0,
        );

        final first = await spool.enqueue(_job(id: 'a', op: 'dup'));
        final second = await spool.enqueue(_job(id: 'b', op: 'dup'));
        expect(second.id, first.id, reason: 'collapses to the existing job');
        expect(await store.getById('b'), isNull);
      },
    );
  });

  group('retry / backoff / abandon (AC1)', () {
    test(
      'transient failures retry with the backoff schedule, then abandon',
      () async {
        final store = InMemoryPrintSpoolStore();
        var now = _t0;
        final spool = PrintSpool(
          store: store,
          // Always unreachable (transient).
          printer: _ScriptedPrinter([
            const PrintResult.failure(PrinterErrorCategory.unreachable),
          ]),
          auditSink: InMemoryReprintAuditSink(),
          retryPolicy: const PrintRetryPolicy(
            jitter: false,
          ), // deterministic schedule
          clock: () => now,
        );

        await spool.enqueue(_job(maxRetries: 2));

        // Attempt 1 -> failed -> retrying, nextAttemptAt = now + 2s.
        var out = (await spool.drainOnce()).single;
        expect(out.status, PrintJobState.retrying);
        expect(out.retryCount, 1);
        expect(out.nextAttemptAt, now.add(const Duration(seconds: 2)));
        expect(out.lastErrorCode, 'unreachable');

        // Not runnable until the backoff elapses.
        expect(await store.listRunnable(now), isEmpty);

        // Advance past backoff: attempt 2 -> retries exhausted -> abandoned.
        now = now.add(const Duration(seconds: 2));
        out = (await spool.drainOnce()).single;
        expect(out.status, PrintJobState.abandoned);
        expect(out.retryCount, 2);
        expect(out.abandonedAt, isNotNull);

        // Abandoned is terminal: nothing more runs.
        expect(
          await store.listRunnable(now.add(const Duration(hours: 1))),
          isEmpty,
        );
      },
    );

    test(
      'a permanent (unsupported) error abandons immediately — no retry loop',
      () async {
        final store = InMemoryPrintSpoolStore();
        final spool = PrintSpool(
          store: store,
          printer: _ScriptedPrinter([
            const PrintResult.failure(PrinterErrorCategory.unsupported),
          ]),
          auditSink: InMemoryReprintAuditSink(),
          clock: () => _t0,
        );
        await spool.enqueue(_job());
        final out = (await spool.drainOnce()).single;
        expect(out.status, PrintJobState.abandoned);
        expect(
          out.retryCount,
          0,
          reason: 'permanent error consumes no retries',
        );
      },
    );

    test('backoff schedule is exponential (no jitter): 2s, 4s, 8s', () {
      const policy = PrintRetryPolicy(jitter: false);
      expect(policy.backoffFor(1), const Duration(seconds: 2));
      expect(policy.backoffFor(2), const Duration(seconds: 4));
      expect(policy.backoffFor(3), const Duration(seconds: 8));
      // capped at 5 minutes
      expect(policy.backoffFor(20), const Duration(minutes: 5));
    });
  });

  group('crash recovery (possiblyPrinted)', () {
    test(
      'a job left printing becomes possiblyPrinted and is not auto-retried',
      () async {
        final store = InMemoryPrintSpoolStore();
        // Persist a job already in `printing` (as if interrupted mid-print).
        await store.save(_job().copyWith(status: PrintJobState.printing));
        final spool = PrintSpool(
          store: store,
          printer: _ScriptedPrinter([const PrintResult.success()]),
          auditSink: InMemoryReprintAuditSink(),
          clock: () => _t0,
        );

        final moved = await spool.recover();
        expect(moved, 1);
        expect(
          (await store.getById('j1'))!.status,
          PrintJobState.possiblyPrinted,
        );

        // It is NOT runnable and a drain never touches it (no auto-reprint).
        expect(await spool.drainOnce(), isEmpty);
        expect(
          (await store.getById('j1'))!.status,
          PrintJobState.possiblyPrinted,
        );
      },
    );
  });

  group('reprint (AC2/AC3 at the sink boundary)', () {
    test(
      'reprint creates a NEW job with reprintOf + reason and audits it',
      () async {
        final store = InMemoryPrintSpoolStore();
        final sink = InMemoryReprintAuditSink();
        var seq = 0;
        final spool = PrintSpool(
          store: store,
          printer: _ScriptedPrinter([const PrintResult.success()]),
          auditSink: sink,
          clock: () => _t0,
          newId: () => 'new-${seq++}',
        );

        final original = _job(id: 'orig', op: 'op-orig');
        await spool.enqueue(original);

        final reprint = await spool.reprint(
          'orig',
          reason: 'lost receipt',
          actorId: 'emp-1',
        );

        // New job, distinct id + idempotency key, links to the original.
        expect(reprint.id, isNot('orig'));
        expect(reprint.localOperationId, isNot('op-orig'));
        expect(reprint.reprintOf, 'orig');
        expect(reprint.reprintReason, 'lost receipt');
        expect(reprint.status, PrintJobState.created);
        expect(reprint.document, same(original.document));

        // Original is unchanged.
        final orig = (await store.getById('orig'))!;
        expect(orig.reprintOf, isNull);
        expect(orig.status, PrintJobState.created);

        // Exactly one audit entry with actor + reason + reprint_of + new job id.
        expect(sink.entries.length, 1);
        final e = sink.entries.single;
        expect(e.originalJobId, 'orig');
        expect(e.newJobId, reprint.id);
        expect(e.reason, 'lost receipt');
        expect(e.actorId, 'emp-1');
        expect(e.jobType, PrintJobType.receipt);
        expect(e.organizationId, 'org');
        expect(e.branchId, 'b1');
        expect(e.deviceId, 'dev1');
      },
    );

    test('reprint requires a non-blank reason', () async {
      final store = InMemoryPrintSpoolStore();
      final spool = PrintSpool(
        store: store,
        printer: _ScriptedPrinter([const PrintResult.success()]),
        auditSink: InMemoryReprintAuditSink(),
        clock: () => _t0,
      );
      await spool.enqueue(_job(id: 'orig', op: 'op-orig'));
      expect(() => spool.reprint('orig', reason: '   '), throwsArgumentError);
    });

    test('reprint of a missing job throws', () async {
      final spool = PrintSpool(
        store: InMemoryPrintSpoolStore(),
        printer: _ScriptedPrinter([const PrintResult.success()]),
        auditSink: InMemoryReprintAuditSink(),
        clock: () => _t0,
      );
      expect(() => spool.reprint('nope', reason: 'x'), throwsStateError);
    });
  });

  group('duplicate-dispatch prevention (RF071-B1)', () {
    test(
      'stale processJob snapshots cannot print the same job twice',
      () async {
        final store = InMemoryPrintSpoolStore();
        final printer = _ScriptedPrinter([const PrintResult.success()]);
        final spool = PrintSpool(
          store: store,
          printer: printer,
          auditSink: InMemoryReprintAuditSink(),
          clock: () => _t0,
        );
        await spool.enqueue(_job());

        // Two STALE snapshots of the same runnable job.
        final snap1 = (await store.getById('j1'))!;
        final snap2 = (await store.getById('j1'))!;

        await spool.processJob(snap1); // claims + prints
        await spool.processJob(
          snap2,
        ); // claim fails (already printed) -> no print

        expect(
          printer.calls,
          1,
          reason: 'the stale second dispatch cannot print',
        );
        expect((await store.getById('j1'))!.status, PrintJobState.printed);
      },
    );

    test(
      'concurrent drainOnce calls cannot print the same job twice',
      () async {
        final store = InMemoryPrintSpoolStore();
        final gate = Completer<void>();
        final printer = _CountingGatePrinter(gate.future); // blocks mid-print
        final spool = PrintSpool(
          store: store,
          printer: printer,
          auditSink: InMemoryReprintAuditSink(),
          clock: () => _t0,
        );
        await spool.enqueue(_job());

        // Two drains race: each lists the candidate, but only one can CLAIM it.
        final a = spool.drainOnce();
        final b = spool.drainOnce();
        await Future<void>.delayed(Duration.zero); // let both claim-or-skip
        gate.complete(); // release the in-flight print
        await Future.wait([a, b]);

        expect(printer.calls, 1, reason: 'exactly one drain claimed + printed');
        expect((await store.getById('j1'))!.status, PrintJobState.printed);
      },
    );
  });
}
