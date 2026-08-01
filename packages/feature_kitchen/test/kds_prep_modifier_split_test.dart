import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — the KDS half.
///
/// The classification is decided ONCE, at order time, and travels inside the
/// existing `order_items.prep_snapshot` array. The mapper therefore re-derives
/// nothing: it reads the resolved snapshot the POS wrote and hands it to the
/// SAME shared aggregator the POS direct print uses, so the board, the printed
/// ticket and the paper the cashier reprints cannot disagree.
void main() {
  Map<String, dynamic> order(String id) => <String, dynamic>{
    'id': id,
    'status': 'submitted',
    'order_type': 'dine_in',
  };

  /// A 240g burger line as it arrives on the wire: 1 Bread + 2 Meat pieces per
  /// unit, the meat classified by "Cheese" and already resolved for this line.
  Map<String, dynamic> burger(
    String id,
    String orderId, {
    required int quantity,
    required bool cheese,
    String? roundId,
  }) => <String, dynamic>{
    'id': id,
    'order_id': orderId,
    'quantity': quantity,
    'menu_item_name_snapshot': 'Burger 240g',
    if (roundId != null) 'service_round_id': roundId,
    'prep_snapshot': [
      {'name': 'Bread', 'quantity': 1, 'unit': ''},
      {
        'name': 'Meat pieces',
        'quantity': 2,
        'unit': '',
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': 'Cheese',
        'classifier_selected': cheese,
      },
    ],
  };

  Map<String, dynamic> mod(String orderItemId, String option) =>
      <String, dynamic>{
        'order_item_id': orderItemId,
        'option_name_snapshot': option,
        'quantity': 1,
      };

  List<(num, String, String, bool)> rows(List<KitchenCount> counts) => [
    for (final c in counts)
      (c.quantity, c.label, c.classifier, c.classifierSelected),
  ];

  test('the 3-burger example splits on the KDS exactly as on the POS', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        burger('i1', 'o1', quantity: 2, cheese: true),
        burger('i2', 'o1', quantity: 1, cheese: false),
      ],
      modifiers: [mod('i1', 'Cheese')],
    );

    expect(rows(tickets.single.kitchenCounts), [
      (3, 'Bread', '', false),
      (4, 'Meat pieces', 'Cheese', true),
      (2, 'Meat pieces', 'Cheese', false),
    ]);
  });

  test('all selected prints no empty without-row (and vice versa)', () {
    final allCheese = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [burger('i1', 'o1', quantity: 3, cheese: true)],
      modifiers: [mod('i1', 'Cheese')],
    );
    expect(rows(allCheese.single.kitchenCounts), [
      (3, 'Bread', '', false),
      (6, 'Meat pieces', 'Cheese', true),
    ]);

    final noCheese = KdsTicketMapper.map(
      orders: [order('o2')],
      orderItems: [burger('i1', 'o2', quantity: 3, cheese: false)],
      modifiers: const [],
    );
    expect(rows(noCheese.single.kitchenCounts), [
      (3, 'Bread', '', false),
      (6, 'Meat pieces', 'Cheese', false),
    ]);
  });

  test('a legacy snapshot without the classifier keys stays unsplit', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        <String, dynamic>{
          'id': 'i1',
          'order_id': 'o1',
          'quantity': 3,
          'menu_item_name_snapshot': 'Burger 240g',
          'prep_snapshot': [
            {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
          ],
        },
      ],
      modifiers: const [],
    );
    expect(rows(tickets.single.kitchenCounts), [(6, 'Meat pieces', '', false)]);
  });

  test('a modifier that also counts keeps its own independent total', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [burger('i1', 'o1', quantity: 2, cheese: true)],
      modifiers: [
        <String, dynamic>{
          'order_item_id': 'i1',
          'option_name_snapshot': 'Cheese',
          'quantity': 1,
          'meat_snapshot': {'quantity': 1, 'unit': 'Cheese slices'},
        },
      ],
    );
    expect(rows(tickets.single.kitchenCounts), [
      (2, 'Cheese slices', '', false),
      (2, 'Bread', '', false),
      (4, 'Meat pieces', 'Cheese', true),
    ]);
  });

  test('an Add-items round ticket classifies only its OWN items', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        burger('i1', 'o1', quantity: 2, cheese: true),
        burger('i2', 'o1', quantity: 1, cheese: false, roundId: 'r2'),
      ],
      modifiers: [mod('i1', 'Cheese')],
      serviceRounds: [
        <String, dynamic>{
          'id': 'r2',
          'order_id': 'o1',
          'status': 'submitted',
          'round_number': 2,
        },
      ],
    );

    final initial = tickets.firstWhere((t) => t.roundNumber == null);
    final round = tickets.firstWhere((t) => t.roundNumber == 2);

    // The original work unit: only the two cheese burgers.
    expect(rows(initial.kitchenCounts), [
      (2, 'Bread', '', false),
      (4, 'Meat pieces', 'Cheese', true),
    ]);
    // The round: only its own plain burger, in its own bucket.
    expect(rows(round.kitchenCounts), [
      (1, 'Bread', '', false),
      (2, 'Meat pieces', 'Cheese', false),
    ]);
  });

  test('the mapper stays money-free with the classifier present', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [burger('i1', 'o1', quantity: 2, cheese: true)],
      modifiers: [mod('i1', 'Cheese')],
    );
    for (final count in tickets.single.kitchenCounts) {
      expect(count.toJson().keys.any((k) => k.contains('minor')), isFalse);
    }
  });
}
