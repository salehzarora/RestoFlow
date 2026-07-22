import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// KITCHEN-PRINT-DUAL-001C (case G) — the KDS ACTIVE-FEED containment.
///
/// A direct_print order is dispatched to the kitchen via the POS printer, so the
/// KDS mapper excludes it from the active board REGARDLESS of status — it never
/// becomes an actionable ticket, never accumulates an open local ticket, and
/// never contributes to the active/kitchen counts. A normal 'kds' order is
/// UNCHANGED.
void main() {
  Map<String, dynamic> order(
    String id, {
    String status = 'submitted',
    String? dispatchMode,
  }) => <String, dynamic>{
    'id': id,
    'status': status,
    'order_type': 'takeaway',
    if (dispatchMode != null) 'dispatch_mode': dispatchMode,
  };

  Map<String, dynamic> item(String id, String orderId) => <String, dynamic>{
    'id': id,
    'order_id': orderId,
    'quantity': 1,
    'station_id': 'grill',
    'menu_item_name_snapshot': 'Burger',
  };

  test(
    'a direct_print order produces NO active ticket (submitted or served)',
    () {
      // Even at an otherwise-active 'submitted' status, dispatch_mode wins.
      expect(
        KdsTicketMapper.map(
          orders: [
            order('o1', status: 'submitted', dispatchMode: 'direct_print'),
          ],
          orderItems: [item('i1', 'o1')],
          modifiers: const [],
        ),
        isEmpty,
      );
      // And at its authoritative resting 'served' status too.
      expect(
        KdsTicketMapper.map(
          orders: [order('o2', status: 'served', dispatchMode: 'direct_print')],
          orderItems: [item('i2', 'o2')],
          modifiers: const [],
        ),
        isEmpty,
      );
    },
  );

  test('a normal kds order is UNCHANGED — it appears on the board', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o3', status: 'submitted', dispatchMode: 'kds')],
      orderItems: [item('i3', 'o3')],
      modifiers: const [],
    );
    expect(tickets, hasLength(1));
    expect(tickets.single.items.single.name, 'Burger');
    // A row with NO dispatch_mode key at all (pre-001C data) is treated as kds.
    final legacy = KdsTicketMapper.map(
      orders: [order('o4', status: 'submitted')],
      orderItems: [item('i4', 'o4')],
      modifiers: const [],
    );
    expect(legacy, hasLength(1));
  });

  test('a direct_print order does not inflate the board or its counts', () {
    // One kds order + one direct_print order (with a meat count) -> only the kds
    // order boards, and the direct_print meat NEVER enters any ticket's counts.
    final tickets = KdsTicketMapper.map(
      orders: [
        order('k', status: 'submitted', dispatchMode: 'kds'),
        order('d', status: 'served', dispatchMode: 'direct_print'),
      ],
      orderItems: [item('ik', 'k'), item('id', 'd')],
      modifiers: [
        {
          'order_item_id': 'id',
          'option_name_snapshot': 'Double',
          'quantity': 1,
          'meat_snapshot': {'quantity': 2, 'unit': 'patty'},
        },
      ],
    );
    expect(tickets, hasLength(1), reason: 'only the kds order boards');
    expect(tickets.single.orderId, 'k');
    expect(
      tickets.single.kitchenCounts,
      isEmpty,
      reason: 'the direct_print order contributes no counts anywhere',
    );
  });
}
