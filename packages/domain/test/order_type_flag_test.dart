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

  group('takeaway skip-served is consistent with RF-032 (read-only)', () {
    test('takeaway: ready -> completed is legal (skips served)', () {
      final order = _ready(OrderType.takeaway)..complete(paymentSettled: true);
      expect(order.status, OrderStatus.completed);
    });

    test('takeaway: serve() (ready -> served) is rejected', () {
      final order = _ready(OrderType.takeaway);
      expect(order.serve, throwsA(isA<IllegalOrderTransitionException>()));
      expect(order.status, OrderStatus.ready);
    });
  });

  group('dine-in path is consistent with RF-032 (read-only)', () {
    test('dine-in: ready -> served is legal', () {
      final order = _ready(OrderType.dineIn)..serve();
      expect(order.status, OrderStatus.served);
    });

    test(
      'dine-in: ready -> completed directly is rejected (must pass served)',
      () {
        final order = _ready(OrderType.dineIn);
        expect(
          () => order.complete(paymentSettled: true),
          throwsA(isA<IllegalOrderTransitionException>()),
        );
        expect(order.status, OrderStatus.ready);
      },
    );
  });
}
