import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_preview.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// TABLET-UX-001 (E): a printer-status message must reflect the ACTUAL print
/// result. A successful print never shows/prints "printer not connected"; the
/// honest no-printer message stays only when there really is no printer.

Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

CashPayment _payment() => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#ABC',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 1000,
  tenderedMinor: 1000,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-INTERNAL-9',
  paidAt: DateTime.utc(2026, 7, 8, 14, 30),
);

const _order = SubmittedOrderView(
  orderNumber: '#ABC123',
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 1000,
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
    ),
  ],
);

String _docText(PrintDocument doc) =>
    doc.lines.map((l) => '${l.left ?? ''} ${l.right ?? ''}').join('\n');

/// Pumps [ReceiptPreview] in REAL mode with the order's print job seeded to
/// [seed] (null => no job).
Future<void> _pumpPreview(
  WidgetTester tester, {
  required AppLocalizations l10n,
  required PrintJobStatus? seed,
}) async {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
    ],
  );
  addTearDown(container.dispose);
  final ctrl = container.read(receiptPrintControllerProvider.notifier);
  PrintDocument buildDoc() =>
      buildReceiptDocument(l10n, _order, _payment(), isDemo: false);
  switch (seed) {
    case PrintJobStatus.sentToPrinter:
      ctrl.prepare(
        orderKey: _order.identity.key,
        hasEnabledPrinter: true,
        buildDocument: buildDoc,
      );
      ctrl.markSentToPrinter(_order.identity.key);
    case PrintJobStatus.notConfigured:
      ctrl.prepare(
        orderKey: _order.identity.key,
        hasEnabledPrinter: false,
        buildDocument: buildDoc,
      );
    case PrintJobStatus.bridgeUnavailable:
      ctrl.prepare(
        orderKey: _order.identity.key,
        hasEnabledPrinter: true,
        buildDocument: buildDoc,
      );
      ctrl.markBridgeUnavailable(_order.identity.key);
    case null:
      break;
    default:
      break;
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReceiptPreview(order: _order, payment: _payment()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('printed receipt document', () {
    test('a REAL receipt document never bakes in the "printer not connected" '
        'note', () async {
      final l10n = await _l10n('en');
      final doc = buildReceiptDocument(l10n, _order, _payment(), isDemo: false);
      expect(_docText(doc).contains(l10n.posReceiptNoPrinterNote), isFalse);
    });

    test(
      'Arabic real receipt document carries no printer-status error text',
      () async {
        final ar = await _l10n('ar');
        final doc = buildReceiptDocument(ar, _order, _payment(), isDemo: false);
        expect(_docText(doc).contains(ar.posReceiptNoPrinterNote), isFalse);
      },
    );

    test(
      'demo mode still prints its provisional/demo notes (unchanged)',
      () async {
        final l10n = await _l10n('en');
        final doc = buildReceiptDocument(
          l10n,
          _order,
          _payment(),
          isDemo: true,
        );
        final text = _docText(doc);
        expect(text.contains(l10n.posReceiptProvisionalNote), isTrue);
        expect(text.contains(l10n.posReceiptDemoNote), isTrue);
      },
    );
  });

  group('receipt card status note (real mode)', () {
    testWidgets('a SUCCESSFUL print shows "Printed", never "printer not '
        'connected"', (tester) async {
      final l10n = await _l10n('en');
      await _pumpPreview(
        tester,
        l10n: l10n,
        seed: PrintJobStatus.sentToPrinter,
      );
      expect(find.text(l10n.posReceiptPrintedNote), findsOneWidget);
      expect(find.text(l10n.posReceiptNoPrinterNote), findsNothing);
    });

    testWidgets('no configured printer still shows the honest no-printer '
        'message', (tester) async {
      final l10n = await _l10n('en');
      await _pumpPreview(
        tester,
        l10n: l10n,
        seed: PrintJobStatus.notConfigured,
      );
      expect(find.text(l10n.posReceiptNoPrinterNote), findsOneWidget);
      expect(find.text(l10n.posReceiptPrintedNote), findsNothing);
    });

    testWidgets('a bridge-unavailable job shows NEITHER note here (the status '
        'line surfaces it with Retry)', (tester) async {
      final l10n = await _l10n('en');
      await _pumpPreview(
        tester,
        l10n: l10n,
        seed: PrintJobStatus.bridgeUnavailable,
      );
      expect(find.text(l10n.posReceiptNoPrinterNote), findsNothing);
      expect(find.text(l10n.posReceiptPrintedNote), findsNothing);
    });

    testWidgets('no print job (auto-print off) shows neither note', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      await _pumpPreview(tester, l10n: l10n, seed: null);
      expect(find.text(l10n.posReceiptNoPrinterNote), findsNothing);
      expect(find.text(l10n.posReceiptPrintedNote), findsNothing);
    });
  });
}
