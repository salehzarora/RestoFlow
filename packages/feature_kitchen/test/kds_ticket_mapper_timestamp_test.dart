import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// DESIGN-001: the mapper's display-only submit-timestamp pluck.
///
/// `orders.created_at` (stable server insert time) wins; `client_created_at`
/// is the offline-client fallback; anything unparseable yields null so the
/// card shows NO elapsed pill rather than a fabricated age. The pluck stays
/// money-free — these are the only new keys read.
Map<String, dynamic> _order({Object? createdAt, Object? clientCreatedAt}) =>
    <String, dynamic>{
      'id': 'o1',
      'status': 'submitted',
      if (createdAt != null) 'created_at': createdAt,
      if (clientCreatedAt != null) 'client_created_at': clientCreatedAt,
    };

const Map<String, dynamic> _item = <String, dynamic>{
  'id': 'i1',
  'order_id': 'o1',
  'station_id': 'grill',
  'menu_item_name_snapshot': 'Burger',
  'quantity': 2,
};

List<KdsTicketView> _map(Map<String, dynamic> order) => KdsTicketMapper.map(
  orders: [order],
  orderItems: const [_item],
  modifiers: const [],
);

void main() {
  test('plucks orders.created_at as submittedAt', () {
    final tickets = _map(_order(createdAt: '2026-07-05T11:40:00Z'));
    expect(tickets, hasLength(1));
    expect(tickets.single.submittedAt, DateTime.parse('2026-07-05T11:40:00Z'));
  });

  test('falls back to client_created_at when created_at is unusable', () {
    final tickets = _map(
      _order(createdAt: 'not-a-date', clientCreatedAt: '2026-07-05T11:41:00Z'),
    );
    expect(tickets.single.submittedAt, DateTime.parse('2026-07-05T11:41:00Z'));
  });

  test('created_at wins over client_created_at when both parse', () {
    final tickets = _map(
      _order(
        createdAt: '2026-07-05T11:40:00Z',
        clientCreatedAt: '2026-07-05T09:00:00Z',
      ),
    );
    expect(tickets.single.submittedAt, DateTime.parse('2026-07-05T11:40:00Z'));
  });

  test('no usable timestamp -> null (no fabricated age)', () {
    expect(_map(_order()).single.submittedAt, isNull);
    expect(
      _map(_order(createdAt: 12345, clientCreatedAt: false)).single.submittedAt,
      isNull,
    );
  });
}
