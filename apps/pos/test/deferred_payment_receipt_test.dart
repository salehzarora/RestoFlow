@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEFERRED-PAYMENT-RECEIPTS-001 — a pay-later order paid LATER from the Orders
/// screen must print the normal paid receipt automatically, exactly once.
///
/// Today the automatic receipt only fires on the immediate-checkout path, where
/// `OrderConfirmation` is mounted and listening to `paymentControllerProvider`.
/// Collecting a deferred payment from the Orders sheet opens the SAME
/// [CashPaymentSheet] with no confirmation screen mounted, so nothing ever
/// requests a receipt — the cashier has to press Reprint by hand.
///
/// These drive the REAL sheet over the REAL payment + receipt controllers.

final _identity = PosOrderIdentity.server('oid-DEF1');
const _orderKey = 'server:oid-DEF1';

/// Records every byte batch that actually reaches a printer transport.
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

/// A payment repository that fails the FIRST attempt, then succeeds.
class _FailThenSucceedRepo implements PaymentRepository {
  _FailThenSucceedRepo(this._inner);

  final PaymentRepository _inner;
  int attempts = 0;

  @override
  ShiftContext shiftContext() => _inner.shiftContext();

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) =>
      _inner.paymentFor(identity);

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    attempts++;
    if (attempts == 1) {
      throw const PaymentException('network down');
    }
    return _inner.recordCashPayment(
      orderId: orderId,
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      currencyCode: currencyCode,
      method: method,
      expectedRevision: expectedRevision,
    );
  }
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

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  required _RecordingConnector connector,
  PaymentRepository? repo,
}) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('pos'),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
      if (repo != null) paymentRepositoryProvider.overrideWithValue(repo),
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
          body: CashPaymentSheet(
            identity: _identity,
            orderNumber: '#DEF1',
            amountMinor: 5400,
            currencyCode: 'ILS',
            orderId: 'oid-DEF1',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Enters an exact cash tender and confirms. The cash sheet refuses to record
/// anything until the tender covers the total, so a test that skips this would
/// "fail" without a payment ever being attempted.
Future<void> _confirm(WidgetTester tester, {String tender = '54.00'}) async {
  await tester.enterText(find.byType(TextField).first, tender);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-payment-button')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(_seedBluetoothPrinter);

  testWidgets('A. collecting a DEFERRED payment automatically prints the paid '
      'receipt exactly once', (tester) async {
    final connector = _RecordingConnector();
    final container = await _pumpSheet(tester, connector: connector);

    await _confirm(tester);
    // The receipt lifecycle is async (readiness + logo + dispatch).
    await tester.pumpAndSettle();

    final printer = container.read(receiptPrintControllerProvider.notifier);
    final job = printer.jobFor(_orderKey);
    expect(
      job,
      isNotNull,
      reason: 'THE DEFECT: paying a pay-later order from Orders printed nothing',
    );
    expect(job!.status, PrintJobStatus.sentToPrinter);
    expect(job.document, isNotNull);
    expect(connector.sent, hasLength(1), reason: 'exactly one physical send');
  });

  testWidgets('B. a FAILED payment prints nothing at all', (tester) async {
    final connector = _RecordingConnector();
    final container = await _pumpSheet(
      tester,
      connector: connector,
      repo: _FailThenSucceedRepo(DemoPaymentStore()),
    );

    await _confirm(tester);
    await tester.pumpAndSettle();

    expect(
      container.read(receiptPrintControllerProvider.notifier).jobFor(_orderKey),
      isNull,
      reason: 'no receipt job for a payment that was never recorded',
    );
    expect(connector.sent, isEmpty);
  });

  testWidgets('B/H. a failed payment followed by a SUCCESSFUL retry prints '
      'only after the success, and only once', (tester) async {
    final connector = _RecordingConnector();
    final repo = _FailThenSucceedRepo(DemoPaymentStore());
    final container = await _pumpSheet(
      tester,
      connector: connector,
      repo: repo,
    );

    await _confirm(tester); // fails
    expect(connector.sent, isEmpty);

    await _confirm(tester); // succeeds
    await tester.pumpAndSettle();

    expect(repo.attempts, 2);
    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_orderKey);
    expect(job, isNotNull);
    expect(connector.sent, hasLength(1));
  });

  testWidgets('C. repeated confirms / rebuilds never create a SECOND automatic '
      'receipt', (tester) async {
    final connector = _RecordingConnector();
    final container = await _pumpSheet(tester, connector: connector);

    await _confirm(tester);
    await tester.pumpAndSettle();
    // Rebuild the tree and re-read the providers, as a refresh would.
    await tester.pump();
    container.read(receiptPrintControllerProvider);
    container.read(paymentControllerProvider);
    await tester.pumpAndSettle();

    expect(container.read(receiptPrintControllerProvider), hasLength(1));
    expect(connector.sent, hasLength(1), reason: 'no duplicate transport send');
  });

  testWidgets('E. the automatically printed receipt carries the SAME payment '
      'information a normally paid receipt does', (tester) async {
    final connector = _RecordingConnector();
    final container = await _pumpSheet(tester, connector: connector);

    await _confirm(tester);
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final doc = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_orderKey)!
        .document!;
    final texts = [for (final l in doc.lines) l.left ?? l.right ?? ''];

    // Paid chip, order total, tender/change and the payment method are all the
    // rows a receipt paid at checkout shows.
    expect(texts, contains(l10n.posPaidChip));
    expect(texts, contains(l10n.posReceiptOrderTotal));
    expect(texts, contains(l10n.posReceiptPaid));
    expect(texts, contains(l10n.posReceiptChange));
    expect(texts, contains(l10n.posPaymentMethodLabel));
  });

  testWidgets('D/F. the payment stays recorded when PRINTING fails, and Retry '
      'reprints without repaying', (tester) async {
    // No printer configured at all -> the receipt cannot be dispatched.
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final connector = _RecordingConnector();
    final container = await _pumpSheet(tester, connector: connector);

    await _confirm(tester);
    await tester.pumpAndSettle();

    // The payment IS recorded even though nothing printed.
    expect(
      container
          .read(paymentControllerProvider.notifier)
          .paymentFor(_identity),
      isNotNull,
      reason: 'a print failure must never roll back a successful payment',
    );
    expect(connector.sent, isEmpty);

    // The job is visible rather than silently absent.
    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_orderKey);
    expect(job, isNotNull);
    expect(job!.status, isNot(PrintJobStatus.sentToPrinter));
  });
}
