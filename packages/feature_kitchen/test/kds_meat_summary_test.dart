import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:flutter_test/flutter_test.dart';

/// KDS-ALERTS-AND-KITCHEN-COUNTS-002: the mapper computes the WHOLE-ORDER kitchen
/// count total from the selected options' meat_snapshot (× modifier units × item
/// quantity), grouped by resource label, into the unified [kitchenCounts]. Any
/// owner-written label is supported. Money-free.
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
    String station = 'grill',
    String name = 'Burger',
  }) => <String, dynamic>{
    'id': id,
    'order_id': orderId,
    'quantity': quantity,
    'station_id': station,
    'menu_item_name_snapshot': name,
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

  test('4 double + 1 single = 9 patties (whole order, one station)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', quantity: 4), // 4 double burgers
        item('i2', 'o1', quantity: 1), // 1 single burger
      ],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'patties'}),
        mod('i2', 'Single', meat: {'quantity': 1, 'unit': 'patties'}),
      ],
    );
    // 2×1×4 + 1×1×1 = 9.
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 9, label: 'patties'),
    ]);
    expect(tickets.single.items.length, 2);
  });

  test('modifier units multiply the count (extra patty ×2)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 3)],
      modifiers: [
        mod(
          'i1',
          'Extra patty',
          quantity: 2,
          meat: {'quantity': 1, 'unit': 'patty'},
        ),
      ],
    );
    // 1 × 2 (modifier units) × 3 (item qty) = 6.
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 6, label: 'patty'),
    ]);
  });

  test('different labels stay separate totals', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 2)],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'قطع'}),
        mod('i1', '300g', meat: {'quantity': 300, 'unit': 'g'}),
      ],
    );
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 4, label: 'قطع'), // 2×1×2
      const KitchenCount(quantity: 600, label: 'g'), // 300×1×2
    ]);
  });

  test('no count anywhere -> empty (top summary hidden)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 1)],
      modifiers: [mod('i1', 'No onion')],
    );
    expect(tickets.single.kitchenCounts, isEmpty);
  });

  test('aggregates ANY owner-written resource label (قطع لحم / حبات سمك)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', quantity: 4),
        item('i2', 'o1', quantity: 1),
        item('i3', 'o1', quantity: 6),
      ],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'قطع لحم'}),
        mod('i2', 'Single', meat: {'quantity': 1, 'unit': 'قطع لحم'}),
        mod('i3', 'Fish', meat: {'quantity': 1, 'unit': 'حبات سمك'}),
      ],
    );
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 9, label: 'قطع لحم'), // 2×1×4 + 1×1×1
      const KitchenCount(quantity: 6, label: 'حبات سمك'), // 1×1×6
    ]);
  });
}
