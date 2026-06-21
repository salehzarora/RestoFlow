import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

LocalOrder _submit({OrderType type = OrderType.dineIn, int lines = 1}) {
  final cart = Cart(
    orderId: 'o',
    organizationId: 'org',
    restaurantId: 'rest',
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
  group('cancel requires a reason + is pre-production only (RF-032)', () {
    test('cancel with an empty reason throws MissingReasonException', () {
      final order = _submit();
      expect(
        () => order.cancel(reason: ''),
        throwsA(isA<MissingReasonException>()),
      );
      expect(order.status, OrderStatus.submitted);
    });

    test('submitted can be cancelled pre-production', () {
      final order = _submit()..cancel(reason: 'customer left');
      expect(order.status, OrderStatus.cancelled);
    });

    test('accepted can be cancelled pre-production', () {
      final order = _submit()..accept();
      order.cancel(reason: 'customer left');
      expect(order.status, OrderStatus.cancelled);
    });

    test('cancel is rejected once any item has started production', () {
      final order = _submit(lines: 2);
      order.items[0]
        ..queue()
        ..startPreparing(); // an item is now preparing
      expect(
        () => order.cancel(reason: 'too late'),
        throwsA(isA<CancelNotAllowedException>()),
      );
      expect(order.status, OrderStatus.submitted);
    });

    test('cancel is rejected when a completed payment exists (D-024)', () {
      final order = _submit();
      expect(
        () => order.cancel(reason: 'r', hasCompletedPayment: true),
        throwsA(isA<CompletedPaymentBlockException>()),
      );
      expect(order.status, OrderStatus.submitted);
    });
  });

  group('cancel is illegal outside submitted/accepted (RF-032)', () {
    test('preparing cannot be cancelled (only void)', () {
      final order = _submit()
        ..accept()
        ..startPreparing();
      expect(
        () => order.cancel(reason: 'r'),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });

    test('ready/served/completed cannot be cancelled', () {
      final ready = _submit()
        ..accept()
        ..startPreparing()
        ..markReady();
      expect(
        () => ready.cancel(reason: 'r'),
        throwsA(isA<IllegalOrderTransitionException>()),
      );

      final served = _submit()
        ..accept()
        ..startPreparing()
        ..markReady()
        ..serve();
      expect(
        () => served.cancel(reason: 'r'),
        throwsA(isA<IllegalOrderTransitionException>()),
      );

      final completed = _submit()
        ..accept()
        ..startPreparing()
        ..markReady()
        ..serve()
        ..complete(paymentSettled: true);
      expect(
        () => completed.cancel(reason: 'r'),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });

    test(
      'draft -> cancelled is rejected by the machine (no draft aggregate)',
      () {
        expect(
          () => OrderStateMachine.transition(
            OrderStatus.draft,
            OrderStatus.cancelled,
            OrderType.dineIn,
          ),
          throwsA(isA<IllegalOrderTransitionException>()),
        );
      },
    );
  });

  group('cancel cascade + terminal sink (RF-032)', () {
    test('cancel cascades pending/queued own items to cancelled', () {
      final order = _submit(lines: 2);
      order.items[0].queue(); // one queued, one still pending
      order.cancel(reason: 'customer left');
      expect(order.status, OrderStatus.cancelled);
      expect(
        order.items.every((i) => i.status == OrderItemStatus.cancelled),
        isTrue,
      );
    });

    test('a cancelled order accepts no further transition', () {
      final order = _submit()..cancel(reason: 'r');
      expect(order.accept, throwsA(isA<IllegalOrderTransitionException>()));
      expect(
        () => order.cancel(reason: 'r'),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });
  });
}
