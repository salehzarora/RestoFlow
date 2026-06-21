import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

LocalOrder _order({String? branch}) {
  final cart =
      Cart(
        orderId: 'o1',
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: branch,
        currencyCode: 'ILS',
      )..addLine(
        CartLine.snapshot(
          lineId: 'a',
          menuItemId: 'burger',
          itemNameSnapshot: 'Burger',
          basePriceMinorSnapshot: 1000,
          currencyCodeSnapshot: 'ILS',
        ),
      );
  return LocalOrder.submitFromCart(cart, orderType: OrderType.dineIn);
}

final _rules = KitchenRoutingRules(itemStation: {'burger': 'grill'});

void main() {
  group('tenant/station field presence (RF-033 AC#2)', () {
    test('tickets and station items carry org/restaurant/station + branch '
        '(non-null branch)', () {
      final result = KitchenRouter.route(_order(branch: 'branch-1'), _rules);

      final ticket = result.tickets.single;
      expect(ticket.organizationId, 'org-1');
      expect(ticket.restaurantId, 'rest-1');
      expect(ticket.branchId, 'branch-1');
      expect(ticket.stationId, 'grill');

      final item = ticket.stationItems.single;
      expect(item.organizationId, 'org-1');
      expect(item.restaurantId, 'rest-1');
      expect(item.branchId, 'branch-1');
      expect(item.stationId, 'grill');
    });

    test('branch field is present and null when the order has no branch', () {
      final result = KitchenRouter.route(_order(branch: null), _rules);

      final ticket = result.tickets.single;
      expect(ticket.organizationId, 'org-1');
      expect(ticket.restaurantId, 'rest-1');
      expect(ticket.branchId, isNull);
      expect(ticket.stationId, 'grill');

      final item = ticket.stationItems.single;
      expect(item.organizationId, 'org-1');
      expect(item.restaurantId, 'rest-1');
      expect(item.branchId, isNull);
      expect(item.stationId, 'grill');
    });

    test(
      'unroutable items carry order/branch context (null branch allowed)',
      () {
        final result = KitchenRouter.route(
          _order(branch: null),
          KitchenRoutingRules(), // no rule, no default -> unroutable
        );
        final u = result.unroutableItems.single;
        expect(u.orderId, 'o1');
        expect(u.orderItemId, 'a');
        expect(u.branchId, isNull);
      },
    );
  });
}
