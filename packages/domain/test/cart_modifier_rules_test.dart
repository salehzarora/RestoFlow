import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// RF-031 minimal modifier rule enforcement: RF-030 stores `min_select` /
/// `max_select` / `is_required` on modifier groups but does not enforce them;
/// the cart enforces them at add-to-cart time.
ModifierOptionSnapshot _opt(String optionId, {String modifierId = 'mod-1'}) =>
    ModifierOptionSnapshot(
      modifierId: modifierId,
      modifierNameSnapshot: 'Sauce',
      optionId: optionId,
      optionNameSnapshot: 'Option $optionId',
      priceDeltaMinorSnapshot: 100,
    );

CartLine _lineWith(
  List<ModifierOptionSnapshot> modifiers,
  List<ModifierRule> rules,
) => CartLine.snapshot(
  lineId: 'l1',
  menuItemId: 'item-1',
  itemNameSnapshot: 'Dish',
  basePriceMinorSnapshot: 1000,
  currencyCodeSnapshot: 'ILS',
  modifiers: modifiers,
  modifierRules: rules,
);

void main() {
  group('modifier rule validation (RF-031)', () {
    const requiredRule = ModifierRule(
      modifierId: 'mod-1',
      modifierName: 'Sauce',
      isRequired: true,
    );

    test('required group with no selection fails', () {
      expect(
        () => _lineWith([], [requiredRule]),
        throwsA(isA<InvalidModifierSelectionException>()),
      );
    });

    test('below minSelect fails', () {
      const rule = ModifierRule(
        modifierId: 'mod-1',
        modifierName: 'Sauce',
        minSelect: 2,
        maxSelect: 3,
      );
      expect(
        () => _lineWith([_opt('a')], [rule]),
        throwsA(isA<InvalidModifierSelectionException>()),
      );
    });

    test('above maxSelect fails', () {
      const rule = ModifierRule(
        modifierId: 'mod-1',
        modifierName: 'Sauce',
        maxSelect: 1,
      );
      expect(
        () => _lineWith([_opt('a'), _opt('b')], [rule]),
        throwsA(isA<InvalidModifierSelectionException>()),
      );
    });

    test('a valid selection passes', () {
      const rule = ModifierRule(
        modifierId: 'mod-1',
        modifierName: 'Sauce',
        isRequired: true,
        minSelect: 1,
        maxSelect: 2,
      );
      final line = _lineWith([_opt('a')], [rule]);
      expect(line.modifiers, hasLength(1));
      expect(line.unitPriceMinor, 1100); // 1000 + 100
    });

    test('maxSelect of 0 means unbounded (no upper-bound failure)', () {
      const rule = ModifierRule(
        modifierId: 'mod-1',
        modifierName: 'Sauce',
        maxSelect: 0,
      );
      final line = _lineWith([_opt('a'), _opt('b'), _opt('c')], [rule]);
      expect(line.modifiers, hasLength(3));
    });

    test('rules only constrain their own modifier group', () {
      const rule = ModifierRule(
        modifierId: 'mod-1',
        modifierName: 'Sauce',
        isRequired: true,
      );
      // A selection in a different group does not satisfy mod-1's requirement.
      expect(
        () => _lineWith([_opt('x', modifierId: 'mod-2')], [rule]),
        throwsA(isA<InvalidModifierSelectionException>()),
      );
    });
  });
}
