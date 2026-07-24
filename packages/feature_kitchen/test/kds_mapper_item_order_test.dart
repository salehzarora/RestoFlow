import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketMapper;
import 'package:test/test.dart';

/// PRINT-LAYOUT-001D — where the KDS item order comes from.
///
/// The KDS builds its ticket by iterating the `order_items` rows exactly as they
/// arrive from `sync_pull` (which returns them `ORDER BY updated_at, id` — a
/// batch-identical timestamp + a random uuid, i.e. effectively random). This
/// suite proves the mapper is ORDER-TRANSPARENT: the printed KDS item sequence
/// is precisely the wire row order — so the divergence from the cashier receipt
/// (cart insertion order) is the WIRE ordering, NOT the mapper.
///
/// The fix therefore needs the wire to deliver cart order — an additive
/// `order_items.line_position` ordinal (a migration, out of scope this phase) —
/// after which a stable sort by that ordinal in this mapper makes every KDS
/// surface match the receipt. This test is the ready foundation for that sort.

List<Map<String, dynamic>> _rows(List<String> names) => [
  for (var i = 0; i < names.length; i++)
    {
      'id': 'i${names[i]}',
      'order_id': 'o1',
      'quantity': 1,
      'menu_item_name_snapshot': names[i],
    },
];

List<String> _itemNames(List<String> wireOrder) {
  final tickets = KdsTicketMapper.map(
    orders: const [
      {
        'id': 'o1',
        'status': 'submitted',
        'order_type': 'dine_in',
        'created_at': '2026-07-24T10:00:00Z',
      },
    ],
    orderItems: _rows(wireOrder),
    modifiers: const [],
  );
  expect(tickets, hasLength(1));
  return [for (final it in tickets.single.items) it.name];
}

void main() {
  group('KdsTicketMapper item order (PRINT-LAYOUT-001D)', () {
    test(
      'mirrors the order_items WIRE order verbatim — the mapper adds no sort '
      'of its own',
      () {
        expect(
          _itemNames(const ['Burger A', 'Cola', 'Burger B', 'Side A', 'Fanta']),
          const ['Burger A', 'Cola', 'Burger B', 'Side A', 'Fanta'],
        );
      },
    );

    test('a SHUFFLED wire order yields a shuffled KDS sequence — this is the '
        'root cause: sync_pull (updated_at, id) does not preserve cart order and '
        'order_items has no line ordinal to restore it', () {
      // The same five items delivered in a different (random-uuid) order.
      expect(
        _itemNames(const ['Cola', 'Side A', 'Burger A', 'Fanta', 'Burger B']),
        const ['Cola', 'Side A', 'Burger A', 'Fanta', 'Burger B'],
      );
    });

    test('every item appears exactly once regardless of wire order (no loss / '
        'no duplication) — only the sequence is at issue', () {
      final names = _itemNames(const [
        'Cola',
        'Side A',
        'Burger A',
        'Fanta',
        'Burger B',
      ]);
      expect(names.length, 5);
      expect(names.toSet().length, 5);
    });
  });
}
