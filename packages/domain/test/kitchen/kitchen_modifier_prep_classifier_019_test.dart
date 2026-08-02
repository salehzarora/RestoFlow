import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-019 — the corrected model.
///
/// Saleh's burger has ONE product-level preparation resource (Bread ×1). The
/// MEAT comes from the selected SIZE option through the existing per-option
/// contribution: 120g → 1 Meat piece, 240g → 2, 360g → 3, 480g → 4. A separate
/// Cheese option — in a DIFFERENT modifier group on the same item — decides
/// whether those pieces are reported "with Cheese" or "without Cheese".
///
/// The classifier only re-buckets; it never adds or multiplies meat.
void main() {
  const size120 = 'opt-size-120';
  const size240 = 'opt-size-240';
  const cheeseId = 'opt-cheese';
  const onionId = 'opt-onion';

  /// The item's own options — the only ids a link on this item may name.
  const burgerOptions = <String, String>{
    size120: '120g',
    size240: '240g',
    cheeseId: 'Cheese',
    onionId: 'Onion',
  };

  const bread = KitchenPrepComponent(name: 'Bread', quantity: 1, unit: 'Piece');

  /// A size option's configured contribution, classified by Cheese.
  KitchenMeat sizeMeat(num pieces, {String classifier = cheeseId}) =>
      KitchenMeat(
        quantity: pieces,
        unit: 'Meat pieces',
        classifierOptionId: classifier,
        classifierOptionName: classifier.isEmpty ? '' : 'Cheese',
      );

  /// One burger line: the chosen size contributes its meat, and the line's
  /// selected option ids answer the classifier — the exact shape the POS builds.
  KitchenCountItemInput burger({
    required num pieces,
    required bool cheese,
    int quantity = 1,
    int linePosition = 0,
    String sizeOptionId = size240,
    Set<String> extraSelected = const <String>{},
  }) {
    final selected = <String>{
      sizeOptionId,
      if (cheese) cheeseId,
      ...extraSelected,
    };
    final configured = sizeMeat(pieces);
    final trusted = resolveTrustedMeatClassifier(
      configured,
      optionNamesById: burgerOptions,
      selfOptionId: sizeOptionId,
    )!;
    return KitchenCountItemInput(
      quantity: quantity,
      linePosition: linePosition,
      prepComponents: const [bread],
      meats: [
        trusted.classifierOptionId.isEmpty
            ? trusted
            : trusted.withClassifierSelected(
                selected.contains(trusted.classifierOptionId),
              ),
      ],
    );
  }

  List<(num, String, String, bool)> rows(List<KitchenCount> counts) => [
    for (final c in counts)
      (c.quantity, c.label, c.classifier, c.classifierSelected),
  ];

  group('A. Saleh example A — mixed sizes', () {
    test('120g+Cheese, 120g plain, 240g+Cheese', () {
      final counts = aggregateOrderKitchenCounts([
        burger(pieces: 1, cheese: true, sizeOptionId: size120, linePosition: 1),
        burger(
          pieces: 1,
          cheese: false,
          sizeOptionId: size120,
          linePosition: 2,
        ),
        burger(pieces: 2, cheese: true, linePosition: 3),
      ]);
      // ROW ORDER: an item's MODIFIER contributions are emitted before its
      // item-base prep — the pre-019 contract, deliberately unchanged. The rows
      // and quantities are exactly Saleh's summary.
      expect(rows(counts), [
        // 1 (120g w/ cheese) + 2 (240g w/ cheese) = 3
        (3, 'Meat pieces', 'Cheese', true),
        // 1 (120g without)
        (1, 'Meat pieces', 'Cheese', false),
        (3, 'Bread Piece', '', false),
      ]);
    });
  });

  group('B. Saleh example B — three 240g burgers', () {
    test('two with Cheese, one without', () {
      final counts = aggregateOrderKitchenCounts([
        burger(pieces: 2, cheese: true, quantity: 2, linePosition: 1),
        burger(pieces: 2, cheese: false, linePosition: 2),
      ]);
      // ROW ORDER: an item's MODIFIER contributions are emitted before its
      // item-base prep — the pre-019 contract, deliberately unchanged. The rows
      // and quantities are exactly Saleh's summary.
      expect(rows(counts), [
        (4, 'Meat pieces', 'Cheese', true),
        (2, 'Meat pieces', 'Cheese', false),
        (3, 'Bread Piece', '', false),
      ]);
    });

    test('the split never changes the meat total', () {
      final counts = aggregateOrderKitchenCounts([
        burger(pieces: 2, cheese: true, quantity: 2, linePosition: 1),
        burger(pieces: 2, cheese: false, linePosition: 2),
      ]);
      expect(
        counts
            .where((c) => c.label == 'Meat pieces')
            .fold<num>(0, (sum, c) => sum + c.quantity),
        6,
      );
    });
  });

  group('C. no classifier configured keeps the old unsplit contribution', () {
    test('a bare size contribution totals one row', () {
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 3,
          prepComponents: const [bread],
          meats: const [KitchenMeat(quantity: 2, unit: 'Meat pieces')],
        ),
      ]);
      expect(rows(counts), [
        (6, 'Meat pieces', '', false),
        (3, 'Bread Piece', '', false),
      ]);
    });

    test('a configured link with no order-time answer stays unsplit', () {
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(quantity: 3, meats: [sizeMeat(2)]),
      ]);
      expect(rows(counts), [(6, 'Meat pieces', '', false)]);
    });
  });

  group('D. all-with / all-without omit the zero row', () {
    test('all with Cheese', () {
      final counts = aggregateOrderKitchenCounts([
        burger(pieces: 2, cheese: true, quantity: 3),
      ]);
      expect(rows(counts), [
        (6, 'Meat pieces', 'Cheese', true),
        (3, 'Bread Piece', '', false),
      ]);
    });

    test('none with Cheese', () {
      final counts = aggregateOrderKitchenCounts([
        burger(pieces: 2, cheese: false, quantity: 3),
      ]);
      expect(rows(counts), [
        (6, 'Meat pieces', 'Cheese', false),
        (3, 'Bread Piece', '', false),
      ]);
    });
  });

  group('E/F. classifier presence, unrelated options', () {
    test('the classifier is presence-based, never a multiplier', () {
      // Whether Cheese was taken once or four times, the meat is the same.
      final once = aggregateOrderKitchenCounts([
        burger(pieces: 2, cheese: true),
      ]);
      final many = aggregateOrderKitchenCounts([
        burger(
          pieces: 2,
          cheese: true,
          extraSelected: const {cheeseId, onionId},
        ),
      ]);
      expect(
        rows(many).where((r) => r.$2 == 'Meat pieces'),
        rows(once).where((r) => r.$2 == 'Meat pieces'),
      );
      expect(rows(once).firstWhere((r) => r.$2 == 'Meat pieces').$1, 2);
    });

    test('an unrelated option does not affect the bucket', () {
      final counts = aggregateOrderKitchenCounts([
        burger(
          pieces: 2,
          cheese: false,
          quantity: 2,
          extraSelected: const {onionId},
        ),
      ]);
      expect(rows(counts).where((r) => r.$2 == 'Meat pieces'), [
        (4, 'Meat pieces', 'Cheese', false),
      ]);
    });

    test('order-item quantity multiplies the size contribution once', () {
      final counts = aggregateOrderKitchenCounts([
        burger(pieces: 2, cheese: true, quantity: 3),
      ]);
      expect(rows(counts).firstWhere((r) => r.$2 == 'Meat pieces').$1, 6);
    });

    test('the option\'s own units still scale ITS contribution', () {
      // An "extra patty ×2" option contributes twice — unchanged semantics.
      expect(const KitchenMeat(quantity: 2, unit: 'x').scaledBy(3).quantity, 6);
      // …and scaling never disturbs the classifier.
      final scaled = sizeMeat(2).withClassifierSelected(true).scaledBy(2);
      expect(scaled.quantity, 4);
      expect(scaled.classifierSelected, isTrue);
      expect(scaled.classifierOptionName, 'Cheese');
    });
  });

  group('G. same-item validation', () {
    KitchenMeat? resolve(String id, {String self = size240}) =>
        resolveTrustedMeatClassifier(
          KitchenMeat(
            quantity: 2,
            unit: 'Meat pieces',
            classifierOptionId: id,
            classifierOptionName: 'Whatever',
          ),
          optionNamesById: burgerOptions,
          selfOptionId: self,
        );

    test('a valid same-item id survives, named from the item', () {
      final r = resolve(cheeseId)!;
      expect(r.classifierOptionId, cheeseId);
      expect(r.classifierOptionName, 'Cheese', reason: 'trusted name wins');
      expect(r.quantity, 2);
    });

    test('a FOREIGN product option id becomes unsplit', () {
      final r = resolve('other-product-cheese')!;
      expect(r.isClassified, isFalse);
      expect(r.classifierOptionId, '');
      expect(r.quantity, 2, reason: 'the contribution survives');
      expect(r.unit, 'Meat pieces');
    });

    test('a DELETED option id becomes unsplit', () {
      expect(resolve('opt-deleted')!.classifierOptionId, '');
    });

    test('a SELF-reference becomes unsplit', () {
      expect(resolve(size240, self: size240)!.classifierOptionId, '');
    });

    test('an EMPTY id is untouched (already unsplit)', () {
      const plain = KitchenMeat(quantity: 2, unit: 'Meat pieces');
      expect(
        identical(
          resolveTrustedMeatClassifier(
            plain,
            optionNamesById: burgerOptions,
            selfOptionId: size240,
          ),
          plain,
        ),
        isTrue,
      );
    });

    test('a stale order-time answer is cleared when the link dies', () {
      final r = resolveTrustedMeatClassifier(
        const KitchenMeat(
          quantity: 2,
          unit: 'Meat pieces',
          classifierOptionId: 'opt-gone',
          classifierOptionName: 'Cheese',
          classifierSelected: true,
        ),
        optionNamesById: burgerOptions,
        selfOptionId: size240,
      )!;
      expect(r.classifierSelected, isNull);
      expect(r.isClassified, isFalse);
    });

    test('a target whose live name is blank becomes unsplit', () {
      final r = resolveTrustedMeatClassifier(
        sizeMeat(2),
        optionNamesById: const {cheeseId: '   '},
        selfOptionId: size240,
      )!;
      expect(r.isClassified, isFalse);
    });

    test('null in, null out', () {
      expect(
        resolveTrustedMeatClassifier(
          null,
          optionNamesById: burgerOptions,
          selfOptionId: size240,
        ),
        isNull,
      );
    });
  });

  group('G. malformed JSON never becomes an identifier', () {
    test('a non-string id is dropped, contribution intact', () {
      final m = KitchenMeat.tryFromJson({
        'quantity': 2,
        'unit': 'Meat pieces',
        'classifier_option_id': {'amount_minor': 5},
        'classifier_option_name': 'Cheese',
        'classifier_selected': true,
      })!;
      expect(m.classifierOptionId, '');
      expect(m.classifierSelected, isNull);
      expect(m.quantity, 2);
      expect(m.unit, 'Meat pieces');
    });

    test('a non-string name is dropped', () {
      final m = KitchenMeat.tryFromJson({
        'quantity': 2,
        'classifier_option_id': 'x',
        'classifier_option_name': ['Cheese'],
        'classifier_selected': true,
      })!;
      expect(m.isClassified, isFalse);
    });

    test('a non-boolean answer is dropped', () {
      final m = KitchenMeat.tryFromJson({
        'quantity': 2,
        'classifier_option_id': 'x',
        'classifier_option_name': 'Cheese',
        'classifier_selected': 'yes',
      })!;
      expect(m.classifierSelected, isNull);
    });

    test('malformed metadata never suppresses the contribution', () {
      final m = KitchenMeat.tryFromJson({
        'quantity': 2,
        'unit': 'Meat pieces',
        'classifier_option_id': 42,
      })!;
      expect(
        rows(
          aggregateOrderKitchenCounts([
            KitchenCountItemInput(quantity: 3, meats: [m]),
          ]),
        ),
        [(6, 'Meat pieces', '', false)],
      );
    });
  });

  group('M. backward compatibility', () {
    test('a legacy meat_snapshot decodes as unsplit', () {
      final m = KitchenMeat.tryFromJson({'quantity': 2, 'unit': 'قطع لحم'})!;
      expect(m.classifierOptionId, '');
      expect(m.classifierSelected, isNull);
      expect(m.isClassified, isFalse);
    });

    test('an unclassified contribution serializes exactly as before', () {
      expect(const KitchenMeat(quantity: 2, unit: 'قطع لحم').toJson(), {
        'quantity': 2,
        'unit': 'قطع لحم',
      });
    });

    test('a classified contribution round-trips', () {
      final resolved = sizeMeat(2).withClassifierSelected(false);
      final json = resolved.toJson();
      expect(json, {
        'quantity': 2,
        'unit': 'Meat pieces',
        'classifier_option_id': cheeseId,
        'classifier_option_name': 'Cheese',
        'classifier_selected': false,
      });
      expect(KitchenMeat.tryFromJson(json), resolved);
      expect(json.keys.any((k) => k.contains('minor')), isFalse);
    });

    test('the 016 product-level classifier still works (compatibility)', () {
      // Legacy data configured on a PRODUCT resource keeps splitting.
      final counts = aggregateOrderKitchenCounts([
        KitchenCountItemInput(
          quantity: 2,
          prepComponents: classifyPrepComponents(
            const [
              KitchenPrepComponent(
                name: 'Meat pieces',
                quantity: 2,
                classifierOptionId: cheeseId,
                classifierOptionName: 'Cheese',
              ),
            ],
            const {cheeseId},
          ),
        ),
      ]);
      expect(rows(counts), [(4, 'Meat pieces', 'Cheese', true)]);
    });
  });

  group('display wording reuses the 016 patterns', () {
    String withOption(String r, String o) => '$r مع $o';
    String withoutOption(String r, String o) => '$r بدون $o';

    test('classified rows read resource + with/without + option', () {
      final counts = aggregateOrderKitchenCounts([
        burger(pieces: 1, cheese: true, sizeOptionId: size120, linePosition: 1),
        burger(
          pieces: 1,
          cheese: false,
          sizeOptionId: size120,
          linePosition: 2,
        ),
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
        ['Meat pieces مع Cheese', 'Meat pieces بدون Cheese', 'Bread Piece'],
      );
    });
  });
}
