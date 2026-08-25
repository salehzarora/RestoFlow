import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/kitchen_dispatch_document.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketView;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromCartLines;
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;

/// KIOSK-PRINT-114B.5A — CROSS-PATH parity: the SAME accepted order printed
/// (a) by the POS direct path from its cart lines and (b) from the server's
/// dispatch payload through the canonical adapter (the POS printer-only drain
/// and the kiosk claimed print) is the SAME ticket, byte for byte — whole-order
/// counts on top (4 meat / 2 bun for the owner fixture), items, modifiers,
/// notes. A VOID dispatch keeps the legacy frame.
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

/// The owner fixture as the POS CART sees it: 2 × Classic Burger, the 240g size
/// option (2 meat per selection), and the item's menu-joined bun prep.
KdsTicketView _posDirectTicket() => kdsTicketViewFromCartLines(
  orderCode: '#ABC123',
  orderType: OrderType.takeaway,
  customerName: 'Saleh',
  orderNote: 'no sauce on the side',
  prepByItemId: const {
    'm-classic': [KitchenPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs')],
  },
  lines: const [
    CartLineView(
      lineId: 'l1',
      menuItemId: 'm-classic',
      name: 'Classic Burger',
      quantity: 2,
      unitPriceMinor: 4500,
      lineTotalMinor: 9000,
      currencyCode: 'ILS',
      note: 'well done',
      modifiers: [
        SelectedModifier(
          optionId: 'o-240',
          groupName: 'Size',
          optionName: '240g',
          priceDeltaMinor: 1000,
          quantity: 1,
          kitchenMeat: KitchenMeat(quantity: 2, unit: 'meat'),
        ),
      ],
    ),
  ],
);

/// The SAME order as the server's dispatch payload (`money_free_payload`):
/// line qty beside the PER-UNIT prep and the per-modifier-unit meat.
KitchenDispatchDocument _dispatch() => KitchenDispatchDocument.fromJson({
  'v': 1,
  'kind': 'initial_order',
  'order_code': '#ABC123',
  'order_type': 'takeaway',
  'customer_display_name': 'Saleh',
  'order_note': 'no sauce on the side',
  'created_at': '2026-08-25T10:00:00Z',
  'items': [
    {
      'qty': 2,
      'name': 'Classic Burger',
      'note': 'well done',
      'prep': [
        {'name': 'Bun', 'quantity': 1, 'unit': 'pcs'},
      ],
      'modifiers': [
        {
          'qty': 1,
          'name': '240g',
          'prep': {'quantity': 2, 'unit': 'meat'},
        },
      ],
    },
  ],
});

void main() {
  test('A5/A6. the dispatch adapter aggregates the SAME counts as the POS '
      'cart projection', () {
    final direct = _posDirectTicket();
    final adapted = kdsTicketViewFromKitchenDispatch(_dispatch());
    expect(adapted.kitchenCounts, direct.kitchenCounts);
    expect(adapted.kitchenCounts.map((c) => (c.label, c.quantity)), [
      ('meat', 4),
      ('Bun pcs', 2),
    ]);
  });

  test(
    'A6. POS direct bytes == canonical dispatch bytes (byte parity)',
    () async {
      final direct = await renderKitchenTicketBytes(
        ticket: _posDirectTicket(),
        labels: _labels(),
        restaurantName: 'Burger Maps',
      );
      final drain = await CanonicalKitchenDispatchRenderer(
        labels: _labels(),
        restaurantName: 'Burger Maps',
      ).renderToBytes(_dispatch());
      expect(drain, direct);
      final text = utf8.decode(drain, allowMalformed: true);
      expect(text, contains('Kitchen total: 4 meat'));
      expect(text, contains('Kitchen total: 2 Bun pcs'));
      // '×' / '•' are non-ASCII and leave the text encoder as codepage bytes;
      // assert on the ASCII parts of the lines.
      expect(text, contains('Classic Burger'));
      expect(text, contains('+ 240g'));
      // The count block precedes the first item line.
      expect(
        text.indexOf('Kitchen total: 4 meat'),
        lessThan(text.indexOf('Classic Burger')),
      );
    },
  );

  test('the legacy spool renderer is what used to print 2 meat / 1 bun — '
      'the canonical renderer replaces it on the drain', () async {
    final legacy = utf8.decode(
      await const KitchenTicketRenderer().renderToBytes(_dispatch()),
      allowMalformed: true,
    );
    expect(legacy, isNot(contains('Kitchen total')));
    expect(legacy, contains(' 2 meat'));
    expect(legacy, contains(' Bun 1 pcs'));
  });

  test('a VOID dispatch keeps the legacy void frame byte-for-byte', () async {
    final voidDoc = KitchenDispatchDocument(
      serverPayloadVersion: 1,
      kind: KitchenSpoolDispatchType.voidNotice,
      orderCode: '#ABC123',
      orderType: 'dine_in',
      reason: 'entry_error',
      voidMarker: true,
      affectedItemCount: 3,
    );
    final canonical = await CanonicalKitchenDispatchRenderer(
      labels: _labels(),
      voidRenderer: const KitchenTicketRenderer(),
    ).renderToBytes(voidDoc);
    final legacy = await const KitchenTicketRenderer().renderToBytes(voidDoc);
    expect(canonical, legacy);
    expect(utf8.decode(canonical, allowMalformed: true), contains('VOID'));
  });

  test('A7. the canonical drain/kiosk ticket is money-free', () async {
    final bytes = await CanonicalKitchenDispatchRenderer(
      labels: _labels(),
    ).renderToBytes(_dispatch());
    final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
    for (final token in [
      'subtotal',
      'grand total',
      'tax',
      'discount',
      '₪',
      '4500',
      '9000',
    ]) {
      expect(text.contains(token), isFalse, reason: 'no "$token"');
    }
    expect(RegExp(r'\d+\.\d{2}').hasMatch(text), isFalse);
  });
}
