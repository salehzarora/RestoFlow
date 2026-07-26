import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketMapper, KdsTicketView;
import 'package:test/test.dart';

/// MENU-ORDER-001 — the KDS orders an item's modifiers to match the cashier
/// receipt (menu display order).
///
/// The receipt & POS kitchen ticket print an item's modifiers in the order the
/// POS customization dialog emitted them — group-then-option display order.
/// The KDS builds from `order_items` / `order_item_modifiers` rows delivered by
/// `app.sync_pull` `ORDER BY (updated_at, id)` — effectively random within an
/// item for a freshly submitted order. Each modifier row now carries the stable
/// per-item ordinal `order_item_modifiers.line_position` (assigned in
/// submit-array = menu order), and `KdsTicketMapper` sorts an item's modifiers
/// by it, so the KDS reproduces the receipt sequence regardless of wire order.
/// Legacy rows (no `line_position` -> 0) fall back to their wire order.

const _order = {
  'id': 'o1',
  'status': 'submitted',
  'order_type': 'dine_in',
  'created_at': '2026-07-31T10:00:00Z',
};

/// One item's modifier fixture: (option name, line_position, quantity).
typedef _Mod = (String, int, int);

KdsTicketView _ticket(List<_Mod> mods) {
  final tickets = KdsTicketMapper.map(
    orders: const [_order],
    orderItems: const [
      {
        'id': 'it1',
        'order_id': 'o1',
        'quantity': 1,
        'menu_item_name_snapshot': 'Burger',
        'line_position': 1,
      },
    ],
    modifiers: [
      for (final m in mods)
        {
          'order_item_id': 'it1',
          'option_name_snapshot': m.$1,
          'line_position': m.$2,
          'quantity': m.$3,
        },
    ],
  );
  expect(tickets, hasLength(1));
  return tickets.single;
}

void main() {
  group('KdsTicketMapper modifier order (MENU-ORDER-001)', () {
    test('sorts an item\'s modifiers by line_position from a SHUFFLED wire — '
        'restoring the cashier-receipt (menu) order', () {
      final t = _ticket(const [
        ('No onion', 3, 1),
        ('Extra cheese', 1, 1),
        ('Medium', 2, 1),
      ]);
      expect(t.items.single.modifiers, const [
        'Extra cheese',
        'Medium',
        'No onion',
      ]);
    });

    test('legacy modifiers (all line_position 0) keep their wire order — a '
        'partially-migrated order never scrambles', () {
      final t = _ticket(const [
        ('First', 0, 1),
        ('Second', 0, 1),
        ('Third', 0, 1),
      ]);
      expect(t.items.single.modifiers, const ['First', 'Second', 'Third']);
    });

    test('the ×N quantity suffix survives the sort', () {
      final t = _ticket(const [
        ('Bacon', 2, 2),
        ('Ketchup', 1, 1),
      ]);
      expect(t.items.single.modifiers, const ['Ketchup', 'Bacon ×2']);
    });

    test('modifiers stay attached to the RIGHT item after both items and '
        'modifiers are sorted', () {
      final tickets = KdsTicketMapper.map(
        orders: const [_order],
        orderItems: const [
          {
            'id': 'itA',
            'order_id': 'o1',
            'quantity': 1,
            'menu_item_name_snapshot': 'A',
            'line_position': 1,
          },
          {
            'id': 'itB',
            'order_id': 'o1',
            'quantity': 1,
            'menu_item_name_snapshot': 'B',
            'line_position': 2,
          },
        ],
        // Deliberately interleaved + shuffled across both items.
        modifiers: const [
          {
            'order_item_id': 'itB',
            'option_name_snapshot': 'b2',
            'line_position': 2,
            'quantity': 1,
          },
          {
            'order_item_id': 'itA',
            'option_name_snapshot': 'a2',
            'line_position': 2,
            'quantity': 1,
          },
          {
            'order_item_id': 'itA',
            'option_name_snapshot': 'a1',
            'line_position': 1,
            'quantity': 1,
          },
          {
            'order_item_id': 'itB',
            'option_name_snapshot': 'b1',
            'line_position': 1,
            'quantity': 1,
          },
        ],
      );
      final items = tickets.single.items;
      expect(items.map((i) => i.name).toList(), const ['A', 'B']);
      expect(
        items.firstWhere((i) => i.name == 'A').modifiers,
        const ['a1', 'a2'],
      );
      expect(
        items.firstWhere((i) => i.name == 'B').modifiers,
        const ['b1', 'b2'],
      );
    });

    test('no modifier is lost or duplicated regardless of wire order', () {
      final t = _ticket(const [
        ('m3', 3, 1),
        ('m1', 1, 1),
        ('m4', 4, 1),
        ('m2', 2, 1),
      ]);
      expect(t.items.single.modifiers, const ['m1', 'm2', 'm3', 'm4']);
    });
  });
}
