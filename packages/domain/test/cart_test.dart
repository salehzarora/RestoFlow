import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

Cart _emptyCart({String currency = 'ILS'}) => Cart(
  orderId: 'order-1',
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  currencyCode: currency,
);

CartLine _line(
  String lineId, {
  int basePriceMinor = 1000,
  int quantity = 1,
  String currency = 'ILS',
}) => CartLine.snapshot(
  lineId: lineId,
  menuItemId: 'item-$lineId',
  itemNameSnapshot: 'Item $lineId',
  basePriceMinorSnapshot: basePriceMinor,
  currencyCodeSnapshot: currency,
  quantity: quantity,
);

void main() {
  group('Cart aggregate basics (RF-031)', () {
    test('orderId is injected and tenant scope is carried', () {
      final cart = _emptyCart();
      expect(cart.orderId, 'order-1');
      expect(cart.organizationId, 'org-1');
      expect(cart.restaurantId, 'rest-1');
      expect(cart.branchId, 'branch-1');
      expect(cart.currencyCode, 'ILS');
      expect(cart.isEmpty, isTrue);
    });

    test('branchId may be null', () {
      final cart = Cart(
        orderId: 'o',
        organizationId: 'org',
        restaurantId: 'rest',
        currencyCode: 'ILS',
      );
      expect(cart.branchId, isNull);
    });

    test('lines are exposed read-only', () {
      final cart = _emptyCart()..addLine(_line('a'));
      expect(cart.lines, hasLength(1));
      expect(() => cart.lines.add(_line('b')), throwsUnsupportedError);
    });
  });

  group('order-level / item-level structure + subtotal (RF-031)', () {
    test('subtotal is the sum of line totals', () {
      final cart = _emptyCart()
        ..addLine(_line('a', basePriceMinor: 1000, quantity: 2)) // 2000
        ..addLine(_line('b', basePriceMinor: 1500, quantity: 1)); // 1500
      expect(cart.lineCount, 2);
      expect(cart.subtotalMinor, 3500);
      expect(cart.subtotalMinor, isA<int>());
    });

    test('removing a line updates the subtotal', () {
      final cart = _emptyCart()
        ..addLine(_line('a', basePriceMinor: 1000)) // 1000
        ..addLine(_line('b', basePriceMinor: 2000)); // 2000
      expect(cart.subtotalMinor, 3000);

      cart.removeLine('a');
      expect(cart.lineCount, 1);
      expect(cart.subtotalMinor, 2000);
    });

    test('changing quantity updates the subtotal', () {
      final cart = _emptyCart()..addLine(_line('a', basePriceMinor: 1000));
      expect(cart.subtotalMinor, 1000);

      cart.changeQuantity('a', 5);
      expect(cart.subtotalMinor, 5000);
    });

    test('empty cart has a zero subtotal', () {
      expect(_emptyCart().subtotalMinor, 0);
    });
  });

  group('single-currency invariant (RF-031, Q-007)', () {
    test('a line with a different currency is rejected', () {
      final cart = _emptyCart(currency: 'ILS');
      expect(
        () => cart.addLine(_line('a', currency: 'USD')),
        throwsA(isA<CurrencyMismatchException>()),
      );
      expect(cart.isEmpty, isTrue);
    });

    test('a matching-currency line is accepted', () {
      final cart = _emptyCart(currency: 'ILS');
      cart.addLine(_line('a', currency: 'ILS'));
      expect(cart.lineCount, 1);
    });

    test('an empty cart currency is rejected at construction', () {
      expect(
        () => Cart(
          orderId: 'o',
          organizationId: 'org',
          restaurantId: 'rest',
          currencyCode: '',
        ),
        throwsA(isA<CurrencyMismatchException>()),
      );
    });
  });

  group('line lookup errors (RF-031)', () {
    test('duplicate lineId is rejected', () {
      final cart = _emptyCart()..addLine(_line('a'));
      expect(
        () => cart.addLine(_line('a')),
        throwsA(isA<DuplicateLineException>()),
      );
    });

    test('removing an unknown line throws', () {
      expect(
        () => _emptyCart().removeLine('nope'),
        throwsA(isA<LineNotFoundException>()),
      );
    });

    test('changing quantity of an unknown line throws', () {
      expect(
        () => _emptyCart().changeQuantity('nope', 2),
        throwsA(isA<LineNotFoundException>()),
      );
    });

    test('changing quantity to a non-positive value throws', () {
      final cart = _emptyCart()..addLine(_line('a'));
      expect(
        () => cart.changeQuantity('a', 0),
        throwsA(isA<InvalidQuantityException>()),
      );
    });
  });
}
