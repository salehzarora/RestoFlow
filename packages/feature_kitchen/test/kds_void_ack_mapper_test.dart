import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// PSC-001D — the mapper's four-case cancellation model.
///
/// 1. normal active order: unchanged; 2. voided + ack-required + unacked: ONE
/// pending-ack cancelled ticket WITH its voided items; 3. voided + already
/// acknowledged: excluded; 4. voided without an acknowledgement demand
/// (served-source / historical): excluded. Ordinary voided items never leak
/// onto normal cards.

Map<String, dynamic> _order(
  String id, {
  String status = 'submitted',
  bool ackRequired = false,
  String? ackAt,
  String? voidedAt,
  String? voidedFrom,
}) => {
  'id': id,
  'status': status,
  'order_type': 'takeaway',
  'created_at': '2026-07-21T10:00:00Z',
  'kitchen_ack_required': ackRequired,
  'kitchen_ack_at': ackAt,
  'voided_at': voidedAt,
  'voided_from_status': voidedFrom,
};

Map<String, dynamic> _item(
  String id,
  String orderId, {
  String status = 'pending',
}) => {
  'id': id,
  'order_id': orderId,
  'status': status,
  'menu_item_name_snapshot': 'Burger',
  'quantity': 2,
};

void main() {
  test('a pending-ack void becomes ONE cancelled ticket with its items', () {
    final tickets = KdsTicketMapper.map(
      orders: [
        _order(
          'o1',
          status: 'voided',
          ackRequired: true,
          voidedAt: '2026-07-21T10:05:00Z',
          voidedFrom: 'preparing',
        ),
      ],
      orderItems: [_item('i1', 'o1', status: 'voided')],
      modifiers: const [],
    );
    expect(tickets, hasLength(1));
    final t = tickets.single;
    expect(t.status, KitchenTicketStatus.cancelled);
    expect(t.requiresAck, isTrue);
    expect(t.voidedFromStatus, 'preparing');
    expect(t.voidedAt, DateTime.parse('2026-07-21T10:05:00Z'));
    // The voided item's intact snapshot stays visible on THIS card.
    expect(t.items.single.name, 'Burger');
    expect(t.items.single.quantity, 2);
  });

  test('an ACKNOWLEDGED void is excluded from the active board', () {
    final tickets = KdsTicketMapper.map(
      orders: [
        _order(
          'o1',
          status: 'voided',
          ackRequired: true,
          ackAt: '2026-07-21T10:06:00Z',
          voidedAt: '2026-07-21T10:05:00Z',
          voidedFrom: 'preparing',
        ),
      ],
      orderItems: [_item('i1', 'o1', status: 'voided')],
      modifiers: const [],
    );
    expect(tickets, isEmpty);
  });

  test('a void that requires NO acknowledgement is excluded (served source / '
      'historical)', () {
    final tickets = KdsTicketMapper.map(
      orders: [
        _order(
          'o1',
          status: 'voided',
          voidedAt: '2026-07-21T10:05:00Z',
          voidedFrom: 'served',
        ),
        // A historical void: no provenance at all.
        _order('o2', status: 'voided'),
      ],
      orderItems: [
        _item('i1', 'o1', status: 'voided'),
        _item('i2', 'o2', status: 'voided'),
      ],
      modifiers: const [],
    );
    expect(tickets, isEmpty);
  });

  test('normal active tickets are unchanged and never show voided items', () {
    final tickets = KdsTicketMapper.map(
      orders: [_order('o1', status: 'preparing')],
      orderItems: [
        _item('i1', 'o1'),
        _item('i2', 'o1', status: 'voided'), // line-voided on a live order
      ],
      modifiers: const [],
    );
    final t = tickets.single;
    expect(t.status, KitchenTicketStatus.inPreparation);
    expect(t.requiresAck, isFalse);
    expect(t.voidedAt, isNull);
    expect(t.items, hasLength(1)); // the voided line stays excluded
  });

  test('duplicate pulls do not duplicate the cancellation card', () {
    final order = _order(
      'o1',
      status: 'voided',
      ackRequired: true,
      voidedAt: '2026-07-21T10:05:00Z',
      voidedFrom: 'ready',
    );
    // The coordinator keys rows by id, but the mapper itself must also be
    // stable when handed the same row set twice in a row.
    final first = KdsTicketMapper.map(
      orders: [order],
      orderItems: [_item('i1', 'o1', status: 'voided')],
      modifiers: const [],
    );
    final second = KdsTicketMapper.map(
      orders: [order],
      orderItems: [_item('i1', 'o1', status: 'voided')],
      modifiers: const [],
    );
    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(second.single.kitchenTicketId, first.single.kitchenTicketId);
  });

  test('ORDER-EDIT-001C: the red card excludes EDIT-RETIRED lines '
      '(removed_by_edit_id) but keeps round items and edit-written lines', () {
    // app.edit_order retired i1 (removed_by_edit_id) and wrote i3 into an edit
    // round; the order was then voided while the kitchen still had work.
    final tickets = KdsTicketMapper.map(
      orders: [
        _order(
          'o1',
          status: 'voided',
          ackRequired: true,
          voidedAt: '2026-07-21T10:05:00Z',
          voidedFrom: 'preparing',
        ),
      ],
      orderItems: [
        {
          ..._item('i1', 'o1', status: 'voided'),
          'menu_item_name_snapshot': 'Retired burger',
          'removed_by_edit_id': 'e1',
          'removed_kitchen_stage': 'preparing',
        },
        _item('i2', 'o1', status: 'voided'),
        {
          ..._item('i3', 'o1', status: 'voided'),
          'menu_item_name_snapshot': 'Edit fries',
          'edit_id': 'e1',
          'service_round_id': 'r2',
        },
      ],
      modifiers: const [],
      serviceRounds: const [
        {
          'id': 'r2',
          'order_id': 'o1',
          'round_number': 2,
          'status': 'voided',
          'edit_id': 'e1',
        },
      ],
    );
    final card = tickets.single;
    expect(card.status, KitchenTicketStatus.cancelled);
    expect(card.requiresAck, isTrue);
    expect(card.items.map((i) => i.name), ['Burger', 'Edit fries']);
    expect(card.items.map((i) => i.orderItemId), ['i2', 'i3']);
  });

  test('a pending-ack card contributes NO kitchen prep counts', () {
    final tickets = KdsTicketMapper.map(
      orders: [
        _order(
          'o1',
          status: 'voided',
          ackRequired: true,
          voidedAt: '2026-07-21T10:05:00Z',
          voidedFrom: 'submitted',
        ),
      ],
      orderItems: [
        {
          ..._item('i1', 'o1', status: 'voided'),
          'prep_snapshot': [
            {'name': 'Patty', 'quantity': 1, 'unit': 'pcs'},
          ],
        },
      ],
      modifiers: const [],
    );
    expect(tickets.single.kitchenCounts, isEmpty);
  });
}
