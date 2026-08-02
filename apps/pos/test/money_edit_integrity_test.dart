import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/format/money_format.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// MONEY-EDIT-INTEGRITY-002C — Codex Blockers 4 and 5, reproduced FIRST.
///
/// Both hazards live in the ONE place a cashier re-opens a configured line: the
/// modifier sheet, prefilled from the cart line but populated from the LIVE
/// menu. The stored line is a frozen order-time snapshot (D-008); the sheet is
/// today's catalogue. Where those two disagree, the sheet currently believes the
/// catalogue and says nothing.
///
/// **Blocker 4 — moved option.** A stored selection is considered resolved when
/// its option id appears ANYWHERE in the current groups. Move an option from
/// "Meat" to "Chef's choice" in the Dashboard and the sheet silently adopts the
/// new group's semantics, name and price for a line that was never configured
/// that way.
///
/// **Blocker 5 — live base price.** The sheet renders `widget.item.priceMinor`
/// (today's price) as the base AND as the running total's base, while Save keeps
/// the line's frozen `basePriceMinorSnapshot`. Change the product price in the
/// Dashboard and the amount shown before Save is not the amount Save produces.
///
/// Every money assertion is an exact integer minor-unit value (D-007).

const kFrozenBase = 4500;
const kLiveBase = 5000; // the Dashboard raised the price AFTER the line existed
const k240 = 1500;
const k240Live = 2000; // ...and the option's delta moved too
const k360 = 2500;

/// The item AS IT WAS when the cart line was created — this is what
/// `addItemWithModifiers` snapshots into `basePriceMinorSnapshot`.
const burgerAtAddTime = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kFrozenBase,
  categoryId: 'food',
  categoryName: 'Food',
);

/// The SAME product as the live menu serves it TODAY, after a Dashboard price
/// change. Same id, so the edit path finds it.
const burgerToday = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kLiveBase,
  categoryId: 'food',
  categoryName: 'Food',
);

const meatGroup = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Meat',
  singleSelect: true,
  isRequired: true,
  options: [
    PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
    PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: k240),
    PosModifierOption(id: 'opt-360', name: '360g', priceDeltaMinor: k360),
  ],
);

/// The Dashboard raised the 240g surcharge from 15.00 to 20.00.
const meatGroupRepriced = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Meat',
  singleSelect: true,
  isRequired: true,
  options: [
    PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
    PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: k240Live),
    PosModifierOption(id: 'opt-360', name: '360g', priceDeltaMinor: k360),
  ],
);

// ---------------------------------------------------------------------------
// BLOCKER 4 — the option was MOVED to a different group.
//
// The shape matters. A REQUIRED single-select group would block Save by
// accident (its own minimum goes unmet once the option leaves), which hides the
// defect behind an unrelated guard. The real exposure is an OPTIONAL
// multi-select group: nothing else objects, Save stays live, and confirming
// rewrites a paid selection into whatever the option means in its NEW home.
// ---------------------------------------------------------------------------
const kBacon = 800;
const kCheese = 300;

/// Extras AS IT WAS: bacon is a paid extra here.
const extrasGroup = PosModifierGroup(
  id: 'grp-extras',
  menuItemId: 'burger-meat',
  name: 'Extras',
  maxSelect: 3,
  options: [
    PosModifierOption(id: 'opt-bacon', name: 'Bacon', priceDeltaMinor: kBacon),
    PosModifierOption(
      id: 'opt-cheese',
      name: 'Cheese',
      priceDeltaMinor: kCheese,
    ),
  ],
);

/// Extras TODAY: bacon was moved out.
const extrasGroupWithoutBacon = PosModifierGroup(
  id: 'grp-extras',
  menuItemId: 'burger-meat',
  name: 'Extras',
  maxSelect: 3,
  options: [
    PosModifierOption(
      id: 'opt-cheese',
      name: 'Cheese',
      priceDeltaMinor: kCheese,
    ),
  ],
);

/// ...into Sauces, where the SAME option id is FREE and named differently.
const saucesGroupWithBacon = PosModifierGroup(
  id: 'grp-sauces',
  menuItemId: 'burger-meat',
  name: 'Sauces',
  maxSelect: 2,
  options: [
    PosModifierOption(id: 'opt-bacon', name: 'House sauce', priceDeltaMinor: 0),
  ],
);

/// The stored selection: bacon, bought at 8.00, inside Extras.
final selectedBaconInExtras = SelectedModifier.fromJson(const <String, Object?>{
  'option_id': 'opt-bacon',
  'modifier_group_id': 'grp-extras',
  'group_name': 'Extras',
  'option_name': 'Bacon',
  'price_delta_minor': kBacon,
  'quantity': 1,
});

/// The stored MEAT selection, carrying the group it was configured against.
///
/// Built through [SelectedModifier.fromJson] ON PURPOSE. The stable group id is
/// the very thing this phase introduces, so a constructor argument could not be
/// written before it existed — and a test that does not COMPILE proves nothing.
/// Expressed as the persisted record instead, this same source is a legacy
/// record today (the key is ignored) and the exact group-id case once the field
/// lands.
final selected240InMeat = SelectedModifier.fromJson(const <String, Object?>{
  'option_id': 'opt-240',
  'modifier_group_id': 'grp-meat',
  'group_name': 'Meat',
  'option_name': '240g',
  'price_delta_minor': k240,
  'quantity': 1,
});

PosMenuData menuWith(
  List<PosModifierGroup> groups, {
  DemoMenuItem item = burgerAtAddTime,
}) => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'food',
      name: 'Food',
      icon: Icons.lunch_dining,
      color: Colors.orange,
    ),
  ],
  items: [item],
  currencyCode: 'ILS',
  modifierGroups: groups,
);

/// Pumps the real POS screen with one cart line already configured at 240g,
/// frozen at [kFrozenBase], over whatever the live [menu] says today.
Future<ProviderContainer> pumpConfigured(
  WidgetTester tester, {
  required PosMenuData menu,
  List<SelectedModifier> selections = const <SelectedModifier>[],
}) async {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posMenuProvider.overrideWith((ref) async => menu),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(cartControllerProvider.notifier)
      .addItemWithModifiers(
        burgerAtAddTime,
        selections.isEmpty ? [selected240InMeat] : selections,
      );

  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

CartViewState viewOf(ProviderContainer c) => c.read(cartControllerProvider);

Future<void> openEdit(
  WidgetTester tester,
  ProviderContainer c, {
  int lineIndex = 0,
}) async {
  final lineId = viewOf(c).lines[lineIndex].lineId;
  final edit = find.byKey(Key('cart-edit-$lineId'));
  expect(edit, findsOneWidget, reason: 'the cart line offers Edit');
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);
}

Finder confirmButton() => find.byKey(const Key('modifier-add-button'));

bool saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(confirmButton()).onPressed != null;

Future<void> save(WidgetTester tester) async {
  await tester.tap(confirmButton());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The money string the sheet renders for [minor], as the sheet formats it.
String money(int minor) => MoneyFormatter.formatMinor(minor, 'ILS');

void main() {
  // =========================================================================
  group('A. BLOCKER 4 — an option MOVED to another group must not resolve', () {
    testWidgets('A1 a stored selection whose option now lives in a DIFFERENT '
        'group is unresolved, and Save is blocked', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [extrasGroupWithoutBacon, saucesGroupWithBacon]),
        selections: [selectedBaconInExtras],
      );
      expect(viewOf(c).lines.single.lineTotalMinor, kFrozenBase + kBacon);

      await openEdit(tester, c);
      expect(
        saveEnabled(tester),
        isFalse,
        reason:
            'opt-bacon exists today only inside grp-sauces, where it is FREE '
            'and named "House sauce". Nothing else objects — both groups are '
            'optional — so Save stays live and confirming would rewrite an '
            '8.00 paid extra into a free sauce the cashier never chose.',
      );
    });

    testWidgets('A2 the cashier is TOLD, rather than shown a sheet that looks '
        'ordinary', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [extrasGroupWithoutBacon, saucesGroupWithBacon]),
        selections: [selectedBaconInExtras],
      );
      await openEdit(tester, c);
      expect(
        find.byKey(const Key('modifier-saved-options-changed')),
        findsOneWidget,
        reason: 'a MOVED option is not "no longer on the menu" — say so truly',
      );
    });

    testWidgets('A3 the moved option is NOT preselected under its new group '
        '— no substitution, no adopted semantics', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [extrasGroupWithoutBacon, saucesGroupWithBacon]),
        selections: [selectedBaconInExtras],
      );
      await openEdit(tester, c);
      // Sauces (max 2) must report ZERO selected. Under the old cross-group
      // match the stored bacon was seeded INTO Sauces, so this group showed
      // 1/2 — the sheet had adopted an option the cashier never chose there,
      // at that group's free price.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.posModifierSelectedCount(0, 2)),
        findsOneWidget,
        reason: 'the moved option must not be preselected under its new group',
      );
      final line = viewOf(c).lines.single;
      expect(line.modifiers.single.priceDeltaMinor, kBacon);
      expect(line.modifiers.single.optionName, 'Bacon');
    });

    testWidgets('A4 Cancel leaves the line byte-for-byte unchanged', (
      tester,
    ) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [extrasGroupWithoutBacon, saucesGroupWithBacon]),
        selections: [selectedBaconInExtras],
      );
      final before = viewOf(c).lines.single;
      final beforeMods = [
        for (final m in before.modifiers) m.toJson().toString(),
      ];

      await openEdit(tester, c);
      await tester.tapAt(const Offset(20, 20)); // dismiss
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final after = viewOf(c).lines.single;
      expect([
        for (final m in after.modifiers) m.toJson().toString(),
      ], beforeMods);
      expect(after.lineTotalMinor, kFrozenBase + kBacon);
      expect(viewOf(c).subtotalMinor, kFrozenBase + kBacon);
    });

    testWidgets('A6 an OPTIONAL group whose option merely VANISHED is still '
        'blocked — the existing removed-option guard is unchanged', (
      tester,
    ) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [extrasGroupWithoutBacon]),
        selections: [selectedBaconInExtras],
      );
      await openEdit(tester, c);
      expect(saveEnabled(tester), isFalse);
      expect(
        find.byKey(const Key('modifier-saved-options-unavailable')),
        findsOneWidget,
        reason: 'genuinely gone is genuinely "no longer on the menu"',
      );
    });

    testWidgets('A5 the SAME option id in the SAME group still resolves — the '
        'guard must not break ordinary editing', (tester) async {
      final c = await pumpConfigured(tester, menu: menuWith(const [meatGroup]));
      await openEdit(tester, c);
      expect(
        saveEnabled(tester),
        isTrue,
        reason: 'grp-meat still owns opt-240; this is a healthy edit',
      );
    });
  });

  // =========================================================================
  group('E. BLOCKER 5 — the edit sheet must show the FROZEN base price', () {
    testWidgets('E1 the base price shown when editing is the LINE\'s frozen '
        '45.00, not today\'s 50.00', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroup], item: burgerToday),
      );
      expect(viewOf(c).lines.single.unitPriceMinor, kFrozenBase);

      await openEdit(tester, c);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.posModifierBasePrice(ltrIsolate(money(kFrozenBase)))),
        findsOneWidget,
        reason: 'the cashier is editing a line priced at 45.00',
      );
      expect(
        find.text(l10n.posModifierBasePrice(ltrIsolate(money(kLiveBase)))),
        findsNothing,
        reason: "today's catalogue price is not this line's price",
      );
    });

    testWidgets('E2 the running TOTAL is 60.00 (frozen 45.00 + 15.00), never '
        '65.00', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroup], item: burgerToday),
      );
      await openEdit(tester, c);
      expect(
        find.text(money(kFrozenBase + k240)),
        findsWidgets,
        reason: 'the amount shown must be the amount Save will produce',
      );
      expect(
        find.text(money(kLiveBase + k240)),
        findsNothing,
        reason: 'displaying 65.00 and saving 60.00 is the divergence itself',
      );
    });

    testWidgets('E3 Save without changes keeps the frozen base — the displayed '
        'amount and the resulting line agree exactly', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroup], item: burgerToday),
      );
      await openEdit(tester, c);
      expect(saveEnabled(tester), isTrue);
      await save(tester);

      final line = viewOf(c).lines.single;
      expect(line.unitPriceMinor, kFrozenBase);
      expect(line.lineTotalMinor, kFrozenBase + k240);
      expect(viewOf(c).subtotalMinor, kFrozenBase + k240);
    });

    testWidgets('E4 at item quantity 2 the sheet shows the LINE total 120.00 '
        '(it carries the quantity) and the line stays 120.00 under the 002A '
        'rule', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroup], item: burgerToday),
      );
      final lineId = viewOf(c).lines.single.lineId;
      c.read(cartControllerProvider.notifier).increaseQuantity(lineId);
      await tester.pump();
      expect(viewOf(c).lines.single.lineTotalMinor, 2 * (kFrozenBase + k240));

      await openEdit(tester, c);
      expect(
        find.text(money(2 * (kFrozenBase + k240))),
        findsWidgets,
        // POS-MODIFIER-SHEET-QUANTITY-003: the sheet now carries the line's
        // quantity, so it shows what will be saved rather than a per-unit
        // amount the cashier would have to multiply mentally. The frozen base
        // and the 002A line formula are unchanged and still asserted below.
        reason:
            'the edit sheet opens at the line quantity and shows qty x unit',
      );
      await save(tester);
      expect(
        viewOf(c).lines.single.lineTotalMinor,
        2 * (kFrozenBase + k240),
        reason: 'qty x (base + mods) — the corrected 002A formula',
      );
    });

    testWidgets('E5 ADD mode is unchanged — a NEW line uses today\'s price', (
      tester,
    ) async {
      await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroup], item: burgerToday),
      );
      // Tap the menu card to ADD a second, brand-new configured line.
      final card = find.text('Burger').first;
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.posModifierBasePrice(ltrIsolate(money(kLiveBase)))),
        findsOneWidget,
        reason: 'a new line is priced at the CURRENT catalogue price',
      );
    });
  });

  // =========================================================================
  group('F. a changed catalogue delta must not silently reprice a stored '
      'selection', () {
    testWidgets('F1 opening and saving WITHOUT touching the selection keeps '
        'the stored 15.00 — the sheet shows 60.00 and saves 60.00', (
      tester,
    ) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroupRepriced], item: burgerToday),
      );
      await openEdit(tester, c);

      expect(
        find.text(money(kFrozenBase + k240)),
        findsWidgets,
        reason: 'an untouched selection keeps its order-time snapshot (D-008)',
      );
      expect(
        find.text(money(kFrozenBase + k240Live)),
        findsNothing,
        reason: 'merely LOOKING at a line must not reprice it',
      );

      await save(tester);
      final line = viewOf(c).lines.single;
      expect(line.modifiers.single.priceDeltaMinor, k240);
      expect(line.lineTotalMinor, kFrozenBase + k240);
    });

    testWidgets('F2 actively choosing a DIFFERENT option takes that option\'s '
        'CURRENT delta, and the display matches the result', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroupRepriced], item: burgerToday),
      );
      await openEdit(tester, c);
      await tester.tap(find.text('360g'));
      await tester.pump();

      expect(find.text(money(kFrozenBase + k360)), findsWidgets);
      await save(tester);

      final line = viewOf(c).lines.single;
      expect(line.modifiers.single.optionId, 'opt-360');
      expect(line.modifiers.single.priceDeltaMinor, k360);
      expect(line.lineTotalMinor, kFrozenBase + k360);
    });

    testWidgets('F3 choosing AWAY and BACK is an active re-selection: the '
        'option takes its CURRENT 20.00 delta, and the sheet says so BEFORE '
        'Save', (tester) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroupRepriced], item: burgerToday),
      );
      await openEdit(tester, c);
      await tester.tap(find.text('360g'));
      await tester.pump();
      await tester.tap(find.text('240g'));
      await tester.pump();

      expect(
        find.text(money(kFrozenBase + k240Live)),
        findsWidgets,
        reason: 'the cashier actively picked 240g at its current price',
      );
      await save(tester);

      final line = viewOf(c).lines.single;
      expect(line.modifiers.single.optionId, 'opt-240');
      expect(
        line.modifiers.single.priceDeltaMinor,
        k240Live,
        reason: 'display and Save must agree; the sheet showed 65.00',
      );
      expect(line.lineTotalMinor, kFrozenBase + k240Live);
    });

    testWidgets('F4 a sibling configured line keeps its own money throughout', (
      tester,
    ) async {
      final c = await pumpConfigured(
        tester,
        menu: menuWith(const [meatGroupRepriced], item: burgerToday),
      );
      c.read(cartControllerProvider.notifier).addItemWithModifiers(
        burgerAtAddTime,
        [selected240InMeat],
      );
      await tester.pump();
      final siblingId = viewOf(c).lines.last.lineId;

      await openEdit(tester, c);
      await tester.tap(find.text('360g'));
      await tester.pump();
      await save(tester);

      final sibling = viewOf(c).lines.firstWhere((l) => l.lineId == siblingId);
      expect(sibling.modifiers.single.priceDeltaMinor, k240);
      expect(sibling.lineTotalMinor, kFrozenBase + k240);
    });
  });
}
