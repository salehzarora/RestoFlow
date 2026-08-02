@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        KitchenDispatchDocument,
        KitchenDispatchItem,
        KitchenDispatchModifier,
        KitchenDispatchModifierPrep,
        KitchenSpoolDispatchType;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenCount, KitchenMeat, KitchenPrepComponent, OrderType;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/spool/kitchen_ticket_renderer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-019 — the POS + durable spool sides.
///
/// The meat comes from the SIZE option (120g → 1 Meat piece, 240g → 2) and a
/// Cheese option in another group classifies it. This exercises the real POS
/// ticket builder, the trusted menu boundary, and the durable spool decode +
/// render — the boundary that silently dropped metadata in the 016 round.
void main() {
  const size120 = 'opt-size-120';
  const size240 = 'opt-size-240';
  const cheeseId = 'opt-cheese';
  const onionId = 'opt-onion';
  const foreignCheeseId = 'chicken-opt-cheese';

  /// The burger: Bread ×1 at product level; the meat lives on the size options.
  const burger = DemoMenuItem(
    id: 'burger',
    name: 'Burger',
    priceMinor: 4500,
    categoryId: 'meals',
    categoryName: 'Meals',
    attributes: <String, dynamic>{
      'prep_components': [
        {'name': 'Bread', 'quantity': 1, 'unit': 'Piece'},
      ],
    },
  );

  KitchenMeat sizeMeat(num pieces, {String classifier = cheeseId}) =>
      KitchenMeat(
        quantity: pieces,
        unit: 'Meat pieces',
        classifierOptionId: classifier,
        classifierOptionName: classifier.isEmpty ? '' : 'Cheese',
      );

  SelectedModifier size(
    String id,
    String name,
    num pieces, {
    String classifier = cheeseId,
    int quantity = 1,
  }) => SelectedModifier(
    optionId: id,
    groupName: 'Size',
    optionName: name,
    priceDeltaMinor: 0,
    quantity: quantity,
    kitchenMeat: sizeMeat(pieces, classifier: classifier),
  );

  SelectedModifier cheese({int quantity = 1}) => SelectedModifier(
    optionId: cheeseId,
    groupName: 'Extras',
    optionName: 'Cheese',
    priceDeltaMinor: 300,
    quantity: quantity,
  );

  const onion = SelectedModifier(
    optionId: onionId,
    groupName: 'Extras',
    optionName: 'Onion',
    priceDeltaMinor: 0,
  );

  CartLineView line({
    required String lineId,
    required int quantity,
    required List<SelectedModifier> modifiers,
    int position = 0,
  }) => CartLineView(
    lineId: lineId,
    menuItemId: 'burger',
    name: 'Burger',
    quantity: quantity,
    unitPriceMinor: 4500,
    lineTotalMinor: 4500 * quantity,
    currencyCode: 'ILS',
    modifiers: modifiers,
    itemDisplayOrder: position,
  );

  const prepByItemId = <String, List<KitchenPrepComponent>>{
    'burger': [KitchenPrepComponent(name: 'Bread', quantity: 1, unit: 'Piece')],
  };

  List<(num, String, String, bool)> rows(List<KitchenCount> counts) => [
    for (final c in counts)
      (c.quantity, c.label, c.classifier, c.classifierSelected),
  ];

  KdsTicketView ticket(List<CartLineView> lines, {String? roundId}) =>
      kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: prepByItemId,
        roundId: roundId,
        roundNumber: roundId == null ? null : 2,
        lines: lines,
      );

  // =====================================================================
  group('A/B. Saleh\'s examples on the real POS ticket', () {
    test('A. 120g+Cheese, 120g plain, 240g+Cheese', () {
      final t = ticket([
        line(
          lineId: 'l1',
          quantity: 1,
          position: 1,
          modifiers: [size(size120, '120g', 1), cheese()],
        ),
        line(
          lineId: 'l2',
          quantity: 1,
          position: 2,
          modifiers: [size(size120, '120g', 1)],
        ),
        line(
          lineId: 'l3',
          quantity: 1,
          position: 3,
          modifiers: [size(size240, '240g', 2), cheese()],
        ),
      ]);
      expect(rows(t.kitchenCounts), [
        (3, 'Meat pieces', 'Cheese', true),
        (1, 'Meat pieces', 'Cheese', false),
        (3, 'Bread Piece', '', false),
      ]);
    });

    test('B. three 240g burgers, two with Cheese', () {
      final t = ticket([
        line(
          lineId: 'l1',
          quantity: 2,
          position: 1,
          modifiers: [size(size240, '240g', 2), cheese()],
        ),
        line(
          lineId: 'l2',
          quantity: 1,
          position: 2,
          modifiers: [size(size240, '240g', 2)],
        ),
      ]);
      expect(rows(t.kitchenCounts), [
        (4, 'Meat pieces', 'Cheese', true),
        (2, 'Meat pieces', 'Cheese', false),
        (3, 'Bread Piece', '', false),
      ]);
    });

    test('no separate Cheese row, and no size-named rows', () {
      final t = ticket([
        line(
          lineId: 'l1',
          quantity: 1,
          modifiers: [size(size240, '240g', 2), cheese()],
        ),
      ]);
      final labels = t.kitchenCounts.map((c) => c.label).toList();
      expect(labels, isNot(contains('Cheese')));
      expect(labels, isNot(contains('240g')));
      expect(labels, ['Meat pieces', 'Bread Piece']);
    });
  });

  group('E/F. quantity and unrelated options', () {
    test('Cheese ×4 does not multiply the meat', () {
      final t = ticket([
        line(
          lineId: 'l1',
          quantity: 1,
          modifiers: [size(size240, '240g', 2), cheese(quantity: 4)],
        ),
      ]);
      expect(rows(t.kitchenCounts).first, (2, 'Meat pieces', 'Cheese', true));
    });

    test('Onion alone leaves the line in the without bucket', () {
      final t = ticket([
        line(
          lineId: 'l1',
          quantity: 2,
          modifiers: [size(size240, '240g', 2), onion],
        ),
      ]);
      expect(rows(t.kitchenCounts).first, (4, 'Meat pieces', 'Cheese', false));
    });

    test('an unclassified size keeps the old unsplit contribution', () {
      final t = ticket([
        line(
          lineId: 'l1',
          quantity: 3,
          modifiers: [
            size(size240, '240g', 2, classifier: ''),
            cheese(),
          ],
        ),
      ]);
      expect(rows(t.kitchenCounts).first, (6, 'Meat pieces', '', false));
    });
  });

  // =====================================================================
  group('G. the POS menu boundary rejects untrusted links', () {
    PosMenuData menuWith(String classifierId, {String on = size240}) =>
        PosMenuData.withTrustedPrepClassifiers(
          PosMenuData(
            categories: const [],
            items: const [burger],
            currencyCode: 'ILS',
            modifierGroups: [
              PosModifierGroup(
                id: 'grp-size',
                menuItemId: 'burger',
                name: 'Size',
                options: [
                  PosModifierOption(
                    id: size240,
                    name: '240g',
                    priceDeltaMinor: 0,
                    kitchenMeat: on == size240
                        ? sizeMeat(2, classifier: classifierId)
                        : sizeMeat(2),
                  ),
                ],
              ),
              const PosModifierGroup(
                id: 'grp-extras',
                menuItemId: 'burger',
                name: 'Extras',
                options: [
                  PosModifierOption(
                    id: cheeseId,
                    name: 'Cheese',
                    priceDeltaMinor: 300,
                  ),
                ],
              ),
              // A DIFFERENT product whose option is also called "Cheese".
              const PosModifierGroup(
                id: 'grp-chicken',
                menuItemId: 'chicken',
                name: 'Extras',
                options: [
                  PosModifierOption(
                    id: foreignCheeseId,
                    name: 'Cheese',
                    priceDeltaMinor: 300,
                  ),
                ],
              ),
            ],
          ),
        );

    KitchenMeat? meatOf(PosMenuData menu) => menu.modifierGroups
        .firstWhere((g) => g.id == 'grp-size')
        .options
        .single
        .kitchenMeat;

    test('a same-item Cheese id survives the boundary', () {
      final m = meatOf(menuWith(cheeseId))!;
      expect(m.classifierOptionId, cheeseId);
      expect(m.classifierOptionName, 'Cheese');
      expect(m.quantity, 2);
    });

    test('another product\'s Cheese id is STRIPPED', () {
      final m = meatOf(menuWith(foreignCheeseId))!;
      expect(m.isClassified, isFalse);
      expect(m.classifierOptionId, '');
      expect(m.quantity, 2, reason: 'the contribution survives');
      expect(m.unit, 'Meat pieces');
    });

    test('a deleted id is STRIPPED', () {
      expect(meatOf(menuWith('opt-gone'))!.classifierOptionId, '');
    });

    test('a SELF-reference is STRIPPED', () {
      expect(meatOf(menuWith(size240))!.classifierOptionId, '');
    });

    test('the trusted name overrides a stale stored name', () {
      final menu = PosMenuData.withTrustedPrepClassifiers(
        PosMenuData(
          categories: const [],
          items: const [burger],
          currencyCode: 'ILS',
          modifierGroups: [
            PosModifierGroup(
              id: 'grp-size',
              menuItemId: 'burger',
              name: 'Size',
              options: [
                PosModifierOption(
                  id: size240,
                  name: '240g',
                  priceDeltaMinor: 0,
                  kitchenMeat: const KitchenMeat(
                    quantity: 2,
                    unit: 'Meat pieces',
                    classifierOptionId: cheeseId,
                    classifierOptionName: 'Free Beer',
                  ),
                ),
              ],
            ),
            const PosModifierGroup(
              id: 'grp-extras',
              menuItemId: 'burger',
              name: 'Extras',
              options: [
                PosModifierOption(
                  id: cheeseId,
                  name: 'Cheese',
                  priceDeltaMinor: 300,
                ),
              ],
            ),
          ],
        ),
      );
      expect(meatOf(menu)!.classifierOptionName, 'Cheese');
    });
  });

  // =====================================================================
  group('I/K. order-time snapshot + Add-items', () {
    test('the snapshot carries the resolved answer to the wire', () {
      final snaps = kitchenMeatSnapshots([size(size240, '240g', 2), cheese()]);
      expect(snaps.single.toJson(), {
        'quantity': 2,
        'unit': 'Meat pieces',
        'classifier_option_id': cheeseId,
        'classifier_option_name': 'Cheese',
        'classifier_selected': true,
      });
      for (final k in snaps.single.toJson().keys) {
        expect(k.contains('minor'), isFalse);
      }
    });

    test('without the classifier the answer is false, not absent', () {
      final snaps = kitchenMeatSnapshots([size(size240, '240g', 2)]);
      expect(snaps.single.classifierSelected, isFalse);
      expect(snaps.single.isClassified, isTrue);
    });

    test('an unclassified contribution serializes as before', () {
      final snaps = kitchenMeatSnapshots([
        size(size240, '240g', 2, classifier: ''),
      ]);
      expect(snaps.single.toJson(), {'quantity': 2, 'unit': 'Meat pieces'});
    });

    test('an Add-items round ticket splits its own items', () {
      final t = ticket([
        line(
          lineId: 'a1',
          quantity: 1,
          modifiers: [size(size240, '240g', 2), cheese()],
        ),
      ], roundId: 'round-2');
      expect(t.roundNumber, 2);
      expect(rows(t.kitchenCounts).first, (2, 'Meat pieces', 'Cheese', true));
    });
  });

  // =====================================================================
  group('J. the durable spool carries the modifier contribution', () {
    KitchenDispatchDocument doc({required bool cheese, int modQty = 1}) =>
        KitchenDispatchDocument(
          serverPayloadVersion: 1,
          kind: KitchenSpoolDispatchType.initialOrder,
          orderCode: '#000042',
          orderType: 'dine_in',
          items: [
            KitchenDispatchItem(
              qty: 1,
              name: 'Burger',
              modifiers: [
                KitchenDispatchModifier(
                  qty: modQty,
                  name: '240g',
                  prep: KitchenDispatchModifierPrep(
                    quantity: 2,
                    unit: 'Meat pieces',
                    classifierOptionId: cheeseId,
                    classifierOptionName: 'Cheese',
                    classifierSelected: cheese,
                  ),
                ),
                if (cheese) KitchenDispatchModifier(qty: 1, name: 'Cheese'),
              ],
            ),
          ],
        );

    List<String> subLines(
      KitchenTicketLabels labels,
      KitchenDispatchDocument d,
    ) {
      final built = KitchenTicketRenderer(labels: labels).buildDocument(d);
      return [
        for (final l in built.lines)
          if (l is pp.PrintTextLine) l.text,
      ].where((t) => t.startsWith('  ')).toList();
    }

    test('a classified contribution prints WITH the option (en)', () {
      expect(
        subLines(KitchenTicketLabels.en, doc(cheese: true)),
        containsAll(<String>['  + 240g', '  • 2 Meat pieces with Cheese']),
      );
    });

    test('and WITHOUT it when unselected', () {
      expect(
        subLines(KitchenTicketLabels.en, doc(cheese: false)),
        contains('  • 2 Meat pieces without Cheese'),
      );
    });

    test('the ar bundle words it in Arabic', () {
      expect(
        subLines(KitchenTicketLabels.ar, doc(cheese: true)),
        contains('  • 2 Meat pieces مع Cheese'),
      );
    });

    test('the option\'s own units scale its contribution on paper', () {
      expect(
        subLines(KitchenTicketLabels.en, doc(cheese: true, modQty: 3)),
        contains('  • 6 Meat pieces with Cheese'),
      );
    });

    test('a modifier with NO contribution prints nothing extra', () {
      final built = KitchenTicketRenderer().buildDocument(
        KitchenDispatchDocument(
          serverPayloadVersion: 1,
          kind: KitchenSpoolDispatchType.initialOrder,
          orderCode: '#1',
          orderType: 'takeaway',
          items: [
            KitchenDispatchItem(
              qty: 1,
              name: 'Burger',
              modifiers: [KitchenDispatchModifier(qty: 1, name: 'Onion')],
            ),
          ],
        ),
      );
      final texts = [
        for (final l in built.lines)
          if (l is pp.PrintTextLine) l.text,
      ];
      expect(texts, contains('  + Onion'));
      expect(texts.where((t) => t.startsWith('  • ')), isEmpty);
    });

    test('the durable document aggregates to the SAME rows as the POS', () {
      // Map the durable modifiers through the shared contract…
      final fromSpool = <KitchenMeat>[
        for (final m in doc(cheese: true).items.single.modifiers)
          if (m.prep case final p?)
            KitchenMeat(
              quantity: (p.quantity ?? 0) * m.qty,
              unit: p.unit ?? '',
              classifierOptionId: p.classifierOptionId ?? '',
              classifierOptionName: p.classifierOptionName ?? '',
              classifierSelected: p.classifierSelected,
            ),
      ];
      final direct = kitchenMeatSnapshots([size(size240, '240g', 2), cheese()]);
      expect(fromSpool, direct);
    });
  });
}
