import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

LocalOrder _submit({required OrderType type}) {
  final cart =
      Cart(
        orderId: 'o',
        organizationId: 'org',
        restaurantId: 'rest',
        currencyCode: 'ILS',
      )..addLine(
        CartLine.snapshot(
          lineId: 'l0',
          menuItemId: 'm0',
          itemNameSnapshot: 'Item 0',
          basePriceMinorSnapshot: 1000,
          currencyCodeSnapshot: 'ILS',
        ),
      );
  return LocalOrder.submitFromCart(cart, orderType: type);
}

LocalOrder _readyDineIn() => _submit(type: OrderType.dineIn)
  ..accept()
  ..startPreparing()
  ..markReady();

LocalOrder _readyTakeaway() => _submit(type: OrderType.takeaway)
  ..accept()
  ..startPreparing()
  ..markReady();

void main() {
  group('completion payment-settled seam (RF-032, D-025)', () {
    test('dine-in completion requires the injected paymentSettled = true', () {
      final order = _readyDineIn()..serve();
      expect(
        () => order.complete(paymentSettled: false),
        throwsA(isA<PaymentNotSettledException>()),
      );
      expect(order.status, OrderStatus.served);
    });

    test('dine-in served -> completed when paymentSettled is true', () {
      final order = _readyDineIn()..serve();
      order.complete(paymentSettled: true);
      expect(order.status, OrderStatus.completed);
    });

    test('takeaway ready -> completed requires paymentSettled = true', () {
      final blocked = _readyTakeaway();
      expect(
        () => blocked.complete(paymentSettled: false),
        throwsA(isA<PaymentNotSettledException>()),
      );

      final order = _readyTakeaway()..complete(paymentSettled: true);
      expect(order.status, OrderStatus.completed);
    });
  });

  group('takeaway skips served / dine-in does not (RF-032)', () {
    test('dine-in: full happy path ready -> served -> completed', () {
      final order = _readyDineIn();
      order.serve();
      expect(order.status, OrderStatus.served);
      order.complete(paymentSettled: true);
      expect(order.status, OrderStatus.completed);
    });

    test('takeaway: serve() is rejected (skips served)', () {
      final order = _readyTakeaway();
      expect(order.serve, throwsA(isA<IllegalOrderTransitionException>()));
      expect(order.status, OrderStatus.ready);
    });

    test('dine-in: ready -> completed is rejected (must pass served)', () {
      final order = _readyDineIn();
      expect(
        () => order.complete(paymentSettled: true),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
      expect(order.status, OrderStatus.ready);
    });

    test('a completed order is terminal (no further transition)', () {
      final order = _readyTakeaway()..complete(paymentSettled: true);
      expect(order.isTerminal, isTrue);
      expect(order.accept, throwsA(isA<IllegalOrderTransitionException>()));
    });
  });
}
