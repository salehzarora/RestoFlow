import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

const _auth = OrderActionAuthorization(canVoid: true, actorId: 'test-actor');

LocalOrder _submit({OrderType type = OrderType.dineIn, int lines = 1}) {
  final cart = Cart(
    orderId: 'o',
    organizationId: 'org',
    restaurantId: 'rest',
    branchId: 'br',
    currencyCode: 'ILS',
  );
  for (var i = 0; i < lines; i++) {
    cart.addLine(
      CartLine.snapshot(
        lineId: 'l$i',
        menuItemId: 'm$i',
        itemNameSnapshot: 'Item $i',
        basePriceMinorSnapshot: 1000,
        currencyCodeSnapshot: 'ILS',
      ),
    );
  }
  return LocalOrder.submitFromCart(cart, orderType: type);
}

void main() {
  group('void requires reason + placeholder authorization (RF-032)', () {
    test('void with an empty reason throws MissingReasonException', () {
      final order = _submit();
      expect(
        () => order.voidOrder(reason: '  ', authorization: _auth),
        throwsA(isA<MissingReasonException>()),
      );
      expect(order.status, OrderStatus.submitted);
    });

    test('void without an authorization throws UnauthorizedVoidException', () {
      final order = _submit();
      expect(
        () => order.voidOrder(reason: 'mistake', authorization: null),
        throwsA(isA<UnauthorizedVoidException>()),
      );
    });

    test('authorization that does not permit voiding is rejected', () {
      final order = _submit();
      expect(
        () => order.voidOrder(
          reason: 'mistake',
          authorization: const OrderActionAuthorization(
            canVoid: false,
            actorId: 'cashier',
          ),
        ),
        throwsA(isA<UnauthorizedVoidException>()),
      );
    });
  });

  group('void is post-submission only (RF-032)', () {
    test('submitted/accepted/preparing/ready/served can be voided', () {
      // submitted
      expect(
        (_submit()..voidOrder(reason: 'r', authorization: _auth)).status,
        OrderStatus.voided,
      );
      // accepted
      final accepted = _submit()..accept();
      accepted.voidOrder(reason: 'r', authorization: _auth);
      expect(accepted.status, OrderStatus.voided);
      // preparing
      final preparing = _submit()
        ..accept()
        ..startPreparing();
      preparing.voidOrder(reason: 'r', authorization: _auth);
      expect(preparing.status, OrderStatus.voided);
      // ready
      final ready = _submit()
        ..accept()
        ..startPreparing()
        ..markReady();
      ready.voidOrder(reason: 'r', authorization: _auth);
      expect(ready.status, OrderStatus.voided);
      // served (dine-in)
      final served = _submit()
        ..accept()
        ..startPreparing()
        ..markReady()
        ..serve();
      served.voidOrder(reason: 'r', authorization: _auth);
      expect(served.status, OrderStatus.voided);
    });

    test('a completed order cannot be voided', () {
      final order = _submit()
        ..accept()
        ..startPreparing()
        ..markReady()
        ..serve()
        ..complete(paymentSettled: true);
      expect(
        () => order.voidOrder(reason: 'r', authorization: _auth),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
      expect(order.status, OrderStatus.completed);
    });
  });

  group('completed payment blocks void (RF-032, D-024)', () {
    test('void is rejected when hasCompletedPayment is true', () {
      final order = _submit();
      expect(
        () => order.voidOrder(
          reason: 'r',
          authorization: _auth,
          hasCompletedPayment: true,
        ),
        throwsA(isA<CompletedPaymentBlockException>()),
      );
      expect(order.status, OrderStatus.submitted);
    });
  });

  group('void cascade + terminal sink (RF-032)', () {
    test('void cascades the order own non-terminal items to voided', () {
      final order = _submit(lines: 2);
      // drive one item into production so it is still non-terminal
      order.items[0]
        ..queue()
        ..startPreparing();
      order.voidOrder(reason: 'r', authorization: _auth);
      expect(order.status, OrderStatus.voided);
      expect(
        order.items.every((i) => i.status == OrderItemStatus.voided),
        isTrue,
      );
    });

    test('a voided order accepts no further transition', () {
      final order = _submit()..voidOrder(reason: 'r', authorization: _auth);
      expect(order.accept, throwsA(isA<IllegalOrderTransitionException>()));
      expect(
        () => order.voidOrder(reason: 'r', authorization: _auth),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });

    test('draft -> voided is rejected by the machine (no draft aggregate)', () {
      expect(
        () => OrderStateMachine.transition(
          OrderStatus.draft,
          OrderStatus.voided,
          OrderType.dineIn,
        ),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });
  });
}
