@TestOn('vm')
library;

import 'dart:convert' show utf8;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenCount, KitchenMeat, KitchenPrepComponent, OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show buildKdsTicketPrintDocument;
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/print/kitchen_ticket_render.dart'
    show renderKitchenTicketBytes;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// PRINT-STARTUP-REPRINT-001 (Defect 2) — REPRODUCTION.
///
/// The automatic initial kitchen print and the manual kitchen reprint use
/// divergent mapping paths:
///
///  * automatic  -> [kdsTicketViewFromCartLines] consumes STRUCTURED cart lines,
///    so it keeps modifier quantity + kitchen-meat + prep components and calls
///    `aggregateOrderKitchenCounts` (pos_kitchen_ticket_printer.dart:504);
///  * reprint    -> [kdsTicketViewFromSubmittedOrder] consumes the FLATTENED
///    confirmation snapshot, supplies no prep components and no kitchenCounts
///    at all (pos_kitchen_ticket_printer.dart:513-537).
///
/// The per-modifier "×N" text still shows, so the divergence is easy to miss —
/// but the canonical AGGREGATE kitchen-count section (the chef's extra-meat /
/// prep totals) is simply absent from a reprinted ticket.
///
/// These tests drive the REAL cart -> submit -> snapshot -> reprint path
/// (`CartController.addItemWithModifiers` + `submitOrder`), not a helper in
/// isolation, and compare the two documents that actually reach the printer.

// The representative order required by the phase spec: burger qty 1, extra meat
// qty 2, another modifier qty 2, one meal/group selection, one item note.
const _burger = DemoMenuItem(
  id: 'burger',
  name: 'Classic Burger',
  priceMinor: 4500,
  categoryId: 'burgers',
  categoryName: 'Burgers',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 1,
  // KITCHEN-PREP-001: the item's owner-configured per-unit prep snapshot.
  attributes: {
    'prep_components': [
      {'name': 'خبز', 'quantity': 1},
    ],
  },
);

const _fries = DemoMenuItem(
  id: 'fries',
  name: 'Fries',
  priceMinor: 1200,
  categoryId: 'sides',
  categoryName: 'Sides',
  categoryDisplayOrder: 2,
  itemDisplayOrder: 1,
);

const _modifiers = <SelectedModifier>[
  // EXTRA MEAT ×2 — one patty per selection, two selections => 2 patties.
  SelectedModifier(
    optionId: 'o-meat',
    groupName: 'Extras',
    optionName: 'Extra meat',
    priceDeltaMinor: 1500,
    quantity: 2,
    kitchenMeat: KitchenMeat(quantity: 1, unit: 'قطع لحم'),
  ),
  // ANOTHER modifier at quantity 2 (no meat contribution).
  SelectedModifier(
    optionId: 'o-ketchup',
    groupName: 'Extras',
    optionName: 'Ketchup',
    priceDeltaMinor: 0,
    quantity: 2,
  ),
  // A MEAL / GROUP selection.
  SelectedModifier(
    optionId: 'o-meal',
    groupName: 'Meal',
    optionName: 'Make it a meal',
    priceDeltaMinor: 900,
    quantity: 1,
  ),
];

const _note = 'no onions';

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
  // Deliberately avoids the word "total" so the money scan stays exact.
  kitchenTotal: (count, unit) => 'KCount $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
);

/// Money tokens that must NEVER reach a kitchen ticket (D-007).
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
  '4500',
  '1500',
  '1200',
  '900',
];

/// Drives the REAL cart: adds the burger (with modifiers + note) and the fries
/// in a SHUFFLED input order, captures the live cart lines the automatic print
/// would use, then submits to produce the confirmation snapshot the manual
/// reprint uses. Both come from one real submit.
({List<CartLineView> cartLines, SubmittedOrderView submitted}) _realSubmit() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final cart = container.read(cartControllerProvider.notifier);

  // Shuffled relative to the menu-configured order (fries added first) so the
  // canonical print ordering is genuinely exercised rather than accidental.
  cart.addItem(_fries);
  cart.addItemWithModifiers(_burger, _modifiers, note: _note);

  final cartLines = container.read(cartControllerProvider).lines;
  cart.submitOrder(orderType: OrderType.dineIn, tableLabel: 'T2');
  final submitted = container.read(cartControllerProvider).submittedOrder!;
  return (cartLines: cartLines, submitted: submitted);
}

/// The AUTOMATIC initial kitchen ticket, built the way the live path builds it.
KdsTicketView _autoTicket(List<CartLineView> lines, String orderCode) =>
    kdsTicketViewFromCartLines(
      orderCode: orderCode,
      orderType: OrderType.dineIn,
      tableLabel: 'T2',
      lines: lines,
      prepByItemId: {
        for (final item in [_burger, _fries])
          if (item.prepComponents.isNotEmpty) item.id: item.prepComponents,
      },
    );

/// The MANUAL kitchen reprint, built from the confirmation snapshot.
KdsTicketView _reprintTicket(SubmittedOrderView submitted) =>
    kdsTicketViewFromSubmittedOrder(submitted);

List<String> _lineTexts(dynamic doc) => [
  for (final l in doc.lines) l.left ?? l.right ?? '',
];

void main() {
  group('the reprint must carry the SAME operational content as the initial '
      'kitchen ticket', () {
    test('AGGREGATE kitchen counts match (extra meat + prep)', () {
      final r = _realSubmit();
      final auto = _autoTicket(r.cartLines, r.submitted.orderNumber);
      final reprint = _reprintTicket(r.submitted);

      // Extra meat: 1 patty × 2 selections × 1 burger = 2. Bread: 1 × 1 = 1.
      expect(
        auto.kitchenCounts,
        [
          const KitchenCount(quantity: 2, label: 'قطع لحم'),
          const KitchenCount(quantity: 1, label: 'خبز'),
        ],
        reason: 'the automatic ticket is the CORRECT reference',
      );

      // THE DEFECT: pre-fix the reprint carries no counts at all.
      expect(
        reprint.kitchenCounts,
        auto.kitchenCounts,
        reason:
            'the chef must see the same extra-meat/prep totals on a reprint',
      );
    });

    test('product quantity, modifier names + quantities, meal selection and '
        'item note all match', () {
      final r = _realSubmit();
      final auto = _autoTicket(r.cartLines, r.submitted.orderNumber);
      final reprint = _reprintTicket(r.submitted);

      expect(auto.items, hasLength(2));
      expect(reprint.items, hasLength(2));
      for (var i = 0; i < auto.items.length; i++) {
        expect(reprint.items[i].name, auto.items[i].name);
        expect(reprint.items[i].quantity, auto.items[i].quantity);
        expect(
          reprint.items[i].modifiers,
          auto.items[i].modifiers,
          reason: 'modifier names AND ×N quantities must match',
        );
        expect(reprint.items[i].note, auto.items[i].note);
        expect(
          reprint.items[i].prepComponents,
          auto.items[i].prepComponents,
          reason: 'preparation components must survive the reprint',
        );
      }

      // The concrete contract, spelled out so a regression is unambiguous.
      final burger = reprint.items.firstWhere(
        (i) => i.name == 'Classic Burger',
      );
      expect(burger.quantity, 1);
      expect(burger.modifiers, [
        'Extra meat ×2',
        'Ketchup ×2',
        'Make it a meal',
      ]);
      expect(burger.note, _note);
      expect(burger.prepComponents, [
        const KitchenPrepComponent(name: 'خبز', quantity: 1),
      ]);
    });

    test('menu print ORDERING matches despite shuffled input', () {
      final r = _realSubmit();
      final auto = _autoTicket(r.cartLines, r.submitted.orderNumber);
      final reprint = _reprintTicket(r.submitted);

      // Burgers (category 1) before Sides (category 2), though Fries was added
      // to the cart FIRST.
      expect([for (final i in auto.items) i.name], ['Classic Burger', 'Fries']);
      expect(
        [for (final i in reprint.items) i.name],
        [for (final i in auto.items) i.name],
      );
    });

    test('the RENDERED documents contain equivalent operational lines', () {
      final r = _realSubmit();
      final labels = _labels();
      final autoDoc = buildKdsTicketPrintDocument(
        ticket: _autoTicket(r.cartLines, r.submitted.orderNumber),
        labels: labels,
      );
      final reprintDoc = buildKdsTicketPrintDocument(
        ticket: _reprintTicket(r.submitted),
        labels: labels,
      );

      final autoTexts = _lineTexts(autoDoc);
      final reprintTexts = _lineTexts(reprintDoc);

      // The aggregate count section is the part that goes missing.
      expect(autoTexts, contains('KCount 2 قطع لحم'));
      expect(
        reprintTexts,
        contains('KCount 2 قطع لحم'),
        reason: 'THE DEFECT: the reprint omits the aggregate meat section',
      );
      expect(reprintTexts, contains('KCount 1 خبز'));

      // Item + modifier + note lines are equivalent.
      expect(reprintTexts, contains('+ Extra meat ×2'));
      expect(reprintTexts, contains('+ Ketchup ×2'));
      expect(reprintTexts, contains('+ Make it a meal'));
      expect(
        autoTexts.where((t) => t.startsWith('+ ')).toList(),
        reprintTexts.where((t) => t.startsWith('+ ')).toList(),
      );
    });

    test(
      'BYTE equivalence: the same canonical inputs render identical bytes',
      () async {
        final r = _realSubmit();
        final labels = _labels();
        final autoBytes = await renderKitchenTicketBytes(
          ticket: _autoTicket(r.cartLines, r.submitted.orderNumber),
          labels: labels,
        );
        final reprintBytes = await renderKitchenTicketBytes(
          ticket: _reprintTicket(r.submitted),
          labels: labels,
        );
        expect(
          reprintBytes,
          autoBytes,
          reason: 'same canonical content + same renderer => identical bytes',
        );
      },
    );

    test('the kitchen reprint stays MONEY-FREE', () {
      final r = _realSubmit();
      final doc = buildKdsTicketPrintDocument(
        ticket: _reprintTicket(r.submitted),
        labels: _labels(),
      );
      final blob = utf8.decode(utf8.encode(_lineTexts(doc).join('\n')));
      for (final token in _moneyTokens) {
        expect(
          blob.toLowerCase(),
          isNot(contains(token.toLowerCase())),
          reason: 'a kitchen ticket must never carry money (D-007): $token',
        );
      }
    });
  });
}
