import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:flutter_test/flutter_test.dart';

/// KITCHEN-MEAT-001: the mapper computes the WHOLE-ORDER meat total from the
/// selected options' meat_snapshot (× modifier units × item quantity), grouped
/// by unit, and attaches it to every ticket of the order. Money-free.
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
    expect(tickets.single.meatTotals, [
      const KitchenMeat(quantity: 9, unit: 'patties'),
    ]);
    // Item details remain (money-free).
    expect(tickets.single.items.length, 2);
  });

  test(
    'the whole-order meat total shows on EVERY station ticket of the order',
    () {
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [
          item('i1', 'o1', quantity: 2, station: 'grill'),
          item('i2', 'o1', quantity: 1, station: 'fryer'),
        ],
        modifiers: [
          mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'قطع'}),
          mod('i2', 'Single', meat: {'quantity': 1, 'unit': 'قطع'}),
        ],
      );
      // Two tickets (grill + fryer); each carries the whole-order total (5 قطع).
      expect(tickets.length, 2);
      for (final t in tickets) {
        expect(t.meatTotals, [const KitchenMeat(quantity: 5, unit: 'قطع')]);
      }
    },
  );

  test('modifier units multiply the meat (extra patty ×2)', () {
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
    expect(tickets.single.meatTotals, [
      const KitchenMeat(quantity: 6, unit: 'patty'),
    ]);
  });

  test('different units stay separate totals', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 2)],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'قطع'}),
        mod('i1', '300g', meat: {'quantity': 300, 'unit': 'g'}),
      ],
    );
    expect(tickets.single.meatTotals, [
      const KitchenMeat(quantity: 4, unit: 'قطع'), // 2×1×2
      const KitchenMeat(quantity: 600, unit: 'g'), // 300×1×2
    ]);
  });

  test('no meat_snapshot anywhere -> empty meatTotals (top note hidden)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 1)],
      modifiers: [mod('i1', 'No onion')],
    );
    expect(tickets.single.meatTotals, isEmpty);
  });

  test('meat totals are money-free (only quantity/unit)', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 1)],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'patties'}),
      ],
    );
    for (final meat in tickets.single.meatTotals) {
      final json = meat.toJson();
      expect(json.keys.any((k) => k.toLowerCase().contains('minor')), isFalse);
    }
  });

  test(
    'KITCHEN-COUNT-001: aggregates ANY owner-written unit (قطع لحم / حبات سمك)',
    () {
      // Generic kitchen count: the aggregation is unit-agnostic (not meat-only).
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [
          item('i1', 'o1', quantity: 4), // 4 double burgers
          item('i2', 'o1', quantity: 1), // 1 single burger
          item('i3', 'o1', quantity: 6), // 6 fish
        ],
        modifiers: [
          mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'قطع لحم'}),
          mod('i2', 'Single', meat: {'quantity': 1, 'unit': 'قطع لحم'}),
          mod('i3', 'Fish', meat: {'quantity': 1, 'unit': 'حبات سمك'}),
        ],
      );
      expect(tickets.single.meatTotals, [
        const KitchenMeat(quantity: 9, unit: 'قطع لحم'), // 2×1×4 + 1×1×1
        const KitchenMeat(quantity: 6, unit: 'حبات سمك'), // 1×1×6
      ]);
    },
  );
}
