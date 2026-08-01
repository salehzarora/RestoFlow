import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 — Codex HIGH #2 and MEDIUM #4.
///
/// #2: a stored `classifier_option_id` is an ASSERTION, not a fact. It is only
/// honoured when it names an option of the SAME menu item; anything else fails
/// safe to an ordinary unsplit preparation resource, and the resource itself is
/// never lost.
///
/// #4: when one resource is split by more than one option, each classifier's
/// with/without PAIR must stay together, and the row order must not depend on
/// the order the surface happened to feed items in.
void main() {
  const burgerCheese = 'opt-cheese-burger';
  const burgerBacon = 'opt-bacon-burger';
  const chickenCheese = 'opt-cheese-chicken';

  KitchenPrepComponent meat({
    String classifierId = '',
    String classifierName = '',
  }) => KitchenPrepComponent(
    name: 'Meat pieces',
    quantity: 2,
    classifierOptionId: classifierId,
    classifierOptionName: classifierName,
  );

  // The burger's OWN options — the only ones its resources may be split by.
  const burgerOptions = <String, String>{
    burgerCheese: 'Cheese',
    burgerBacon: 'Bacon',
  };

  List<(num, String, String, bool)> rows(List<KitchenCount> counts) => [
    for (final c in counts)
      (c.quantity, c.label, c.classifier, c.classifierSelected),
  ];

  group('C. item-scoped classifier validation', () {
    test('a valid same-item link survives and is named from the item', () {
      final resolved = resolveTrustedPrepClassifiers([
        meat(classifierId: burgerCheese, classifierName: 'Cheese'),
      ], burgerOptions);
      expect(resolved.single.classifierOptionId, burgerCheese);
      expect(resolved.single.classifierOptionName, 'Cheese');
    });

    test('a FOREIGN product\'s option id is stripped to unsplit', () {
      // The chicken's "Cheese" option, stored on the burger's resource.
      final resolved = resolveTrustedPrepClassifiers([
        meat(classifierId: chickenCheese, classifierName: 'Cheese'),
      ], burgerOptions);
      expect(resolved.single.classifierOptionId, '');
      expect(resolved.single.classifierOptionName, '');
      expect(resolved.single.isClassified, isFalse);
      // The resource itself is intact.
      expect(resolved.single.name, 'Meat pieces');
      expect(resolved.single.quantity, 2);
    });

    test('two products with an option NAMED Cheese do not cross over', () {
      const chickenOptions = <String, String>{chickenCheese: 'Cheese'};
      // The burger's link is meaningless in the chicken's scope and vice versa.
      expect(
        resolveTrustedPrepClassifiers([
          meat(classifierId: burgerCheese, classifierName: 'Cheese'),
        ], chickenOptions).single.isClassified,
        isFalse,
      );
      expect(
        resolveTrustedPrepClassifiers([
          meat(classifierId: chickenCheese, classifierName: 'Cheese'),
        ], burgerOptions).single.isClassified,
        isFalse,
      );
    });

    test('a DELETED option is stripped to unsplit', () {
      final resolved = resolveTrustedPrepClassifiers([
        meat(classifierId: 'opt-gone', classifierName: 'Bacon'),
      ], burgerOptions);
      expect(resolved.single.isClassified, isFalse);
      expect(resolved.single.classifierOptionName, '');
    });

    test('an EMPTY id is unsplit and the component is untouched', () {
      const plain = KitchenPrepComponent(name: 'Bread', quantity: 1);
      final resolved = resolveTrustedPrepClassifiers([plain], burgerOptions);
      expect(identical(resolved.single, plain), isTrue);
    });

    test('the trusted name WINS over a stale/hostile stored name', () {
      // The stored pair claims a different display name than the live option.
      final resolved = resolveTrustedPrepClassifiers([
        meat(classifierId: burgerCheese, classifierName: 'Free Beer'),
      ], burgerOptions);
      expect(resolved.single.classifierOptionName, 'Cheese');
    });

    test('a target whose live name is blank is stripped to unsplit', () {
      final resolved = resolveTrustedPrepClassifiers(
        [meat(classifierId: burgerCheese, classifierName: 'Cheese')],
        const {burgerCheese: '   '},
      );
      expect(resolved.single.isClassified, isFalse);
    });

    test('resolution CLEARS a stale order-time answer', () {
      // A previously-resolved snapshot re-validated against a menu that no
      // longer has the option must not keep its old "with" answer.
      const stale = KitchenPrepComponent(
        name: 'Meat pieces',
        quantity: 2,
        classifierOptionId: 'opt-gone',
        classifierOptionName: 'Cheese',
        classifierSelected: true,
      );
      final resolved = resolveTrustedPrepClassifiers([stale], burgerOptions);
      expect(resolved.single.classifierSelected, isNull);
      expect(resolved.single.isClassified, isFalse);
    });

    test('legacy no-link data passes through identically', () {
      const legacy = [
        KitchenPrepComponent(name: 'Bread', quantity: 1),
        KitchenPrepComponent(name: 'Meat pieces', quantity: 2),
      ];
      expect(
        identical(resolveTrustedPrepClassifiers(legacy, burgerOptions), legacy),
        isTrue,
      );
    });

    test('an empty option map strips every link (item has no options)', () {
      final resolved = resolveTrustedPrepClassifiers([
        meat(classifierId: burgerCheese, classifierName: 'Cheese'),
      ], const <String, String>{});
      expect(resolved.single.isClassified, isFalse);
      expect(resolved.single.quantity, 2);
    });
  });

  group('C. malformed JSON types never become identifiers', () {
    test('a non-string classifier id is dropped, not stringified', () {
      final parsed = KitchenPrepComponent.tryFromJson({
        'name': 'Meat pieces',
        'quantity': 2,
        'unit': '',
        'classifier_option_id': {'amount_minor': 5},
        'classifier_option_name': 'Cheese',
        'classifier_selected': true,
      })!;
      expect(parsed.classifierOptionId, '');
      expect(parsed.classifierSelected, isNull);
      expect(parsed.isClassified, isFalse);
      // The resource survives intact — malformed metadata never suppresses it.
      expect(parsed.name, 'Meat pieces');
      expect(parsed.quantity, 2);
    });

    test('a non-string classifier NAME is dropped', () {
      final parsed = KitchenPrepComponent.tryFromJson({
        'name': 'Meat pieces',
        'quantity': 2,
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': ['Cheese'],
        'classifier_selected': true,
      })!;
      expect(parsed.classifierOptionName, '');
      expect(parsed.isClassified, isFalse);
      expect(parsed.quantity, 2);
    });

    test('a non-boolean classifier_selected is dropped', () {
      final parsed = KitchenPrepComponent.tryFromJson({
        'name': 'Meat pieces',
        'quantity': 2,
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': 'Cheese',
        'classifier_selected': 'yes',
      })!;
      expect(parsed.classifierSelected, isNull);
      expect(parsed.isClassified, isFalse);
    });

    test('an answer with NO id is not a classification', () {
      final parsed = KitchenPrepComponent.tryFromJson({
        'name': 'Meat pieces',
        'quantity': 2,
        'classifier_selected': true,
      })!;
      expect(parsed.classifierSelected, isNull);
      expect(parsed.isClassified, isFalse);
    });

    test(
      'a malformed classifier never removes the resource from the total',
      () {
        final parsed = KitchenPrepComponent.tryFromJson({
          'name': 'Meat pieces',
          'quantity': 2,
          'classifier_option_id': 42,
        })!;
        expect(
          rows(
            aggregateOrderKitchenCounts([
              KitchenCountItemInput(quantity: 3, prepComponents: [parsed]),
            ]),
          ),
          [(6, 'Meat pieces', '', false)],
        );
      },
    );
  });

  group('E. two classifiers on one resource keep their pairs together', () {
    /// One burger line classified by BOTH Cheese and Bacon.
    KitchenCountItemInput burger({
      required int quantity,
      required bool cheese,
      required bool bacon,
      int linePosition = 0,
    }) => KitchenCountItemInput(
      quantity: quantity,
      linePosition: linePosition,
      prepComponents: classifyPrepComponents(
        resolveTrustedPrepClassifiers(const [
          KitchenPrepComponent(
            name: 'Meat pieces',
            quantity: 2,
            classifierOptionId: burgerCheese,
            classifierOptionName: 'Cheese',
          ),
          KitchenPrepComponent(
            name: 'Meat pieces',
            quantity: 1,
            classifierOptionId: burgerBacon,
            classifierOptionName: 'Bacon',
          ),
        ], burgerOptions),
        <String>{if (cheese) burgerCheese, if (bacon) burgerBacon},
      ),
    );

    test(
      'pairs are adjacent: Cheese with/without, then Bacon with/without',
      () {
        final counts = aggregateOrderKitchenCounts([
          burger(quantity: 2, cheese: true, bacon: false, linePosition: 1),
          burger(quantity: 1, cheese: false, bacon: true, linePosition: 2),
        ]);
        expect(rows(counts), [
          // Cheese: 2 burgers x 2 pieces with, 1 burger x 2 pieces without.
          (4, 'Meat pieces', 'Cheese', true),
          (2, 'Meat pieces', 'Cheese', false),
          // Bacon: 1 burger x 1 piece with, 2 burgers x 1 piece without.
          (1, 'Meat pieces', 'Bacon', true),
          (2, 'Meat pieces', 'Bacon', false),
        ]);
      },
    );

    test('the defect shape is gone: never with/with then without/without', () {
      final labels = [
        for (final c in aggregateOrderKitchenCounts([
          burger(quantity: 2, cheese: true, bacon: false, linePosition: 1),
          burger(quantity: 1, cheese: false, bacon: true, linePosition: 2),
        ]))
          '${c.classifier}:${c.classifierSelected}',
      ];
      expect(
        labels,
        isNot(['Cheese:true', 'Bacon:true', 'Cheese:false', 'Bacon:false']),
      );
      expect(labels, [
        'Cheese:true',
        'Cheese:false',
        'Bacon:true',
        'Bacon:false',
      ]);
    });

    test('REVERSED input order yields the SAME rows (canonical ordering)', () {
      final forward = aggregateOrderKitchenCounts([
        burger(quantity: 2, cheese: true, bacon: false, linePosition: 1),
        burger(quantity: 1, cheese: false, bacon: true, linePosition: 2),
      ]);
      final reversed = aggregateOrderKitchenCounts([
        burger(quantity: 1, cheese: false, bacon: true, linePosition: 2),
        burger(quantity: 2, cheese: true, bacon: false, linePosition: 1),
      ]);
      expect(reversed, forward);
    });

    test('repeated runs are deterministic', () {
      final runs = [
        for (var i = 0; i < 25; i++)
          aggregateOrderKitchenCounts([
            burger(quantity: 2, cheese: true, bacon: true, linePosition: 1),
            burger(quantity: 1, cheese: false, bacon: false, linePosition: 2),
          ]),
      ];
      for (final run in runs) {
        expect(run, runs.first);
      }
    });

    test('two resources split by the SAME option order independently', () {
      const bread = KitchenPrepComponent(
        name: 'Bread',
        quantity: 1,
        classifierOptionId: burgerCheese,
        classifierOptionName: 'Cheese',
      );
      const meatCheese = KitchenPrepComponent(
        name: 'Meat pieces',
        quantity: 2,
        classifierOptionId: burgerCheese,
        classifierOptionName: 'Cheese',
      );
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 1,
          linePosition: 1,
          prepComponents: classifyPrepComponents(
            const [bread, meatCheese],
            const {burgerCheese},
          ),
        ),
        KitchenCountItemInput(
          quantity: 1,
          linePosition: 2,
          prepComponents: classifyPrepComponents(const [
            bread,
            meatCheese,
          ], const <String>{}),
        ),
      ]);
      expect(rows(counts), [
        (1, 'Bread', 'Cheese', true),
        (1, 'Bread', 'Cheese', false),
        (2, 'Meat pieces', 'Cheese', true),
        (2, 'Meat pieces', 'Cheese', false),
      ]);
    });
  });

  group('E. canonical input order across surfaces', () {
    test('items are aggregated in menu print order, not arrival order', () {
      const fries = KitchenPrepComponent(name: 'Fries', quantity: 1);
      const bread = KitchenPrepComponent(name: 'Bread', quantity: 1);
      // Fed in the WRONG order (as an arbitrary sync_pull wire order would).
      final counts = aggregateOrderKitchenCounts([
        const KitchenCountItemInput(
          quantity: 1,
          prepComponents: [fries],
          categoryDisplayOrder: 2,
          linePosition: 2,
        ),
        const KitchenCountItemInput(
          quantity: 1,
          prepComponents: [bread],
          categoryDisplayOrder: 1,
          linePosition: 1,
        ),
      ]);
      expect(counts.map((c) => c.label), ['Bread', 'Fries']);
    });

    test('canonicalKitchenCountOrder is the exposed shared key', () {
      final ordered = canonicalKitchenCountOrder(const [
        KitchenCountItemInput(quantity: 1, linePosition: 3),
        KitchenCountItemInput(quantity: 2, linePosition: 1),
        KitchenCountItemInput(quantity: 3, linePosition: 2),
      ]);
      expect(ordered.map((i) => i.quantity), [2, 3, 1]);
    });

    test('all-zero keys fall back to input order (legacy orders)', () {
      final ordered = canonicalKitchenCountOrder(const [
        KitchenCountItemInput(quantity: 7),
        KitchenCountItemInput(quantity: 8),
      ]);
      expect(ordered.map((i) => i.quantity), [7, 8]);
    });
  });
}
