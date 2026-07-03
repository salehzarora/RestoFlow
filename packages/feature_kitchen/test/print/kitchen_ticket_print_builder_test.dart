import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// RF-072 — the money-free kitchen-ticket document builder.
///
/// Golden = a STABLE document representation (line kind + alignment + emphasis +
/// text), not raw ESC/POS bytes, so the assertions stay readable while still
/// pinning the exact layout. A second pass renders the document through the
/// real RF-070 ESC/POS adapter and scans the bytes to prove no money leaks.
void main() {
  // A fixed instant so timestamps are deterministic in goldens.
  final at = DateTime.utc(2026, 6, 23, 12, 0, 0);

  group('kitchen ticket document (golden)', () {
    test(
      'exact line structure: header, ref, service, time, items, mods, cut',
      () {
        final order = _order(
          orderType: OrderType.dineIn,
          items: [
            _Line(
              lineId: 'a',
              menuItemId: 'burger',
              name: 'Burger',
              qty: 2,
              modifiers: [_mod('Extra Cheese')],
              note: 'no salt',
            ),
            _Line(lineId: 'b', menuItemId: 'fries', name: 'Fries', qty: 1),
          ],
        );
        final ticket = _ticketFor(order, 'grill');

        final doc = KitchenTicketPrintBuilder.build(
          ticket,
          order,
          at: at,
          destination: const PrintDestination(
            destinationId: 'p-grill',
            profile: PrinterProfile.escPos80mm,
            label: 'Grill Station',
          ),
        );

        expect(doc.lines.map(_repr).toList(), <String>[
          'T[center,bold] "Grill Station"',
          'T[left,normal] "Order: o1"',
          'T[left,normal] "Dine-in"',
          'T[left,normal] "2026-06-23T12:00:00.000Z"',
          'FEED 1',
          'T[left,normal] "Burger x2"',
          'T[left,normal] "  + Extra Cheese"',
          // The item note follows its modifiers (product-rescue sprint) and is
          // ABSENT for the note-less Fries line below.
          'T[left,normal] "  * no salt"',
          'T[left,normal] "Fries x1"',
          'FEED 2',
          'CUT',
        ]);
      },
    );

    test('falls back to the station id when the destination has no label', () {
      final order = _order(
        items: [_Line(lineId: 'a', menuItemId: 'burger', name: 'Burger')],
      );
      final ticket = _ticketFor(order, 'grill');

      final doc = KitchenTicketPrintBuilder.build(
        ticket,
        order,
        at: at,
        destination: const PrintDestination(
          destinationId: 'p-grill',
          profile: PrinterProfile.escPos80mm,
        ),
      );

      final header = doc.lines.whereType<PrintTextLine>().first;
      expect(header.text, 'grill');
      expect(header.alignment, PrintAlignment.center);
      expect(header.emphasis, TextEmphasis.bold);
    });

    test('takeaway prints the takeaway service type', () {
      final order = _order(
        orderType: OrderType.takeaway,
        items: [_Line(lineId: 'a', menuItemId: 'burger', name: 'Burger')],
      );
      final doc = KitchenTicketPrintBuilder.build(
        _ticketFor(order, 'grill'),
        order,
        at: at,
      );
      expect(_texts(doc), contains('Takeaway'));
      expect(_texts(doc), isNot(contains('Dine-in')));
    });
  });

  group('modifiers (option names only, no price)', () {
    test('multiple modifiers render indented; qty>1 shows a multiplier', () {
      final order = _order(
        items: [
          _Line(
            lineId: 'a',
            menuItemId: 'coffee',
            name: 'Coffee',
            qty: 1,
            modifiers: [_mod('Oat Milk'), _mod('Extra Shot', quantity: 2)],
          ),
        ],
      );
      final doc = KitchenTicketPrintBuilder.build(
        _ticketFor(order, 'bar'),
        order,
        at: at,
      );
      expect(
        _texts(doc),
        containsAllInOrder(<String>[
          'Coffee x1',
          '  + Oat Milk',
          '  + Extra Shot x2',
        ]),
      );
    });
  });

  group('item notes (kitchen data, no money)', () {
    test('a note prints as an indented "  * " line after the modifiers; '
        'note-less items emit no note line', () {
      final order = _order(
        items: [
          _Line(
            lineId: 'a',
            menuItemId: 'shawarma',
            name: 'Shawarma',
            qty: 1,
            modifiers: [_mod('Extra Tahini', quantity: 2)],
            // Tenant DATA may be Arabic — carried verbatim (not chrome).
            note: 'بدون بصل',
          ),
          _Line(lineId: 'b', menuItemId: 'fries', name: 'Fries', qty: 1),
        ],
      );
      final doc = KitchenTicketPrintBuilder.build(
        _ticketFor(order, 'grill'),
        order,
        at: at,
      );
      expect(
        _texts(doc),
        containsAllInOrder(<String>[
          'Shawarma x1',
          '  + Extra Tahini x2',
          '  * بدون بصل',
          'Fries x1',
        ]),
      );
      // Exactly one note line — the note-less item contributes none.
      expect(_texts(doc).where((t) => t.startsWith('  * ')).length, 1);
    });
  });

  group('only this station\'s items appear (no cross-station bleed)', () {
    test('the grill ticket omits bar items and vice versa', () {
      final order = _order(
        items: [
          _Line(lineId: 'a', menuItemId: 'burger', name: 'Burger'),
          _Line(lineId: 'b', menuItemId: 'beer', name: 'Beer'),
        ],
      );
      final result = KitchenRouter.route(
        order,
        KitchenRoutingRules(itemStation: {'burger': 'grill', 'beer': 'bar'}),
      );
      final grill = result.tickets.firstWhere((t) => t.stationId == 'grill');
      final bar = result.tickets.firstWhere((t) => t.stationId == 'bar');

      final grillDoc = KitchenTicketPrintBuilder.build(grill, order, at: at);
      final barDoc = KitchenTicketPrintBuilder.build(bar, order, at: at);

      expect(_texts(grillDoc), contains('Burger x1'));
      expect(_texts(grillDoc).where((t) => t.contains('Beer')), isEmpty);
      expect(_texts(barDoc), contains('Beer x1'));
      expect(_texts(barDoc).where((t) => t.contains('Burger')), isEmpty);
    });
  });

  group('no money ever reaches the kitchen ticket (D-007/D-008)', () {
    test('document text + rendered ESC/POS bytes contain no money', () {
      // Plant DISTINCTIVE money values that cannot collide with qty/timestamp.
      final order = _order(
        items: [
          _Line(
            lineId: 'a',
            menuItemId: 'burger',
            name: 'Burger',
            qty: 2,
            basePriceMinor: 4242,
            modifiers: [_mod('Extra Cheese', priceDeltaMinor: 8181)],
          ),
        ],
      );
      final doc = KitchenTicketPrintBuilder.build(
        _ticketFor(order, 'grill'),
        order,
        at: at,
      );

      // (a) Document model carries no money values or money words.
      final docText = _texts(doc).join('\n');
      for (final needle in <String>['4242', '8181']) {
        expect(docText, isNot(contains(needle)), reason: 'money value leaked');
      }
      for (final word in <String>[
        'total',
        'price',
        'minor',
        'payment',
        'cash',
        'tax',
        'subtotal',
        r'$',
        '₪',
      ]) {
        expect(
          docText.toLowerCase(),
          isNot(contains(word.toLowerCase())),
          reason: 'money word "$word" leaked',
        );
      }

      // (b) The real ESC/POS render leaks no money either.
      final bytes = const EscPosPrintAdapter().encode(
        doc,
        PrinterProfile.escPos80mm,
      );
      final rendered = String.fromCharCodes(bytes);
      expect(rendered, isNot(contains('4242')));
      expect(rendered, isNot(contains('8181')));
    });
  });
}

// ---------------------------------------------------------------------------
// Test fixtures (mirror packages/domain/test/kitchen_router_test.dart).
// ---------------------------------------------------------------------------

class _Line {
  _Line({
    required this.lineId,
    required this.menuItemId,
    required this.name,
    this.qty = 1,
    this.basePriceMinor = 1000,
    this.modifiers = const [],
    this.note,
  });

  final String lineId;
  final String menuItemId;
  final String name;
  final int qty;
  final int basePriceMinor;
  final List<ModifierOptionSnapshot> modifiers;
  final String? note;
}

ModifierOptionSnapshot _mod(
  String name, {
  int quantity = 1,
  int priceDeltaMinor = 0,
}) => ModifierOptionSnapshot(
  modifierId: 'm-$name',
  modifierNameSnapshot: name,
  optionId: 'o-$name',
  optionNameSnapshot: name,
  priceDeltaMinorSnapshot: priceDeltaMinor,
  quantity: quantity,
);

LocalOrder _order({
  String orderId = 'o1',
  OrderType orderType = OrderType.dineIn,
  String? branch = 'branch-1',
  required List<_Line> items,
}) {
  final cart = Cart(
    orderId: orderId,
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: branch,
    currencyCode: 'ILS',
  );
  for (final it in items) {
    cart.addLine(
      CartLine.snapshot(
        lineId: it.lineId,
        menuItemId: it.menuItemId,
        itemNameSnapshot: it.name,
        basePriceMinorSnapshot: it.basePriceMinor,
        currencyCodeSnapshot: 'ILS',
        quantity: it.qty,
        modifiers: it.modifiers,
        note: it.note,
      ),
    );
  }
  return LocalOrder.submitFromCart(cart, orderType: orderType);
}

/// Route [order] sending every item to [stationId], then return that ticket.
KitchenTicket _ticketFor(LocalOrder order, String stationId) {
  final result = KitchenRouter.route(
    order,
    KitchenRoutingRules(defaultStationId: stationId),
  );
  return result.tickets.firstWhere((t) => t.stationId == stationId);
}

List<String> _texts(PrintDocument doc) =>
    doc.lines.whereType<PrintTextLine>().map((l) => l.text).toList();

String _repr(PrintLine line) {
  if (line is PrintTextLine) {
    return 'T[${line.alignment.name},${line.emphasis.name}] "${line.text}"';
  }
  if (line is PrintFeedLine) return 'FEED ${line.lines}';
  if (line is PrintCutLine) return 'CUT';
  return 'OTHER';
}
