@TestOn('vm')
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenCount, KitchenMeat, KitchenPrepComponent, OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show PrintLineKind, buildKdsTicketPrintDocument;
import 'package:restoflow_pos/src/print/kitchen_ticket_render.dart'
    show renderKitchenTicketBytes;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;

import 'support/pos_package_root.dart';

/// KITCHEN-PRINT-DUAL-001B — the POS direct kitchen print carries the SAME
/// operational detail as the KDS ticket, by building the SAME shared
/// [KdsTicketView] and rendering it through the SAME shared builder.
///
/// A DETAILED representative order: two items, qty>1, an owner-configured meat
/// count (Double => 2 قطع لحم) on a quantity modifier, a per-item bread prep
/// component, an addition (Ketchup ×2) + a removal ("no onion") modifier, and
/// both an item note and an order note. These inspect the ACTUAL semantic
/// document fields + the rendered bytes — never "a helper was called".

// Money tokens that must NEVER reach a kitchen ticket. 'KTotal' (the counts
// label used here) deliberately avoids the word "total" so the scan is exact.
const _moneyTokens = [
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
];

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

KdsTicketView _representativeTicket() => kdsTicketViewFromCartLines(
  orderCode: '#000042',
  orderType: OrderType.dineIn,
  tableLabel: '5',
  customerName: 'Dana',
  orderNote: 'call when ready',
  // The bread prep is a MENU snapshot (joined by menuItemId) — not on the cart.
  prepByItemId: const {
    'm1': [KitchenPrepComponent(name: 'خبز', quantity: 1)],
  },
  lines: const [
    CartLineView(
      lineId: 'l1',
      menuItemId: 'm1',
      name: 'Double Burger',
      quantity: 2,
      unitPriceMinor: 4500,
      lineTotalMinor: 9000,
      currencyCode: 'ILS',
      note: 'well done',
      modifiers: [
        // A Double => 2 قطع لحم per selection (owner meat count).
        SelectedModifier(
          optionId: 'o1',
          groupName: 'Size',
          optionName: 'Double',
          priceDeltaMinor: 1500,
          quantity: 1,
          kitchenMeat: KitchenMeat(quantity: 2, unit: 'قطع لحم'),
        ),
        // A quantity ADDITION (×2) + a REMOVAL, both money-free display.
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
      menuItemId: 'm2',
      name: 'Fries',
      quantity: 1,
      unitPriceMinor: 1000,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
    ),
  ],
);

void main() {
  group('A/E — the POS projection preserves detail + computes counts', () {
    test('items keep name/qty/modifiers(×N)/note/prep', () {
      final ticket = _representativeTicket();
      expect(ticket.items, hasLength(2));
      final burger = ticket.items.first;
      expect(burger.name, 'Double Burger');
      expect(burger.quantity, 2);
      // A qty-2 modifier folds in ×2; qty-1 modifiers stay bare.
      expect(burger.modifiers, ['Double', 'Ketchup ×2', 'no onion']);
      expect(burger.note, 'well done');
      expect(burger.prepComponents, [
        const KitchenPrepComponent(name: 'خبز', quantity: 1),
      ]);
      expect(ticket.items[1].name, 'Fries');
      expect(ticket.items[1].quantity, 1);
      // Order-level fields.
      expect(ticket.orderNumber, '#000042');
      expect(ticket.orderType, 'dine_in');
      expect(ticket.tableLabel, '5');
      expect(ticket.customerName, 'Dana');
      expect(ticket.notes, 'call when ready');
    });

    test('whole-order counts aggregate meat × modifier × item + prep × item', () {
      final ticket = _representativeTicket();
      // Double (2 قطع لحم) × 1 selection × 2 burgers = 4; bread 1 × 2 burgers = 2.
      expect(ticket.kitchenCounts, [
        const KitchenCount(quantity: 4, label: 'قطع لحم'),
        const KitchenCount(quantity: 2, label: 'خبز'),
      ]);
    });
  });

  group('B/D — the rendered document has full detail + is money-free', () {
    test('the shared document shows items, modifiers, counts, notes', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _representativeTicket(),
        labels: _labels(),
      );
      final texts = [for (final l in doc.lines) l.left ?? l.right ?? ''];
      expect(texts, contains('Dine-in'));
      expect(texts, contains('Table 5'));
      expect(texts, contains('Customer: Dana'));
      expect(texts, contains('KTotal 4 قطع لحم'));
      expect(texts, contains('KTotal 2 خبز'));
      expect(
        doc.lines.any(
          (l) =>
              l.kind == PrintLineKind.item &&
              l.left == 'Double Burger' &&
              l.right == '2×',
        ),
        isTrue,
      );
      expect(texts, contains('+ Ketchup ×2'));
      expect(texts, contains('+ no onion'));
      expect(texts, contains('» Note: well done'));
      expect(texts, contains('» Note: call when ready'));
    });

    test('the rendered bytes carry the items but no money token', () async {
      final bytes = await renderKitchenTicketBytes(
        ticket: _representativeTicket(),
        labels: _labels(),
      );
      expect(bytes, isNotEmpty);
      final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
      expect(text.contains('double burger'), isTrue);
      expect(text.contains('fries'), isTrue);
      for (final token in _moneyTokens) {
        expect(
          text.contains(token.toLowerCase()),
          isFalse,
          reason: 'no money token "$token" on a kitchen ticket',
        );
      }
    });
  });

  group('G — the auto-print toggle is ADDITIVE (source boundary)', () {
    test(
      'order submission never references the kitchen print or its toggle',
      () {
        final root = locatePosPackageRoot();
        final submissionSources = [
          File(
            p.join(root.path, 'lib', 'src', 'state', 'outbox_controller.dart'),
          ).readAsStringSync(),
          File(
            p.join(root.path, 'lib', 'src', 'data', 'order_submission.dart'),
          ).readAsStringSync(),
        ].join('\n');

        // The submission/KDS-dispatch path is fully decoupled from the toggle
        // and the kitchen printer, so flipping the toggle can NEVER alter what
        // is submitted or dispatched to the KDS — it is purely additive.
        for (final needle in [
          'posAutoPrintKitchenTicket',
          'runAutoKitchenTicketPrintOnSubmit',
          'PosKitchenTicketPrinter',
          'kdsTicketViewFromCartLines',
          'renderKitchenTicketBytes',
          'kitchen_ticket_render',
        ]) {
          expect(
            submissionSources.contains(needle),
            isFalse,
            reason: 'order submission must not reference "$needle"',
          );
        }
      },
    );
  });
}
