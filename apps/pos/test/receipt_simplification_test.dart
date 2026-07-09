import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// POS-ORDERS-AND-PAYMENT-001 (A): the customer receipt is simplified — a single
/// "Order total" + "Paid" + "Change" in the common cash case, no internal receipt
/// number, no cashier/staff name, and the subtotal/discount/tax breakout only
/// when a discount or tax is present.
Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

CashPayment _cash({
  int amount = 12900,
  int tendered = 20000,
  int change = 7100,
}) => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#ABC',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: amount,
  tenderedMinor: tendered,
  changeMinor: change,
  currencyCode: 'ILS',
  receiptNumber: 'R-INTERNAL-9',
  paidAt: DateTime.utc(2026, 7, 9, 14, 30),
);

SubmittedOrderView _order({
  int subtotal = 12900,
  int discount = 0,
  int tax = 0,
  int taxRateBp = 0,
}) => SubmittedOrderView(
  orderNumber: '#ABC123',
  orderType: OrderType.dineIn,
  tableLabel: 'T3',
  currencyCode: 'ILS',
  subtotalMinor: subtotal,
  discountTotalMinor: discount,
  taxTotalMinor: tax,
  taxRateBp: taxRateBp,
  lines: const [
    SubmittedLineView(
      name: 'Burger',
      quantity: 2,
      lineTotalMinor: 12900,
      currencyCode: 'ILS',
    ),
  ],
);

Map<String, String?> _kv(PrintDocument doc) => <String, String?>{
  for (final l in doc.lines)
    if (l.kind == PrintLineKind.keyValue) l.left ?? '': l.right,
};

void main() {
  test('the common cash receipt shows only Order total + Paid + Change '
      '(no subtotal duplication)', () async {
    final l10n = await _l10n('en');
    final doc = buildReceiptDocument(l10n, _order(), _cash(), isDemo: false);
    final kv = _kv(doc);
    expect(kv[l10n.posReceiptOrderTotal], '₪129.00');
    expect(kv[l10n.posReceiptPaid], '₪200.00');
    expect(kv[l10n.posReceiptChange], '₪71.00');
    // No subtotal line when subtotal == total (no discount/tax).
    expect(kv.containsKey(l10n.posCartSubtotal), isFalse);
  });

  test('the customer receipt never shows the internal receipt number '
      'or a cashier/staff name', () async {
    final l10n = await _l10n('en');
    final doc = buildReceiptDocument(l10n, _order(), _cash(), isDemo: false);
    final all = doc.lines
        .map((l) => '${l.left ?? ''} ${l.right ?? ''}')
        .join('\n');
    expect(all.contains('R-INTERNAL-9'), isFalse);
    expect(all.contains(l10n.posReceiptNumberLabel), isFalse);
    // No "Paid at" / cashier line — no staff identity is even available.
    expect(all.toLowerCase().contains('cashier'), isFalse);
  });

  test('a discount + tax order STILL shows the honest breakout above the '
      'order total', () async {
    final l10n = await _l10n('en');
    // subtotal 10000, discount 500, tax 1700 -> grand 11200.
    final doc = buildReceiptDocument(
      l10n,
      _order(subtotal: 10000, discount: 500, tax: 1700, taxRateBp: 1700),
      _cash(amount: 11200, tendered: 12000, change: 800),
      isDemo: false,
    );
    final kv = _kv(doc);
    expect(kv[l10n.posCartSubtotal], '₪100.00');
    expect(kv[l10n.posDiscountLabel], isNotNull); // discount row present
    expect(kv[l10n.posReceiptOrderTotal], '₪112.00'); // final total
    expect(kv[l10n.posReceiptPaid], '₪120.00');
    expect(kv[l10n.posReceiptChange], '₪8.00');
  });

  test(
    'a non-cash tender shows the order total but no Paid/Change rows',
    () async {
      final l10n = await _l10n('en');
      final card = _cash().copyMethod(PaymentMethod.card);
      final doc = buildReceiptDocument(l10n, _order(), card, isDemo: false);
      final kv = _kv(doc);
      expect(kv[l10n.posReceiptOrderTotal], '₪129.00');
      expect(kv.containsKey(l10n.posReceiptPaid), isFalse);
      expect(kv.containsKey(l10n.posReceiptChange), isFalse);
    },
  );
}

extension on CashPayment {
  CashPayment copyMethod(PaymentMethod m) => CashPayment(
    paymentId: paymentId,
    orderNumber: orderNumber,
    deviceId: deviceId,
    localOperationId: localOperationId,
    method: m,
    status: status,
    amountMinor: amountMinor,
    tenderedMinor: tenderedMinor,
    changeMinor: changeMinor,
    currencyCode: currencyCode,
    receiptNumber: receiptNumber,
    paidAt: paidAt,
  );
}
