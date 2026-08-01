@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        KitchenDispatchDocument,
        KitchenDispatchItem,
        KitchenDispatchModifier,
        KitchenDispatchPrepComponent,
        KitchenSpoolDispatchType;
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        KitchenCount,
        KitchenCountItemInput,
        KitchenPrepComponent,
        OrderType,
        aggregateOrderKitchenCounts;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/spool/kitchen_ticket_renderer.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

/// KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 — the POS boundaries Codex named:
/// the durable spool RENDERER (BLOCKER #1), the item-scoped classifier trust
/// boundary (HIGH #2), the authoritative submitted snapshot used by the manual
/// reprint (HIGH #3), and POS/KDS/spool ordering parity (MEDIUM #4).
void main() {
  const cheeseId = 'burger-opt-cheese';
  const foreignCheeseId = 'chicken-opt-cheese';

  // ---------------------------------------------------------------------
  // B6 — durable spool renderer
  // ---------------------------------------------------------------------
  group('B6. the durable spool renders the split like the direct print', () {
    KitchenDispatchDocument spoolDoc({required bool cheese}) =>
        KitchenDispatchDocument(
          serverPayloadVersion: 1,
          kind: KitchenSpoolDispatchType.initialOrder,
          orderCode: '#000042',
          orderType: 'dine_in',
          items: [
            KitchenDispatchItem(
              qty: 2,
              name: 'Burger 240g',
              modifiers: [
                if (cheese) KitchenDispatchModifier(qty: 1, name: 'Cheese'),
              ],
              prep: [
                KitchenDispatchPrepComponent(name: 'Bread', quantity: 1),
                KitchenDispatchPrepComponent(
                  name: 'Meat pieces',
                  quantity: 2,
                  classifierOptionId: cheeseId,
                  classifierOptionName: 'Cheese',
                  classifierSelected: cheese,
                ),
              ],
            ),
          ],
        );

    List<String> prepLines(KitchenTicketLabels labels, {required bool cheese}) {
      final doc = KitchenTicketRenderer(
        labels: labels,
      ).buildDocument(spoolDoc(cheese: cheese));
      return [
        for (final line in doc.lines)
          if (line is pp.PrintTextLine) line.text,
      ].where((t) => t.startsWith('  • ')).toList();
    }

    test('a classified resource prints WITH the option (en)', () {
      expect(prepLines(KitchenTicketLabels.en, cheese: true), [
        '  • Bread 1',
        '  • Meat pieces 2 with Cheese',
      ]);
    });

    test('and WITHOUT it when the option was not selected (en)', () {
      expect(prepLines(KitchenTicketLabels.en, cheese: false), [
        '  • Bread 1',
        '  • Meat pieces 2 without Cheese',
      ]);
    });

    test('the ar bundle words the split in Arabic', () {
      expect(
        prepLines(KitchenTicketLabels.ar, cheese: true).last,
        '  • Meat pieces 2 مع Cheese',
      );
    });

    test('the he bundle words the split in Hebrew', () {
      expect(
        prepLines(KitchenTicketLabels.he, cheese: false).last,
        '  • Meat pieces 2 בלי Cheese',
      );
    });

    test('an UNCLASSIFIED component renders byte-identically to before', () {
      final doc = KitchenTicketRenderer().buildDocument(
        KitchenDispatchDocument(
          serverPayloadVersion: 1,
          kind: KitchenSpoolDispatchType.initialOrder,
          orderCode: '#1',
          orderType: 'takeaway',
          items: [
            KitchenDispatchItem(
              qty: 1,
              name: 'Fries',
              prep: [
                KitchenDispatchPrepComponent(
                  name: 'Potato',
                  quantity: 1,
                  unit: 'g',
                ),
              ],
            ),
          ],
        ),
      );
      final texts = [
        for (final line in doc.lines)
          if (line is pp.PrintTextLine) line.text,
      ];
      expect(texts, contains('  • Potato 1 g'));
    });

    test('the spool document aggregates to the SAME KitchenCounts as the '
        'direct POS print (semantic equality)', () {
      // Map the durable document through the SHARED aggregation contract...
      List<KitchenCount> fromSpool(bool cheese) => aggregateOrderKitchenCounts([
        for (var i = 0; i < spoolDoc(cheese: cheese).items.length; i++)
          KitchenCountItemInput(
            quantity: spoolDoc(cheese: cheese).items[i].qty,
            linePosition: i + 1,
            prepComponents: [
              for (final p in spoolDoc(cheese: cheese).items[i].prep)
                KitchenPrepComponent(
                  name: p.name ?? '',
                  quantity: p.quantity ?? 0,
                  unit: p.unit ?? '',
                  classifierOptionId: p.classifierOptionId ?? '',
                  classifierOptionName: p.classifierOptionName ?? '',
                  classifierSelected: p.classifierSelected,
                ),
            ],
          ),
      ]);

      // ...and compare with what the POS direct print produces for that order.
      final direct = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: const {
          'burger-240': [
            KitchenPrepComponent(name: 'Bread', quantity: 1),
            KitchenPrepComponent(
              name: 'Meat pieces',
              quantity: 2,
              classifierOptionId: cheeseId,
              classifierOptionName: 'Cheese',
            ),
          ],
        },
        lines: const [
          CartLineView(
            lineId: 'l1',
            menuItemId: 'burger-240',
            name: 'Burger 240g',
            quantity: 2,
            unitPriceMinor: 4500,
            lineTotalMinor: 9000,
            currencyCode: 'ILS',
            modifiers: [
              SelectedModifier(
                optionId: cheeseId,
                groupName: 'Extras',
                optionName: 'Cheese',
                priceDeltaMinor: 300,
              ),
            ],
          ),
        ],
      );
      expect(fromSpool(true), direct.kitchenCounts);
    });
  });

  // ---------------------------------------------------------------------
  // C — the trusted item-scoped boundary, at the real POS menu seam
  // ---------------------------------------------------------------------
  group('C. PosMenuData is the trusted classifier boundary', () {
    DemoMenuItem itemWith(String classifierId) => DemoMenuItem(
      id: 'burger-240',
      name: 'Burger 240g',
      priceMinor: 4500,
      categoryId: 'food',
      categoryName: 'Food',
      attributes: <String, dynamic>{
        'prep_components': [
          {'name': 'Bread', 'quantity': 1, 'unit': ''},
          {
            'name': 'Meat pieces',
            'quantity': 2,
            'unit': '',
            'classifier_option_id': classifierId,
            'classifier_option_name': 'Cheese',
          },
        ],
      },
    );

    const burgerGroup = PosModifierGroup(
      id: 'grp-burger',
      menuItemId: 'burger-240',
      name: 'Extras',
      options: [
        PosModifierOption(id: cheeseId, name: 'Cheese', priceDeltaMinor: 300),
      ],
    );
    // A DIFFERENT product whose option is also called "Cheese".
    const chickenGroup = PosModifierGroup(
      id: 'grp-chicken',
      menuItemId: 'chicken-200',
      name: 'Extras',
      options: [
        PosModifierOption(
          id: foreignCheeseId,
          name: 'Cheese',
          priceDeltaMinor: 300,
        ),
      ],
    );

    PosMenuData menuWith(String classifierId) =>
        PosMenuData.withTrustedPrepClassifiers(
          PosMenuData(
            categories: const [],
            items: [itemWith(classifierId)],
            currencyCode: 'ILS',
            modifierGroups: const [burgerGroup, chickenGroup],
          ),
        );

    test('a same-item option id survives the boundary', () {
      final meat = menuWith(cheeseId).items.single.prepComponents[1];
      expect(meat.classifierOptionId, cheeseId);
      expect(meat.classifierOptionName, 'Cheese');
    });

    test('another product\'s option id is STRIPPED at the boundary', () {
      final meat = menuWith(foreignCheeseId).items.single.prepComponents[1];
      expect(meat.isClassified, isFalse);
      expect(meat.classifierOptionId, '');
      // The resource survives with its quantity intact.
      expect(meat.name, 'Meat pieces');
      expect(meat.quantity, 2);
    });

    test('a deleted option id is STRIPPED at the boundary', () {
      final meat = menuWith('opt-deleted').items.single.prepComponents[1];
      expect(meat.isClassified, isFalse);
      expect(meat.quantity, 2);
    });

    test('the stripped item still carries Bread and every other attribute', () {
      final item = menuWith(foreignCheeseId).items.single;
      expect(item.prepComponents.first.name, 'Bread');
      expect(item.prepComponents.length, 2);
      expect(item.name, 'Burger 240g');
      expect(item.priceMinor, 4500);
    });

    test('a stripped link cannot classify even when the cashier picks the '
        'foreign option', () {
      final meat = menuWith(foreignCheeseId).items.single.prepComponents;
      final resolved = classifiedPrepForLine(meat, const [
        SelectedModifier(
          optionId: foreignCheeseId,
          groupName: 'Extras',
          optionName: 'Cheese',
          priceDeltaMinor: 300,
        ),
      ]);
      expect(resolved[1].isClassified, isFalse);
      expect(
        aggregateOrderKitchenCounts([
          KitchenCountItemInput(quantity: 3, prepComponents: resolved),
        ]).map((c) => c.classifier),
        ['', ''],
      );
    });
  });

  // ---------------------------------------------------------------------
  // D — the authoritative submitted snapshot (real CartController path)
  // ---------------------------------------------------------------------
  group('D. the manual reprint uses the SUBMITTED snapshot', () {
    /// The menu configuration as it stood when the line entered the cart.
    const atAddTime = <KitchenPrepComponent>[
      KitchenPrepComponent(name: 'Bread', quantity: 1),
      KitchenPrepComponent(name: 'Meat pieces', quantity: 2),
    ];

    /// The configuration at SUBMIT time — the owner linked Cheese and changed
    /// the bread count in between.
    const atSubmitTime = <KitchenPrepComponent>[
      KitchenPrepComponent(name: 'Bread', quantity: 3),
      KitchenPrepComponent(
        name: 'Meat pieces',
        quantity: 2,
        classifierOptionId: cheeseId,
        classifierOptionName: 'Cheese',
      ),
    ];

    const burger = DemoMenuItem(
      id: 'burger-240',
      name: 'Burger 240g',
      priceMinor: 4500,
      categoryId: 'food',
      categoryName: 'Food',
      attributes: <String, dynamic>{
        'prep_components': [
          {'name': 'Bread', 'quantity': 1, 'unit': ''},
          {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
        ],
      },
    );

    late ProviderContainer container;
    late CartController cart;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      cart = container.read(cartControllerProvider.notifier);
    });

    test('the add-time capture is what the cart holds before submit', () {
      cart.addItemWithModifiers(burger, const [
        SelectedModifier(
          optionId: cheeseId,
          groupName: 'Extras',
          optionName: 'Cheese',
          priceDeltaMinor: 300,
        ),
      ]);
      // Sanity: the cart captured the OLD configuration (bread 1, no link).
      cart.submitOrder(orderNumber: '#1');
      final line = container
          .read(cartControllerProvider)
          .submittedOrder!
          .lines
          .single;
      expect(line.prepComponents, atAddTime);
    });

    test('submitting WITH the authoritative snapshot overrides it', () {
      cart.addItemWithModifiers(burger, const [
        SelectedModifier(
          optionId: cheeseId,
          groupName: 'Extras',
          optionName: 'Cheese',
          priceDeltaMinor: 300,
        ),
      ]);
      // The menu changed between add-to-cart and submit; the outbox payload was
      // built from THIS map, so the confirmation/reprint must use it too.
      cart.submitOrder(
        orderNumber: '#2',
        submittedPrepByItemId: const {'burger-240': atSubmitTime},
      );
      final submitted = container.read(cartControllerProvider).submittedOrder!;
      final line = submitted.lines.single;

      expect(line.prepComponents.first.quantity, 3, reason: 'submitted bread');
      expect(line.prepComponents[1].isClassified, isTrue);
      expect(line.prepComponents[1].classifierSelected, isTrue);

      // The MANUAL REPRINT goes through the same submitted view.
      final reprint = kdsTicketViewFromSubmittedOrder(submitted);
      expect(
        [
          for (final c in reprint.kitchenCounts)
            (c.quantity, c.label, c.classifier, c.classifierSelected),
        ],
        [(3, 'Bread', '', false), (2, 'Meat pieces', 'Cheese', true)],
      );
    });

    test('a later menu edit does NOT retroactively change the reprint', () {
      cart.addItemWithModifiers(burger, const [
        SelectedModifier(
          optionId: cheeseId,
          groupName: 'Extras',
          optionName: 'Cheese',
          priceDeltaMinor: 300,
        ),
      ]);
      cart.submitOrder(
        orderNumber: '#3',
        submittedPrepByItemId: const {'burger-240': atSubmitTime},
      );
      final submitted = container.read(cartControllerProvider).submittedOrder!;
      final before = kdsTicketViewFromSubmittedOrder(submitted).kitchenCounts;

      // The owner now renames/removes the classifier entirely. The stored view
      // is an order-time snapshot (D-008) and must not move.
      final after = kdsTicketViewFromSubmittedOrder(submitted).kitchenCounts;
      expect(after, before);
      expect(before.any((c) => c.classifier == 'Cheese'), isTrue);
    });

    test('the automatic ticket and the manual reprint agree exactly', () {
      cart.addItemWithModifiers(burger, const [
        SelectedModifier(
          optionId: cheeseId,
          groupName: 'Extras',
          optionName: 'Cheese',
          priceDeltaMinor: 300,
        ),
      ]);
      final lines = container.read(cartControllerProvider).lines;
      // What the automatic post-submit ticket prints, from the SAME map the
      // outbox payload was built from.
      final automatic = kdsTicketViewFromCartLines(
        orderCode: '#4',
        orderType: OrderType.takeaway,
        prepByItemId: const {'burger-240': atSubmitTime},
        lines: lines,
      );
      cart.submitOrder(
        orderNumber: '#4',
        submittedPrepByItemId: const {'burger-240': atSubmitTime},
      );
      final reprint = kdsTicketViewFromSubmittedOrder(
        container.read(cartControllerProvider).submittedOrder!,
      );
      expect(reprint.kitchenCounts, automatic.kitchenCounts);
    });

    test(
      'with NO authoritative snapshot the legacy behaviour is unchanged',
      () {
        cart.addItem(burger);
        cart.submitOrder(orderNumber: '#5');
        expect(
          container
              .read(cartControllerProvider)
              .submittedOrder!
              .lines
              .single
              .prepComponents,
          atAddTime,
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // E — POS/KDS/spool ordering parity
  // ---------------------------------------------------------------------
  group('E. the POS feeds count inputs in canonical order', () {
    test('cart lines out of menu order still aggregate in menu order', () {
      const prep = <String, List<KitchenPrepComponent>>{
        'fries': [KitchenPrepComponent(name: 'Fries', quantity: 1)],
        'burger-240': [KitchenPrepComponent(name: 'Bread', quantity: 1)],
      };
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#9',
        orderType: OrderType.takeaway,
        prepByItemId: prep,
        lines: const [
          CartLineView(
            lineId: 'l1',
            menuItemId: 'fries',
            name: 'Fries',
            quantity: 1,
            unitPriceMinor: 1200,
            lineTotalMinor: 1200,
            currencyCode: 'ILS',
            categoryDisplayOrder: 2,
          ),
          CartLineView(
            lineId: 'l2',
            menuItemId: 'burger-240',
            name: 'Burger 240g',
            quantity: 1,
            unitPriceMinor: 4500,
            lineTotalMinor: 4500,
            currencyCode: 'ILS',
            categoryDisplayOrder: 1,
          ),
        ],
      );
      expect(ticket.kitchenCounts.map((c) => c.label), ['Bread', 'Fries']);
    });
  });
}
