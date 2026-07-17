import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// PSC-001C — service rounds on the KDS board: a round is a SEPARATE ticket
/// carrying the ROUND's own status and submit time; the original ticket never
/// re-receives old items; served/voided rounds leave the board; a served
/// parent renders ONLY its live rounds; the PSC-001D red cancellation card
/// keeps showing everything (round items included). Money-free throughout.

Map<String, dynamic> _order(
  String id, {
  String status = 'submitted',
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'status': status,
  'order_type': 'dine_in',
  'created_at': '2026-07-22T10:00:00Z',
  ...extra,
};

Map<String, dynamic> _item(
  String id,
  String orderId, {
  String? roundId,
  String status = 'pending',
  String name = 'Burger',
}) => {
  'id': id,
  'order_id': orderId,
  'status': status,
  'menu_item_name_snapshot': name,
  'quantity': 1,
  if (roundId != null) 'service_round_id': roundId,
};

Map<String, dynamic> _round(
  String id,
  String orderId, {
  int number = 2,
  String status = 'submitted',
  String createdAt = '2026-07-22T10:30:00Z',
}) => {
  'id': id,
  'order_id': orderId,
  'round_number': number,
  'status': status,
  'created_at': createdAt,
};

void main() {
  test('a round item becomes a SEPARATE ticket with the ROUND status/time', () {
    final tickets = KdsTicketMapper.map(
      orders: [_order('o1')],
      orderItems: [
        _item('i1', 'o1'),
        _item('i2', 'o1', roundId: 'r1', name: 'Fries'),
      ],
      modifiers: const [],
      serviceRounds: [_round('r1', 'o1', status: 'preparing')],
    );
    expect(tickets, hasLength(2));
    final original = tickets.singleWhere((t) => t.roundId == null);
    final round = tickets.singleWhere((t) => t.roundId == 'r1');
    expect(original.items.single.name, 'Burger');
    expect(original.roundNumber, isNull);
    expect(round.items.single.name, 'Fries');
    expect(round.roundNumber, 2);
    expect(round.kitchenTicketId, contains(':r'));
    // The round's OWN status and submission time — not the parent's.
    expect(round.status, KitchenTicketStatus.inPreparation);
    expect(original.status, KitchenTicketStatus.newTicket);
    expect(round.submittedAt, DateTime.parse('2026-07-22T10:30:00Z'));
    expect(original.submittedAt, DateTime.parse('2026-07-22T10:00:00Z'));
  });

  test('a SERVED or VOIDED round leaves the board', () {
    final tickets = KdsTicketMapper.map(
      orders: [_order('o1')],
      orderItems: [
        _item('i1', 'o1'),
        _item('i2', 'o1', roundId: 'r1'),
        _item('i3', 'o1', roundId: 'r2'),
      ],
      modifiers: const [],
      serviceRounds: [
        _round('r1', 'o1', status: 'served'),
        _round('r2', 'o1', number: 3, status: 'voided'),
      ],
    );
    expect(tickets, hasLength(1));
    expect(tickets.single.roundId, isNull);
  });

  test('a SERVED parent renders ONLY its live rounds — its original items '
      'never return to the board', () {
    final tickets = KdsTicketMapper.map(
      orders: [_order('o1', status: 'served')],
      orderItems: [
        _item('i1', 'o1'),
        _item('i2', 'o1', roundId: 'r1', name: 'Fries'),
      ],
      modifiers: const [],
      serviceRounds: [_round('r1', 'o1', status: 'accepted')],
    );
    expect(tickets, hasLength(1));
    expect(tickets.single.roundId, 'r1');
    expect(tickets.single.items.single.name, 'Fries');
  });

  test('a served parent with NO live rounds stays off the board entirely', () {
    final tickets = KdsTicketMapper.map(
      orders: [_order('o1', status: 'served')],
      orderItems: [_item('i1', 'o1')],
      modifiers: const [],
      serviceRounds: [_round('r1', 'o1', status: 'served')],
    );
    expect(tickets, isEmpty);
  });

  test('the PSC-001D red cancellation card keeps ALL items — round items '
      'included — as ONE order-level card', () {
    final tickets = KdsTicketMapper.map(
      orders: [
        _order(
          'o1',
          status: 'voided',
          extra: {
            'kitchen_ack_required': true,
            'kitchen_ack_at': null,
            'voided_at': '2026-07-22T11:00:00Z',
            'voided_from_status': 'preparing',
          },
        ),
      ],
      orderItems: [
        _item('i1', 'o1', status: 'voided'),
        _item('i2', 'o1', roundId: 'r1', status: 'voided', name: 'Fries'),
      ],
      modifiers: const [],
      serviceRounds: [_round('r1', 'o1', status: 'voided')],
    );
    expect(tickets, hasLength(1));
    final card = tickets.single;
    expect(card.status, KitchenTicketStatus.cancelled);
    expect(card.requiresAck, isTrue);
    expect(card.roundId, isNull); // the red card is ORDER-level
    expect(card.items, hasLength(2));
  });

  test('round rows are consumed money-free (no *_minor key is required)', () {
    final tickets = KdsTicketMapper.map(
      orders: [_order('o1')],
      orderItems: [_item('i2', 'o1', roundId: 'r1')],
      modifiers: const [],
      serviceRounds: [_round('r1', 'o1')],
    );
    expect(tickets.single.roundNumber, 2);
  });
}
