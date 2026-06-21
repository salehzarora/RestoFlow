import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

void main() {
  group('CartLine integer totals (RF-031, D-007)', () {
    test('unit price sums base + size + variant + modifier deltas', () {
      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: 'Burger',
        basePriceMinorSnapshot: 5000,
        currencyCodeSnapshot: 'ILS',
        sizeId: 'sz-large',
        sizeNameSnapshot: 'Large',
        sizePriceDeltaMinorSnapshot: 700,
        variantId: 'var-spicy',
        variantNameSnapshot: 'Spicy',
        variantPriceDeltaMinorSnapshot: 150,
        modifiers: [
          ModifierOptionSnapshot(
            modifierId: 'mod-cheese',
            modifierNameSnapshot: 'Cheese',
            optionId: 'opt-extra',
            optionNameSnapshot: 'Extra cheese',
            priceDeltaMinorSnapshot: 200,
            quantity: 2, // 200 * 2 = 400
          ),
        ],
      );

      // 5000 + 700 + 150 + (200 * 2) = 6250
      expect(line.unitPriceMinor, 6250);
      expect(line.unitPriceMinor, isA<int>());
    });

    test('line total multiplies unit price by quantity', () {
      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: 'Fries',
        basePriceMinorSnapshot: 1200,
        currencyCodeSnapshot: 'ILS',
        quantity: 3,
      );

      expect(line.lineTotalMinor, 3600); // 1200 * 3
      expect(line.lineTotalMinor, isA<int>());
    });

    test('modifier-option quantity multiplies the delta', () {
      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: 'Coffee',
        basePriceMinorSnapshot: 1000,
        currencyCodeSnapshot: 'ILS',
        modifiers: [
          ModifierOptionSnapshot(
            modifierId: 'mod-shot',
            modifierNameSnapshot: 'Extra shot',
            optionId: 'opt-shot',
            optionNameSnapshot: 'Shot',
            priceDeltaMinorSnapshot: 300,
            quantity: 3, // 300 * 3 = 900
          ),
        ],
        quantity: 2,
      );

      // (1000 + 900) * 2 = 3800
      expect(line.lineTotalMinor, 3800);
    });

    test('size/variant are optional and default to no delta', () {
      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: 'Water',
        basePriceMinorSnapshot: 500,
        currencyCodeSnapshot: 'ILS',
      );

      expect(line.size, isNull);
      expect(line.variant, isNull);
      expect(line.unitPriceMinor, 500);
    });
  });

  group('CartLine quantity validation (RF-031)', () {
    test('zero quantity is rejected', () {
      expect(
        () => CartLine.snapshot(
          lineId: 'l1',
          menuItemId: 'item-1',
          itemNameSnapshot: 'X',
          basePriceMinorSnapshot: 100,
          currencyCodeSnapshot: 'ILS',
          quantity: 0,
        ),
        throwsA(isA<InvalidQuantityException>()),
      );
    });

    test('negative quantity is rejected', () {
      expect(
        () => CartLine.snapshot(
          lineId: 'l1',
          menuItemId: 'item-1',
          itemNameSnapshot: 'X',
          basePriceMinorSnapshot: 100,
          currencyCodeSnapshot: 'ILS',
          quantity: -1,
        ),
        throwsA(isA<InvalidQuantityException>()),
      );
    });

    test('a modifier option with quantity < 1 is rejected', () {
      expect(
        () => ModifierOptionSnapshot(
          modifierId: 'm',
          modifierNameSnapshot: 'M',
          optionId: 'o',
          optionNameSnapshot: 'O',
          priceDeltaMinorSnapshot: 100,
          quantity: 0,
        ),
        throwsA(isA<InvalidQuantityException>()),
      );
    });

    test('withQuantity rejects a non-positive quantity', () {
      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: 'X',
        basePriceMinorSnapshot: 100,
        currencyCodeSnapshot: 'ILS',
      );
      expect(
        () => line.withQuantity(0),
        throwsA(isA<InvalidQuantityException>()),
      );
    });
  });
}
