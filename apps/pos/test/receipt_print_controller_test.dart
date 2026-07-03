import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';

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
      orderNumber: '#A1',
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
      orderNumber: '#A1',
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
        orderNumber: '#A1',
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
      orderNumber: '#A1',
      hasEnabledPrinter: true,
      buildDocument: () => throw StateError('boom'),
    );

    expect(controller.jobFor('#A1')!.status, PrintJobStatus.failed);
  });
}
