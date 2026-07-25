import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketMapper, KdsTicketView;
import 'package:test/test.dart';

/// PRINT-LAYOUT-001D — the KDS mapper orders items to match the cashier receipt.
///
/// The KDS builds its ticket from `order_items` rows delivered by `sync_pull`
/// `ORDER BY (updated_at, id)` — effectively random for a freshly submitted
/// order. Each row now carries `order_items.line_position` (the stable per-order
/// cart ordinal), and `KdsTicketMapper` sorts a ticket's items by it, so the
/// printed KDS sequence (and every KDS reprint, which reuses the same ticket)
/// matches the cashier receipt (cart order) — regardless of wire order. Legacy
/// rows (no `line_position` -> 0) fall back to their wire order.

/// One item's wire fixture: (name, line_position, modifier?, note?).
typedef _Wire = (String, int, String?, String?);

List<Map<String, dynamic>> _rows(List<_Wire> wire) => [
  for (final w in wire)
    {
      'id': 'i-${w.$1}',
      'order_id': 'o1',
      'quantity': 1,
      'menu_item_name_snapshot': w.$1,
      'line_position': w.$2,
      if (w.$4 != null) 'notes': w.$4,
    },
];

List<Map<String, dynamic>> _mods(List<_Wire> wire) => [
  for (final w in wire)
    if (w.$3 != null)
      {'order_item_id': 'i-${w.$1}', 'option_name_snapshot': w.$3},
];

KdsTicketView _ticket(List<_Wire> wire) {
  final tickets = KdsTicketMapper.map(
    orders: const [
      {
        'id': 'o1',
        'status': 'submitted',
        'order_type': 'dine_in',
        'created_at': '2026-07-24T10:00:00Z',
      },
    ],
    orderItems: _rows(wire),
    modifiers: _mods(wire),
  );
  expect(tickets, hasLength(1));
  return tickets.single;
}

void main() {
  group('KdsTicketMapper item order (PRINT-LAYOUT-001D)', () {
    test('sorts items by line_position into cart order — restoring the cashier '
        'receipt sequence from a SHUFFLED wire order', () {
      // The wire delivers them shuffled (as sync_pull (updated_at, id) does),
      // but each row carries its cart line_position.
      final t = _ticket(const [
        ('Cola', 2, null, null),
        ('Side A', 4, 'extra sauce', null),
        ('Burger A', 1, 'no onion', 'A note'),
        ('Fanta', 5, null, null),
        ('Burger B', 3, null, 'B note'),
      ]);
      expect(
        [for (final it in t.items) it.name],
        const ['Burger A', 'Cola', 'Burger B', 'Side A', 'Fanta'],
      );
    });

    test(
      'keeps each item BLOCK (modifiers + note) attached to the correct item '
      'after the sort',
      () {
        final t = _ticket(const [
          ('Cola', 2, null, null),
          ('Burger A', 1, 'no onion', 'A note'),
          ('Burger B', 3, null, 'B note'),
        ]);
        final burgerA = t.items.firstWhere((it) => it.name == 'Burger A');
        expect(burgerA.modifiers, const ['no onion']);
        expect(burgerA.note, 'A note');
        final burgerB = t.items.firstWhere((it) => it.name == 'Burger B');
        expect(burgerB.modifiers, isEmpty);
        expect(burgerB.note, 'B note');
      },
    );

    test('legacy rows without a line_position (all 0) keep their wire order — '
        'backward-compatible fallback (a partially-migrated order never '
        'scrambles)', () {
      final t = _ticket(const [
        ('Cola', 0, null, null),
        ('Burger A', 0, null, null),
        ('Fanta', 0, null, null),
      ]);
      expect(
        [for (final it in t.items) it.name],
        const ['Cola', 'Burger A', 'Fanta'],
      );
    });

    test(
      'every item appears exactly once (no loss / no duplication) regardless '
      'of wire order',
      () {
        final t = _ticket(const [
          ('Cola', 2, null, null),
          ('Side A', 4, null, null),
          ('Burger A', 1, null, null),
          ('Fanta', 5, null, null),
          ('Burger B', 3, null, null),
        ]);
        final names = [for (final it in t.items) it.name];
        expect(names.length, 5);
        expect(names.toSet().length, 5);
      },
    );
  });
}
