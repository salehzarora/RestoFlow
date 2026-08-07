@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Locale;
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
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/pos_receipt_logo.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEFERRED-PAYMENT-RECEIPTS-001 (Goal 2) — the "Print bill" PRINT PATH.
///
/// Drives the EXACT chain the Orders-screen action runs — the repeatable
/// document request on the real [ReceiptPrintController], the real readiness
/// resolver, the real async bridge resolution and the real
/// [buildBillDocument] — over real prefs and a recording Bluetooth connector.
///
/// SCOPE NOTE. This suite drives the print CHAIN, not the Orders-sheet widget.
///
/// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass C] THE WIDGET-LEVEL ASSERTION
/// THIS NOTE RECORDED AS OUTSTANDING IS NOW CLOSED, in two places and on two
/// different fixtures:
///
///   * `print_bill_eligibility_test.dart` — the real [RecentOrdersSheet] over a
///     realistic server-snapshot row: the button renders beside Collect payment,
///     disappears when the order becomes paid or cancelled, and its label comes
///     from the ARB in ar as well as en;
///   * `pos_offline_prebill_test.dart` — the same sheet for a QUEUED OFFLINE
///     order, where Collect payment is correctly withheld (Pass B) and the
///     pre-bill must still be offered.
///
/// The gate itself also changed: the action is emitted inside
/// `if (actions.canPrintBill)`, its OWN policy field, no longer `canPay`.

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

String get _billKey => 'bill:${_unpaid.identity.key}';

void _seedPrinter({bool configured = true}) {
  SharedPreferences.setMockInitialValues(
    configured
        ? <String, Object>{
            'restoflow.printer.selected.pos.local': 'bluetooth',
            'restoflow.printer.bluetooth.pos.local': jsonEncode(
              <String, Object?>{
                'address': '66:32:1E:0A:BB:CD',
                'name': 'Counter',
              },
            ),
          }
        : const <String, Object>{},
  );
}

ProviderContainer _container(_RecordingConnector connector) {
  final c = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('pos'),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
    ],
  );
  addTearDown(c.dispose);
  c.read(posRecentOrdersControllerProvider.notifier).recordSubmitted(_unpaid);
  return c;
}

/// EXACTLY what the Orders action's handler does.
Future<void> _printBill(ProviderContainer c, AppLocalizations l10n) => c
    .read(receiptPrintControllerProvider.notifier)
    .requestRepeatableDocument(
      orderKey: _billKey,
      resolveReadiness: c.read(posReceiptReadinessResolverProvider),
      awaitLogoReady: () =>
          c.read(posReceiptLogoAssetProvider.notifier).firstResolution,
      buildDocument: () => buildBillDocument(l10n, _unpaid, isDemo: false),
      resolveBridge: () async =>
          (await c.read(posActivePrintBridgeReadyProvider.future))?.submit,
    );

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  setUp(() => _seedPrinter());

  test('D. one Print bill request sends ONE unpaid bill to the selected '
      'printer', () async {
    final connector = _RecordingConnector();
    final c = _container(connector);
    final l10n = await _en();

    await _printBill(c, l10n);

    expect(connector.sent, hasLength(1), reason: 'exactly one send');
    final job = c
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_billKey);
    expect(job, isNotNull, reason: 'the bill job is visible');
    expect(job!.status, PrintJobStatus.sentToPrinter);

    // The document is the UNPAID bill, never a paid receipt.
    final texts = [for (final l in job.document!.lines) l.left ?? ''];
    expect(texts, contains(l10n.receiptUnpaidBillLabel));
    expect(texts, isNot(contains(l10n.posPaidChip)));
    expect(texts, isNot(contains(l10n.posPaymentMethodLabel)));
  });

  test('F. concurrent requests send ONCE; a later intentional request sends '
      'another copy', () async {
    final connector = _RecordingConnector();
    final c = _container(connector);
    final l10n = await _en();

    // Two presses before the first can settle (the double-tap case).
    await Future.wait([_printBill(c, l10n), _printBill(c, l10n)]);
    expect(connector.sent, hasLength(1), reason: 'no double send');

    // A LATER deliberate press must still print — a bill is repeatable, unlike
    // the once-per-order paid receipt.
    await _printBill(c, l10n);
    expect(
      connector.sent,
      hasLength(2),
      reason: 'manual bill printing is intentionally repeatable',
    );
  });

  test('the paid receipt key is NOT consumed by a bill, so a later paid '
      'receipt is still possible', () async {
    final connector = _RecordingConnector();
    final c = _container(connector);
    await _printBill(c, await _en());

    final printer = c.read(receiptPrintControllerProvider.notifier);
    expect(printer.jobFor(_billKey), isNotNull);
    expect(
      printer.jobFor(_unpaid.identity.key),
      isNull,
      reason: 'the bill uses its OWN key; the paid receipt slot stays free',
    );
  });

  test('H. printing a bill mutates NO order or payment state', () async {
    final connector = _RecordingConnector();
    final c = _container(connector);
    final before = c.read(posRecentOrdersControllerProvider);
    final beforeSettlement = before.single.settlement;
    final beforeStatus = before.single.status;

    await _printBill(c, await _en());

    final after = c.read(posRecentOrdersControllerProvider);
    expect(after, hasLength(1));
    expect(after.single.settlement, beforeSettlement);
    expect(after.single.status, beforeStatus);
    expect(after.single.payment, isNull);
    expect(
      c.read(paymentControllerProvider.notifier).paymentFor(_unpaid.identity),
      isNull,
      reason: 'printing a bill never records a payment',
    );
  });

  test('G. with NO printer configured the order stays unpaid and the job is '
      'visible rather than dropped', () async {
    _seedPrinter(configured: false);
    final connector = _RecordingConnector();
    final c = _container(connector);

    await _printBill(c, await _en());

    expect(connector.sent, isEmpty);
    expect(c.read(posRecentOrdersControllerProvider).single.payment, isNull);
    final job = c
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_billKey);
    expect(job, isNotNull);
    expect(job!.status, isNot(PrintJobStatus.sentToPrinter));
  });

  test('E. a COLD start still prints the first bill once, with the bridge '
      'resolved after readiness', () async {
    final connector = _RecordingConnector();
    // A brand-new container over the persisted profile: nothing is warm.
    final c = _container(connector);

    await _printBill(c, await _en());

    expect(
      connector.sent,
      hasLength(1),
      reason: 'the first bill is not lost to an unresolved bridge',
    );
    expect(
      c.read(receiptPrintControllerProvider.notifier).jobFor(_billKey)!.status,
      PrintJobStatus.sentToPrinter,
    );
  });
}
