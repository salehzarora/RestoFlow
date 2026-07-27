import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// KITCHEN-PRINT-DUAL-001B: the KDS mapper now computes its whole-order kitchen
/// counts through the SHARED [aggregateOrderKitchenCounts]. These pin the count
/// cases the review calls out, driven through the REAL [KdsTicketMapper.map]:
/// modifier-quantity × item-quantity (once), additions/removals excluded from
/// counts, and station/exclusion filtering.
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
    String? status,
    Object? prep,
  }) => <String, dynamic>{
    'id': id,
    'order_id': orderId,
    'quantity': quantity,
    'station_id': station,
    'menu_item_name_snapshot': name,
    if (status != null) 'status': status,
    if (prep != null) 'prep_snapshot': prep,
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

  test('A: meat modifier quantity × item quantity, counted exactly once', () {
    // 1 (meat per selection) × 2 (modifier units) × 2 (item quantity) = 4.
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 2)],
      modifiers: [
        mod(
          'i1',
          'Extra patty',
          quantity: 2,
          meat: {'quantity': 1, 'unit': 'patty'},
        ),
      ],
    );
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 4, label: 'patty'),
    ]);
  });

  test('C: a bread/prep component multiplies by the item quantity once', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item(
          'i1',
          'o1',
          quantity: 3,
          prep: [
            {'name': 'bun', 'quantity': 1},
          ],
        ),
      ],
      modifiers: const [],
    );
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 3, label: 'bun'),
    ]);
  });

  test('D: additions/removals (no meat) never enter the meat counts', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [item('i1', 'o1', quantity: 1)],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'patty'}),
        mod('i1', 'Extra ketchup', quantity: 2), // addition, no meat
        mod('i1', 'No onion'), // removal, no meat
      ],
    );
    // Only the meat-bearing option counts: 2×1×1 = 2. The addition/removal add 0.
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 2, label: 'patty'),
    ]);
  });

  test('E: a SERVED (excluded) item leaves the board and adds no count', () {
    final tickets = KdsTicketMapper.map(
      orders: [order('o1')],
      orderItems: [
        item('i1', 'o1', quantity: 1, station: 'grill'),
        // Served -> excluded from the board AND from the counts.
        item('i2', 'o1', quantity: 1, station: 'bar', status: 'served'),
      ],
      modifiers: [
        mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'patty'}),
        mod('i2', 'Single', meat: {'quantity': 1, 'unit': 'patty'}),
      ],
    );
    // Only the active grill ticket exists; its count reflects i1 only (2), never
    // the served i2's Single.
    expect(tickets, hasLength(1));
    expect(tickets.single.stationId, 'grill');
    expect(tickets.single.kitchenCounts, [
      const KitchenCount(quantity: 2, label: 'patty'),
    ]);
  });

  test(
    'E2: the whole-unit total attaches to EACH station ticket of the unit',
    () {
      final tickets = KdsTicketMapper.map(
        orders: [order('o1')],
        orderItems: [
          item('i1', 'o1', quantity: 1, station: 'grill'),
          item('i2', 'o1', quantity: 1, station: 'bar'),
        ],
        modifiers: [
          mod('i1', 'Double', meat: {'quantity': 2, 'unit': 'patty'}),
          mod('i2', 'Single', meat: {'quantity': 1, 'unit': 'patty'}),
        ],
      );
      // Two station tickets; both carry the WHOLE work-unit total (2 + 1 = 3),
      // never a per-station slice.
      expect(tickets, hasLength(2));
      for (final t in tickets) {
        expect(t.kitchenCounts, [
          const KitchenCount(quantity: 3, label: 'patty'),
        ]);
      }
    },
  );
}
