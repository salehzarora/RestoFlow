import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device settings sprint (Part E): the receipt print job is prepared ONLY
/// after a SUCCESSFUL payment for the confirmed order, only when the
/// per-device toggle is effectively on, and it never claims a physical
/// print (prepared, not printed). Payload carries modifier quantities +
/// item notes.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

class _FakeAssignmentsReader implements DevicePrinterAssignmentsReader {
  _FakeAssignmentsReader({required this.hasPrinter});

  final bool hasPrinter;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 7, 3, 12, 30),
      printers: hasPrinter
          ? const [
              AssignedPrinter(
                id: 'prn-1',
                displayName: 'Counter receipt',
                role: 'receipt',
                connectionType: 'network',
                paperWidth: '80mm',
                isEnabled: true,
              ),
            ]
          : const [],
    ),
  );
}

/// Auto-print explicitly OFF (the cashier flipped the toggle) — bypasses the
/// device-id-keyed shared_preferences read.
class _OffAutoPrint extends PosAutoPrintReceiptController {
  @override
  Future<bool?> build() async => false;
}

final _snapAt = DateTime.utc(2026, 7, 14, 12);

const _order = SubmittedOrderView(
  orderNumber: '#3F7A2C',
  orderType: OrderType.dineIn,
  tableLabel: 'T2',
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 5400,
      currencyCode: 'ILS',
      modifiers: ['Medium', 'Extra cheese ×2'],
      note: 'no onions',
    ),
  ],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool hasPrinter,
  bool autoPrintOff = false,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      posPrinterAssignmentsReaderProvider.overrideWithValue(
        _FakeAssignmentsReader(hasPrinter: hasPrinter),
      ),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
      if (autoPrintOff)
        posAutoPrintReceiptProvider.overrideWith(_OffAutoPrint.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: OrderConfirmation(order: _order, onNewOrder: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Let the assignments + prefs resolve before paying.
  await container.read(posPrinterAssignmentsProvider.future);
  await container.read(posAutoPrintReceiptProvider.future);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _pay(WidgetTester tester, ProviderContainer container) async {
  await container
      .read(paymentControllerProvider.notifier)
      .payCash(
        identity: _order.identity,
        orderId: 'order-1',
        orderNumber: _order.orderNumber,
        amountMinor: _order.subtotalMinor,
        tenderedMinor: 6000,
        currencyCode: 'ILS',
      );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('payment success + printer + toggle-on (default) -> ONE '
      'prepared job whose payload carries modifier quantities + notes; '
      'the UI shows prepared, never printed', (tester) async {
    final l10n = await _en();
    final container = await _pump(tester, hasPrinter: true);

    // Nothing before the payment: a submit alone must not print.
    expect(container.read(receiptPrintControllerProvider), isEmpty);
    expect(find.byKey(const Key('receipt-print-status')), findsNothing);

    await _pay(tester, container);

    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_order.identity.key)!;
    expect(job.status, PrintJobStatus.prepared);
    final html = documentToHtml(job.document!);
    expect(html, contains('Extra cheese ×2')); // modifier quantity
    expect(html, contains('no onions')); // item note
    expect(html, contains('#3F7A2C'));
    // The honest status line: prepared/bridge-required, NOT printed.
    expect(find.byKey(const Key('receipt-print-status')), findsOneWidget);
    expect(find.textContaining(l10n.printStatusPrepared), findsOneWidget);
    expect(find.textContaining(l10n.printStatusPrinted), findsNothing);
  });

  testWidgets(
    'the RECEIPT prints the AUTHORITATIVE money: a discount landing from '
    'another till before payment realigns the printed totals, not just the '
    'screen',
    (tester) async {
      // An order this device SUBMITTED, with a server id — so the confirmation can
      // bind to the reconciled row.
      const submitted = SubmittedOrderView(
        orderNumber: '#3F7A2C',
        orderType: OrderType.dineIn,
        tableLabel: 'T2',
        currencyCode: 'ILS',
        subtotalMinor: 5400,
        orderId: 'order-1',
        lines: [
          SubmittedLineView(
            name: 'Classic Burger',
            quantity: 1,
            lineTotalMinor: 5400,
            currencyCode: 'ILS',
          ),
        ],
      );
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          posPrinterAssignmentsReaderProvider.overrideWithValue(
            _FakeAssignmentsReader(hasPrinter: true),
          ),
          paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: OrderConfirmation(order: submitted, onNewOrder: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await container.read(posPrinterAssignmentsProvider.future);
      await container.read(posAutoPrintReceiptProvider.future);
      await tester.pumpAndSettle();

      // ANOTHER TILL discounts the order to 40.00 while this screen is open. The
      // reconciliation lands through the REAL production path.
      container
          .read(posRecentOrdersControllerProvider.notifier)
          .recordSubmitted(submitted);
      await container
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots([
            PosOrderSnapshot(
              orderId: 'order-1',
              orderCode: '#3F7A2C',
              revision: 2,
              status: 'served',
              settlement: PosSettlement.unpaid,
              subtotalMinor: 5400,
              discountTotalMinor: 1400,
              taxTotalMinor: 0,
              grandTotalMinor: 4000,
              createdAt: _snapAt,
              updatedAt: _snapAt,
              syncAt: _snapAt,
              currencyCode: 'ILS',
            ),
          ]);
      await tester.pumpAndSettle();

      // The cashier takes the AUTHORITATIVE 40.00.
      await container
          .read(paymentControllerProvider.notifier)
          .payCash(
            identity: submitted.identity,
            orderId: 'order-1',
            orderNumber: submitted.orderNumber,
            amountMinor: 4000,
            tenderedMinor: 4000,
            currencyCode: 'ILS',
          );
      await tester.pumpAndSettle();

      final job = container
          .read(receiptPrintControllerProvider.notifier)
          .jobFor(submitted.identity.key)!;
      final html = documentToHtml(job.document!);

      // THE PRINTED RECEIPT SAYS WHAT WAS CHARGED. It used to be built from the
      // FROZEN submit-time view, so this exact scenario printed "Total ₪54.00 /
      // Paid ₪40.00" — an incoherent financial document — while the orders
      // centre's reprint of the SAME order printed ₪40.00.
      expect(html, contains('₪40.00'), reason: 'the authoritative total');
      expect(
        html,
        contains('₪14.00'),
        reason: 'the discount line the server applied',
      );
      // The ON-SCREEN receipt shows the same realigned money: the discounted
      // total appears in the widget tree, not just in the printable payload.
      expect(
        find.textContaining('₪40.00'),
        findsWidgets,
        reason: 'the on-screen receipt shows what was charged',
      );
    },
  );

  testWidgets('the per-device toggle OFF -> payment succeeds, NO job, NO '
      'status line', (tester) async {
    final container = await _pump(tester, hasPrinter: true, autoPrintOff: true);

    await _pay(tester, container);

    expect(container.read(receiptPrintControllerProvider), isEmpty);
    expect(find.byKey(const Key('receipt-print-status')), findsNothing);
  });

  testWidgets('no assigned printer -> payment succeeds, an HONEST '
      'notConfigured marker (no fake job)', (tester) async {
    final l10n = await _en();
    final container = await _pump(tester, hasPrinter: false);

    await _pay(tester, container);

    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_order.identity.key)!;
    expect(job.status, PrintJobStatus.notConfigured);
    expect(job.document, isNull);
    expect(find.textContaining(l10n.printStatusNotConfigured), findsOneWidget);
  });

  testWidgets('a FAILED payment triggers nothing', (tester) async {
    final container = await _pump(tester, hasPrinter: true);

    // Tender below the amount => PaymentException => no payment recorded.
    await expectLater(
      container
          .read(paymentControllerProvider.notifier)
          .payCash(
            identity: _order.identity,
            orderId: 'order-1',
            orderNumber: _order.orderNumber,
            amountMinor: _order.subtotalMinor,
            tenderedMinor: 100,
            currencyCode: 'ILS',
          ),
      throwsA(isA<PaymentException>()),
    );
    await tester.pumpAndSettle();

    expect(container.read(receiptPrintControllerProvider), isEmpty);
    expect(find.byKey(const Key('receipt-print-status')), findsNothing);
  });
}
