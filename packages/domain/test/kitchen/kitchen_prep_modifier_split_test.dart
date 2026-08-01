import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — the aggregation contract.
///
/// A modifier option may CLASSIFY an existing preparation resource, so the
/// kitchen summary reports that resource split into "with the option" and
/// "without the option". The option contributes NO quantity of its own: the
/// product's configured resource quantity stays the sole source of the number,
/// and the classification only decides which bucket it lands in.
void main() {
  // Saleh's configuration: Burger 240g needs 1 Bread + 2 Meat pieces per unit,
  // and its "Cheese" option classifies the Meat pieces.
  const cheeseOptionId = 'opt-cheese';
  const bread = KitchenPrepComponent(name: 'Bread', quantity: 1);
  const meat = KitchenPrepComponent(
    name: 'Meat pieces',
    quantity: 2,
    classifierOptionId: cheeseOptionId,
    classifierOptionName: 'Cheese',
  );

  /// One burger line: [quantity] units, with or without the cheese selection —
  /// resolved exactly the way the POS resolves it at order time.
  KitchenCountItemInput burgers(int quantity, {required bool cheese}) =>
      KitchenCountItemInput(
        quantity: quantity,
        prepComponents: classifyPrepComponents(const [
          bread,
          meat,
        ], cheese ? const {cheeseOptionId} : const <String>{}),
      );

  /// The rows as `(quantity, label, classifier, selected)` for exact matching.
  List<(num, String, String, bool)> rows(List<KitchenCount> counts) => [
    for (final c in counts)
      (c.quantity, c.label, c.classifier, c.classifierSelected),
  ];

  group('A. Saleh example — 3 burgers, 2 with cheese, 1 without', () {
    test('splits meat and leaves bread whole', () {
      final counts = aggregateOrderKitchenCounts([
        burgers(2, cheese: true),
        burgers(1, cheese: false),
      ]);

      // 2 cheese burgers x 2 pieces = 4 with; 1 plain burger x 2 = 2 without;
      // bread is unclassified so all 3 units total one row.
      expect(rows(counts), [
        (3, 'Bread', '', false),
        (4, 'Meat pieces', 'Cheese', true),
        (2, 'Meat pieces', 'Cheese', false),
      ]);
    });

    test('splitting never changes the resource total', () {
      final counts = aggregateOrderKitchenCounts([
        burgers(2, cheese: true),
        burgers(1, cheese: false),
      ]);
      final meatTotal = counts
          .where((c) => c.label == 'Meat pieces')
          .fold<num>(0, (sum, c) => sum + c.quantity);
      // Exactly what the unsplit configuration would have reported: 3 x 2.
      expect(meatTotal, 6);
    });

    test('the split rows stay adjacent, in the resource position', () {
      // Bread first (unclassified), then BOTH meat buckets together — even
      // though the without-cheese line was ordered first and an unrelated
      // resource was counted in between.
      final counts = aggregateOrderKitchenCounts([
        burgers(1, cheese: false),
        const KitchenCountItemInput(
          quantity: 1,
          prepComponents: [KitchenPrepComponent(name: 'Fries', quantity: 1)],
        ),
        burgers(2, cheese: true),
      ]);
      expect(rows(counts), [
        (3, 'Bread', '', false),
        (4, 'Meat pieces', 'Cheese', true),
        (2, 'Meat pieces', 'Cheese', false),
        (1, 'Fries', '', false),
      ]);
    });
  });

  group('B/C. one-sided orders print no empty bucket', () {
    test('all three with cheese — no "without" row', () {
      final counts = aggregateOrderKitchenCounts([burgers(3, cheese: true)]);
      expect(rows(counts), [
        (3, 'Bread', '', false),
        (6, 'Meat pieces', 'Cheese', true),
      ]);
    });

    test('none with cheese — no "with" row', () {
      final counts = aggregateOrderKitchenCounts([burgers(3, cheese: false)]);
      expect(rows(counts), [
        (3, 'Bread', '', false),
        (6, 'Meat pieces', 'Cheese', false),
      ]);
    });
  });

  group('D. no classifier configured — unsplit behaviour preserved', () {
    test('one plain "Meat pieces" row of 6', () {
      const plainMeat = KitchenPrepComponent(name: 'Meat pieces', quantity: 2);
      final counts = aggregateOrderKitchenCounts([
        const KitchenCountItemInput(
          quantity: 3,
          prepComponents: [bread, plainMeat],
        ),
      ]);
      expect(rows(counts), [
        (3, 'Bread', '', false),
        (6, 'Meat pieces', '', false),
      ]);
      expect(counts.every((c) => !c.isClassified), isTrue);
    });

    test('a configured classifier with no order-time answer stays unsplit', () {
      // Menu config that never went through classifyPrepComponents (a legacy
      // order row, or a snapshot written before this feature).
      final counts = aggregateOrderKitchenCounts([
        const KitchenCountItemInput(quantity: 3, prepComponents: [meat]),
      ]);
      expect(rows(counts), [(6, 'Meat pieces', '', false)]);
    });
  });

  group('E. line quantity multiplies the base resource exactly once', () {
    test('two identical cheese burgers on ONE line -> 4 with cheese', () {
      final counts = aggregateOrderKitchenCounts([burgers(2, cheese: true)]);
      expect(rows(counts), [
        (2, 'Bread', '', false),
        (4, 'Meat pieces', 'Cheese', true),
      ]);
    });
  });

  group('F. modifier quantity does not multiply the base resource', () {
    test('cheese x3 still classifies two meat pieces, not six', () {
      // Presence-based: the resolver is given the option id once regardless of
      // how many units of the option were selected.
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 1,
          prepComponents: classifyPrepComponents(
            const [meat],
            const {cheeseOptionId},
          ),
        ),
      ]);
      expect(rows(counts), [(2, 'Meat pieces', 'Cheese', true)]);
    });

    test('selecting the option twice classifies once', () {
      // Two selections of the SAME option collapse in the id set — the shape
      // the POS builds from a quantity-enabled group.
      final resolved = classifyPrepComponents(
        const [meat],
        <String>{
          ...['$cheeseOptionId', cheeseOptionId],
        },
      );
      expect(resolved.single.classifierSelected, isTrue);
      expect(resolved.single.quantity, 2, reason: 'quantity is never touched');
    });
  });

  group('G. unrelated modifiers do not affect the split', () {
    test('onion + spicy selected, cheese not -> without cheese', () {
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 3,
          prepComponents: classifyPrepComponents(
            const [bread, meat],
            const {'opt-onion', 'opt-spicy'},
          ),
        ),
      ]);
      expect(rows(counts), [
        (3, 'Bread', '', false),
        (6, 'Meat pieces', 'Cheese', false),
      ]);
    });

    test('cheese plus another option classifies the meat only once', () {
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 3,
          prepComponents: classifyPrepComponents(
            const [meat],
            const {'opt-onion', cheeseOptionId, 'opt-spicy'},
          ),
        ),
      ]);
      expect(rows(counts), [(6, 'Meat pieces', 'Cheese', true)]);
    });
  });

  group('H. the modifier\'s own preparation count stays independent', () {
    test('a classifying option that ALSO counts keeps its own total', () {
      // Cheese classifies the meat AND (deliberately) carries its own
      // "count in preparation total" contribution under its own label.
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 2,
          meats: const [KitchenMeat(quantity: 1, unit: 'Cheese slices')],
          prepComponents: classifyPrepComponents(
            const [meat],
            const {cheeseOptionId},
          ),
        ),
      ]);
      expect(rows(counts), [
        (2, 'Cheese slices', '', false),
        (4, 'Meat pieces', 'Cheese', true),
      ]);
    });

    test('classifying alone adds NO separate row for the option', () {
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 2,
          prepComponents: classifyPrepComponents(
            const [bread, meat],
            const {cheeseOptionId},
          ),
        ),
      ]);
      expect(counts.map((c) => c.label), ['Bread', 'Meat pieces']);
    });
  });

  group('9. invalid / half-configured targets fail safe to unsplit', () {
    test('a classifier id with no name is never split', () {
      const halfConfigured = KitchenPrepComponent(
        name: 'Meat pieces',
        quantity: 2,
        classifierOptionId: cheeseOptionId,
      );
      final resolved = classifyPrepComponents(
        const [halfConfigured],
        const {cheeseOptionId},
      );
      expect(resolved.single.classifierSelected, isNull);
      expect(
        rows(
          aggregateOrderKitchenCounts([
            KitchenCountItemInput(quantity: 3, prepComponents: resolved),
          ]),
        ),
        [(6, 'Meat pieces', '', false)],
      );
    });

    test('unconfigured components are returned unchanged, identically', () {
      const components = [bread];
      expect(
        identical(classifyPrepComponents(components, const {'x'}), components),
        isTrue,
      );
    });
  });

  group('serialization round-trips the classifier', () {
    test('resolved component -> json -> component', () {
      final resolved = classifyPrepComponents(
        const [meat],
        const {cheeseOptionId},
      ).single;
      final json = resolved.toJson();
      expect(json, {
        'name': 'Meat pieces',
        'quantity': 2,
        'unit': '',
        'classifier_option_id': cheeseOptionId,
        'classifier_option_name': 'Cheese',
        'classifier_selected': true,
      });
      expect(KitchenPrepComponent.tryFromJson(json), resolved);
      // Non-money throughout (D-007).
      expect(json.keys.any((k) => k.contains('minor')), isFalse);
    });

    test('an unclassified component serializes exactly as before', () {
      expect(bread.toJson(), {'name': 'Bread', 'quantity': 1, 'unit': ''});
    });

    test('a legacy row without the keys decodes as unsplit', () {
      final parsed = KitchenPrepComponent.tryFromJson({
        'name': 'Meat pieces',
        'quantity': 2,
        'unit': '',
      });
      expect(parsed!.classifierOptionId, '');
      expect(parsed.classifierSelected, isNull);
      expect(parsed.isClassified, isFalse);
    });
  });

  group('display label composition is locale-supplied', () {
    String withOption(String r, String o) => '$r مع $o';
    String withoutOption(String r, String o) => '$r بدون $o';

    test('classified rows read "resource with/without option"', () {
      final counts = aggregateOrderKitchenCounts([
        burgers(2, cheese: true),
        burgers(1, cheese: false),
      ]);
      expect(
        [
          for (final c in counts)
            kitchenCountDisplayLabel(
              c,
              withOption: withOption,
              withoutOption: withoutOption,
            ),
        ],
        ['Bread', 'Meat pieces مع Cheese', 'Meat pieces بدون Cheese'],
      );
    });

    test('an unsplit row is the bare resource label', () {
      expect(
        kitchenCountDisplayLabel(
          const KitchenCount(quantity: 6, label: 'Meat pieces'),
          withOption: withOption,
          withoutOption: withoutOption,
        ),
        'Meat pieces',
      );
    });
  });
}
