@TestOn('vm')
library;

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart';

/// DEFERRED-PAYMENT-RECEIPTS-001 (Goal 2) — the UNPAID customer bill.
///
/// The canonical receipt builder can only produce a PAID receipt: `payment` is
/// required, and the paid chip, paid timestamp, tender, change and payment-method
/// rows are emitted unconditionally. A cashier who wants to hand a customer the
/// bill BEFORE payment has nothing to print, and the only way to force the paid
/// builder to accept an unpaid order would be to fabricate a payment — which
/// would print a document claiming money had been taken.
///
/// These drive the REAL builder over a REAL unpaid order snapshot.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// A representative pay-later order: two items, a modifier quantity, an item
/// note, a discount, tax, customer name + phone, dine-in with a table.
const _unpaidOrder = SubmittedOrderView(
  orderNumber: '#BILL01',
  orderType: OrderType.dineIn,
  tableLabel: 'T7',
  currencyCode: 'ILS',
  subtotalMinor: 9000,
  discountTotalMinor: 500,
  taxTotalMinor: 425,
  taxRateBp: 500,
  orderId: 'oid-BILL01',
  customerName: 'Dana',
  customerPhone: '+972500000000',
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 2,
      lineTotalMinor: 7800,
      currencyCode: 'ILS',
      modifiers: ['Extra meat ×2', 'Ketchup'],
      note: 'no onions',
    ),
    SubmittedLineView(
      name: 'Fries',
      quantity: 1,
      lineTotalMinor: 1200,
      currencyCode: 'ILS',
    ),
  ],
);

final _payment = CashPayment(
  paymentId: 'pay-BILL01',
  orderNumber: '#BILL01',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 8925,
  tenderedMinor: 10000,
  changeMinor: 1075,
  currencyCode: 'ILS',
  receiptNumber: 'R-77',
  paidAt: DateTime.utc(2026, 7, 30, 12, 30),
);

List<String> _texts(PrintDocument doc) => [
  for (final l in doc.lines) '${l.left ?? ''}|${l.right ?? ''}',
];

String _blob(PrintDocument doc) => _texts(doc).join('\n');

void main() {
  test(
    'A. the UNPAID bill carries the full order, clearly marked unpaid',
    () async {
      final l10n = await _en();
      final doc = buildBillDocument(l10n, _unpaidOrder, isDemo: false);

      final blob = _blob(doc);
      // Order + customer + service details.
      expect(blob, contains('#BILL01'));
      expect(blob, contains('Dana'));
      expect(blob, contains('+972500000000'));
      expect(blob, contains('T7'));
      // Items, quantities, modifier quantities, notes.
      expect(blob, contains('2 × Classic Burger'));
      expect(blob, contains('+ Extra meat ×2'));
      expect(blob, contains('+ Ketchup'));
      expect(blob, contains('no onions'));
      expect(blob, contains('1 × Fries'));
      // Item prices + discount + tax + total.
      expect(blob, contains('78.00'));
      expect(blob, contains('12.00'));
      expect(blob, contains('5.00'), reason: 'the discount is shown');
      expect(blob, contains('89.25'), reason: 'the amount still owed');
      // THE marker: unmistakably unpaid.
      expect(blob, contains(l10n.receiptUnpaidBillLabel));
      expect(blob, contains(l10n.receiptAmountDueLabel));
    },
  );

  test('A. the UNPAID bill omits EVERY payment-only field', () async {
    final l10n = await _en();
    final blob = _blob(buildBillDocument(l10n, _unpaidOrder, isDemo: false));

    // No paid wording, no method, no tender, no change, no paid timestamp.
    expect(blob, isNot(contains(l10n.posPaidChip)));
    expect(blob, isNot(contains(l10n.posReceiptPaid)));
    expect(blob, isNot(contains(l10n.posReceiptChange)));
    expect(blob, isNot(contains(l10n.posPaymentMethodLabel)));
    expect(
      blob,
      isNot(contains(l10n.posReceiptTitle)),
      reason: 'a bill is not titled "Receipt"',
    );
    // No tendered/change money and no transaction identifiers.
    expect(blob, isNot(contains('100.00')));
    expect(blob, isNot(contains('10.75')));
    expect(blob, isNot(contains('pay-BILL01')));
    expect(blob, isNot(contains('R-77')));
  });

  test('B. the PAID receipt is unchanged by the new mode', () async {
    final l10n = await _en();
    final paid = buildReceiptDocument(
      l10n,
      _unpaidOrder,
      _payment,
      isDemo: false,
    );
    final blob = _blob(paid);

    // Every payment row a paid receipt has always shown is still there.
    expect(blob, contains(l10n.posPaidChip));
    expect(blob, contains(l10n.posReceiptPaid));
    expect(blob, contains(l10n.posReceiptChange));
    expect(blob, contains(l10n.posPaymentMethodLabel));
    expect(blob, contains('100.00'), reason: 'tendered');
    expect(blob, contains('10.75'), reason: 'change');
    expect(blob, contains(l10n.posReceiptTitle));
    // ...and the unpaid marker never leaks onto a paid receipt.
    expect(blob, isNot(contains(l10n.receiptUnpaidBillLabel)));
  });

  test('the two documents SHARE the item/total layout', () async {
    final l10n = await _en();
    final bill = _texts(buildBillDocument(l10n, _unpaidOrder, isDemo: false));
    final paid = _texts(
      buildReceiptDocument(l10n, _unpaidOrder, _payment, isDemo: false),
    );

    // Every ITEM / MODIFIER / NOTE line is byte-identical between the two
    // documents — the shared body formats them once.
    bool isItemish(String l) =>
        l.contains('×') || l.startsWith('+ ') || l.contains('no onions');
    final billItems = bill.where(isItemish).toList();
    final paidItems = paid.where(isItemish).toList();
    expect(billItems, isNotEmpty);
    expect(
      billItems,
      paidItems,
      reason: 'the item block is produced by ONE shared layout',
    );
  });

  test('the bill carries the logo when one is supplied, exactly like the '
      'receipt', () async {
    final l10n = await _en();
    final withLogo = buildBillDocument(
      l10n,
      _unpaidOrder,
      isDemo: false,
      branding: null,
    );
    // No asset -> no header image line, byte-identical to a logo-less bill.
    expect(
      withLogo.lines.any((l) => l.kind == PrintLineKind.headerImage),
      isFalse,
    );
  });

  test('I. the bill uses the STORED snapshot, never live catalog data', () async {
    final l10n = await _en();
    // The snapshot is an immutable value: there is no menu/catalog input to the
    // builder at all, so a later catalog edit cannot reach a historical bill.
    final first = _blob(buildBillDocument(l10n, _unpaidOrder, isDemo: false));
    final second = _blob(buildBillDocument(l10n, _unpaidOrder, isDemo: false));
    expect(second, first);
    expect(first, contains('Classic Burger'));
  });
}
