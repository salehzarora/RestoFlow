import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-CODEX-FIX-020 — Codex HIGH #2.
///
/// The mapper decoded `meat_snapshot` and then REBUILT it as
/// `KitchenMeat(quantity: …, unit: …)`, silently discarding
/// classifierOptionId / classifierOptionName / classifierSelected — so a
/// classified size option reached the KDS board as one undifferentiated total
/// even though the wire carried the answer.
///
/// These drive the real `KdsTicketMapper.map`, not a domain helper.
void main() {
  const cheeseId = 'opt-cheese';

  Map<String, dynamic> order(String id) => <String, dynamic>{
    'id': id,
    'status': 'submitted',
    'order_type': 'dine_in',
  };

  Map<String, dynamic> item(
    String id,
    String orderId, {
    int quantity = 1,
    int linePosition = 1,
  }) => <String, dynamic>{
    'id': id,
    'order_id': orderId,
    'quantity': quantity,
    'menu_item_name_snapshot': 'Burger',
    'line_position': linePosition,
    'prep_snapshot': [
      {'name': 'Bread', 'quantity': 1, 'unit': 'Piece'},
    ],
  };

  /// A size modifier carrying the wire snapshot the POS now sends.
  Map<String, dynamic> sizeMod(
    String itemId, {
    required num pieces,
    required bool? cheese,
    int quantity = 1,
    String name = '240g',
  }) => <String, dynamic>{
    'order_item_id': itemId,
    'option_name_snapshot': name,
    'quantity': quantity,
    'meat_snapshot': <String, dynamic>{
      'quantity': pieces,
      'unit': 'Meat pieces',
      if (cheese != null) ...<String, dynamic>{
        'classifier_option_id': cheeseId,
        'classifier_option_name': 'Cheese',
        'classifier_selected': cheese,
      },
    },
  };

  Map<String, dynamic> cheeseMod(String itemId) => <String, dynamic>{
    'order_item_id': itemId,
    'option_name_snapshot': 'Cheese',
    'quantity': 1,
  };

  List<(num, String, String, bool)> rows(List<KitchenCount> counts) => [
    for (final c in counts)
      (c.quantity, c.label, c.classifier, c.classifierSelected),
  ];

  test('020-K1. 240g + Cheese maps to 2 Meat pieces WITH Cheese', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1')],
      modifiers: [sizeMod('i1', pieces: 2, cheese: true), cheeseMod('i1')],
    );
    expect(rows(tickets.single.kitchenCounts), [
      (2, 'Meat pieces', 'Cheese', true),
      (1, 'Bread Piece', '', false),
    ]);
  });

  test('020-K2. 240g without Cheese maps to 2 Meat pieces WITHOUT Cheese', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1')],
      modifiers: [sizeMod('i1', pieces: 2, cheese: false)],
    );
    expect(rows(tickets.single.kitchenCounts), [
      (2, 'Meat pieces', 'Cheese', false),
      (1, 'Bread Piece', '', false),
    ]);
  });

  test('020-K3. Saleh: three 240g burgers, two with Cheese -> 4 / 2', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', quantity: 2, linePosition: 1),
        item('i2', 'o1', quantity: 1, linePosition: 2),
      ],
      modifiers: [
        sizeMod('i1', pieces: 2, cheese: true),
        cheeseMod('i1'),
        sizeMod('i2', pieces: 2, cheese: false),
      ],
    );
    expect(rows(tickets.single.kitchenCounts), [
      (4, 'Meat pieces', 'Cheese', true),
      (2, 'Meat pieces', 'Cheese', false),
      (3, 'Bread Piece', '', false),
    ]);
  });

  test('020-K4. mixed sizes: 120g+Cheese, 120g plain, 240g+Cheese', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', linePosition: 1),
        item('i2', 'o1', linePosition: 2),
        item('i3', 'o1', linePosition: 3),
      ],
      modifiers: [
        sizeMod('i1', pieces: 1, cheese: true, name: '120g'),
        cheeseMod('i1'),
        sizeMod('i2', pieces: 1, cheese: false, name: '120g'),
        sizeMod('i3', pieces: 2, cheese: true),
        cheeseMod('i3'),
      ],
    );
    expect(rows(tickets.single.kitchenCounts), [
      (3, 'Meat pieces', 'Cheese', true),
      (1, 'Meat pieces', 'Cheese', false),
      (3, 'Bread Piece', '', false),
    ]);
  });

  test('020-K5. the metadata survives decoding AND scaling', () {
    // The option taken twice: the QUANTITY scales, the classifier does not.
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1')],
      modifiers: [
        sizeMod('i1', pieces: 2, cheese: true, quantity: 3),
        cheeseMod('i1'),
      ],
    );
    final meat = tickets.single.kitchenCounts.firstWhere(
      (c) => c.label == 'Meat pieces',
    );
    expect(meat.quantity, 6, reason: '2 per unit x 3 units');
    expect(meat.classifier, 'Cheese');
    expect(meat.classifierSelected, isTrue);
  });

  test('020-K6. modifier units and item quantity are each applied ONCE', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 5)],
      modifiers: [
        sizeMod('i1', pieces: 2, cheese: true, quantity: 3),
        cheeseMod('i1'),
      ],
    );
    // 2 per unit x 3 modifier units x 5 ordered items = 30. Not 2x3x3x5, and
    // not 2x5 — exactly one application of each factor.
    expect(
      tickets.single.kitchenCounts
          .firstWhere((c) => c.label == 'Meat pieces')
          .quantity,
      30,
    );
  });

  test('020-K7. a LEGACY snapshot with no classifier stays unsplit', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 3)],
      modifiers: [sizeMod('i1', pieces: 2, cheese: null)],
    );
    expect(rows(tickets.single.kitchenCounts), [
      (6, 'Meat pieces', '', false),
      (3, 'Bread Piece', '', false),
    ]);
  });

  test('020-K8. an UNRESOLVED snapshot (id/name but no answer) is unsplit', () {
    // What the pre-020 wire actually sent: menu config with no answer. The KDS
    // must not invent one.
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1')],
      modifiers: [
        <String, dynamic>{
          'order_item_id': 'i1',
          'option_name_snapshot': '240g',
          'quantity': 1,
          'meat_snapshot': <String, dynamic>{
            'quantity': 2,
            'unit': 'Meat pieces',
            'classifier_option_id': cheeseId,
            'classifier_option_name': 'Cheese',
          },
        },
      ],
    );
    expect(rows(tickets.single.kitchenCounts).first, (
      2,
      'Meat pieces',
      '',
      false,
    ));
  });

  test('020-K9. an Add-items round classifies only its own items', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', quantity: 2, linePosition: 1),
        <String, dynamic>{
          ...item('i2', 'o1', linePosition: 2),
          'service_round_id': 'r2',
        },
      ],
      modifiers: [
        sizeMod('i1', pieces: 2, cheese: true),
        cheeseMod('i1'),
        sizeMod('i2', pieces: 2, cheese: false),
      ],
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
    expect(rows(initial.kitchenCounts).first, (
      4,
      'Meat pieces',
      'Cheese',
      true,
    ));
    expect(rows(round.kitchenCounts).first, (
      2,
      'Meat pieces',
      'Cheese',
      false,
    ));
  });

  test('020-K10. the mapper stays money-free with the classifier present', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1')],
      modifiers: [sizeMod('i1', pieces: 2, cheese: true), cheeseMod('i1')],
    );
    for (final c in tickets.single.kitchenCounts) {
      expect(c.toJson().keys.any((k) => k.contains('minor')), isFalse);
    }
  });
}
