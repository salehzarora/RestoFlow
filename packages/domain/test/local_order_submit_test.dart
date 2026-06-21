import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

Cart _emptyCart() => Cart(
  orderId: 'order-1',
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  currencyCode: 'ILS',
);

CartLine _line(
  String id, {
  int basePriceMinor = 1000,
  int quantity = 1,
  List<ModifierOptionSnapshot> modifiers = const [],
}) => CartLine.snapshot(
  lineId: id,
  menuItemId: 'menu-$id',
  itemNameSnapshot: 'Item $id',
  basePriceMinorSnapshot: basePriceMinor,
  currencyCodeSnapshot: 'ILS',
  quantity: quantity,
  modifiers: modifiers,
);

void main() {
  group('LocalOrder.submitFromCart (RF-032)', () {
    test('an empty cart is rejected', () {
      expect(
        () => LocalOrder.submitFromCart(
          _emptyCart(),
          orderType: OrderType.dineIn,
        ),
        throwsA(isA<EmptyOrderException>()),
      );
    });

    test('a non-empty cart submits to status submitted', () {
      final cart = _emptyCart()..addLine(_line('a'));
      final order = LocalOrder.submitFromCart(
        cart,
        orderType: OrderType.dineIn,
      );
      expect(order.status, OrderStatus.submitted);
      expect(order.isTerminal, isFalse);
    });

    test('tenant scope, currency, orderId, and order type are copied', () {
      final cart = _emptyCart()..addLine(_line('a'));
      final order = LocalOrder.submitFromCart(
        cart,
        orderType: OrderType.takeaway,
      );
      expect(order.orderId, 'order-1');
      expect(order.organizationId, 'org-1');
      expect(order.restaurantId, 'rest-1');
      expect(order.branchId, 'branch-1');
      expect(order.currencyCode, 'ILS');
      expect(order.orderType, OrderType.takeaway);
    });

    test('the cart subtotal is carried as the integer preview', () {
      final cart = _emptyCart()
        ..addLine(_line('a', basePriceMinor: 1000, quantity: 2)) // 2000
        ..addLine(_line('b', basePriceMinor: 1500)); // 1500
      final order = LocalOrder.submitFromCart(
        cart,
        orderType: OrderType.dineIn,
      );
      expect(order.subtotalMinorPreview, cart.subtotalMinor);
      expect(order.subtotalMinorPreview, 3500);
      expect(order.subtotalMinorPreview, isA<int>());
    });

    test(
      'order items are created from cart lines (initial status pending)',
      () {
        final cart = _emptyCart()
          ..addLine(_line('a'))
          ..addLine(_line('b'));
        final order = LocalOrder.submitFromCart(
          cart,
          orderType: OrderType.dineIn,
        );
        expect(order.items, hasLength(2));
        expect(
          order.items.every((i) => i.status == OrderItemStatus.pending),
          isTrue,
        );
        expect(order.items.map((i) => i.orderItemId), ['a', 'b']);
      },
    );

    test('item price/name snapshots and line-total preview are copied', () {
      final cart = _emptyCart()
        ..addLine(_line('a', basePriceMinor: 1200, quantity: 3));
      final order = LocalOrder.submitFromCart(
        cart,
        orderType: OrderType.dineIn,
      );
      final item = order.items.single;
      expect(item.menuItemId, 'menu-a');
      expect(item.itemNameSnapshot, 'Item a');
      expect(item.basePriceMinorSnapshot, 1200);
      expect(item.currencyCodeSnapshot, 'ILS');
      expect(item.quantity, 3);
      expect(item.lineTotalMinorPreview, 3600); // 1200 * 3
    });

    test('modifier snapshots are copied onto the order item', () {
      final cart = _emptyCart()
        ..addLine(
          _line(
            'a',
            modifiers: [
              ModifierOptionSnapshot(
                modifierId: 'mod-1',
                modifierNameSnapshot: 'Cheese',
                optionId: 'opt-1',
                optionNameSnapshot: 'Extra cheese',
                priceDeltaMinorSnapshot: 200,
                quantity: 2,
              ),
            ],
          ),
        );
      final order = LocalOrder.submitFromCart(
        cart,
        orderType: OrderType.dineIn,
      );
      final mod = order.items.single.modifiers.single;
      expect(mod.optionNameSnapshot, 'Extra cheese');
      expect(mod.priceDeltaMinorSnapshot, 200);
      expect(mod.quantity, 2);
      expect(mod.extendedPriceMinor, 400);
    });

    test('the items list is read-only', () {
      final cart = _emptyCart()..addLine(_line('a'));
      final order = LocalOrder.submitFromCart(
        cart,
        orderType: OrderType.dineIn,
      );
      expect(
        () => order.items.add(LocalOrderItem.fromCartLine(_line('b'))),
        throwsUnsupportedError,
      );
    });
  });
}
