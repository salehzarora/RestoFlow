import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// KITCHEN-PREP-001: the pure prep model, tolerant parser, and the order
/// aggregation. Nothing is derived from a name/price — only configured data is
/// aggregated. Non-money throughout (D-007): quantity is a count, unit is text.
void main() {
  group('parseKitchenPrepComponents', () {
    test(
      'parses a clean wire list, preserving Arabic/Hebrew names + units',
      () {
        final parsed = parseKitchenPrepComponents([
          {'name': 'لحم برجر', 'quantity': 2, 'unit': 'قطع'},
          {'name': 'בשר', 'quantity': 1, 'unit': ''},
          {'name': 'Bun', 'quantity': 1},
        ]);
        expect(parsed, [
          const KitchenPrepComponent(
            name: 'لحم برجر',
            quantity: 2,
            unit: 'قطع',
          ),
          const KitchenPrepComponent(name: 'בשר', quantity: 1),
          const KitchenPrepComponent(name: 'Bun', quantity: 1),
        ]);
      },
    );

    test('drops blank names, non-positive quantities, and bad shapes', () {
      final parsed = parseKitchenPrepComponents([
        {'name': '   ', 'quantity': 3}, // blank name
        {'name': 'Patty', 'quantity': 0}, // non-positive
        {'name': 'Patty', 'quantity': -1}, // negative
        {'name': 'Patty'}, // missing quantity
        'not-an-object',
        {'name': 'Cheese', 'quantity': 2, 'unit': 'pcs'}, // the only valid row
      ]);
      expect(parsed, [
        const KitchenPrepComponent(name: 'Cheese', quantity: 2, unit: 'pcs'),
      ]);
    });

    test('parses string quantities and trims name/unit', () {
      final parsed = parseKitchenPrepComponents([
        {'name': '  Patty  ', 'quantity': '2', 'unit': '  pcs '},
      ]);
      expect(parsed.single.name, 'Patty');
      expect(parsed.single.quantity, 2);
      expect(parsed.single.unit, 'pcs');
    });

    test('non-list input yields an empty list (never throws)', () {
      expect(parseKitchenPrepComponents(null), isEmpty);
      expect(parseKitchenPrepComponents('x'), isEmpty);
      expect(parseKitchenPrepComponents(<String, Object?>{}), isEmpty);
    });
  });

  group('aggregateKitchenPrep', () {
    KitchenPrepLine line(int qty, List<KitchenPrepComponent> comps) =>
        KitchenPrepLine(components: comps, quantity: qty);

    test('multiplies item base prep by the line quantity (§3)', () {
      // 3 double burgers: each unit = 2 patties + 1 bun.
      final summary = aggregateKitchenPrep([
        line(3, const [
          KitchenPrepComponent(name: 'لحم برجر', quantity: 2, unit: 'قطع'),
          KitchenPrepComponent(name: 'خبز برجر', quantity: 1, unit: 'حبة'),
        ]),
      ]);
      expect(summary, [
        const KitchenPrepComponent(name: 'لحم برجر', quantity: 6, unit: 'قطع'),
        const KitchenPrepComponent(name: 'خبز برجر', quantity: 3, unit: 'حبة'),
      ]);
    });

    test(
      'groups the same (name, unit) across multiple items, first-seen order',
      () {
        final summary = aggregateKitchenPrep([
          line(2, const [
            KitchenPrepComponent(name: 'Patty', quantity: 1, unit: 'pcs'),
            KitchenPrepComponent(name: 'Bun', quantity: 1),
          ]),
          line(1, const [
            KitchenPrepComponent(name: 'Patty', quantity: 2, unit: 'pcs'),
            KitchenPrepComponent(name: 'Sauce', quantity: 1, unit: 'cup'),
          ]),
        ]);
        // Patty = 2×1 + 1×2 = 4; Bun = 2; Sauce = 1. Order: Patty, Bun, Sauce.
        expect(summary, [
          const KitchenPrepComponent(name: 'Patty', quantity: 4, unit: 'pcs'),
          const KitchenPrepComponent(name: 'Bun', quantity: 2),
          const KitchenPrepComponent(name: 'Sauce', quantity: 1, unit: 'cup'),
        ]);
      },
    );

    test('modifier-added prep aggregates via extra lines (§4)', () {
      // 2 burgers each with an "extra patty" option that adds 1 patty.
      final summary = aggregateKitchenPrep([
        line(2, const [
          KitchenPrepComponent(name: 'Patty', quantity: 1, unit: 'pcs'),
        ]),
        // the modifier contributes its own line: +1 patty on each of the 2 items
        line(2, const [
          KitchenPrepComponent(name: 'Patty', quantity: 1, unit: 'pcs'),
        ]),
      ]);
      expect(summary, [
        const KitchenPrepComponent(name: 'Patty', quantity: 4, unit: 'pcs'),
      ]);
    });

    test('same name but different unit stays separate', () {
      final summary = aggregateKitchenPrep([
        line(1, const [
          KitchenPrepComponent(name: 'Cheese', quantity: 1, unit: 'slice'),
          KitchenPrepComponent(name: 'Cheese', quantity: 30, unit: 'g'),
        ]),
      ]);
      expect(summary.length, 2);
      expect(summary[0].unit, 'slice');
      expect(summary[1].unit, 'g');
    });

    test('skips blank names, non-positive quantities, and zero-qty lines', () {
      final summary = aggregateKitchenPrep([
        line(0, const [KitchenPrepComponent(name: 'Patty', quantity: 5)]),
        line(2, const [
          KitchenPrepComponent(name: '  ', quantity: 3),
          KitchenPrepComponent(name: 'Bun', quantity: 0),
          KitchenPrepComponent(name: 'Patty', quantity: 1, unit: 'pcs'),
        ]),
      ]);
      expect(summary, [
        const KitchenPrepComponent(name: 'Patty', quantity: 2, unit: 'pcs'),
      ]);
    });

    test('no name/unit collision when a space is embedded', () {
      final summary = aggregateKitchenPrep([
        line(1, const [
          KitchenPrepComponent(name: 'A B', quantity: 1, unit: 'C'),
          KitchenPrepComponent(name: 'A', quantity: 1, unit: 'B C'),
        ]),
      ]);
      // Distinct components — must NOT merge into a single group.
      expect(summary.length, 2);
    });

    test('empty input yields an empty summary', () {
      expect(aggregateKitchenPrep(const []), isEmpty);
      expect(aggregateKitchenPrep([line(3, const [])]), isEmpty);
    });
  });

  group('formatPrepQuantity', () {
    test('whole numbers drop the decimal', () {
      expect(formatPrepQuantity(6), '6');
      expect(formatPrepQuantity(2.0), '2');
    });
    test('fractions keep up to 2 dp, trimmed', () {
      expect(formatPrepQuantity(1.5), '1.5');
      expect(formatPrepQuantity(0.25), '0.25');
    });
  });

  test('toJson round-trips through tryFromJson', () {
    const component = KitchenPrepComponent(
      name: 'لحم',
      quantity: 2,
      unit: 'قطع',
    );
    expect(KitchenPrepComponent.tryFromJson(component.toJson()), component);
  });
}
