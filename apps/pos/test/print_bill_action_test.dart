@TestOn('vm')
library;

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
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEFERRED-PAYMENT-RECEIPTS-001 (Goal 2) — the Orders-screen "Print bill"
/// action for an order that is still unpaid.
///
/// Drives the REAL RecentOrdersSheet over the REAL recent-orders, payment and
/// receipt controllers, with a recording Bluetooth connector, so these pin what
/// the cashier can actually do.

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

const _unpaid = SubmittedOrderView(
  orderNumber: '#BILL9',
  orderType: OrderType.dineIn,
  tableLabel: 'T3',
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  customerName: 'Dana',
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 5400,
      currencyCode: 'ILS',
      modifiers: ['Extra meat ×2'],
    ),
  ],
);

void _seedPrinter() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restoflow.printer.selected.pos.local': 'bluetooth',
    'restoflow.printer.bluetooth.pos.local': jsonEncode(<String, Object?>{
      'address': '66:32:1E:0A:BB:CD',
      'name': 'Counter',
    }),
  });
}

Future<ProviderContainer> _pumpOrders(
  WidgetTester tester, {
  required _RecordingConnector connector,
  bool seedPrinter = true,
}) async {
  if (seedPrinter) {
    _seedPrinter();
  } else {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  }
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('pos'),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(posRecentOrdersControllerProvider.notifier)
      .recordSubmitted(_unpaid);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: RecentOrdersSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder get _billButton => find.byKey(const Key('recent-print-bill-#BILL9'));

void main() {
  testWidgets('C. an UNPAID order offers Print bill alongside Collect payment',
      (tester) async {
    final connector = _RecordingConnector();
    await _pumpOrders(tester, connector: connector);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(_billButton, findsOneWidget);
    expect(find.text(l10n.posPrintBillAction), findsOneWidget);
    // It does NOT replace the existing payment action.
    expect(find.byKey(const Key('recent-pay-#BILL9')), findsOneWidget);
  });

  testWidgets('D. pressing Print bill sends ONE unpaid bill to the selected '
      'printer', (tester) async {
    final connector = _RecordingConnector();
    final container = await _pumpOrders(tester, connector: connector);

    await tester.tap(_billButton);
    await tester.pumpAndSettle();

    expect(connector.sent, hasLength(1), reason: 'exactly one send');
    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor('bill:${_unpaid.identity.key}');
    expect(job, isNotNull, reason: 'the bill job is visible');
    expect(job!.status, PrintJobStatus.sentToPrinter);

    // The document is the UNPAID bill, not a paid receipt.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final texts = [for (final l in job.document!.lines) l.left ?? ''];
    expect(texts, contains(l10n.receiptUnpaidBillLabel));
    expect(texts, isNot(contains(l10n.posPaidChip)));
  });

  testWidgets('F. a rapid DOUBLE TAP sends once; a later intentional press '
      'sends another copy', (tester) async {
    final connector = _RecordingConnector();
    await _pumpOrders(tester, connector: connector);

    // Two taps before the first print can settle.
    await tester.tap(_billButton);
    await tester.tap(_billButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(connector.sent, hasLength(1), reason: 'no double send');

    // A LATER deliberate press must still work — a bill is repeatable.
    await tester.tap(_billButton);
    await tester.pumpAndSettle();
    expect(
      connector.sent,
      hasLength(2),
      reason: 'manual bill printing is intentionally repeatable',
    );
  });

  testWidgets('H. printing a bill mutates NO order or payment state',
      (tester) async {
    final connector = _RecordingConnector();
    final container = await _pumpOrders(tester, connector: connector);

    final before = container.read(posRecentOrdersControllerProvider);
    final beforeSettlement = before.single.settlement;
    final beforeStatus = before.single.status;
    final beforePayment = container
        .read(paymentControllerProvider.notifier)
        .paymentFor(_unpaid.identity);

    await tester.tap(_billButton);
    await tester.pumpAndSettle();

    final after = container.read(posRecentOrdersControllerProvider);
    expect(after, hasLength(1));
    expect(after.single.settlement, beforeSettlement);
    expect(after.single.status, beforeStatus);
    expect(after.single.payment, isNull);
    expect(
      container.read(paymentControllerProvider.notifier).paymentFor(
        _unpaid.identity,
      ),
      beforePayment,
      reason: 'printing a bill never records a payment',
    );
  });

  testWidgets('G. with NO printer the order stays unpaid and the failure is '
      'visible', (tester) async {
    final connector = _RecordingConnector();
    final container = await _pumpOrders(
      tester,
      connector: connector,
      seedPrinter: false,
    );

    await tester.tap(_billButton);
    await tester.pumpAndSettle();

    expect(connector.sent, isEmpty);
    // The order is untouched...
    final orders = container.read(posRecentOrdersControllerProvider);
    expect(orders.single.payment, isNull);
    // ...and the job exists rather than being silently dropped.
    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor('bill:${_unpaid.identity.key}');
    expect(job, isNotNull);
    expect(job!.status, isNot(PrintJobStatus.sentToPrinter));
  });
}
