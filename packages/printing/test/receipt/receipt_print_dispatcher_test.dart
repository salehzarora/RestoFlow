import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-073 — the receipt dispatcher: validate (D9) -> build -> enqueue a
/// `receipt` job keyed `receipt:<paymentId>` (D8). In-memory only; never prints,
/// never drains, never touches transport.
void main() {
  final at = DateTime.utc(2026, 6, 23, 12, 0, 0);

  group('enqueue original receipt (D8)', () {
    test('enqueues one receipt job with the right scope + key', () async {
      final h = _Harness(clock: () => at);
      final job = await h.dispatcher.enqueueOriginalReceipt(
        _input(),
        ReceiptPaperSpec.mm80,
      );

      expect(job.jobType, PrintJobType.receipt);
      expect(job.stationId, isNull);
      expect(job.localOperationId, 'receipt:pay-1');
      expect(job.id, 'receipt:pay-1');
      expect(job.organizationId, 'org-1');
      expect(job.branchId, 'branch-1');
      expect(job.deviceId, 'dev-1');
      expect(job.createdAt, at);
      expect(job.document.lines, isNotEmpty);
      expect(await h.store.listRunnable(at), hasLength(1));
    });

    test('localOperationIdFor is deterministic per payment', () {
      expect(
        ReceiptPrintDispatcher.localOperationIdFor('pay-1'),
        'receipt:pay-1',
      );
    });
  });

  group('idempotency (D-022): receipt:<paymentId>', () {
    test(
      're-dispatching the same payment does not duplicate the job',
      () async {
        final h = _Harness(clock: () => at);
        final first = await h.dispatcher.enqueueOriginalReceipt(
          _input(),
          ReceiptPaperSpec.mm80,
        );
        final second = await h.dispatcher.enqueueOriginalReceipt(
          _input(),
          ReceiptPaperSpec.mm80,
        );

        expect(second.id, first.id);
        expect(await h.store.listRunnable(at), hasLength(1));
      },
    );

    test('different payments enqueue distinct jobs', () async {
      final h = _Harness(clock: () => at);
      await h.dispatcher.enqueueOriginalReceipt(
        _input(paymentId: 'pay-1'),
        ReceiptPaperSpec.mm80,
      );
      await h.dispatcher.enqueueOriginalReceipt(
        _input(paymentId: 'pay-2'),
        ReceiptPaperSpec.mm80,
      );
      expect(await h.store.listRunnable(at), hasLength(2));
    });
  });

  group('issue gating (D9): refuse to print bad/unsettled receipts', () {
    test('empty paymentId is rejected', () {
      final h = _Harness(clock: () => at);
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(paymentId: ''),
          ReceiptPaperSpec.mm80,
        ),
        throwsArgumentError,
      );
    });

    test('empty receiptNumber is rejected', () {
      final h = _Harness(clock: () => at);
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(receiptNumber: ''),
          ReceiptPaperSpec.mm80,
        ),
        throwsArgumentError,
      );
    });

    test('empty branchId / deviceId are rejected', () {
      final h = _Harness(clock: () => at);
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(branchId: ''),
          ReceiptPaperSpec.mm80,
        ),
        throwsArgumentError,
      );
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(deviceId: ''),
          ReceiptPaperSpec.mm80,
        ),
        throwsArgumentError,
      );
    });

    test('empty orderRef / currencyCode are rejected', () {
      final h = _Harness(clock: () => at);
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(orderRef: ''),
          ReceiptPaperSpec.mm80,
        ),
        throwsArgumentError,
      );
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(currencyCode: ''),
          ReceiptPaperSpec.mm80,
        ),
        throwsArgumentError,
      );
    });

    test('an unpaid order is rejected', () {
      final h = _Harness(clock: () => at);
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(isPaid: false),
          ReceiptPaperSpec.mm80,
        ),
        throwsStateError,
      );
    });

    test('a voided/cancelled order is rejected', () {
      final h = _Harness(clock: () => at);
      expect(
        () => h.dispatcher.enqueueOriginalReceipt(
          _input(isVoidedOrCancelled: true),
          ReceiptPaperSpec.mm80,
        ),
        throwsStateError,
      );
    });

    test('nothing is enqueued when gating fails', () async {
      final h = _Harness(clock: () => at);
      try {
        await h.dispatcher.enqueueOriginalReceipt(
          _input(isPaid: false),
          ReceiptPaperSpec.mm80,
        );
      } catch (_) {
        // expected
      }
      expect(await h.store.listRunnable(at), isEmpty);
    });
  });

  group('Arabic dispatch uses the injected rasterizer', () {
    test('the enqueued document is a raster image', () async {
      final raster = FakeReceiptRasterizer();
      final h = _Harness(clock: () => at, rasterizer: raster);
      final job = await h.dispatcher.enqueueOriginalReceipt(
        _input(locale: ReceiptLocale.ar),
        ReceiptPaperSpec.mm80,
      );
      expect(
        job.document.lines.whereType<PrintRasterImageLine>(),
        hasLength(1),
      );
      expect(job.document.lines.whereType<PrintTextLine>(), isEmpty);
      expect(raster.requests, hasLength(1));
    });
  });

  group('no hardware / no transport (A6 analogue)', () {
    test('dispatch only queues; the printer is never invoked', () async {
      final h = _Harness(clock: () => at);
      await h.dispatcher.enqueueOriginalReceipt(
        _input(),
        ReceiptPaperSpec.mm80,
      );
      expect(h.printer.printed, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Harness + fixture.
// ---------------------------------------------------------------------------

class _Harness {
  _Harness({DateTime Function()? clock, ReceiptRasterizer? rasterizer})
    : store = InMemoryPrintSpoolStore() {
    final spool = PrintSpool(
      store: store,
      printer: printer,
      auditSink: InMemoryReprintAuditSink(),
    );
    dispatcher = ReceiptPrintDispatcher(
      spool: spool,
      rasterizer: rasterizer,
      clock: clock,
    );
  }

  final InMemoryPrintSpoolStore store;
  final FakePrinter printer = FakePrinter();
  late final ReceiptPrintDispatcher dispatcher;
}

ReceiptInput _input({
  String paymentId = 'pay-1',
  String receiptNumber = 'R-1',
  String branchId = 'branch-1',
  String deviceId = 'dev-1',
  String orderRef = 'o1',
  String currencyCode = 'ILS',
  bool isPaid = true,
  bool isVoidedOrCancelled = false,
  ReceiptLocale locale = ReceiptLocale.en,
}) => ReceiptInput(
  organizationId: 'org-1',
  branchId: branchId,
  deviceId: deviceId,
  paymentId: paymentId,
  receiptNumber: receiptNumber,
  orderRef: orderRef,
  serviceType: ReceiptServiceType.dineIn,
  currencyCode: currencyCode,
  locale: locale,
  issuedAt: DateTime.utc(2026, 6, 23, 12, 0, 0),
  items: [
    ReceiptItemLine(nameSnapshot: 'Burger', quantity: 1, lineTotalMinor: 4000),
  ],
  subtotalMinor: 4000,
  totalMinor: 4000,
  tender: const ReceiptTenderLine(
    method: 'Cash',
    paidMinor: 4000,
    changeMinor: 0,
  ),
  isPaid: isPaid,
  isVoidedOrCancelled: isVoidedOrCancelled,
);
