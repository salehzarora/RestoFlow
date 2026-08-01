import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// MONEY-LOCAL-ATOMICITY-003A [E] — the POS MENU SOURCE BOUNDARY fails closed.
///
/// Every identifier on this boundary used to be coerced with
/// `(row['x'] ?? '').toString()`, and the consequence was not a loud failure —
/// it was that the PRODUCT SILENTLY BECAME PLAIN-ADDABLE. A group row with a
/// blank id was still constructed (`id: ''`), its options orphaned under their
/// real `modifier_id`, `groupsForItem` dropped it for having no options, and the
/// add handler took the `groups.isEmpty -> addItem` branch. A required PAID
/// group vanished and the item sold at base price with no indicator.
///
/// THE CHOSEN RULE, stated: a product is UNAVAILABLE when any group associated
/// with it cannot be interpreted safely — not merely the broken group dropped.
/// Dropping only the bad group still sells the item, just without a choice the
/// operator configured and possibly charged for. An unsellable product is a
/// better outcome than an undercharged sale.
///
/// This is the first suite in the repository to feed a `pos_menu` envelope
/// containing `modifiers` / `modifier_options` rows.

const kBase = 4500;
const kBurgerId = 'burger-meat';
const kColaId = 'cola';

class _Transport implements SyncRpcTransport {
  _Transport(this._menu);
  final Map<String, Object?> _menu;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'pos_menu') return _menu;
    return null;
  }
}

Map<String, Object?> envelope({
  List<Object?> modifiers = const [],
  List<Object?> options = const [],
}) => <String, Object?>{
  'ok': true,
  'currency_code': 'ILS',
  'categories': <Object?>[
    <String, Object?>{'id': 'food', 'name': 'Food', 'display_order': 1},
  ],
  'items': <Object?>[
    <String, Object?>{
      'id': kBurgerId,
      'name': 'Burger',
      'base_price_minor': kBase,
      'menu_category_id': 'food',
    },
    <String, Object?>{
      'id': kColaId,
      'name': 'Cola',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
    },
  ],
  'modifiers': modifiers,
  'modifier_options': options,
};

Map<String, Object?> groupRow([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'id': 'grp-meat',
      'menu_item_id': kBurgerId,
      'name': 'Meat',
      'selection_type': 'single',
      'is_required': true,
      ...o,
    };

Map<String, Object?> optionRow([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'id': 'opt-240',
      'modifier_id': 'grp-meat',
      'name': '240g',
      'price_delta_minor': 1500,
      ...o,
    };

Future<PosMenuData> loadMenu(Map<String, Object?> menu) async {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_Transport(menu)),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c.read(posMenuProvider.future);
}

DemoMenuItem itemOf(PosMenuData menu, String id) =>
    menu.items.firstWhere((i) => i.id == id);

void main() {
  test('E0 a HEALTHY configuration is unchanged: the group resolves, the item '
      'stays sellable, and the sheet has its paid option', () async {
    final menu = await loadMenu(
      envelope(modifiers: [groupRow()], options: [optionRow()]),
    );
    final burger = itemOf(menu, kBurgerId);
    expect(burger.isUnavailable, isFalse);
    final groups = menu.groupsForItem(kBurgerId);
    expect(groups, hasLength(1));
    expect(groups.single.id, 'grp-meat');
    expect(groups.single.options.single.priceDeltaMinor, 1500);
  });

  group('[E] a broken GROUP row makes its product unavailable', () {
    for (final entry in <String, Object?>{
      'missing id': null,
      'blank id': '',
      'whitespace id': '   ',
      'non-string id': 7,
      'list id': <Object?>[],
    }.entries) {
      test(
        'E1 group ${entry.key} — the product must NOT become plain-addable',
        () async {
          final g = groupRow();
          if (entry.key == 'missing id') {
            g.remove('id');
          } else {
            g['id'] = entry.value;
          }
          final menu = await loadMenu(
            envelope(modifiers: [g], options: [optionRow()]),
          );

          final burger = itemOf(menu, kBurgerId);
          expect(
            burger.isUnavailable,
            isTrue,
            reason:
                'a required PAID group vanished; selling at base price '
                'would be an under-charge with no indicator',
          );
          expect(
            burger.availabilityReason,
            DemoMenuItem.configurationUnavailableReason,
            reason: 'and the reason is CONFIGURATION, not sold-out',
          );
          expect(
            menu.groupsForItem(kBurgerId),
            isEmpty,
            reason: 'no half-group is offered either',
          );
          // The healthy sibling is untouched.
          expect(itemOf(menu, kColaId).isUnavailable, isFalse);
        },
      );
    }

    test('E2 a group with a missing/blank NAME is broken too', () async {
      for (final bad in <Object?>[null, '', '   ', 7]) {
        final g = groupRow();
        if (bad == null) {
          g.remove('name');
        } else {
          g['name'] = bad;
        }
        final menu = await loadMenu(
          envelope(modifiers: [g], options: [optionRow()]),
        );
        expect(itemOf(menu, kBurgerId).isUnavailable, isTrue);
      }
    });

    // MONEY-CODEX-FINAL-CLOSURE-005 (F3) — THIS EXPECTATION WAS CORRECTED.
    //
    // E3 used to assert that a group with an unreadable `menu_item_id` is simply
    // DROPPED, on the reasoning that "it cannot make any one product unsafe
    // because it never named one". That reasoning is exactly backwards. The
    // group belonged to SOME item. If it was that item's only group, dropping it
    // leaves the item looking PLAIN — `groupsForItem` returns nothing and
    // `pos_menu_screen`'s add handler takes the `groups.isEmpty -> addItem`
    // branch, selling a configured product at base price. The item that is most
    // at risk is precisely the one we cannot identify.
    //
    // There is no field to recover the owner from: `app.pos_menu` emits a
    // modifier row as {id, menu_item_id, name, …} and an option row as
    // {id, modifier_id, name, display_order, price_delta_minor, kitchen_meat} —
    // neither carries a second path to the item. So the affected set cannot be
    // bounded, and the only honest answer is to fail the whole payload closed.
    // The POS then shows its existing safe menu-error state, which is
    // recoverable; an undercharged sale is not.
    test(
      'E3 a group whose owning item cannot be proven fails the WHOLE menu '
      'payload closed — the unidentifiable item is the one most at risk',
      () async {
        for (final badOwner in <Object?>[null, '', '   ', 42, <Object?>[]]) {
          await expectLater(
            loadMenu(
              envelope(
                modifiers: [
                  groupRow({'menu_item_id': badOwner}),
                ],
                options: [optionRow()],
              ),
            ),
            throwsA(isA<PosMenuUnavailable>()),
            reason:
                'menu_item_id ${badOwner.runtimeType}: an entire configured group '
                'was lost and we cannot say whose — any item may now be '
                'plain-addable at base price',
          );
        }
      },
    );
  });

  group('[E] a broken OPTION row makes its product unavailable', () {
    for (final entry in <String, Object?>{
      'missing id': null,
      'blank id': '',
      'non-string id': 7,
    }.entries) {
      test('E4 option ${entry.key} — the group is untrustworthy', () async {
        final o = optionRow();
        if (entry.key == 'missing id') {
          o.remove('id');
        } else {
          o['id'] = entry.value;
        }
        final menu = await loadMenu(
          envelope(modifiers: [groupRow()], options: [o]),
        );
        expect(
          itemOf(menu, kBurgerId).isUnavailable,
          isTrue,
          reason:
              'the cashier would be offered a SUBSET of the real choices, '
              'at the real prices, with no sign one is missing',
        );
      });
    }

    test('E5 a malformed PAID price is the sharpest case', () async {
      for (final bad in <Object?>['1500', 15.0, null, true]) {
        final o = optionRow();
        if (bad == null) {
          o.remove('price_delta_minor');
        } else {
          o['price_delta_minor'] = bad;
        }
        final menu = await loadMenu(
          envelope(modifiers: [groupRow()], options: [o]),
        );
        expect(
          itemOf(menu, kBurgerId).isUnavailable,
          isTrue,
          reason: 'a skipped paid option is a silent under-charge',
        );
      }
    });

    // MONEY-CODEX-FINAL-CORRECTIONS-004 (F3/F6). This test used to wrap its only
    // assertion in `if (groups.isNotEmpty)`, so it could not fail from the
    // direction the whole suite exists to guard: had a change made the product
    // unavailable, or emptied the group list, E6 would still have passed green.
    // It now pins the decided outcome exactly, and asserts the thing that
    // actually protects money — the item cannot be sold plain.
    // MONEY-CODEX-FINAL-CLOSURE-005 (F3) — THIS EXPECTATION WAS CORRECTED.
    //
    // E6 used to assert the healthy outcome: the group keeps its good option and
    // the product stays SELLABLE. That approved the defect. An option whose
    // parent cannot be read belonged to a group belonging to an item, and if
    // that group is not among the declared ones the item looks plain — so a
    // valid sibling proves nothing about what was lost. "One choice we can read"
    // is not "every choice the operator configured".
    //
    // A VALID SIBLING DOES NOT RESCUE THE CONFIGURATION.
    test('E6 an option with an unreadable modifier_id fails the payload closed '
        'even when a VALID sibling option is present', () async {
      for (final badParent in <Object?>[null, '', '   ', 42, <Object?>[]]) {
        await expectLater(
          loadMenu(
            envelope(
              modifiers: [groupRow()],
              options: [
                optionRow(), // the healthy sibling
                optionRow({'id': 'opt-360', 'modifier_id': badParent}),
              ],
            ),
          ),
          throwsA(isA<PosMenuUnavailable>()),
          reason:
              'modifier_id ${badParent.runtimeType}: the lost option may have '
              'been the only one of a required PAID group on some OTHER item',
        );
      }
    });

    test(
      'E6a an option naming an UNKNOWN group fails the payload closed',
      () async {
        await expectLater(
          loadMenu(
            envelope(
              modifiers: [groupRow()],
              options: [
                optionRow(),
                optionRow({
                  'id': 'opt-360',
                  'modifier_id': 'grp-that-is-not-here',
                }),
              ],
            ),
          ),
          throwsA(isA<PosMenuUnavailable>()),
          reason:
              'the parent group is not in this payload, so the owning item cannot '
              'be identified and may look plain',
        );
      },
    );

    test(
      'E6a2 an option row that is not an object at all fails closed',
      () async {
        await expectLater(
          loadMenu(
            envelope(
              modifiers: [groupRow()],
              options: [optionRow(), 'not-an-object'],
            ),
          ),
          throwsA(isA<PosMenuUnavailable>()),
        );
      },
    );

    // THE EXACT CASE CODEX ASKED FOR: a required PAID group whose ONLY option
    // is unattributable. The group then offers nothing, `groupsForItem` would
    // hide it, and the add handler would take the plain `addItem` branch —
    // selling a configured product at its base price with the surcharge gone.
    test('E6b a required PAID group whose ONLY option has an unreadable '
        'modifier_id fails the whole menu payload closed', () async {
      // MONEY-CODEX-FINAL-CLOSURE-005 (F3) upgraded this outcome. An option
      // whose PARENT cannot be read is unattributable — nothing on the row
      // names the owning item and `app.pos_menu` offers no second path to it —
      // so 005 refuses the whole payload rather than guessing which product
      // lost the choice. That is a strictly STRONGER version of the same
      // guarantee, and the 004 intent is intact: the product is never
      // plain-sellable at base price. E6b2 keeps the per-item path covered.
      await expectLater(
        loadMenu(
          envelope(
            modifiers: [groupRow()], // required: true, paid options
            options: [
              optionRow({'id': 'opt-240', 'modifier_id': ''}),
            ],
          ),
        ),
        throwsA(isA<PosMenuUnavailable>()),
        reason:
            'the configured paid choice was lost — selling at base price '
            'would undercharge every customer who ordered it',
      );
    });

    // The ATTRIBUTABLE form of the same defect, so the per-item path stays
    // proven: the option names its group correctly but its OWN fields are
    // unreadable, leaving the group with nothing to offer.
    test('E6b2 a required PAID group whose only option is unreadable makes '
        'exactly THAT product unavailable', () async {
      final menu = await loadMenu(
        envelope(
          modifiers: [groupRow()],
          options: [
            optionRow({'id': ''}), // attributable: modifier_id is fine
          ],
        ),
      );
      final burger = itemOf(menu, kBurgerId);
      expect(burger.isUnavailable, isTrue);
      expect(
        burger.availabilityReason,
        DemoMenuItem.configurationUnavailableReason,
        reason: 'the cashier is told it is a configuration fault, not sold out',
      );
      expect(
        menu.groupsForItem(kBurgerId),
        isEmpty,
        reason:
            'there is no half-group to present — which is exactly why the '
            'item must be blocked rather than silently plain-added',
      );
      expect(
        itemOf(menu, kColaId).isUnavailable,
        isFalse,
        reason: 'ownership is provable here, so the sibling keeps selling',
      );
    });

    // A PADDED identity used to validate (trim) but be stored raw, so it never
    // matched its group — the same silent loss by a different route.
    test('E6c a PADDED modifier_id still matches its group (canonical '
        'identity)', () async {
      final menu = await loadMenu(
        envelope(
          modifiers: [groupRow()],
          options: [
            optionRow({'modifier_id': '  grp-meat  '}),
          ],
        ),
      );
      final groups = menu.groupsForItem(kBurgerId);
      expect(groups, hasLength(1));
      expect(
        groups.single.options.map((o) => o.id).toList(),
        ['opt-240'],
        reason:
            'trimming ONCE at the boundary makes every reference agree; storing '
            'the raw padded value orphaned the option from its own group',
      );
      expect(itemOf(menu, kBurgerId).isUnavailable, isFalse);
    });
  });

  // THE PRODUCTION SCREEN PROOF for E6b. The data assertions above pin the
  // decision; this pins the CONSEQUENCE the money depends on — that the real
  // `PosMenuScreen` add handler cannot reach its `groups.isEmpty -> addItem`
  // branch for a product whose paid configuration was lost. That branch is the
  // undercharge: `pos_menu_screen.dart` adds the item at `item.priceMinor` with
  // no modifier at all.
  testWidgets('E6d PRODUCTION SCREEN: the broken product offers no add action '
      'and cannot create a base-price cart line', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // F3/005: an ATTRIBUTABLE breakage, so a real `PosMenuData` still loads and
    // the screen can be driven. (The unattributable form now fails the whole
    // payload closed — proven by E6b — and there is no screen to test then.)
    final menu = await loadMenu(
      envelope(
        modifiers: [groupRow()], // required, paid
        options: [
          optionRow({'id': ''}),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [posMenuProvider.overrideWith((ref) async => menu)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const PosMenuScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final burgerCard = find.byWidgetPredicate(
      (w) => w is MenuItemCard && w.item.id == kBurgerId,
    );
    final colaCard = find.byWidgetPredicate(
      (w) => w is MenuItemCard && w.item.id == kColaId,
    );
    expect(burgerCard, findsOneWidget, reason: 'it is still VISIBLE to staff');
    expect(colaCard, findsOneWidget);

    // The healthy sibling still offers its add button — so a missing button on
    // the burger means "blocked", not "this screen renders no buttons".
    expect(
      find.descendant(of: colaCard, matching: find.byType(IconButton)),
      findsOneWidget,
      reason:
          'the control case proves the add affordance exists on this screen',
    );
    expect(
      find.descendant(of: burgerCard, matching: find.byType(IconButton)),
      findsNothing,
      reason: 'no add button is offered for a product we cannot price',
    );

    // And the card itself takes no tap.
    await tester.tap(burgerCard, warnIfMissed: false);
    await tester.pumpAndSettle();

    final cart = container.read(cartControllerProvider);
    expect(
      cart.lines,
      isEmpty,
      reason:
          'the plain-add branch would have created a 4500 line and dropped the '
          '1500 paid choice — every such sale undercharges by 15.00',
    );
    expect(cart.subtotalMinor, 0);
  });

  // MONEY-CODEX-FINAL-CLOSURE-005 (F3) — the remaining matrix cases.
  group('[F] every option must map to exactly one valid group', () {
    test('F3-3 an OPTIONAL group with one valid and one malformed option is '
        'still unsafe — optional does not mean free', () async {
      await expectLater(
        loadMenu(
          envelope(
            modifiers: [
              groupRow({'is_required': false, 'selection_type': 'multi'}),
            ],
            options: [
              optionRow(),
              optionRow({'id': 'opt-360', 'modifier_id': ''}),
            ],
          ),
        ),
        throwsA(isA<PosMenuUnavailable>()),
        reason:
            'an optional group still carries PAID choices; losing one silently '
            'undercharges exactly as much as losing a required one',
      );
    });

    test('F3-4 PADDED group and parent ids normalize consistently and stay '
        'healthy', () async {
      final menu = await loadMenu(
        envelope(
          modifiers: [
            groupRow({'id': '  grp-meat  ', 'menu_item_id': '  $kBurgerId  '}),
          ],
          options: [
            optionRow({'modifier_id': ' grp-meat '}),
          ],
        ),
      );
      final groups = menu.groupsForItem(kBurgerId);
      expect(groups, hasLength(1), reason: 'trimmed ONCE, everywhere');
      expect(groups.single.id, 'grp-meat');
      expect(groups.single.options.single.id, 'opt-240');
      expect(itemOf(menu, kBurgerId).isUnavailable, isFalse);
    });

    test('F3-5 an option whose parent group belongs to ANOTHER item affects '
        'that item, and only that item', () async {
      // Two items, two groups. Cola's group loses its only option because that
      // option was attributed to the BURGER's group instead.
      final menu = await loadMenu(
        envelope(
          modifiers: [
            groupRow(),
            groupRow({'id': 'grp-ice', 'menu_item_id': kColaId, 'name': 'Ice'}),
          ],
          options: [
            optionRow(),
            // Declared for Cola's group in spirit, but pointing at the burger's.
            optionRow({'id': 'opt-ice', 'modifier_id': 'grp-meat'}),
          ],
        ),
      );
      expect(
        itemOf(menu, kColaId).isUnavailable,
        isTrue,
        reason: 'Cola\'s group ended up with zero options — a lost choice',
      );
      expect(
        itemOf(menu, kColaId).availabilityReason,
        DemoMenuItem.configurationUnavailableReason,
      );
      expect(
        itemOf(menu, kBurgerId).isUnavailable,
        isFalse,
        reason:
            'the burger group is fully readable and both its options attribute '
            'to it — ownership isolation is provable here, so it keeps selling',
      );
    });

    test('F3-7 a healthy UNRELATED item stays available when one item is '
        'broken', () async {
      final menu = await loadMenu(
        envelope(
          modifiers: [
            groupRow({'name': ''}), // broken: burger only
          ],
          options: [optionRow()],
        ),
      );
      expect(itemOf(menu, kBurgerId).isUnavailable, isTrue);
      expect(
        itemOf(menu, kColaId).isUnavailable,
        isFalse,
        reason: 'a plain product with no configuration cannot have lost one',
      );
    });
  });

  test('E7 a BROKEN group alongside a HEALTHY one still makes the product '
      'unavailable — the safe default for money', () async {
    final menu = await loadMenu(
      envelope(
        modifiers: [
          groupRow(),
          groupRow({'id': '', 'name': 'Extras'}),
        ],
        options: [optionRow()],
      ),
    );
    expect(
      itemOf(menu, kBurgerId).isUnavailable,
      isTrue,
      reason:
          'selling with only the readable half would omit a configured '
          'choice the operator may charge for',
    );
    expect(itemOf(menu, kColaId).isUnavailable, isFalse);
  });

  test('E8 an item with genuinely NO groups stays plainly sellable — the '
      'guard must distinguish "none" from "unreadable"', () async {
    final menu = await loadMenu(envelope());
    expect(itemOf(menu, kBurgerId).isUnavailable, isFalse);
    expect(menu.groupsForItem(kBurgerId), isEmpty);
  });
}
