import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// KITCHEN-PRINT-DUAL-001B: [aggregateOrderKitchenCounts] is the SINGLE shared
/// count mapping used by BOTH the KDS mapper and the POS direct kitchen print.
/// These pin its contract directly: the item quantity is the factor, applied to
/// each per-option meat (already × modifier units) and each per-item prep,
/// EXACTLY ONCE — never double-multiplied. Money-free.
void main() {
  KitchenCountItemInput item({
    required int quantity,
    List<KitchenMeat> meats = const [],
    List<KitchenPrepComponent> prep = const [],
  }) => KitchenCountItemInput(
    quantity: quantity,
    meats: meats,
    prepComponents: prep,
  );

  test('A: the item quantity is the meat factor, applied exactly once', () {
    // meats are ALREADY × modifier units (the caller pre-multiplies); the
    // aggregator applies × item quantity ONCE. 2 (per item) × 2 (items) = 4.
    final counts = aggregateOrderKitchenCounts([
      item(quantity: 2, meats: const [KitchenMeat(quantity: 2, unit: 'patty')]),
    ]);
    expect(counts, [const KitchenCount(quantity: 4, label: 'patty')]);
    expect(
      counts.single.quantity,
      isNot(8),
      reason: 'the factor must not be squared (no double multiply)',
    );
  });

  test('B: multiple items contributing the same resource aggregate', () {
    final counts = aggregateOrderKitchenCounts([
      item(
        quantity: 2,
        prep: const [KitchenPrepComponent(name: 'buns', quantity: 1)],
      ),
      item(
        quantity: 3,
        prep: const [KitchenPrepComponent(name: 'buns', quantity: 1)],
      ),
    ]);
    // 1×2 + 1×3 = 5, one merged total.
    expect(counts, [const KitchenCount(quantity: 5, label: 'buns')]);
  });

  test('C: a bread/prep count multiplies by the item quantity once', () {
    final counts = aggregateOrderKitchenCounts([
      item(
        quantity: 4,
        prep: const [KitchenPrepComponent(name: 'bun', quantity: 1)],
      ),
    ]);
    expect(counts, [const KitchenCount(quantity: 4, label: 'bun')]);
  });

  test('C2: a prep unit is folded into the grouping label', () {
    final counts = aggregateOrderKitchenCounts([
      item(
        quantity: 2,
        prep: const [
          KitchenPrepComponent(name: 'Fish', quantity: 1, unit: 'pcs'),
        ],
      ),
    ]);
    expect(counts, [const KitchenCount(quantity: 2, label: 'Fish pcs')]);
  });

  test(
    'D: an item with NO meats yields only prep counts (no phantom meat)',
    () {
      final counts = aggregateOrderKitchenCounts([
        item(
          quantity: 2,
          meats: const [],
          prep: const [KitchenPrepComponent(name: 'bun', quantity: 1)],
        ),
      ]);
      expect(counts, [const KitchenCount(quantity: 2, label: 'bun')]);
    },
  );

  test('D2: an item with neither meats nor prep contributes nothing', () {
    expect(aggregateOrderKitchenCounts([item(quantity: 3)]), isEmpty);
  });

  test(
    'meat and prep both present: meat first, then prep (first appearance)',
    () {
      final counts = aggregateOrderKitchenCounts([
        item(
          quantity: 2,
          meats: const [KitchenMeat(quantity: 2, unit: 'قطع لحم')],
          prep: const [KitchenPrepComponent(name: 'خبز', quantity: 1)],
        ),
      ]);
      expect(counts, [
        const KitchenCount(quantity: 4, label: 'قطع لحم'), // 2×2
        const KitchenCount(quantity: 2, label: 'خبز'), // 1×2
      ]);
    },
  );

  test('non-positive item quantity contributes nothing (skipped)', () {
    expect(
      aggregateOrderKitchenCounts([
        item(
          quantity: 0,
          meats: const [KitchenMeat(quantity: 2, unit: 'patty')],
          prep: const [KitchenPrepComponent(name: 'bun', quantity: 1)],
        ),
      ]),
      isEmpty,
    );
  });
}
