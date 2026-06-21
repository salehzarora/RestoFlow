import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// RF-031 acceptance #1 (DECISION D-008): adding an item snapshots its price
/// and modifier prices; later menu price/name changes do not alter the existing
/// cart line.
void main() {
  group('snapshot immutability (RF-031, D-008)', () {
    test('a later menu price change does not reprice an existing line', () {
      // Original menu values at add-to-cart time.
      const originalName = 'Burger';
      const originalBaseMinor = 5000;
      const originalOptionDelta = 200;

      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: originalName,
        basePriceMinorSnapshot: originalBaseMinor,
        currencyCodeSnapshot: 'ILS',
        modifiers: [
          ModifierOptionSnapshot(
            modifierId: 'mod-cheese',
            modifierNameSnapshot: 'Cheese',
            optionId: 'opt-extra',
            optionNameSnapshot: 'Extra cheese',
            priceDeltaMinorSnapshot: originalOptionDelta,
          ),
        ],
        quantity: 2,
      );

      final totalBefore = line.lineTotalMinor; // (5000 + 200) * 2 = 10400

      // Simulate the menu changing AFTER the line was added (e.g. a fresh pull
      // or a MenuRepository.updateItem): a brand-new line built from the new
      // values. The original line holds no live reference to any menu row, so
      // it must be entirely unaffected.
      final repricedLine = CartLine.snapshot(
        lineId: 'l2',
        menuItemId: 'item-1',
        itemNameSnapshot: 'Burger (new recipe)',
        basePriceMinorSnapshot: 9999,
        currencyCodeSnapshot: 'ILS',
        modifiers: [
          ModifierOptionSnapshot(
            modifierId: 'mod-cheese',
            modifierNameSnapshot: 'Cheese',
            optionId: 'opt-extra',
            optionNameSnapshot: 'Extra cheese',
            priceDeltaMinorSnapshot: 1000,
          ),
        ],
        quantity: 2,
      );

      // The existing line is unchanged...
      expect(line.itemNameSnapshot, originalName);
      expect(line.basePriceMinorSnapshot, originalBaseMinor);
      expect(
        line.modifiers.single.priceDeltaMinorSnapshot,
        originalOptionDelta,
      );
      expect(line.lineTotalMinor, totalBefore);
      expect(line.lineTotalMinor, 10400);
      // ...and the new line reflects the new prices independently.
      expect(repricedLine.lineTotalMinor, (9999 + 1000) * 2);
      expect(line.lineTotalMinor, isNot(repricedLine.lineTotalMinor));
    });

    test(
      'mutating the source modifier list after add does not affect the line',
      () {
        final sourceModifiers = <ModifierOptionSnapshot>[
          ModifierOptionSnapshot(
            modifierId: 'm',
            modifierNameSnapshot: 'M',
            optionId: 'o1',
            optionNameSnapshot: 'O1',
            priceDeltaMinorSnapshot: 100,
          ),
        ];

        final line = CartLine.snapshot(
          lineId: 'l1',
          menuItemId: 'item-1',
          itemNameSnapshot: 'X',
          basePriceMinorSnapshot: 1000,
          currencyCodeSnapshot: 'ILS',
          modifiers: sourceModifiers,
        );

        // Caller keeps editing its own list afterwards.
        sourceModifiers.add(
          ModifierOptionSnapshot(
            modifierId: 'm',
            modifierNameSnapshot: 'M',
            optionId: 'o2',
            optionNameSnapshot: 'O2',
            priceDeltaMinorSnapshot: 9999,
          ),
        );

        expect(line.modifiers, hasLength(1));
        expect(line.unitPriceMinor, 1100); // 1000 + 100, not affected by o2
      },
    );

    test('the line modifier list is read-only', () {
      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: 'X',
        basePriceMinorSnapshot: 1000,
        currencyCodeSnapshot: 'ILS',
      );
      expect(
        () => line.modifiers.add(
          ModifierOptionSnapshot(
            modifierId: 'm',
            modifierNameSnapshot: 'M',
            optionId: 'o',
            optionNameSnapshot: 'O',
            priceDeltaMinorSnapshot: 1,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('withQuantity preserves all price/name snapshots', () {
      final line = CartLine.snapshot(
        lineId: 'l1',
        menuItemId: 'item-1',
        itemNameSnapshot: 'Burger',
        basePriceMinorSnapshot: 5000,
        currencyCodeSnapshot: 'ILS',
        sizeId: 'sz',
        sizeNameSnapshot: 'Large',
        sizePriceDeltaMinorSnapshot: 700,
      );

      final requantified = line.withQuantity(4);

      expect(requantified.item, line.item);
      expect(requantified.size, line.size);
      expect(requantified.basePriceMinorSnapshot, 5000);
      expect(requantified.lineTotalMinor, (5000 + 700) * 4);
    });
  });
}
