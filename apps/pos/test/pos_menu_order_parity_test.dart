import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kit;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketMapper;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show
        kdsTicketViewFromCartLines,
        kdsTicketViewFromSubmittedOrder,
        kitchenTicketPrintLabelsFromL10n;
import 'package:restoflow_pos/src/print/print_document.dart' as pos;
import 'package:restoflow_pos/src/state/cart_controller.dart' show CartLineView;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// MENU-ORDER-001 — the required cross-surface DASHBOARD-ORDER parity test.
///
/// Dashboard configuration:
///   Categories: Meals(1), Sides(2), Drinks(3)
///   Items: Meals[Burger B(1), Burger A(2)], Sides[Fries(1)], Drinks[Fanta(1), Cola(2)]
/// The cart is filled in a DELIBERATELY different order:
///   Cola, Burger A, Fries, Fanta, Burger B
/// Every print surface MUST print the Dashboard-configured order:
///   Burger B, Burger A, Fries, Fanta, Cola
/// (NOT cart insertion order.)

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

CashPayment _payment() => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#100',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 5000,
  tenderedMinor: 5000,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.utc(2026, 7, 31, 12, 0),
);

/// (name, categoryDisplayOrder, itemDisplayOrder) — listed in CART (insertion)
/// order: Cola, Burger A, Fries, Fanta, Burger B.
const _cart = <(String, int, int)>[
  ('Cola', 3, 2),
  ('Burger A', 1, 2),
  ('Fries', 2, 1),
  ('Fanta', 3, 1),
  ('Burger B', 1, 1),
];

/// The 1-based cart position (== server line_position) for [name].
int _cartPos(String name) => _cart.indexWhere((c) => c.$1 == name) + 1;

const _expected = <String>[
  '1 × Burger B',
  '1 × Burger A',
  '1 × Fries',
  '1 × Fanta',
  '1 × Cola',
];

List<CartLineView> _cartLines() => [
  for (var i = 0; i < _cart.length; i++)
    CartLineView(
      lineId: 'l$i',
      menuItemId: 'm$i',
      name: _cart[i].$1,
      quantity: 1,
      unitPriceMinor: 1000,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
      categoryDisplayOrder: _cart[i].$2,
      itemDisplayOrder: _cart[i].$3,
    ),
];

SubmittedOrderView _submitted() => SubmittedOrderView(
  orderNumber: '#100',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 5000,
  lines: [
    for (var i = 0; i < _cart.length; i++)
      SubmittedLineView(
        name: _cart[i].$1,
        quantity: 1,
        lineTotalMinor: 1000,
        currencyCode: 'ILS',
        categoryDisplayOrder: _cart[i].$2,
        itemDisplayOrder: _cart[i].$3,
        linePosition: i + 1,
      ),
  ],
);

/// The AUTHORITATIVE server detail (pos_order_detail) — items delivered in a
/// SHUFFLED order, each carrying its immutable submit-time snapshots.
PosOrderDetail _detail() {
  final shuffled = <(String, int, int)>[
    _cart[2], // Fries
    _cart[4], // Burger B
    _cart[0], // Cola
    _cart[3], // Fanta
    _cart[1], // Burger A
  ];
  return PosOrderDetail(
    orderId: 'o1',
    orderCode: '#100',
    orderType: 'dine_in',
    status: 'served',
    revision: 1,
    currencyCode: 'ILS',
    subtotalMinor: 5000,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 5000,
    rounds: const [],
    items: [
      for (final c in shuffled)
        PosOrderDetailItem(
          name: c.$1,
          quantity: 1,
          unitPriceMinor: 1000,
          lineDiscountMinor: 0,
          lineTotalMinor: 1000,
          modifiers: const [],
          categoryDisplayOrder: c.$2,
          itemDisplayOrder: c.$3,
          linePosition: _cartPos(c.$1),
        ),
    ],
  );
}

List<String> _receiptItems(pos.PrintDocument doc) => [
  for (final l in doc.lines)
    if (l.kind == pos.PrintLineKind.item) l.left ?? '',
];

List<String> _kitchenItems(kit.PrintDocument doc) => [
  for (final l in doc.lines)
    if (l.kind == kit.PrintLineKind.item) l.left ?? '',
];

void main() {
  group('MENU-ORDER-001 — Dashboard-order parity across every print surface', () {
    test('the customer receipt, POS auto + manual kitchen, and POS server-backed '
        'reprint all print the Dashboard order for a mixed cart', () async {
      final l10n = await _l10n();
      final labels = kitchenTicketPrintLabelsFromL10n(l10n);

      // 1) Customer receipt (client cart).
      final receipt = buildReceiptDocument(
        l10n,
        _submitted(),
        _payment(),
        isDemo: false,
      );
      expect(_receiptItems(receipt), _expected);

      // 2) POS AUTOMATIC kitchen ticket (from the live cart lines).
      final auto = kit.buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromCartLines(
          orderCode: '#100',
          orderType: OrderType.dineIn,
          lines: _cartLines(),
        ),
        labels: labels,
      );
      expect(_kitchenItems(auto), _expected);

      // 3) POS MANUAL kitchen ticket (from the submitted-order view).
      final manual = kit.buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromSubmittedOrder(_submitted()),
        labels: labels,
      );
      expect(_kitchenItems(manual), _expected);

      // 4) POS SERVER-BACKED reprint (pos_order_detail -> the combined view),
      //    delivered SHUFFLED but carrying the immutable submit-time snapshots.
      final reprint = buildReceiptDocument(
        l10n,
        submittedOrderViewFromDetail(_detail()),
        _payment(),
        isDemo: false,
      );
      expect(_receiptItems(reprint), _expected);
    });

    test(
      'the KDS ticket + reprint (mapped from a SHUFFLED sync_pull wire that '
      'carries the category/item snapshots) print the SAME Dashboard order',
      () async {
        final l10n = await _l10n();
        final labels = kitchenTicketPrintLabelsFromL10n(l10n);

        final shuffled = <(String, int, int)>[
          _cart[0], // Cola
          _cart[4], // Burger B
          _cart[2], // Fries
          _cart[1], // Burger A
          _cart[3], // Fanta
        ];
        final tickets = KdsTicketMapper.map(
          orders: const [
            {
              'id': 'o1',
              'status': 'submitted',
              'order_type': 'dine_in',
              'created_at': '2026-07-31T10:00:00Z',
            },
          ],
          orderItems: [
            for (final c in shuffled)
              {
                'id': 'i-${c.$1}',
                'order_id': 'o1',
                'quantity': 1,
                'menu_item_name_snapshot': c.$1,
                'category_display_order_snapshot': c.$2,
                'item_display_order_snapshot': c.$3,
                'line_position': _cartPos(c.$1),
              },
          ],
          modifiers: const [],
        );
        // The KDS reprint reuses the same mapped ticket, so proving the mapped
        // ticket's order proves both surfaces.
        final kdsDoc = kit.buildKdsTicketPrintDocument(
          ticket: tickets.single,
          labels: labels,
        );
        expect(_kitchenItems(kdsDoc), _expected);
      },
    );
  });
}
