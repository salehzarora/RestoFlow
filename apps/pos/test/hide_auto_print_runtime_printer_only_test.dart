@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart' show CartLineView;
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// HIDE-REDUNDANT-AUTO-PRINT-SETTINGS-014 — the RUNTIME half.
///
/// Hiding the two switches must not disable printing. These drive the two REAL
/// decision points that put ink on paper, with the stored preference explicitly
/// OFF, and prove that `printer_only` prints exactly once anyway while `kds`
/// keeps its existing behaviour byte-for-byte. The stored preference is never
/// written by either path.

final DateTime _verifiedAt = DateTime.utc(2026, 8, 1, 9);
final _printerOnly = KitchenModePrinterOnlyWithRevision(
  revision: 4,
  verifiedAt: _verifiedAt,
);
final _kds = KitchenModeVerifiedKds(verifiedAt: _verifiedAt, revision: 4);

/// Stored preference explicitly OFF.
class _OffReceipt extends PosAutoPrintReceiptController {
  @override
  Future<bool?> build() async => false;
}

class _OffKitchen extends PosAutoPrintKitchenTicketController {
  @override
  Future<bool?> build() async => false;
}

class _FakeTransport implements pp.PrintTransport {
  final List<Uint8List> sent = [];

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

class _Assignments implements DevicePrinterAssignmentsReader {
  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 8, 1, 12, 30),
      deviceLabel: 'Front POS',
      deviceType: 'pos',
      restaurantName: 'Maps Burger',
      branchName: 'Kafr Manda',
      printers: const [
        AssignedPrinter(
          id: 'prn-1',
          displayName: 'Counter receipt',
          role: 'receipt',
          connectionType: 'network',
          paperWidth: '80mm',
          isEnabled: true,
        ),
      ],
    ),
  );
}

const _paidOrder = SubmittedOrderView(
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
    ),
  ],
);

KdsTicketView _ticket() => kdsTicketViewFromCartLines(
  orderCode: '#000042',
  orderType: OrderType.dineIn,
  tableLabel: 'T1',
  lines: const [
    CartLineView(
      lineId: 'l1',
      menuItemId: 'm1',
      name: 'Falafel',
      quantity: 2,
      unitPriceMinor: 1500,
      lineTotalMinor: 3000,
      currencyCode: 'ILS',
    ),
  ],
  prepByItemId: const {},
);

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket preview',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'Kitchen total: $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
);

Future<ProviderContainer> _pumpConfirmation(
  WidgetTester tester,
  KitchenModeResult mode,
) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      posPrinterAssignmentsReaderProvider.overrideWithValue(_Assignments()),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
      posAutoPrintReceiptProvider.overrideWith(_OffReceipt.new),
      posVerifiedKitchenModeProvider.overrideWithValue(mode),
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
          body: OrderConfirmation(order: _paidOrder, onNewOrder: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await container.read(posPrinterAssignmentsProvider.future);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _pay(WidgetTester tester, ProviderContainer container) async {
  await container
      .read(paymentControllerProvider.notifier)
      .payCash(
        identity: _paidOrder.identity,
        orderId: 'order-1',
        orderNumber: _paidOrder.orderNumber,
        amountMinor: _paidOrder.subtotalMinor,
        tenderedMinor: 6000,
        currencyCode: 'ILS',
      );
  await tester.pumpAndSettle();
}

Future<PosKitchenPrintOutcome> _runKitchen(
  KitchenModeResult mode,
  _FakeTransport fake,
) async {
  SharedPreferences.setMockInitialValues(const {});
  final c = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      posAutoPrintKitchenTicketProvider.overrideWith(_OffKitchen.new),
      posVerifiedKitchenModeProvider.overrideWithValue(mode),
    ],
  );
  addTearDown(c.dispose);
  return runAutoKitchenTicketPrintOnSubmit(
    container: c,
    orderId: 'order-1',
    ticket: _ticket(),
    labels: _labels(),
    printer: PosKitchenTicketPrinter(
      c,
      targetOverride: ResolvedKitchenPrinter(
        destinationKey: 'k',
        transportFactory: () => fake,
      ),
    ),
  );
}

void main() {
  testWidgets('3. RECEIPT RUNTIME: stored preference OFF + printer_only -> a '
      'completed payment still prepares exactly ONE receipt', (tester) async {
    final container = await _pumpConfirmation(tester, _printerOnly);
    expect(container.read(receiptPrintControllerProvider), isEmpty);

    await _pay(tester, container);

    expect(
      container.read(receiptPrintControllerProvider),
      hasLength(1),
      reason: 'printer_only forces the receipt despite the stored OFF',
    );
    expect(
      container
          .read(receiptPrintControllerProvider.notifier)
          .jobFor(_paidOrder.identity.key),
      isNotNull,
    );
    // The stored preference was never rewritten.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('restoflow.autoprint.pos.receiptOnPaid.dev-1'),
      isNull,
    );
  });

  testWidgets('3b. RECEIPT RUNTIME under kds: the stored OFF still suppresses '
      'the receipt — unchanged behaviour', (tester) async {
    final container = await _pumpConfirmation(tester, _kds);
    await _pay(tester, container);
    expect(
      container.read(receiptPrintControllerProvider),
      isEmpty,
      reason: 'kds keeps honouring the cashier preference',
    );
  });

  test('4. KITCHEN RUNTIME: stored preference OFF + printer_only -> exactly '
      'ONE ticket prints', () async {
    final fake = _FakeTransport();
    final outcome = await _runKitchen(_printerOnly, fake);
    expect(outcome, PosKitchenPrintOutcome.printed);
    expect(fake.sent, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('restoflow.autoprint.pos.kitchenTicket.dev-1'),
      isNull,
      reason: 'the stored OFF is preserved, never overwritten',
    );
  });

  test(
    '4b. KITCHEN RUNTIME under kds: the stored OFF keeps the flow inert',
    () async {
      final fake = _FakeTransport();
      final outcome = await _runKitchen(_kds, fake);
      expect(outcome, PosKitchenPrintOutcome.noPrinterConfigured);
      expect(fake.sent, isEmpty, reason: 'unchanged kds behaviour');
    },
  );

  test('4c. an UNRESOLVED mode never forces the kitchen print', () async {
    final fake = _FakeTransport();
    SharedPreferences.setMockInitialValues(const {});
    final c = ProviderContainer(
      overrides: [
        posNativePrintingAvailableProvider.overrideWithValue(true),
        posAutoPrintKitchenTicketProvider.overrideWith(_OffKitchen.new),
        posVerifiedKitchenModeProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    final outcome = await runAutoKitchenTicketPrintOnSubmit(
      container: c,
      orderId: 'order-1',
      ticket: _ticket(),
      labels: _labels(),
      printer: PosKitchenTicketPrinter(
        c,
        targetOverride: ResolvedKitchenPrinter(
          destinationKey: 'k',
          transportFactory: () => fake,
        ),
      ),
    );
    expect(outcome, PosKitchenPrintOutcome.noPrinterConfigured);
    expect(fake.sent, isEmpty, reason: 'fail-safe: never assume printer_only');
  });
}
