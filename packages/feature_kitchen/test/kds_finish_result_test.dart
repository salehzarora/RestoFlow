import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// KITCHEN-PRINT-DUAL-001D (case H) — after the bulk finish advances orders to
/// `served`, they leave the active KDS board + counts, while a NEWLY submitted
/// order still boards normally (the mapper's active-status gate, unchanged).
void main() {
  Map<String, dynamic> order(String id, String status) => <String, dynamic>{
    'id': id,
    'status': status,
    'order_type': 'takeaway',
  };

  Map<String, dynamic> item(String id, String orderId) => <String, dynamic>{
    'id': id,
    'order_id': orderId,
    'quantity': 1,
    'station_id': 'grill',
    'menu_item_name_snapshot': 'Burger',
  };

  test('a served order is off the active board; a submitted order boards', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o-served', 'served'), order('o-new', 'submitted')],
      orderItems: [item('i-served', 'o-served'), item('i-new', 'o-new')],
      modifiers: const [],
    );
    expect(tickets, hasLength(1), reason: 'only the active order boards');
    expect(tickets.single.orderId, 'o-new');
    expect(
      tickets.any((t) => t.orderId == 'o-served'),
      isFalse,
      reason: 'a finished (served) order is not an active ticket',
    );
  });

  test('a served order contributes no kitchen counts', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o-served', 'served'), order('o-new', 'submitted')],
      orderItems: [item('i-served', 'o-served'), item('i-new', 'o-new')],
      modifiers: [
        {
          'order_item_id': 'i-served',
          'option_name_snapshot': 'Double',
          'quantity': 1,
          'meat_snapshot': {'quantity': 2, 'unit': 'patty'},
        },
      ],
    );
    expect(tickets, hasLength(1));
    expect(tickets.single.orderId, 'o-new');
    expect(
      tickets.single.kitchenCounts,
      isEmpty,
      reason: 'the served order adds nothing to the active counts',
    );
  });

  test(
    'every active status still boards (submitted/accepted/preparing/ready)',
    () {
      for (final status in ['submitted', 'accepted', 'preparing', 'ready']) {
        final tickets = KdsTicketMapper.map(
          orders: [order('o', status)],
          orderItems: [item('i', 'o')],
          modifiers: const [],
        );
        expect(tickets, hasLength(1), reason: status);
      }
    },
  );
}
