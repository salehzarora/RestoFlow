import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_print_bridge.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/state/kds_auto_print_prefs.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_kds/src/state/kds_printer_assignments.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// RF-115: the kitchen print controller reaches `sentToPrinter` ONLY on a
/// CONFIRMED bridge result, records an honest failure otherwise, NEVER
/// fabricates a hardware "printed", its Retry re-runs a job, and the ESC/POS
/// payload is MONEY-FREE (T-003).

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

class _FakeReader implements DevicePrinterAssignmentsReader {
  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 7, 4, 12),
      printers: const [
        AssignedPrinter(
          id: 'prn-k1',
          displayName: 'Kitchen printer',
          role: 'kitchen',
          connectionType: 'network',
          paperWidth: '80mm',
          isEnabled: true,
        ),
      ],
    ),
  );
}

KdsTicketView _ticket() => KdsTicketView(
  kitchenTicketId: 'kt-1',
  stationId: 'grill',
  orderId: 'o1',
  orderNumber: '#3F7A2C',
  orderType: 'dine_in',
  tableLabel: 'T2',
  notes: 'rush order',
  items: [
    KdsItemView(
      name: 'برجر كلاسيك',
      quantity: 1,
      modifiers: const ['جبنة إضافية ×2'],
      note: 'بدون بصل',
    ),
  ],
  status: KitchenTicketStatus.acknowledged,
);

Future<ProviderContainer> _container() async {
  final c = ProviderContainer(
    overrides: [
      kdsPrinterAssignmentsReaderProvider.overrideWithValue(_FakeReader()),
    ],
  );
  addTearDown(c.dispose);
  await c.read(kdsPrinterAssignmentsProvider.future);
  await c.read(kdsAutoPrintAcknowledgeProvider.future);
  return c;
}

KdsBridgeSubmit _always(pp.BridgeSubmitResult result) =>
    (_) async => result;

void main() {
  test('a CONFIRMED bridge write -> sentToPrinter (never printed)', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    await controller.prepareOnAcknowledge(
      _ticket(),
      buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
      submitToBridge: _always(const pp.BridgeSubmitResult.sentToPrinter()),
    );
    final job = controller.jobFor(_ticket())!;
    expect(job.status, KdsPrintJobStatus.sentToPrinter);
    expect(job.status, isNot(KdsPrintJobStatus.printed));
  });

  test('a demo SINK accept -> stays prepared (not sent to hardware)', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    await controller.prepareOnAcknowledge(
      _ticket(),
      buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
      submitToBridge: _always(
        const pp.BridgeSubmitResult.accepted(mode: 'sink'),
      ),
    );
    expect(controller.jobFor(_ticket())!.status, KdsPrintJobStatus.prepared);
  });

  test('an unreachable bridge -> bridgeUnavailable', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    await controller.prepareOnAcknowledge(
      _ticket(),
      buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
      submitToBridge: _always(
        const pp.BridgeSubmitResult.failed(pp.PrinterErrorCategory.unreachable),
      ),
    );
    expect(
      controller.jobFor(_ticket())!.status,
      KdsPrintJobStatus.bridgeUnavailable,
    );
  });

  test('a transport failure -> failed WITH a category', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    await controller.prepareOnAcknowledge(
      _ticket(),
      buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
      submitToBridge: _always(
        const pp.BridgeSubmitResult.failed(pp.PrinterErrorCategory.coverOpen),
      ),
    );
    final job = controller.jobFor(_ticket())!;
    expect(job.status, KdsPrintJobStatus.failed);
    expect(job.failureCategory, pp.PrinterErrorCategory.coverOpen);
  });

  test(
    'retry re-runs a failed job -> a confirmed write reaches sentToPrinter',
    () async {
      final l10n = await _en();
      final c = await _container();
      final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
      await controller.prepareOnAcknowledge(
        _ticket(),
        buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
        submitToBridge: _always(
          const pp.BridgeSubmitResult.failed(pp.PrinterErrorCategory.coverOpen),
        ),
      );
      expect(controller.jobFor(_ticket())!.status, KdsPrintJobStatus.failed);
      await controller.retry(
        _ticket(),
        hasEnabledPrinter: true,
        buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
        submitToBridge: _always(const pp.BridgeSubmitResult.sentToPrinter()),
      );
      expect(
        controller.jobFor(_ticket())!.status,
        KdsPrintJobStatus.sentToPrinter,
      );
    },
  );

  test('the kitchen ESC/POS payload is MONEY-FREE (T-003)', () async {
    final l10n = await _en();
    final escpos = kitchenTicketToEscPosDocument(
      buildKdsTicketDocument(l10n, _ticket()),
    );
    final text = escpos.lines
        .whereType<pp.PrintTextLine>()
        .map((l) => l.text)
        .join('\n');
    // Carries the ticket content but never any money.
    expect(text.contains('#3F7A2C'), isTrue);
    expect(text.contains('جبنة إضافية ×2'), isTrue); // modifier quantity
    expect(text.contains('₪'), isFalse);
    expect(text.contains(r'$'), isFalse);
    expect(text.toLowerCase().contains('minor'), isFalse);
  });
}
