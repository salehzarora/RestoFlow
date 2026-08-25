import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/kitchen_dispatch_document.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        CanonicalKitchenDispatchRenderer,
        KitchenTicketPrintLabels,
        buildKdsTicketPrintDocument,
        formatKitchenTicketTimestamp,
        kdsTicketViewFromKitchenDispatch,
        kitchenServiceModeBadge,
        renderKitchenTicketBytes;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketView;
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromCartLines, kdsTicketViewFromSubmittedOrder;
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;

/// KIOSK-PRINT-114B.6 — THREE-PATH header/ordering parity.
///
/// The SAME accepted order — 2 × Classic Burger 240g with add-ons in a
/// deliberate NON-alphabetical order (240g, cheese, lettuce, tomato, onion) —
/// rendered from (1) the POS direct cart path, (2) the kiosk/drain dispatch
/// payload through the canonical adapter and (3) the POS manual reprint from
/// `pos_order_detail` must be the ONE canonical ticket: identical sub-line
/// order, the same creation timestamp (order creation, never print time), the
/// same large service-mode badge, the same counts (4 meat / 2 bun), money-free,
/// byte-identical.
KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket',
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
  restaurantNameFallback: 'RestoFlow',
);

const _names = ['240g', 'cheese', 'lettuce', 'tomato', 'onion'];
final _createdAtUtc = DateTime.utc(2026, 8, 25, 11, 7, 0);
final _createdAtLocal = _createdAtUtc.toLocal();

KdsTicketView _direct({String orderType = 'takeaway'}) =>
    kdsTicketViewFromCartLines(
      orderCode: '#ABC123',
      orderType: orderType == 'dine_in' ? OrderType.dineIn : OrderType.takeaway,
      tableLabel: orderType == 'dine_in' ? '7' : null,
      customerName: 'Saleh',
      createdAt: _createdAtLocal,
      prepByItemId: const {
        'm-classic': [
          KitchenPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
        ],
      },
      lines: [
        CartLineView(
          lineId: 'l1',
          menuItemId: 'm-classic',
          name: 'Classic Burger',
          quantity: 2,
          unitPriceMinor: 4500,
          lineTotalMinor: 9000,
          currencyCode: 'ILS',
          modifiers: [
            for (final n in _names)
              SelectedModifier(
                optionId: 'o-$n',
                groupName: n == '240g' ? 'Size' : 'Extras',
                optionName: n,
                priceDeltaMinor: 0,
                quantity: 1,
                kitchenMeat: n == '240g'
                    ? const KitchenMeat(quantity: 2, unit: 'meat')
                    : null,
              ),
          ],
        ),
      ],
    );

KitchenDispatchDocument _dispatch({String orderType = 'takeaway'}) =>
    KitchenDispatchDocument.fromJson({
      'v': 1,
      'kind': 'initial_order',
      'order_code': '#ABC123',
      'order_type': orderType,
      if (orderType == 'dine_in') 'table_label': '7',
      'customer_display_name': 'Saleh',
      'created_at': _createdAtUtc.toIso8601String(),
      'items': [
        {
          'qty': 2,
          'name': 'Classic Burger',
          'prep': [
            {'name': 'Bun', 'quantity': 1, 'unit': 'pcs'},
          ],
          'modifiers': [
            for (final n in _names)
              {
                'qty': 1,
                'name': n,
                if (n == '240g') 'prep': {'quantity': 2, 'unit': 'meat'},
              },
          ],
        },
      ],
    });

PosOrderDetail _detail({String orderType = 'takeaway'}) => PosOrderDetail(
  orderId: 'order-1',
  orderCode: '#ABC123',
  orderType: orderType,
  status: 'served',
  revision: 3,
  currencyCode: 'ILS',
  subtotalMinor: 9000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 9000,
  tableLabel: orderType == 'dine_in' ? '7' : null,
  customerName: 'Saleh',
  createdAt: _createdAtUtc,
  items: [
    PosOrderDetailItem.fromJson({
      'menu_item_name_snapshot': 'Classic Burger',
      'quantity': 2,
      'unit_price_minor_snapshot': 4500,
      'line_discount_minor': 0,
      'line_total_minor': 9000,
      'line_position': 1,
      'prep_snapshot': [
        {'name': 'Bun', 'quantity': 1, 'unit': 'pcs'},
      ],
      'modifiers': [
        for (final n in _names)
          {
            'option_name_snapshot': n,
            'price_minor_snapshot': 0,
            'quantity': 1,
            if (n == '240g') 'meat_snapshot': {'quantity': 2, 'unit': 'meat'},
          },
      ],
    })!,
  ],
  rounds: const [],
);

List<String> _texts(KdsTicketView t) => [
  for (final l in buildKdsTicketPrintDocument(
    ticket: t,
    labels: _labels(),
  ).lines)
    l.left ?? l.right ?? '',
];

List<String> _subs(KdsTicketView t) =>
    _texts(t).where((x) => x.startsWith('+ ')).toList();

void main() {
  test('A. ORDERING — identical non-alphabetical sub-line order on all three '
      'paths', () {
    final direct = _direct();
    final adapted = kdsTicketViewFromKitchenDispatch(_dispatch());
    final detail = kdsTicketViewFromSubmittedOrder(
      submittedOrderViewFromDetail(_detail()),
    );
    const expected = ['+ 240g', '+ cheese', '+ lettuce', '+ tomato', '+ onion'];
    expect(_subs(direct), expected);
    expect(_subs(adapted), expected);
    expect(_subs(detail), expected);
  });

  test('B. TIMESTAMP — all three paths print the ORDER CREATION time', () {
    final stamp = formatKitchenTicketTimestamp(_createdAtLocal);
    for (final t in [
      _direct(),
      kdsTicketViewFromKitchenDispatch(_dispatch()),
      kdsTicketViewFromSubmittedOrder(submittedOrderViewFromDetail(_detail())),
    ]) {
      expect(t.submittedAt, _createdAtLocal);
      final texts = _texts(t);
      expect(texts, contains(stamp));
      expect(
        texts.indexOf(stamp),
        lessThan(texts.indexWhere((x) => x.startsWith('Kitchen total'))),
      );
    }
  });

  test('C. BADGE — takeaway and dine-in markers on all three paths, directly '
      'under the order code', () {
    for (final mode in ['takeaway', 'dine_in']) {
      final badge = kitchenServiceModeBadge(_labels(), mode)!;
      for (final t in [
        _direct(orderType: mode),
        kdsTicketViewFromKitchenDispatch(_dispatch(orderType: mode)),
        kdsTicketViewFromSubmittedOrder(
          submittedOrderViewFromDetail(_detail(orderType: mode)),
        ),
      ]) {
        final texts = _texts(t);
        expect(texts.indexOf(badge), texts.indexOf('#ABC123') + 1);
      }
    }
  });

  test('D. NON-REGRESSION — counts 4 meat / 2 bun, money-free, and BYTE parity '
      'across the three paths', () async {
    final views = [
      _direct(),
      kdsTicketViewFromKitchenDispatch(_dispatch()),
      kdsTicketViewFromSubmittedOrder(submittedOrderViewFromDetail(_detail())),
    ];
    final bytes = [
      for (final v in views)
        await renderKitchenTicketBytes(ticket: v, labels: _labels()),
    ];
    expect(bytes[1], bytes[0]);
    expect(bytes[2], bytes[0]);
    // The kiosk lane's own renderer agrees too.
    final lane = await CanonicalKitchenDispatchRenderer(
      labels: _labels(),
    ).renderToBytes(_dispatch());
    expect(lane, bytes[0]);
    final text = utf8.decode(bytes[0], allowMalformed: true);
    expect(text, contains('Kitchen total: 4 meat'));
    expect(text, contains('Kitchen total: 2 Bun pcs'));
    expect(text, contains(formatKitchenTicketTimestamp(_createdAtLocal)));
    expect(text, contains(kitchenServiceModeBadge(_labels(), 'takeaway')!));
    final lower = text.toLowerCase();
    for (final token in ['subtotal', 'grand total', '4500', '9000', '₪']) {
      expect(lower.contains(token), isFalse, reason: 'no "$token"');
    }
    expect(RegExp(r'\d+\.\d{2}').hasMatch(lower), isFalse);
  });
}
