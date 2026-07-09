import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:flutter_test/flutter_test.dart';

/// KDS-ALERTS-AND-KITCHEN-COUNTS-002: the mapper unifies the item-base counts
/// (`order_items.prep_snapshot`) AND the modifier-option counts
/// (`order_item_modifiers.meat_snapshot`) into ONE whole-order [kitchenCounts]
/// summary, grouped by resource label. Nothing is derived from a name/price —
/// only the explicit owner-configured snapshot is rolled up. Money-free.
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

  Map<String, dynamic> mod(
    String orderItemId,
    String option, {
    int quantity = 1,
    Object? meat,
  }) => <String, dynamic>{
    'order_item_id': orderItemId,
    'option_name_snapshot': option,
    'quantity': quantity,
    if (meat != null) 'meat_snapshot': meat,
  };

  test('aggregates item-base counts across the ticket (× item quantity), '
      'Arabic preserved', () {
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

    // Labels combine name + unit; quantities are × the item quantity.
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 6, label: 'لحم برجر قطع'),
      const KitchenCount(quantity: 3, label: 'خبز برجر حبة'),
      const KitchenCount(quantity: 2, label: 'بطاطا'),
    ]);
    // Per-item snapshot is carried too (the summary is derived from it).
    expect(tickets.single.items.first.prepComponents.length, 2);
  });

  test('UNIFIED: modifier-option counts (patties) + item-base counts (buns) '
      'roll up together — 2 double + 5 triple = 19 patties + 7 buns', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item(
          'i1',
          'o1',
          quantity: 2, // 2 double burgers
          name: 'Burger',
          prepSnapshot: [
            {'name': 'خبز', 'quantity': 1},
          ],
        ),
        item(
          'i2',
          'o1',
          quantity: 5, // 5 triple burgers
          name: 'Burger',
          prepSnapshot: [
            {'name': 'خبز', 'quantity': 1},
          ],
        ),
      ],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'قطع لحم'}),
        mod('i2', 'Triple', meat: {'quantity': 3, 'unit': 'قطع لحم'}),
      ],
    );

    expect(tickets.single.kitchenCounts, [
      // 2×1×2 (double) + 3×1×5 (triple) = 19 patties.
      const KitchenCount(quantity: 19, label: 'قطع لحم'),
      // 1×2 + 1×5 = 7 buns.
      const KitchenCount(quantity: 7, label: 'خبز'),
    ]);
    // Item details remain (money-free).
    expect(tickets.single.items.length, 2);
  });

  test('the whole-order counts show on EVERY station ticket of the order', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        {
          'id': 'i1',
          'order_id': 'o1',
          'station_id': 'grill',
          'quantity': 2,
          'menu_item_name_snapshot': 'Burger',
          'prep_snapshot': [
            {'name': 'خبز', 'quantity': 1},
          ],
        },
        {
          'id': 'i2',
          'order_id': 'o1',
          'station_id': 'fryer',
          'quantity': 1,
          'menu_item_name_snapshot': 'Fries',
        },
      ],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'قطع لحم'}),
      ],
    );
    // Two tickets (grill + fryer); each carries the whole-order counts.
    expect(tickets.length, 2);
    for (final t in tickets) {
      expect(t.kitchenCounts, [
        const KitchenCount(quantity: 4, label: 'قطع لحم'), // 2×1×2
        const KitchenCount(quantity: 2, label: 'خبز'), // 1×2
      ]);
    }
  });

  test(
    'no configured count anywhere -> an empty summary (card/ticket hide it)',
    () {
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [item('i1', 'o1', quantity: 1, name: 'Plain Soda')],
        modifiers: const [],
      );
      expect(tickets.single.kitchenCounts, isEmpty);
      expect(tickets.single.items.single.prepComponents, isEmpty);
    },
  );

  test(
    'the count summary is MONEY-FREE — entries carry only quantity/label',
    () {
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [
          item(
            'i1',
            'o1',
            quantity: 1,
            name: 'Burger',
            prepSnapshot: [
              {'name': 'Patty', 'quantity': 1, 'unit': 'pcs'},
            ],
          ),
        ],
        modifiers: const [],
      );
      for (final count in tickets.single.kitchenCounts) {
        final json = count.toJson();
        expect(json.keys, containsAll(<String>['quantity', 'label']));
        expect(
          json.keys.any((k) => k.toLowerCase().contains('minor')),
          isFalse,
        );
      }
    },
  );

  test('bad prep_snapshot shapes degrade to no count (never throws)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', quantity: 1, name: 'Burger', prepSnapshot: 'garbage'),
        item('i2', 'o1', quantity: 1, name: 'Fries', prepSnapshot: 42),
      ],
      modifiers: const [],
    );
    expect(tickets.single.kitchenCounts, isEmpty);
  });
}
