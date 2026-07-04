import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// RF-115: the receipt print controller reaches `sentToPrinter` ONLY on a
/// CONFIRMED bridge result, records an honest failure otherwise, NEVER
/// fabricates a hardware "printed", and its Retry re-runs a job.

void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  PrintDocument doc() => PrintDocument(
    title: 'r',
    lines: [
      PrintLine.item('2× Burger', '₪96.00'),
      PrintLine.kv('Total', '₪96.00', emphasised: true),
    ],
  );

  ReceiptBridgeSubmit always(pp.BridgeSubmitResult result) =>
      (_) async => result;

  test(
    'no bridge (null) -> the job stays PREPARED (unchanged honest behavior)',
    () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);
      await controller.prepareAndDispatch(
        orderNumber: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: null,
      );
      expect(controller.jobFor('#A1')!.status, PrintJobStatus.prepared);
    },
  );

  test('a CONFIRMED bridge write -> sentToPrinter (never printed)', () async {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);
    await controller.prepareAndDispatch(
      orderNumber: '#A1',
      hasEnabledPrinter: true,
      buildDocument: doc,
      submitToBridge: always(
        const pp.BridgeSubmitResult.sentToPrinter(mode: 'tcp'),
      ),
    );
    final job = controller.jobFor('#A1')!;
    expect(job.status, PrintJobStatus.sentToPrinter);
    expect(job.status, isNot(PrintJobStatus.printed));
    expect(job.at, isNotNull);
  });

  test(
    'a demo SINK accept -> stays prepared (honestly NOT sent to hardware)',
    () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);
      await controller.prepareAndDispatch(
        orderNumber: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: always(
          const pp.BridgeSubmitResult.accepted(mode: 'sink'),
        ),
      );
      final job = controller.jobFor('#A1')!;
      expect(job.status, PrintJobStatus.prepared);
      expect(job.status, isNot(PrintJobStatus.sentToPrinter));
      // A job WAS submitted, so the "last job" time is recorded.
      expect(job.at, isNotNull);
    },
  );

  test('an unreachable bridge -> bridgeUnavailable', () async {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);
    await controller.prepareAndDispatch(
      orderNumber: '#A1',
      hasEnabledPrinter: true,
      buildDocument: doc,
      submitToBridge: always(
        const pp.BridgeSubmitResult.failed(pp.PrinterErrorCategory.unreachable),
      ),
    );
    expect(controller.jobFor('#A1')!.status, PrintJobStatus.bridgeUnavailable);
  });

  test(
    'a transport failure -> failed WITH a reason (category preserved)',
    () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);
      await controller.prepareAndDispatch(
        orderNumber: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: always(
          const pp.BridgeSubmitResult.failed(
            pp.PrinterErrorCategory.paperOut,
            'out of paper',
          ),
        ),
      );
      final job = controller.jobFor('#A1')!;
      expect(job.status, PrintJobStatus.failed);
      expect(job.failureCategory, pp.PrinterErrorCategory.paperOut);
      expect(job.failureMessage, 'out of paper');
      // NEVER a fabricated hardware print.
      expect(job.status, isNot(PrintJobStatus.printed));
    },
  );

  test('a throwing bridge -> bridgeUnavailable (order unaffected)', () async {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);
    await controller.prepareAndDispatch(
      orderNumber: '#A1',
      hasEnabledPrinter: true,
      buildDocument: doc,
      submitToBridge: (_) async => throw StateError('boom'),
    );
    expect(controller.jobFor('#A1')!.status, PrintJobStatus.bridgeUnavailable);
  });

  test(
    'retry re-runs a failed job -> a later confirmed write reaches sentToPrinter',
    () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);
      // First attempt fails (paper out).
      await controller.prepareAndDispatch(
        orderNumber: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: always(
          const pp.BridgeSubmitResult.failed(pp.PrinterErrorCategory.paperOut),
        ),
      );
      expect(controller.jobFor('#A1')!.status, PrintJobStatus.failed);
      // Retry with a now-healthy bridge.
      await controller.retry(
        orderNumber: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: always(const pp.BridgeSubmitResult.sentToPrinter()),
      );
      expect(controller.jobFor('#A1')!.status, PrintJobStatus.sentToPrinter);
    },
  );

  test('dispatch is idempotent — repeated calls send once', () async {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);
    var submits = 0;
    ReceiptBridgeSubmit counting = (_) async {
      submits++;
      return const pp.BridgeSubmitResult.sentToPrinter();
    };
    for (var i = 0; i < 3; i++) {
      await controller.prepareAndDispatch(
        orderNumber: '#A1',
        hasEnabledPrinter: true,
        buildDocument: doc,
        submitToBridge: counting,
      );
    }
    expect(submits, 1);
  });

  test('the receipt ESC/POS payload PRESERVES money totals', () {
    final escpos = receiptToEscPosDocument(doc());
    final text = escpos.lines
        .whereType<pp.PrintTextLine>()
        .map((l) => l.text)
        .join('\n');
    expect(text.contains('₪96.00'), isTrue);
    expect(text.contains('Total'), isTrue);
  });
}
