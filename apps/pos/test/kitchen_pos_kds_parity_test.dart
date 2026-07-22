@TestOn('vm')
library;

import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        KitchenCount,
        KitchenMeat,
        KitchenPrepComponent,
        OrderType,
        displayOrderCode;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        KitchenTicketPrintLabels,
        PrintDocument,
        buildKdsTicketPrintDocument,
        kitchenTicketToEscPosDocument;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketMapper, KdsTicketView;
import 'package:restoflow_pos/src/print/kitchen_ticket_render.dart'
    show renderKitchenTicketBytes;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromCartLines;
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-PRINT-DUAL-001B — REAL POS↔KDS parity from ONE submitted order.
///
/// One raw order is fed through BOTH real mapping paths — the KDS
/// [KdsTicketMapper.map] (from sync_pull rows) and the POS
/// [kdsTicketViewFromCartLines] (from the immutable cart snapshot) — and the two
/// [KdsTicketView]s are rendered through the SAME shared builder. The resulting
/// semantic documents + deterministic ESC/POS output must be IDENTICAL: if
/// either mapper dropped or changed a kitchen-relevant detail, the render would
/// diverge. Only surface-specific differences (station identity, transport-only
/// ids that never render) are normalized. Money-free.

const _orderId = 'order-parity-0001';

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket preview',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'KTotal $count $unit',
);

/// The SAME representative order expressed as KDS sync_pull rows.
KdsTicketView _kdsTicket() {
  final tickets = KdsTicketMapper.map(
    orders: [
      {
        'id': _orderId,
        'status': 'submitted',
        'order_type': 'dine_in',
        'table_id': 't1',
        'customer_name': 'Dana',
        'notes': 'call when ready',
        'created_at': '2026-07-22T10:00:00Z',
      },
    ],
    tables: [
      {'id': 't1', 'label': '5'},
    ],
    orderItems: [
      {
        'id': 'i1',
        'order_id': _orderId,
        'quantity': 2,
        'menu_item_name_snapshot': 'Double Burger',
        'notes': 'well done',
        // Station deliberately UNASSIGNED — the POS whole-order ticket is not
        // station-routed, so both suppress the station line (normalized).
        'prep_snapshot': [
          {'name': 'خبز', 'quantity': 1},
        ],
      },
      {
        'id': 'i2',
        'order_id': _orderId,
        'quantity': 1,
        'menu_item_name_snapshot': 'Fries',
      },
    ],
    modifiers: [
      {
        'order_item_id': 'i1',
        'option_name_snapshot': 'Double',
        'quantity': 1,
        'meat_snapshot': {'quantity': 2, 'unit': 'قطع لحم'},
      },
      {'order_item_id': 'i1', 'option_name_snapshot': 'Ketchup', 'quantity': 2},
      {
        'order_item_id': 'i1',
        'option_name_snapshot': 'no onion',
        'quantity': 1,
      },
    ],
  );
  return tickets.single;
}

/// The SAME representative order expressed as the POS immutable cart snapshot.
KdsTicketView _posTicket() => kdsTicketViewFromCartLines(
  orderCode: displayOrderCode(_orderId),
  orderType: OrderType.dineIn,
  tableLabel: '5',
  customerName: 'Dana',
  orderNote: 'call when ready',
  prepByItemId: const {
    'i1': [KitchenPrepComponent(name: 'خبز', quantity: 1)],
  },
  lines: const [
    CartLineView(
      lineId: 'l1',
      menuItemId: 'i1',
      name: 'Double Burger',
      quantity: 2,
      unitPriceMinor: 4500,
      lineTotalMinor: 9000,
      currencyCode: 'ILS',
      note: 'well done',
      modifiers: [
        SelectedModifier(
          optionId: 'o1',
          groupName: 'Size',
          optionName: 'Double',
          priceDeltaMinor: 1500,
          quantity: 1,
          kitchenMeat: KitchenMeat(quantity: 2, unit: 'قطع لحم'),
        ),
        SelectedModifier(
          optionId: 'o2',
          groupName: 'Extras',
          optionName: 'Ketchup',
          priceDeltaMinor: 0,
          quantity: 2,
        ),
        SelectedModifier(
          optionId: 'o3',
          groupName: 'Extras',
          optionName: 'no onion',
          priceDeltaMinor: 0,
          quantity: 1,
        ),
      ],
    ),
    CartLineView(
      lineId: 'l2',
      menuItemId: 'i2',
      name: 'Fries',
      quantity: 1,
      unitPriceMinor: 1000,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
    ),
  ],
);

List<String> _docStrings(PrintDocument doc) => [
  for (final l in doc.lines)
    '${l.kind.name}|${l.left ?? ''}|${l.right ?? ''}|${l.emphasised}',
];

void main() {
  test('the two mappers agree on every kitchen-relevant detail', () {
    final kds = _kdsTicket();
    final pos = _posTicket();

    // Item detail parity (names / quantities / modifiers-with-xN / notes / prep).
    expect(kds.items.length, pos.items.length);
    for (var i = 0; i < kds.items.length; i++) {
      expect(pos.items[i].name, kds.items[i].name, reason: 'item $i name');
      expect(
        pos.items[i].quantity,
        kds.items[i].quantity,
        reason: 'item $i qty',
      );
      expect(
        pos.items[i].modifiers,
        kds.items[i].modifiers,
        reason: 'item $i modifiers (additions/removals/xN)',
      );
      expect(pos.items[i].note, kds.items[i].note, reason: 'item $i note');
      expect(
        pos.items[i].prepComponents,
        kds.items[i].prepComponents,
        reason: 'item $i prep',
      );
    }
    // Whole-order counts (meat modifier×item + bread×item), order ref, context.
    expect(pos.kitchenCounts, kds.kitchenCounts);
    expect(pos.kitchenCounts, [
      const KitchenCount(quantity: 4, label: 'قطع لحم'), // 2×1×2
      const KitchenCount(quantity: 2, label: 'خبز'), // 1×2
    ]);
    expect(pos.orderNumber, kds.orderNumber, reason: 'order reference');
    expect(pos.orderType, kds.orderType);
    expect(pos.tableLabel, kds.tableLabel);
    expect(pos.customerName, kds.customerName);
    expect(pos.notes, kds.notes);
  });

  test(
    'the SHARED builder renders BYTE-IDENTICAL documents from both paths',
    () {
      final labels = _labels();
      final kdsDoc = buildKdsTicketPrintDocument(
        ticket: _kdsTicket(),
        labels: labels,
      );
      final posDoc = buildKdsTicketPrintDocument(
        ticket: _posTicket(),
        labels: labels,
      );

      // Semantic PrintDocument content is identical, line for line.
      expect(posDoc.title, kdsDoc.title);
      expect(_docStrings(posDoc), _docStrings(kdsDoc));

      // Deterministic ESC/POS encoding (pre-raster text) is identical too.
      final kdsEsc = kitchenTicketToEscPosDocument(
        kdsDoc,
      ).lines.whereType<pp.PrintTextLine>().map((l) => l.text).toList();
      final posEsc = kitchenTicketToEscPosDocument(
        posDoc,
      ).lines.whereType<pp.PrintTextLine>().map((l) => l.text).toList();
      expect(posEsc, kdsEsc);

      // The rendered detail is actually present (not a vacuous empty match).
      final joined = _docStrings(posDoc).join('\n');
      expect(joined, contains('Double Burger'));
      expect(joined, contains('2×'));
      expect(joined, contains('+ Ketchup ×2'));
      expect(joined, contains('+ no onion'));
      expect(joined, contains('» Note: well done'));
      expect(joined, contains('» Note: call when ready'));
      expect(joined, contains('KTotal 4 قطع لحم'));
      expect(joined, contains('KTotal 2 خبز'));
      expect(joined, contains('Table 5'));
      expect(joined, contains('Customer: Dana'));
      expect(joined, contains('Dine-in'));
    },
  );

  test('both rendered outputs remain money-free', () async {
    final labels = _labels();
    for (final ticket in [_kdsTicket(), _posTicket()]) {
      final bytes = await renderKitchenTicketBytes(
        ticket: ticket,
        labels: labels,
      );
      final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
      for (final token in [
        'subtotal',
        'discount',
        'payment',
        'tender',
        'price',
        '₪',
        r'$',
        '€',
        '45.00',
        '90.00',
        '4500',
        '9000',
        '1500',
      ]) {
        expect(text.contains(token.toLowerCase()), isFalse, reason: token);
      }
    }
  });
}
