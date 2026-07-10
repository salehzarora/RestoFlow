import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/print/order_preview_builders.dart';
import 'package:restoflow_dashboard/src/print/print_document.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDERS-HISTORY-001 — the reprint-center builders use STORED order values
/// (never recompute money), and the kitchen ticket is MONEY-FREE.
Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

OrderDetail _order({String? customer}) => OrderDetail(
  orderId: 'o1',
  orderCode: '#1001AA',
  status: 'completed',
  orderType: 'dine_in',
  currencyCode: 'ILS',
  subtotalMinor: 8400,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 8400,
  createdAtLabel: '12:40',
  customerName: customer,
  tableLabel: 'T3',
  branchName: 'Downtown',
  staffName: 'Amira',
  items: const [
    OrderDetailItem(
      name: 'Double Burger',
      quantity: 2,
      unitPriceMinor: 3200,
      lineTotalMinor: 6400,
      notes: 'No pickles',
      modifiers: [
        OrderDetailModifier(
          optionName: 'Double patty',
          quantity: 1,
          meatQuantity: 2,
          meatUnit: 'patties',
        ),
      ],
      prepComponents: [
        OrderPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
      ],
    ),
    OrderDetailItem(
      name: 'Fries',
      quantity: 2,
      unitPriceMinor: 1000,
      lineTotalMinor: 2000,
    ),
  ],
  payments: const [
    OrderPayment(
      method: 'cash',
      status: 'completed',
      amountMinor: 8400,
      tenderedMinor: 8400,
      changeMinor: 0,
      receiptNumber: 'R-1001',
    ),
  ],
);

void main() {
  test('aggregateKitchenCounts uses the KDS rule (qty × mod × item)', () {
    // 2 patties × 1 modifier × 2 burgers = 4.
    final counts = aggregateKitchenCounts(_order());
    expect(counts.length, 1);
    expect(counts.single.unit, 'patties');
    expect(counts.single.quantity, 4);
  });

  test(
    'receipt preview uses the STORED total (never recomputed) + customer',
    () async {
      final l10n = await _l10n('en');
      final doc = buildOrderReceiptPreview(l10n, _order(customer: 'Layla'));
      final html = documentToHtml(doc);
      // Stored grand total ₪84.00 is present; customer name shown.
      expect(html.contains('₪84.00'), isTrue);
      expect(html.contains('Layla'), isTrue);
      // POS-ORDERS-AND-PAYMENT-001: the customer receipt no longer prints the
      // internal receipt number or the cashier/staff name.
      expect(html.contains('R-1001'), isFalse);
      expect(html.contains('Amira'), isFalse);
    },
  );

  test('receipt preview omits the customer row when absent', () async {
    final l10n = await _l10n('en');
    final doc = buildOrderReceiptPreview(l10n, _order());
    final html = documentToHtml(doc);
    expect(html.contains('Layla'), isFalse);
    // Still shows the total (money) — it is a receipt.
    expect(html.contains('₪84.00'), isTrue);
  });

  test(
    'kitchen ticket preview is MONEY-FREE and carries the kitchen count',
    () async {
      final l10n = await _l10n('en');
      final doc = buildOrderKitchenTicketPreview(
        l10n,
        _order(customer: 'Layla'),
      );
      final html = documentToHtml(doc);
      // NO money anywhere (no ₪, no minor token, no price).
      expect(html.contains('₪'), isFalse);
      expect(html.toLowerCase().contains('minor'), isFalse);
      expect(html.contains('84.00'), isFalse);
      // Carries the order code, items, customer, and the aggregated kitchen count.
      expect(html.contains('#1001AA'), isTrue);
      expect(html.contains('Double Burger'), isTrue);
      expect(html.contains('Layla'), isTrue);
      expect(html.contains(l10n.kdsMeatTotalLabel('4', 'patties')), isTrue);
    },
  );

  test('Arabic kitchen ticket preview stays money-free', () async {
    final l10n = await _l10n('ar');
    final doc = buildOrderKitchenTicketPreview(l10n, _order());
    final html = documentToHtml(doc);
    expect(html.contains('₪'), isFalse);
    expect(html.toLowerCase().contains('minor'), isFalse);
    expect(html.contains(l10n.kdsMeatTotalLabel('4', 'patties')), isTrue);
  });

  test(
    'an unpaid order receipt shows the Unpaid marker, no payment line',
    () async {
      final l10n = await _l10n('en');
      final unpaid = OrderDetail(
        orderId: 'o2',
        orderCode: '#1002BB',
        status: 'preparing',
        orderType: 'takeaway',
        currencyCode: 'ILS',
        subtotalMinor: 3600,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: 3600,
        items: const [
          OrderDetailItem(name: 'Wrap', quantity: 1, lineTotalMinor: 3600),
        ],
      );
      final html = documentToHtml(buildOrderReceiptPreview(l10n, unpaid));
      expect(html.contains(l10n.dashboardUnpaid), isTrue);
      expect(html.contains('₪36.00'), isTrue);
    },
  );

  // ---- MONEY-VOID-001: a voided/cancelled order's preview is banner-stamped ----

  OrderDetail voided() => OrderDetail(
    orderId: 'oV',
    orderCode: '#1003CC',
    status: 'voided',
    orderType: 'takeaway',
    currencyCode: 'ILS',
    subtotalMinor: 3600,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 3600,
    items: const [
      OrderDetailItem(name: 'Wrap', quantity: 1, lineTotalMinor: 3600),
    ],
  );

  test('a voided order receipt preview is stamped CANCELLED', () async {
    final l10n = await _l10n('en');
    final html = documentToHtml(buildOrderReceiptPreview(l10n, voided()));
    expect(html.contains(l10n.ordersReprintCancelledBanner), isTrue);
  });

  test(
    'a voided order kitchen preview is stamped CANCELLED and stays money-free',
    () async {
      final l10n = await _l10n('en');
      final html = documentToHtml(
        buildOrderKitchenTicketPreview(l10n, voided()),
      );
      expect(html.contains(l10n.ordersReprintCancelledBanner), isTrue);
      expect(html.contains('₪'), isFalse);
      expect(html.contains('36.00'), isFalse);
    },
  );

  test('a normal (completed) order preview is NOT banner-stamped', () async {
    final l10n = await _l10n('en');
    final html = documentToHtml(buildOrderReceiptPreview(l10n, _order()));
    expect(html.contains(l10n.ordersReprintCancelledBanner), isFalse);
  });
}
