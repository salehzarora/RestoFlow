import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// KITCHEN-MEAT-001: the meat value type, tolerant parser, and the whole-order
/// meat rollup (grouped by unit). Nothing is derived from a name/price — only
/// configured meta is aggregated. Non-money (D-007): quantity is a count.
void main() {
  group('KitchenMeat.tryFromJson', () {
    test('parses an object, preserving Arabic units', () {
      expect(
        KitchenMeat.tryFromJson({'quantity': 2, 'unit': 'قطع'}),
        const KitchenMeat(quantity: 2, unit: 'قطع'),
      );
      expect(
        KitchenMeat.tryFromJson({'quantity': '300', 'unit': ' g '}),
        const KitchenMeat(quantity: 300, unit: 'g'),
      );
    });

    test('returns null for non-object / non-positive / missing quantity', () {
      expect(KitchenMeat.tryFromJson(null), isNull);
      expect(KitchenMeat.tryFromJson('x'), isNull);
      expect(KitchenMeat.tryFromJson([]), isNull);
      expect(KitchenMeat.tryFromJson({'unit': 'قطع'}), isNull);
      expect(KitchenMeat.tryFromJson({'quantity': 0, 'unit': 'قطع'}), isNull);
      expect(KitchenMeat.tryFromJson({'quantity': -1}), isNull);
    });

    test('toJson round-trips', () {
      const meat = KitchenMeat(quantity: 2, unit: 'قطع');
      expect(KitchenMeat.tryFromJson(meat.toJson()), meat);
    });
  });

  group('aggregateMeatByUnit', () {
    MeatContribution c(num qty, String unit, int factor) => MeatContribution(
      meat: KitchenMeat(quantity: qty, unit: unit),
      factor: factor,
    );

    test('4 double + 1 single = 9 patties (the canonical example)', () {
      // A Double option = 2 patties on 4 items; a Single = 1 patty on 1 item.
      final totals = aggregateMeatByUnit([
        c(2, 'patties', 4),
        c(1, 'patties', 1),
      ]);
      expect(totals, [const KitchenMeat(quantity: 9, unit: 'patties')]);
    });

    test('different units yield SEPARATE totals (stable first-seen order)', () {
      final totals = aggregateMeatByUnit([
        c(2, 'قطع', 4), // 8 قطع
        c(300, 'g', 4), // 1200 g
        c(1, 'قطع', 1), // +1 قطع => 9 قطع
      ]);
      expect(totals, [
        const KitchenMeat(quantity: 9, unit: 'قطع'),
        const KitchenMeat(quantity: 1200, unit: 'g'),
      ]);
    });

    test('multiplies quantity by factor and sums the same unit', () {
      final totals = aggregateMeatByUnit([
        c(1, 'patty', 2), // 2
        c(1, 'patty', 3), // +3 => 5
      ]);
      expect(totals.single, const KitchenMeat(quantity: 5, unit: 'patty'));
    });

    test('skips non-positive factor / quantity', () {
      final totals = aggregateMeatByUnit([
        c(2, 'patties', 0), // factor 0 -> skipped
        c(0, 'patties', 4), // quantity 0 -> skipped
        c(1, 'patties', 2), // 2
      ]);
      expect(totals, [const KitchenMeat(quantity: 2, unit: 'patties')]);
    });

    test('empty input yields an empty total', () {
      expect(aggregateMeatByUnit(const []), isEmpty);
    });
  });
}
