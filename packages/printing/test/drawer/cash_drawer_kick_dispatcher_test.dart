import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// A [Printer] that always fails with a TRANSIENT error and counts dispatches —
/// proves a `maxRetries: 0` drawer job is dispatched at most once (no re-kick).
class _TransientFailPrinter implements Printer {
  int calls = 0;

  @override
  Future<PrintResult> printDocument(PrintDocument document) async {
    calls++;
    return const PrintResult.failure(PrinterErrorCategory.unreachable);
  }
}

final _t0 = DateTime.utc(2026, 6, 23, 12);

/// RF-074 — the cash-drawer kick dispatcher. In-memory only: no hardware, no
/// real transport. SAFETY: the drawer must open at most once.
void main() {
  group('completed authorized cash payment (AC1)', () {
    test('enqueues exactly one no-retry cashDrawer kick job', () async {
      final h = _Harness();
      final job = await h.dispatcher.enqueueKick(_input());

      expect(job, isNotNull);
      expect(job!.jobType, PrintJobType.cashDrawer);
      expect(job.id, 'drawer:pay-1');
      expect(job.localOperationId, 'drawer:pay-1');
      expect(job.maxRetries, 0);
      expect(job.organizationId, 'org-1');
      expect(job.branchId, 'branch-1');
      expect(job.deviceId, 'dev-1');
      expect(job.stationId, isNull);

      // Document is exactly one drawer-kick line (no text, no money).
      expect(job.document.lines, hasLength(1));
      expect(job.document.lines.single, isA<PrintDrawerKickLine>());

      // Persisted as a runnable job; the dispatcher never printed directly.
      expect(await h.store.listRunnable(_t0), hasLength(1));
      expect(h.printer.printed, isEmpty);
    });

    test('localOperationIdFor is deterministic', () {
      expect(
        CashDrawerKickDispatcher.localOperationIdFor('pay-1'),
        'drawer:pay-1',
      );
    });
  });

  group('idempotency (D-022): drawer:<paymentId> (AC: kick once)', () {
    test(
      'duplicate dispatch for the same payment collapses to one job',
      () async {
        final h = _Harness();
        final first = await h.dispatcher.enqueueKick(_input());
        final second = await h.dispatcher.enqueueKick(_input());

        expect(second!.id, first!.id);
        expect(await h.store.listRunnable(_t0), hasLength(1));
      },
    );
  });

  group('gating: never open the drawer for the wrong payment', () {
    test('non-cash / not-completed payment does not enqueue', () async {
      final h = _Harness();
      final job = await h.dispatcher.enqueueKick(
        _input(isCompletedCashPayment: false),
      );
      expect(job, isNull);
      expect(await h.store.listRunnable(_t0), isEmpty);
      expect(h.printer.printed, isEmpty);
    });

    test('voided/cancelled payment does not enqueue', () async {
      final h = _Harness();
      final job = await h.dispatcher.enqueueKick(
        _input(isVoidedOrCancelled: true),
      );
      expect(job, isNull);
      expect(await h.store.listRunnable(_t0), isEmpty);
    });

    test('unauthorized session throws and enqueues nothing', () async {
      final h = _Harness();
      await expectLater(
        () => h.dispatcher.enqueueKick(_input(authorized: false)),
        throwsStateError,
      );
      expect(await h.store.listRunnable(_t0), isEmpty);
    });

    test('missing ids throw ArgumentError', () async {
      final h = _Harness();
      for (final bad in <CashDrawerKickInput>[
        _input(paymentId: ''),
        _input(organizationId: ''),
        _input(branchId: ''),
        _input(deviceId: ''),
      ]) {
        await expectLater(
          () => h.dispatcher.enqueueKick(bad),
          throwsArgumentError,
        );
      }
      expect(await h.store.listRunnable(_t0), isEmpty);
    });
  });

  group('no automatic retry (AC: at-most-once)', () {
    test(
      'a transient failure abandons the kick and never re-dispatches',
      () async {
        final store = InMemoryPrintSpoolStore();
        final printer = _TransientFailPrinter();
        final spool = PrintSpool(
          store: store,
          printer: printer,
          auditSink: InMemoryReprintAuditSink(),
          clock: () => _t0,
        );
        final dispatcher = CashDrawerKickDispatcher(
          spool: spool,
          clock: () => _t0,
        );

        await dispatcher.enqueueKick(_input());

        // First drain dispatches once; maxRetries:0 -> straight to abandoned
        // (never `retrying`), so the drawer is opened at most once.
        final out = (await spool.drainOnce()).single;
        expect(out.status, PrintJobState.abandoned);
        expect(printer.calls, 1);

        // Nothing runnable remains; a second drain never re-kicks.
        expect(
          await store.listRunnable(_t0.add(const Duration(hours: 1))),
          isEmpty,
        );
        expect(await spool.drainOnce(), isEmpty);
        expect(printer.calls, 1, reason: 'the drawer is never opened twice');
      },
    );
  });

  group('crash/unknown state never auto-opens again', () {
    test(
      'an interrupted kick becomes possiblyPrinted and is not re-dispatched',
      () async {
        final h = _Harness();
        final job = (await h.dispatcher.enqueueKick(_input()))!;

        // Simulate a crash mid-print: the job was left in `printing`.
        await h.store.save(job.copyWith(status: PrintJobState.printing));

        final moved = await h.spool.recover();
        expect(moved, 1);
        expect(
          (await h.store.getById('drawer:pay-1'))!.status,
          PrintJobState.possiblyPrinted,
        );

        // Recovery does NOT re-open the drawer.
        expect(await h.spool.drainOnce(), isEmpty);
        expect(
          (await h.store.getById('drawer:pay-1'))!.status,
          PrintJobState.possiblyPrinted,
        );
        expect(h.printer.printed, isEmpty);
      },
    );
  });

  group('a drawer job created by RF-074 cannot be reprinted (RF-58 guard)', () {
    test('reprint of the enqueued kick throws', () async {
      final h = _Harness();
      await h.dispatcher.enqueueKick(_input());
      await expectLater(
        () => h.spool.reprint('drawer:pay-1', reason: 'manager asked'),
        throwsA(isA<StateError>()),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Harness + fixture.
// ---------------------------------------------------------------------------

class _Harness {
  _Harness() : store = InMemoryPrintSpoolStore() {
    spool = PrintSpool(
      store: store,
      printer: printer,
      auditSink: InMemoryReprintAuditSink(),
      clock: () => _t0,
    );
    dispatcher = CashDrawerKickDispatcher(spool: spool, clock: () => _t0);
  }

  final InMemoryPrintSpoolStore store;
  final FakePrinter printer = FakePrinter();
  late final PrintSpool spool;
  late final CashDrawerKickDispatcher dispatcher;
}

CashDrawerKickInput _input({
  String organizationId = 'org-1',
  String branchId = 'branch-1',
  String deviceId = 'dev-1',
  String paymentId = 'pay-1',
  bool isCompletedCashPayment = true,
  bool isVoidedOrCancelled = false,
  bool authorized = true,
}) => CashDrawerKickInput(
  organizationId: organizationId,
  branchId: branchId,
  deviceId: deviceId,
  paymentId: paymentId,
  isCompletedCashPayment: isCompletedCashPayment,
  isVoidedOrCancelled: isVoidedOrCancelled,
  authorized: authorized,
);
