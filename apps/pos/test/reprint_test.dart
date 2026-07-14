import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// PRINT-STABILITY-001: POS "Reprint last receipt". Reprint re-submits the
/// ALREADY-BUILT receipt document through the bridge WITHOUT rebuilding it — so
/// it never creates a new order or payment and never recomputes money. The
/// last-receipt provider tracks the most recent BUILT receipt.

void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  PrintDocument doc() =>
      PrintDocument(title: 'r', lines: [PrintLine.item('2× Burger', '₪96.00')]);

  test(
    'reprint re-sends the STORED document (no rebuild, no new order/payment)',
    () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);
      var builds = 0;
      final sent = <PrintDocument>[];
      Future<pp.BridgeSubmitResult> record(PrintDocument d) async {
        sent.add(d);
        return const pp.BridgeSubmitResult.sentToPrinter(mode: 'x');
      }

      await controller.prepareAndDispatch(
        orderKey: '#A',
        hasEnabledPrinter: true,
        buildDocument: () {
          builds++;
          return doc();
        },
        submitToBridge: record,
      );
      expect(builds, 1);
      expect(sent, hasLength(1));
      final firstDoc = sent.first;

      await controller.reprint(orderKey: '#A', submitToBridge: record);

      expect(builds, 1); // the document was NOT rebuilt (no re-computation)
      expect(sent, hasLength(2)); // it was re-sent
      expect(identical(sent[1], firstDoc), isTrue); // the SAME snapshot
      expect(controller.jobFor('#A')!.status, PrintJobStatus.sentToPrinter);
    },
  );

  test(
    'POS-ORDERS-AND-PAYMENT-001: reprint(document:) seeds + re-sends a snapshot '
    'with NO prior job (recent-orders reprint of a prior-session order)',
    () async {
      final c = container();
      final controller = c.read(receiptPrintControllerProvider.notifier);
      final sent = <PrintDocument>[];
      Future<pp.BridgeSubmitResult> record(PrintDocument d) async {
        sent.add(d);
        return const pp.BridgeSubmitResult.sentToPrinter(mode: 'x');
      }

      final snapshot = doc();
      // The order was settled in a PRIOR session: no in-memory print job exists.
      expect(controller.jobFor('#Z'), isNull);
      await controller.reprint(
        orderKey: '#Z',
        document: snapshot,
        submitToBridge: record,
      );
      expect(sent, hasLength(1));
      expect(identical(sent.first, snapshot), isTrue); // the supplied snapshot
      expect(controller.jobFor('#Z')!.status, PrintJobStatus.sentToPrinter);
    },
  );

  test('reprint is a no-op with no stored receipt or no bridge', () async {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);

    // Nothing built yet -> nothing happens.
    await controller.reprint(
      orderKey: '#none',
      submitToBridge: (_) async =>
          const pp.BridgeSubmitResult.sentToPrinter(mode: 'x'),
    );
    expect(controller.jobFor('#none'), isNull);

    // A built receipt but no bridge -> stays prepared, no throw.
    await controller.prepareAndDispatch(
      orderKey: '#A',
      hasEnabledPrinter: true,
      buildDocument: doc,
      submitToBridge: null,
    );
    await controller.reprint(orderKey: '#A', submitToBridge: null);
    expect(controller.jobFor('#A')!.status, PrintJobStatus.prepared);
  });

  test('lastReceiptOrderKeyProvider tracks the last BUILT receipt', () async {
    final c = container();
    final controller = c.read(receiptPrintControllerProvider.notifier);
    expect(c.read(lastReceiptOrderKeyProvider), isNull);

    controller.prepare(
      orderKey: '#A',
      hasEnabledPrinter: true,
      buildDocument: doc,
    );
    controller.prepare(
      orderKey: '#B',
      hasEnabledPrinter: true,
      buildDocument: doc,
    );
    expect(c.read(lastReceiptOrderKeyProvider), '#B');

    // A notConfigured job carries NO document, so it is not "the last receipt".
    controller.prepare(
      orderKey: '#C',
      hasEnabledPrinter: false,
      buildDocument: doc,
    );
    expect(c.read(lastReceiptOrderKeyProvider), '#B');
  });
}
