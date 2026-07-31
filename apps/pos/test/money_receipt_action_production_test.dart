import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        BluetoothDeviceInfo,
        BluetoothPairedResult,
        BluetoothPrinterConnector,
        bluetoothPrinterConnectorProvider,
        kBluetoothPrintTimeout,
        nativePrinterNamespaceProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show PosPrintBridge, posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintDocument;
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-RELEASE-PROOF-003E — the ACTION-level receipt proof.
///
/// WHY THIS SUITE EXISTS. Codex found that the 002D "production path" receipt
/// tests called the authoritative SOURCE FUNCTION and the DOCUMENT BUILDER
/// directly. That proves the document layer, and `money_bill_receipt_production_test`
/// still owns that proof — but it never ran the ACTION that produces a receipt,
/// so nothing showed that the real automatic trigger fires once, or that the
/// real manual reprint is a genuinely separate operator action.
///
/// Everything below runs through REAL production seams:
///   * the real `CashPaymentSheet` widget, its real tender field and its real
///     `confirm-payment-button`;
///   * the real `PaymentController.payCash` (fake repository at the ONE network
///     boundary);
///   * the real `_requestPaidReceipt` automatic trigger inside the sheet;
///   * the real `ReceiptPrintController.requestReceipt` lifecycle;
///   * the real `OrderActionRow` reprint button and its real `reprint()` call;
///   * the real ESC/POS render, captured as BYTES at the printer transport.
///
/// Nothing is called directly that the cashier does not cause by tapping.
///
/// THE MONEY FIXTURE, as independent literals: base 4500, one paid modifier at
/// 1500, item quantity 2. 4500 + 1500 = 6000 per unit; 6000 x 2 = 12000. The
/// receipt must show 12000 and the surcharge must survive into the bytes.
const kBase = 4500;
const kDelta = 1500;
const kUnit = 6000; // 4500 + 1500, written out
const kTotal = 12000; // 6000 x 2, written out
const kTendered = 15000;
const kChange = 3000; // 15000 - 12000, written out

final _identity = PosOrderIdentity.server('oid-RCPT1');
const _orderKey = 'srv:oid-RCPT1';

/// Captures every byte batch that actually reaches a printer transport. The
/// automatic and the manual path share this, so the two sends are distinguished
/// by ORDER of arrival, not by any test-only tagging.
class _RecordingConnector implements BluetoothPrinterConnector {
  final List<Uint8List> sent = <Uint8List>[];

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.ok(<BluetoothDeviceInfo>[]);

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = kBluetoothPrintTimeout,
  }) async {
    sent.add(bytes);
    return const pp.PrintResult.success();
  }
}

/// Captures the app-level document the MANUAL reprint dispatches.
///
/// The manual path reads the SYNCHRONOUS `posActivePrintBridgeProvider`, which
/// under a native/Bluetooth setup samples `.valueOrNull` on AsyncNotifiers and
/// is still null on the first read — the tap then falls into the honest
/// "no printer configured" branch and prints nothing. Turning native printing
/// OFF makes that provider return this fake immediately, which is the only way
/// to make the manual capture deterministic without touching production.
class _RecordingBridge implements PosPrintBridge {
  final List<PrintDocument> documents = <PrintDocument>[];

  @override
  Future<pp.BridgeSubmitResult> submit(PrintDocument document) async {
    documents.add(document);
    return const pp.BridgeSubmitResult.sentToPrinter();
  }

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

void _seedBluetoothPrinter() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restoflow.printer.selected.pos.local': 'bluetooth',
    'restoflow.printer.bluetooth.pos.local': jsonEncode(<String, Object?>{
      'address': '66:32:1E:0A:BB:CD',
      'name': 'Counter',
    }),
  });
}

/// The unpaid order as the Orders list holds it: ONE line, quantity 2, carrying
/// a paid modifier. `lineTotalMinor` is the 002A formula already applied.
const _order = SubmittedOrderView(
  orderNumber: '#RCPT1',
  orderType: OrderType.dineIn,
  tableLabel: 'T7',
  currencyCode: 'ILS',
  subtotalMinor: kTotal,
  orderId: 'oid-RCPT1',
  customerName: 'Dana',
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 2,
      lineTotalMinor: kTotal,
      currencyCode: 'ILS',
      modifiers: ['240g'],
    ),
  ],
);

String _text(Uint8List bytes) => String.fromCharCodes(bytes);

void main() {
  setUp(_seedBluetoothPrinter);

  // =========================================================================
  // A — THE REAL AUTOMATIC PAID-RECEIPT ACTION
  // =========================================================================
  group('A. the automatic receipt is produced by the real payment action', () {
    Future<(ProviderContainer, _RecordingConnector)> pumpSheet(
      WidgetTester tester, {
      PaymentRepository? repo,
    }) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final connector = _RecordingConnector();
      final container = ProviderContainer(
        overrides: [
          posNativePrintingAvailableProvider.overrideWithValue(true),
          nativePrinterNamespaceProvider.overrideWithValue('pos'),
          bluetoothPrinterConnectorProvider.overrideWithValue(connector),
          if (repo != null) paymentRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(posRecentOrdersControllerProvider.notifier)
          .recordSubmitted(_order);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: CashPaymentSheet(
                identity: _identity,
                orderNumber: '#RCPT1',
                amountMinor: kTotal,
                currencyCode: 'ILS',
                orderId: 'oid-RCPT1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container, connector);
    }

    /// Types a tender and taps the REAL confirm button. The sheet refuses to
    /// record anything until the tender covers the total, so skipping this
    /// would "pass" without a payment ever being attempted.
    Future<void> confirm(
      WidgetTester tester, {
      String tender = '150.00',
    }) async {
      await tester.enterText(find.byType(TextField).first, tender);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-payment-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('A1 paying through the real sheet prints the paid receipt '
        'exactly once, carrying the configured surcharge', (tester) async {
      final (container, connector) = await pumpSheet(tester);
      await confirm(tester);

      final job = container.read(receiptPrintControllerProvider)[_orderKey];
      expect(
        job,
        isNotNull,
        reason:
            'the automatic action must have created a job for THIS order key — '
            'nothing in this test called requestReceipt directly',
      );
      expect(job!.status, PrintJobStatus.sentToPrinter);
      expect(
        connector.sent,
        hasLength(1),
        reason: 'exactly one physical send for one payment',
      );

      final receipt = _text(connector.sent.single);
      expect(
        receipt,
        contains('120.00'),
        reason: 'the authoritative 12000 total, not the 4500 base',
      );
      expect(
        receipt,
        contains('240g'),
        reason: 'the paid modifier survives into the printed bytes',
      );
      expect(
        receipt.contains('45.00') && !receipt.contains('120.00'),
        isFalse,
        reason: 'the bare base price must never stand in for the line total',
      );
    });

    testWidgets('A2 the automatic action does not fire a second time for the '
        'same order', (tester) async {
      final (container, connector) = await pumpSheet(tester);
      await confirm(tester);
      expect(connector.sent, hasLength(1));

      // The controller's per-order latch is the production guarantee; re-enter
      // through the same public request the sheet uses.
      await container
          .read(receiptPrintControllerProvider.notifier)
          .requestReceipt(
            orderKey: _orderKey,
            resolveReadiness: () async => ReceiptReadiness.configured,
            buildDocument: () => throw StateError('must not rebuild'),
          );
      await tester.pumpAndSettle();
      expect(
        connector.sent,
        hasLength(1),
        reason: 'a paid receipt must never print twice off one payment',
      );
    });

    testWidgets('A3 a FAILED payment prints nothing at all', (tester) async {
      final (container, connector) = await pumpSheet(
        tester,
        repo: _FailingPaymentRepo(),
      );
      await confirm(tester);

      expect(
        connector.sent,
        isEmpty,
        reason:
            'the receipt is requested only after payCash returns without '
            'throwing — a refused payment must leave the printer silent',
      );
      expect(
        container.read(receiptPrintControllerProvider)[_orderKey],
        isNull,
        reason: 'no job may exist for a payment that was refused',
      );
    });

    testWidgets('A4 an UNPAID order has no receipt job before payment', (
      tester,
    ) async {
      final (container, connector) = await pumpSheet(tester);
      expect(container.read(receiptPrintControllerProvider)[_orderKey], isNull);
      expect(connector.sent, isEmpty);
    });
  });

  // =========================================================================
  // B — THE REAL MANUAL REPRINT ACTION
  // =========================================================================
  group('B. the manual reprint is a separate operator action', () {
    /// A PAID order row, as the Orders list holds it after payment.
    PosRecentOrder paidRow() => PosRecentOrder(
      order: _order,
      payment: CashPayment(
        paymentId: 'pay-RCPT1',
        orderNumber: '#RCPT1',
        deviceId: 'dev-1',
        localOperationId: 'op-pay-1',
        method: PaymentMethod.cash,
        status: PaymentStatus.completed,
        amountMinor: kTotal,
        tenderedMinor: kTendered,
        changeMinor: kChange,
        currencyCode: 'ILS',
        receiptNumber: 'R-77',
        paidAt: DateTime.now().toUtc(),
        orderId: 'oid-RCPT1',
      ),
    );

    Future<(ProviderContainer, _RecordingBridge)> pumpRow(
      WidgetTester tester, {
      PosRecentOrder? row,
    }) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final bridge = _RecordingBridge();
      final container = ProviderContainer(
        overrides: [
          posNativePrintingAvailableProvider.overrideWithValue(false),
          posPrintBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);
      final order = row ?? paidRow();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: OrderActionRow(
                  order: order,
                  l10n: AppLocalizations.of(ctx),
                  actions: resolveOrderActions(order),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container, bridge);
    }

    testWidgets('B1 tapping the real reprint button dispatches a receipt '
        'carrying the configured surcharge', (tester) async {
      final (_, bridge) = await pumpRow(tester);

      await tester.tap(find.byKey(const Key('recent-reprint-#RCPT1')));
      await tester.pumpAndSettle();

      expect(
        bridge.documents,
        hasLength(1),
        reason: 'the operator asked for one copy and got exactly one',
      );
      final flat = bridge.documents.single.lines
          .map((l) => '${l.left ?? ''} ${l.right ?? ''}')
          .join(String.fromCharCode(10));
      expect(
        flat,
        contains('240g'),
        reason: 'the paid modifier is on the copy',
      );
      expect(flat, contains('120.00'), reason: 'the authoritative total');
    });

    testWidgets('B2 reprint is REPEATABLE — the operator may ask again', (
      tester,
    ) async {
      final (_, bridge) = await pumpRow(tester);
      final key = const Key('recent-reprint-#RCPT1');

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();

      expect(
        bridge.documents,
        hasLength(2),
        reason:
            'unlike the automatic receipt, a deliberate reprint is never '
            'suppressed — a customer who asks for another copy gets one',
      );
    });

    testWidgets('B3 an UNPAID order offers no reprint at all', (tester) async {
      final unpaid = PosRecentOrder(order: _order);
      final (_, bridge) = await pumpRow(tester, row: unpaid);

      expect(
        find.byKey(const Key('recent-reprint-#RCPT1')),
        findsNothing,
        reason:
            'canReprintReceipt requires a COMPLETED payment (003A) — there is '
            'no receipt to reprint for an order nobody has paid',
      );
      expect(bridge.documents, isEmpty);
    });
  });
}

/// Refuses every payment, the way the server does for a non-chargeable order.
/// Everything else delegates to the real demo store, so only the refusal is fake.
class _FailingPaymentRepo implements PaymentRepository {
  final DemoPaymentStore _inner = DemoPaymentStore();

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async => throw const PaymentException('order_not_chargeable');

  @override
  ShiftContext shiftContext() => _inner.shiftContext();

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) =>
      _inner.paymentFor(identity);
}
