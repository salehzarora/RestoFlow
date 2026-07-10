import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// KDS-FIFO-001: tickets must be ordered OLDEST submitted first so the kitchen
/// can trust that the top of each column is the next ticket to handle — never
/// by the (random UUID) ticket id as the primary key.

Map<String, dynamic> _order(String id, String? createdAt) => <String, dynamic>{
  'id': id,
  'status': 'submitted',
  if (createdAt != null) 'created_at': createdAt,
};

Map<String, dynamic> _item(String orderId) => <String, dynamic>{
  'id': 'i-$orderId',
  'order_id': orderId,
  'station_id': 'grill',
  'menu_item_name_snapshot': 'Burger',
  'quantity': 1,
};

KdsTicketView _ticket(String id, DateTime? submittedAt) => KdsTicketView(
  kitchenTicketId: id,
  stationId: 's',
  items: const [],
  submittedAt: submittedAt,
);

void main() {
  group('KdsTicketMapper FIFO ordering', () {
    test('orders tickets oldest submittedAt first — NOT by ticket id', () {
      // Ids are chosen so alphabetical id order (a-new < m-mid < z-old) is the
      // REVERSE of arrival order (z-old is oldest): a time sort must win.
      final tickets = KdsTicketMapper.map(
        orders: [
          _order('a-new', '2026-07-05T10:10:00Z'),
          _order('z-old', '2026-07-05T10:00:00Z'),
          _order('m-mid', '2026-07-05T10:05:00Z'),
        ],
        orderItems: [_item('a-new'), _item('z-old'), _item('m-mid')],
        modifiers: const [],
      );

      expect(tickets.map((t) => t.kitchenTicketId), [
        'z-old:grill', // oldest (10:00)
        'm-mid:grill', // 10:05
        'a-new:grill', // newest (10:10)
      ]);
    });

    test('a ticket with no timestamp sorts AFTER dated tickets', () {
      final tickets = KdsTicketMapper.map(
        orders: [
          _order('no-ts', null),
          _order('dated', '2026-07-05T10:00:00Z'),
        ],
        orderItems: [_item('no-ts'), _item('dated')],
        modifiers: const [],
      );

      expect(tickets.map((t) => t.kitchenTicketId), [
        'dated:grill',
        'no-ts:grill',
      ]);
    });

    test('two undated tickets are ordered deterministically by id', () {
      final tickets = KdsTicketMapper.map(
        orders: [_order('bbb', null), _order('aaa', null)],
        orderItems: [_item('bbb'), _item('aaa')],
        modifiers: const [],
      );

      expect(tickets.map((t) => t.kitchenTicketId), ['aaa:grill', 'bbb:grill']);
    });
  });

  group('KdsTicketView.compareByOldestFirst', () {
    final t10 = DateTime.utc(2026, 7, 5, 10);
    final t11 = DateTime.utc(2026, 7, 5, 11);

    test('older submittedAt sorts before newer', () {
      expect(
        KdsTicketView.compareByOldestFirst(
          _ticket('x', t10),
          _ticket('y', t11),
        ),
        isNegative,
      );
      expect(
        KdsTicketView.compareByOldestFirst(
          _ticket('x', t11),
          _ticket('y', t10),
        ),
        isPositive,
      );
    });

    test('an undated ticket sorts after a dated one', () {
      expect(
        KdsTicketView.compareByOldestFirst(
          _ticket('x', t10),
          _ticket('y', null),
        ),
        isNegative,
      );
      expect(
        KdsTicketView.compareByOldestFirst(
          _ticket('x', null),
          _ticket('y', t10),
        ),
        isPositive,
      );
    });

    test('equal times, and both-null, break deterministically on id', () {
      expect(
        KdsTicketView.compareByOldestFirst(
          _ticket('a', t10),
          _ticket('b', t10),
        ),
        isNegative,
      );
      expect(
        KdsTicketView.compareByOldestFirst(
          _ticket('b', null),
          _ticket('a', null),
        ),
        isPositive,
      );
    });

    test('sorting a scrambled list is stable and oldest-first', () {
      final list = [
        _ticket('a-new', t11),
        _ticket('z-old', t10),
        _ticket('b-undated', null),
        _ticket('a-undated', null),
      ]..sort(KdsTicketView.compareByOldestFirst);
      expect(list.map((t) => t.kitchenTicketId), [
        'z-old', // dated, oldest
        'a-new', // dated, newer
        'a-undated', // undated, id tie-break
        'b-undated',
      ]);
    });
  });
}
