import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:flutter_test/flutter_test.dart';

/// KITCHEN-PREP-001: the mapper reads each order item's `prep_snapshot` and
/// aggregates a money-free prep summary across the whole ticket. Nothing is
/// derived from a name/price — only the configured snapshot is rolled up.
void main() {
  Map<String, dynamic> order(String id) => <String, dynamic>{
    'id': id,
    'status': 'submitted',
    'order_type': 'dine_in',
  };

  Map<String, dynamic> item(
    String id,
    String orderId, {
    required int quantity,
    required String name,
    Object? prepSnapshot,
  }) => <String, dynamic>{
    'id': id,
    'order_id': orderId,
    'quantity': quantity,
    'menu_item_name_snapshot': name,
    if (prepSnapshot != null) 'prep_snapshot': prepSnapshot,
  };

  test(
    'aggregates prep across the ticket (× item quantity), Arabic preserved',
    () {
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [
          item(
            'i1',
            'o1',
            quantity: 3,
            name: 'Double Burger',
            prepSnapshot: [
              {'name': 'لحم برجر', 'quantity': 2, 'unit': 'قطع'},
              {'name': 'خبز برجر', 'quantity': 1, 'unit': 'حبة'},
            ],
          ),
          item(
            'i2',
            'o1',
            quantity: 2,
            name: 'Fries',
            prepSnapshot: [
              {'name': 'بطاطا', 'quantity': 1, 'unit': ''},
            ],
          ),
        ],
        modifiers: const [],
      );

      final ticket = tickets.single;
      expect(ticket.prepSummary, [
        const KitchenPrepComponent(name: 'لحم برجر', quantity: 6, unit: 'قطع'),
        const KitchenPrepComponent(name: 'خبز برجر', quantity: 3, unit: 'حبة'),
        const KitchenPrepComponent(name: 'بطاطا', quantity: 2),
      ]);
      // Per-item snapshot is carried too (the summary is derived from it).
      expect(ticket.items.first.prepComponents.length, 2);
    },
  );

  test(
    'no prep_snapshot anywhere -> an empty summary (card/ticket hide it)',
    () {
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [item('i1', 'o1', quantity: 1, name: 'Plain Soda')],
        modifiers: const [],
      );
      expect(tickets.single.prepSummary, isEmpty);
      expect(tickets.single.items.single.prepComponents, isEmpty);
    },
  );

  test(
    'prep summary is MONEY-FREE — components carry only name/quantity/unit',
    () {
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [
          item(
            'i1',
            'o1',
            quantity: 1,
            name: 'Burger',
            // Even if a bad client smuggled a money key, the mapper's plucked
            // KitchenPrepComponent has no money field to surface.
            prepSnapshot: [
              {'name': 'Patty', 'quantity': 1, 'unit': 'pcs'},
            ],
          ),
        ],
        modifiers: const [],
      );
      for (final component in tickets.single.prepSummary) {
        final json = component.toJson();
        expect(json.keys, containsAll(<String>['name', 'quantity', 'unit']));
        expect(
          json.keys.any((k) => k.toLowerCase().contains('minor')),
          isFalse,
        );
      }
    },
  );

  test('bad prep_snapshot shapes degrade to no prep (never throws)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', quantity: 1, name: 'Burger', prepSnapshot: 'garbage'),
        item('i2', 'o1', quantity: 1, name: 'Fries', prepSnapshot: 42),
      ],
      modifiers: const [],
    );
    expect(tickets.single.prepSummary, isEmpty);
  });
}
