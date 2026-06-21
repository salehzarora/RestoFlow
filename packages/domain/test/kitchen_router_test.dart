import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

const _auth = OrderActionAuthorization(canVoid: true, actorId: 'test-actor');

typedef _Item = ({String lineId, String menuItemId, String name, int qty});

LocalOrder _order({
  String orderId = 'o1',
  String org = 'org-1',
  String rest = 'rest-1',
  String? branch = 'branch-1',
  required List<_Item> items,
}) {
  final cart = Cart(
    orderId: orderId,
    organizationId: org,
    restaurantId: rest,
    branchId: branch,
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
        quantity: it.qty,
      ),
    );
  }
  return LocalOrder.submitFromCart(cart, orderType: OrderType.dineIn);
}

LocalOrderItem _item(LocalOrder order, String orderItemId) =>
    order.items.firstWhere((i) => i.orderItemId == orderItemId);

void main() {
  group('routing correctness (RF-033 AC#1)', () {
    test('explicit rules + default station route every active item once', () {
      final order = _order(
        items: const [
          (lineId: 'a', menuItemId: 'burger', name: 'Burger', qty: 1),
          (lineId: 'b', menuItemId: 'beer', name: 'Beer', qty: 2),
          (lineId: 'c', menuItemId: 'fries', name: 'Fries', qty: 1),
        ],
      );
      final rules = KitchenRoutingRules(
        itemStation: {'burger': 'grill', 'beer': 'bar'},
        defaultStationId: 'kitchen',
      );

      final result = KitchenRouter.route(order, rules);

      // One ticket per station, sorted by stationId.
      expect(result.tickets.map((t) => t.stationId), [
        'bar',
        'grill',
        'kitchen',
      ]);
      expect(result.routableItemCount, 3);
      expect(result.unroutableItems, isEmpty);

      // Each active item appears exactly once, on the right station.
      final bar = result.tickets.firstWhere((t) => t.stationId == 'bar');
      final grill = result.tickets.firstWhere((t) => t.stationId == 'grill');
      final kitchen = result.tickets.firstWhere(
        (t) => t.stationId == 'kitchen',
      );
      expect(bar.stationItems.single.orderItemId, 'b');
      expect(grill.stationItems.single.orderItemId, 'a'); // explicit wins
      expect(kitchen.stationItems.single.orderItemId, 'c'); // via default
    });

    test('explicit item rule wins over the default station', () {
      final order = _order(
        items: const [
          (lineId: 'a', menuItemId: 'burger', name: 'Burger', qty: 1),
        ],
      );
      final rules = KitchenRoutingRules(
        itemStation: {'burger': 'grill'},
        defaultStationId: 'kitchen',
      );
      final result = KitchenRouter.route(order, rules);
      expect(result.tickets.single.stationId, 'grill');
    });

    test('items for the same station share one ticket', () {
      final order = _order(
        items: const [
          (lineId: 'a', menuItemId: 'burger', name: 'Burger', qty: 1),
          (lineId: 'd', menuItemId: 'steak', name: 'Steak', qty: 1),
        ],
      );
      final rules = KitchenRoutingRules(
        itemStation: {'burger': 'grill', 'steak': 'grill'},
      );
      final result = KitchenRouter.route(order, rules);
      expect(result.tickets, hasLength(1));
      expect(
        result.tickets.single.stationItems.map((s) => s.orderItemId),
        ['a', 'd'], // sorted by orderItemId
      );
    });

    test('active item with no rule and no default is flagged, not dropped', () {
      final order = _order(
        items: const [
          (lineId: 'a', menuItemId: 'burger', name: 'Burger', qty: 1),
          (lineId: 'c', menuItemId: 'fries', name: 'Fries', qty: 1),
        ],
      );
      final rules = KitchenRoutingRules(itemStation: {'burger': 'grill'});

      final result = KitchenRouter.route(order, rules);

      // The routable item is unaffected by the unroutable one.
      expect(result.tickets.single.stationId, 'grill');
      expect(result.tickets.single.stationItems.single.orderItemId, 'a');
      // The unroutable item is present, not dropped.
      expect(result.unroutableItems, hasLength(1));
      final u = result.unroutableItems.single;
      expect(u.orderItemId, 'c');
      expect(u.menuItemId, 'fries');
      expect(u.itemNameSnapshot, 'Fries');
      expect(u.reason, 'no station rule and no default station');
    });

    test('routing does not throw on unroutable items', () {
      final order = _order(
        items: const [
          (lineId: 'c', menuItemId: 'fries', name: 'Fries', qty: 1),
        ],
      );
      expect(
        () => KitchenRouter.route(order, KitchenRoutingRules()),
        returnsNormally,
      );
    });

    test('cancelled/voided items are skipped, not flagged unroutable', () {
      final order = _order(
        items: const [
          (lineId: 'a', menuItemId: 'burger', name: 'Burger', qty: 1),
          (lineId: 'b', menuItemId: 'beer', name: 'Beer', qty: 1),
          (lineId: 'c', menuItemId: 'fries', name: 'Fries', qty: 1),
        ],
      );
      // b cancelled, c voided — both have NO rule, but must be skipped (not
      // unroutable) because they are inactive.
      _item(order, 'b').cancel('out of stock');
      _item(order, 'c').voidItem('comp', _auth);

      final rules = KitchenRoutingRules(itemStation: {'burger': 'grill'});
      final result = KitchenRouter.route(order, rules);

      expect(result.routableItemCount, 1);
      expect(result.tickets.single.stationItems.single.orderItemId, 'a');
      expect(result.unroutableItems, isEmpty); // b and c skipped, not flagged
    });

    test('station items carry the order-item name + quantity snapshot', () {
      final order = _order(
        items: const [
          (lineId: 'a', menuItemId: 'burger', name: 'Burger', qty: 3),
        ],
      );
      final rules = KitchenRoutingRules(itemStation: {'burger': 'grill'});
      final s = KitchenRouter.route(
        order,
        rules,
      ).tickets.single.stationItems.single;
      expect(s.itemNameSnapshot, 'Burger');
      expect(s.quantity, 3);
      expect(s.menuItemId, 'burger');
    });
  });
}
