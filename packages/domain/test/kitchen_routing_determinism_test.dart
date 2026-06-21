import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

typedef _Item = ({String lineId, String menuItemId, String name});

LocalOrder _order(List<_Item> items) {
  final cart = Cart(
    orderId: 'o1',
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-1',
    currencyCode: 'ILS',
  );
  for (final it in items) {
    cart.addLine(
      CartLine.snapshot(
        lineId: it.lineId,
        menuItemId: it.menuItemId,
        itemNameSnapshot: it.name,
        basePriceMinorSnapshot: 1000,
        currencyCodeSnapshot: 'ILS',
      ),
    );
  }
  return LocalOrder.submitFromCart(cart, orderType: OrderType.dineIn);
}

KitchenRoutingRules _rules() => KitchenRoutingRules(
  itemStation: {'burger': 'grill', 'beer': 'bar', 'steak': 'grill'},
  defaultStationId: 'kitchen',
);

const _items = <_Item>[
  (lineId: 'a', menuItemId: 'burger', name: 'Burger'),
  (lineId: 'b', menuItemId: 'beer', name: 'Beer'),
  (lineId: 'c', menuItemId: 'soup', name: 'Soup'), // -> default
  (lineId: 'd', menuItemId: 'steak', name: 'Steak'),
];

void main() {
  group('determinism / idempotence (RF-033 AC#3)', () {
    test('re-routing the same order + rules returns a value-equal result', () {
      final order = _order(_items);
      final r1 = KitchenRouter.route(order, _rules());
      final r2 = KitchenRouter.route(order, _rules());
      expect(r1, r2);
      expect(r1.hashCode, r2.hashCode);
    });

    test('ticket and station-item ids are deterministic composite keys', () {
      final result = KitchenRouter.route(_order(_items), _rules());
      final grill = result.tickets.firstWhere((t) => t.stationId == 'grill');
      expect(grill.kitchenTicketId, 'o1:grill');
      expect(grill.stationItems.map((s) => s.kitchenStationItemId), [
        'o1:grill:a',
        'o1:grill:d',
      ]);
      for (final item in grill.stationItems) {
        expect(item.kitchenTicketId, 'o1:grill');
      }
    });

    test('tickets sort by stationId; station items sort by orderItemId', () {
      final result = KitchenRouter.route(_order(_items), _rules());
      expect(result.tickets.map((t) => t.stationId), [
        'bar',
        'grill',
        'kitchen',
      ]);
      final grill = result.tickets.firstWhere((t) => t.stationId == 'grill');
      expect(grill.stationItems.map((s) => s.orderItemId), ['a', 'd']);
    });

    test('input item order does not change the routed result', () {
      final forward = KitchenRouter.route(_order(_items), _rules());
      final reversed = KitchenRouter.route(
        _order(_items.reversed.toList()),
        _rules(),
      );
      expect(forward, reversed);
    });
  });
}
