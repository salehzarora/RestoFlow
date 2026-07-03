import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/state/kds_auto_print_prefs.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_kds/src/state/kds_printer_assignments.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Device settings sprint (Part F): the acknowledge print-trigger POLICY.
/// A kitchen job is prepared ONLY when the per-device toggle is effectively
/// on and the branch has a kitchen-printer read; it is idempotent per order
/// (no double-print across re-taps / polls); it never fakes a printed
/// success; and the payload carries modifier quantities + notes with NO
/// money (T-003).

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

class _FakeReader implements DevicePrinterAssignmentsReader {
  _FakeReader({this.hasPrinter = true, this.fail = false});

  final bool hasPrinter;
  final bool fail;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => fail
      ? const Failure(DevicePrinterAssignmentsFailure.network)
      : Success(
          DevicePrinterAssignments(
            fetchedAt: DateTime(2026, 7, 3, 12, 30),
            printers: hasPrinter
                ? const [
                    AssignedPrinter(
                      id: 'prn-k1',
                      displayName: 'Kitchen printer',
                      role: 'kitchen',
                      connectionType: 'network',
                      paperWidth: '80mm',
                      isEnabled: true,
                    ),
                  ]
                : const [],
          ),
        );
}

class _OffAutoPrint extends KdsAutoPrintAcknowledgeController {
  @override
  Future<bool?> build() async => false;
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
      modifiers: const ['وسط', 'جبنة إضافية ×2'],
      note: 'بدون بصل',
    ),
  ],
  status: KitchenTicketStatus.acknowledged,
);

Future<ProviderContainer> _container({
  bool hasPrinter = true,
  bool fail = false,
  bool autoPrintOff = false,
}) async {
  final c = ProviderContainer(
    overrides: [
      kdsPrinterAssignmentsReaderProvider.overrideWithValue(
        _FakeReader(hasPrinter: hasPrinter, fail: fail),
      ),
      if (autoPrintOff)
        kdsAutoPrintAcknowledgeProvider.overrideWith(_OffAutoPrint.new),
    ],
  );
  addTearDown(c.dispose);
  await c.read(kdsPrinterAssignmentsProvider.future);
  await c.read(kdsAutoPrintAcknowledgeProvider.future);
  return c;
}

void main() {
  test('toggle-on (default) + kitchen printer -> ONE prepared job; the '
      'payload has modifier quantities + notes and NO money', () async {
    final l10n = await _en();
    final c = await _container(hasPrinter: true);
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);

    controller.prepareOnAcknowledge(
      _ticket(),
      buildDocument: () => buildKdsTicketDocument(l10n, _ticket()),
    );

    final job = controller.jobFor(_ticket())!;
    expect(job.status, KdsPrintJobStatus.prepared);
    expect(job.status, isNot(KdsPrintJobStatus.printed));
    final html = documentToHtml(job.document!);
    expect(html, contains('جبنة إضافية ×2')); // modifier quantity
    expect(html, contains('بدون بصل')); // item note
    expect(html.contains('₪'), isFalse);
    expect(html.toLowerCase().contains('minor'), isFalse);
  });

  test('toggle OFF -> nothing is prepared', () async {
    final c = await _container(hasPrinter: true, autoPrintOff: true);
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);

    controller.prepareOnAcknowledge(_ticket(), buildDocument: () => throw '');

    expect(controller.jobFor(_ticket()), isNull);
  });

  test(
    'no kitchen printer assigned -> an honest notConfigured marker',
    () async {
      final c = await _container(hasPrinter: false);
      final controller = c.read(kdsKitchenPrintControllerProvider.notifier);

      controller.prepareOnAcknowledge(
        _ticket(),
        buildDocument: () => throw 'never built',
      );

      expect(
        controller.jobFor(_ticket())!.status,
        KdsPrintJobStatus.notConfigured,
      );
    },
  );

  test('a FAILED assignment read -> nothing (never a fake job)', () async {
    final c = await _container(fail: true);
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);

    controller.prepareOnAcknowledge(
      _ticket(),
      buildDocument: () => throw 'never built',
    );

    expect(controller.jobFor(_ticket()), isNull);
  });

  test('re-acknowledge / poll rebuild -> IDEMPOTENT (builds once)', () async {
    final l10n = await _en();
    final c = await _container(hasPrinter: true);
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    var builds = 0;

    for (var i = 0; i < 3; i++) {
      controller.prepareOnAcknowledge(
        _ticket(), // a fresh view each time, same order id
        buildDocument: () {
          builds++;
          return buildKdsTicketDocument(l10n, _ticket());
        },
      );
    }

    expect(builds, 1);
    expect(controller.jobFor(_ticket())!.status, KdsPrintJobStatus.prepared);
  });
}
