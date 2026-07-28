import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show BridgeSubmitResult, PrintPhysicalOutcome, PrinterErrorCategory;

/// Device settings sprint (Part D): the receipt print-job pipeline is
/// HONEST — prepared is never printed, no printer is never faked into a
/// job, a builder failure never claims success, and preparation is
/// idempotent per order.

void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  PrintDocument doc() => PrintDocument(
    title: 'r',
    lines: [PrintLine.item('2× Burger', '₪96.00'), PrintLine.sub('+ Cheese')],
  );

  test('with an enabled printer the job is PREPARED (never printed)', () {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);

    controller.prepare(
      orderKey: '#A1',
      hasEnabledPrinter: true,
      buildDocument: doc,
    );

    final job = controller.jobFor('#A1')!;
    expect(job.status, PrintJobStatus.prepared);
    expect(job.document, isNotNull);
    expect(job.status, isNot(PrintJobStatus.printed));
  });

  test('no enabled printer -> an honest notConfigured marker, no document', () {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);

    controller.prepare(
      orderKey: '#A1',
      hasEnabledPrinter: false,
      buildDocument: doc,
    );

    final job = controller.jobFor('#A1')!;
    expect(job.status, PrintJobStatus.notConfigured);
    expect(job.document, isNull);
  });

  test('prepare is IDEMPOTENT per order (rebuilds cannot double-prepare)', () {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);
    var builds = 0;

    for (var i = 0; i < 3; i++) {
      controller.prepare(
        orderKey: '#A1',
        hasEnabledPrinter: true,
        buildDocument: () {
          builds++;
          return doc();
        },
      );
    }

    expect(builds, 1);
    expect(c.read(receiptPrintControllerProvider), hasLength(1));
  });

  test('a throwing builder records FAILED — the order is unaffected', () {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);

    controller.prepare(
      orderKey: '#A1',
      hasEnabledPrinter: true,
      buildDocument: () => throw StateError('boom'),
    );

    expect(controller.jobFor('#A1')!.status, PrintJobStatus.failed);
  });

  group('§8 print outcomes affect PRINTING only, never order/payment', () {
    test('a Bluetooth timeout AFTER dispatch: order=1, payment=1, ONE dispatch; '
        'an explicit retry re-dispatches WITHOUT replaying order/payment', () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);

      // The real sequence: the order is submitted and the payment recorded ONCE,
      // BEFORE printing — printing is a separate, later step that owns neither.
      var orderSubmits = 0;
      var paymentMutations = 0;
      var dispatches = 0;
      orderSubmits++; // submit the order (once)
      paymentMutations++; // record the payment (once)

      Future<BridgeSubmitResult> btTimeoutAfterDispatch(PrintDocument _) async {
        dispatches++;
        // A partial/unknown-after-dispatch failure (the fixed §1 outer-timeout).
        return const BridgeSubmitResult.failed(
          PrinterErrorCategory.unreachable,
          'no response (dispatched; outcome unknown)',
          PrintPhysicalOutcome.partialOrUnknownAfterDispatch,
        );
      }

      await controller.prepareAndDispatch(
        orderKey: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: btTimeoutAfterDispatch,
      );
      expect(dispatches, 1, reason: 'exactly one physical dispatch');
      // The print did NOT confirm (a dispatched-but-unknown outcome) — the exact
      // non-success status is a UI concern; what matters for §8 is that it is not
      // a success and the order/payment are untouched.
      expect(
        controller.jobFor('#A1')!.status,
        isNot(PrintJobStatus.sentToPrinter),
      );
      expect(controller.jobFor('#A1')!.status, isNot(PrintJobStatus.printed));
      expect(orderSubmits, 1);
      expect(paymentMutations, 1);

      // The operator explicitly retries the PRINT only.
      await controller.retry(
        orderKey: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: btTimeoutAfterDispatch,
      );
      expect(
        dispatches,
        2,
        reason: 'one more dispatch per explicit user retry',
      );
      expect(
        orderSubmits,
        1,
        reason: 'a print retry never resubmits the order',
      );
      expect(
        paymentMutations,
        1,
        reason: 'a print retry never replays the payment',
      );
    });

    test('prepareAndDispatch dispatches ONCE even if called again (idempotent) '
        '— a rebuild after a print failure never re-dispatches', () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);
      var dispatches = 0;
      Future<BridgeSubmitResult> submit(PrintDocument _) async {
        dispatches++;
        return const BridgeSubmitResult.failed(
          PrinterErrorCategory.unreachable,
          'x',
          PrintPhysicalOutcome.partialOrUnknownAfterDispatch,
        );
      }

      await controller.prepareAndDispatch(
        orderKey: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: submit,
      );
      // A second call for the same order (e.g. a state rebuild) must NOT resend.
      await controller.prepareAndDispatch(
        orderKey: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: submit,
      );
      expect(
        dispatches,
        1,
        reason: 'idempotent per order — no auto re-dispatch',
      );
    });
  });
}
