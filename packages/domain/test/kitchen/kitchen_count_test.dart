import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// KDS-ALERTS-AND-KITCHEN-COUNTS-002: the generic whole-order count aggregation
/// — group by resource label, sum quantity × factor, multiple resources at once.
void main() {
  KitchenCountContribution c(num q, String label, int factor) =>
      KitchenCountContribution(quantity: q, label: label, factor: factor);

  test('groups by label and sums quantity × factor', () {
    // 2 double burgers (2 patties × 2) + 5 triple burgers (3 patties × 5) = 19.
    final result = aggregateKitchenCounts([
      c(2, 'قطع لحم', 2),
      c(3, 'قطع لحم', 5),
    ]);
    expect(result, [const KitchenCount(quantity: 19, label: 'قطع لحم')]);
  });

  test(
    'keeps distinct resources as separate totals, in first-appearance order',
    () {
      final result = aggregateKitchenCounts([
        c(2, 'قطع لحم', 2), // 4
        c(1, 'خبز', 2), // 2
        c(1, 'خبز', 5), // +5 = 7
        c(3, 'قطع لحم', 5), // +15 = 19
      ]);
      expect(result, [
        const KitchenCount(quantity: 19, label: 'قطع لحم'),
        const KitchenCount(quantity: 7, label: 'خبز'),
      ]);
    },
  );

  test('skips non-positive quantity / factor', () {
    final result = aggregateKitchenCounts([
      c(0, 'buns', 3),
      c(2, 'buns', 0),
      c(-1, 'buns', 3),
      c(1, 'buns', 3), // the only valid one -> 3
    ]);
    expect(result, [const KitchenCount(quantity: 3, label: 'buns')]);
  });

  test('trims labels and does not collapse different labels', () {
    final result = aggregateKitchenCounts([
      c(1, ' buns ', 2), // trims to "buns"
      c(1, 'buns', 3),
      c(1, 'AB', 1),
      c(1, 'A', 1), // must NOT merge with "AB"
    ]);
    expect(result, [
      const KitchenCount(quantity: 5, label: 'buns'),
      const KitchenCount(quantity: 1, label: 'AB'),
      const KitchenCount(quantity: 1, label: 'A'),
    ]);
  });

  test('empty input -> empty', () {
    expect(aggregateKitchenCounts(const []), isEmpty);
  });

  test('is money-free — toJson carries only quantity + label', () {
    final json = const KitchenCount(quantity: 19, label: 'patties').toJson();
    expect(json.keys, containsAll(<String>['quantity', 'label']));
    expect(json.keys.any((k) => k.toLowerCase().contains('minor')), isFalse);
  });
}
