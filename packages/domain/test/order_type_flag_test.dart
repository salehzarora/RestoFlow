import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

LocalOrder _order({OrderType type = OrderType.dineIn}) {
  final cart =
      Cart(
        orderId: 'o1',
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        currencyCode: 'ILS',
      )..addLine(
        CartLine.snapshot(
          lineId: 'l1',
          menuItemId: 'm1',
          itemNameSnapshot: 'Item',
          basePriceMinorSnapshot: 1000,
          currencyCodeSnapshot: 'ILS',
        ),
      );
  return LocalOrder.submitFromCart(cart, orderType: type);
}

LocalOrder _ready(OrderType type) => _order(type: type)
  ..accept()
  ..startPreparing()
  ..markReady();

void main() {
  group('order-type flag on placement (RF-035 AC#1)', () {
    test('dine-in placement exposes OrderType.dineIn', () {
      expect(OrderPlacement.dineIn('o1', 't1').orderType, OrderType.dineIn);
    });

    test('takeaway placement exposes OrderType.takeaway and no table', () {
      final p = OrderPlacement.takeaway('o1');
      expect(p.orderType, OrderType.takeaway);
      expect(p.tableId, isNull);
    });
  });

  // RESTAURANT-OPERATIONS-V1-001 (review B3): the lifecycle is SHARED — a
  // takeaway is served at pickup (displayed "Picked up") exactly like a
  // dine-in order is served at the table; neither type may jump ready ->
  // completed directly (server auto-completion is a settlement side effect,
  // not a manual transition).
  group(
    'the shared lifecycle is consistent with the aggregate (read-only)',
    () {
      for (final type in OrderType.values) {
        test('${type.name}: ready -> served -> completed is legal', () {
          final order = _ready(type)..serve();
          expect(order.status, OrderStatus.served);
          order.complete(paymentSettled: true);
          expect(order.status, OrderStatus.completed);
        });

        test('${type.name}: direct ready -> completed is rejected '
            '(must pass served)', () {
          final order = _ready(type);
          expect(
            () => order.complete(paymentSettled: true),
            throwsA(isA<IllegalOrderTransitionException>()),
          );
          expect(order.status, OrderStatus.ready);
        });
      }
    },
  );
}
