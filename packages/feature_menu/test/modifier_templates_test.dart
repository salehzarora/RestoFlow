import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Menu/media sprint (Part D): restaurant modifier templates.
///
/// Templates are CLIENT-SIDE copy-on-attach recipes over the EXISTING per-item
/// write seam (menu_upsert_modifier + menu_upsert_modifier_option) — frozen
/// D-031 stays per-item, zero schema change. These tests drive the REAL item
/// editor UI against the demo store and pin:
///   - the picker lists all six templates,
///   - applying Doneness creates a required single group with 3 free options,
///   - applying Extras creates the paid integer-minor deltas (D-007),
///   - option names are seeded as DATA in the ACTIVE locale (Arabic run),
///   - a mid-apply writer failure surfaces the honest error and STOPS,
///   - the created rows are ordinary rows: deletable via the existing flows.
class _FailingOptionStore extends InMemoryMenuStore {
  _FailingOptionStore({super.categories, super.items, required this.failAt});

  /// Fails the [failAt]-th upsertModifierOption call (0-based) with a server
  /// failure; earlier calls succeed normally.
  final int failAt;
  int optionCalls = 0;

  @override
  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    final call = optionCalls++;
    if (call == failAt) return const Failure(MenuServerFailure());
    return super.upsertModifierOption(
      scope: scope,
      id: id,
      modifierId: modifierId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }
}

List<MenuCategory> get _categories => const [
  MenuCategory(
    id: 'cat-1',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    name: 'Grill',
    displayOrder: 0,
    isActive: true,
  ),
];

List<MenuItem> get _items => const [
  MenuItem(
    id: 'item-1',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    menuCategoryId: 'cat-1',
    name: 'House Burger',
    description: null,
    basePriceMinor: 4800,
    currencyCode: demoCurrencyCode,
    defaultStationId: null,
    displayOrder: 0,
    isActive: true,
  ),
];

Future<AppLocalizations> _pump(
  WidgetTester tester,
  InMemoryMenuStore store, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: menuFeatureOverrides(
        scope: demoMenuScope,
        readSource: store,
        writer: store,
      ),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const MenuManagementScreen();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

Future<void> _openItemEditor(WidgetTester tester) async {
  await tester.tap(find.text('House Burger').first);
  await tester.pumpAndSettle();
}

Future<void> _openTemplatePicker(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('menu-template-add')));
  await tester.tap(find.byKey(const ValueKey('menu-template-add')));
  await tester.pumpAndSettle();
}

Future<void> _applyTemplate(WidgetTester tester, String templateId) async {
  await _openTemplatePicker(tester);
  await tester.tap(find.byKey(ValueKey('menu-template-$templateId')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the template picker lists all six templates with localized '
      'names and one-line summaries', (tester) async {
    final store = InMemoryMenuStore(categories: _categories, items: _items);
    final l10n = await _pump(tester, store);
    await _openItemEditor(tester);
    await _openTemplatePicker(tester);

    expect(find.text(l10n.menuTemplatePickerTitle), findsOneWidget);
    for (final id in [
      'burger-toppings',
      'doneness',
      'patty-count',
      'extras',
      'drink-size',
      'spiciness',
    ]) {
      expect(find.byKey(ValueKey('menu-template-$id')), findsOneWidget);
    }
    expect(kMenuModifierTemplates, hasLength(6));
    expect(find.text(l10n.menuTemplateBurgerToppings), findsOneWidget);
    expect(find.text(l10n.menuTemplateDoneness), findsOneWidget);
    expect(find.text(l10n.menuTemplatePattyCount), findsOneWidget);
    expect(find.text(l10n.menuTemplateExtras), findsOneWidget);
    expect(find.text(l10n.menuTemplateDrinkSize), findsOneWidget);
    expect(find.text(l10n.menuTemplateSpiciness), findsOneWidget);

    // One-line summaries: required-single (x3), optional-multi (x2), and
    // optional-single (x1), each with its option count.
    expect(
      find.text(
        '${l10n.menuTemplateRequiredSingle} · ${l10n.menuTemplateOptionCount(3)}',
      ),
      findsNWidgets(3), // Doneness + Patty count + Drink size (3 options each).
    );
    expect(
      find.text(
        '${l10n.menuTemplateOptionalMulti} · ${l10n.menuTemplateOptionCount(5)}',
      ),
      findsOneWidget, // Burger toppings.
    );
    expect(
      find.text(
        '${l10n.menuTemplateOptionalSingle} · ${l10n.menuTemplateOptionCount(3)}',
      ),
      findsOneWidget, // Spiciness.
    );

    // Picking nothing applies nothing. (`.last`: the editor top bar has its
    // own Cancel button behind the dialog.)
    await tester.tap(find.text(l10n.menuCancelAction).last);
    await tester.pumpAndSettle();
    final snapshot = await store.load(demoMenuScope);
    expect(snapshot.modifiers, isEmpty);
    expect(snapshot.modifierOptions, isEmpty);
  });

  testWidgets('applying the Doneness template creates a REQUIRED single '
      'group with 3 free options through the store', (tester) async {
    final store = InMemoryMenuStore(categories: _categories, items: _items);
    final l10n = await _pump(tester, store);
    await _openItemEditor(tester);
    await _applyTemplate(tester, 'doneness');

    final snapshot = await store.load(demoMenuScope);
    final modifiers = snapshot.modifiersForItem('item-1');
    expect(modifiers, hasLength(1));
    final group = modifiers.single;
    expect(group.name, l10n.menuTemplateDoneness);
    expect(group.selectionType, 'single');
    expect(group.isRequired, isTrue);
    expect(group.minSelect, 1);
    expect(group.maxSelect, 1);
    expect(group.isActive, isTrue);
    // Single-select templates stay quantity-free (server rejects otherwise).
    expect(group.allowQuantity, isFalse);
    expect(group.maxQuantity, isNull);

    final options = snapshot.optionsForModifier(group.id);
    expect(options.map((o) => o.name).toList(), [
      l10n.menuTemplateOptRare,
      l10n.menuTemplateOptMediumDoneness,
      l10n.menuTemplateOptWellDone,
    ]);
    for (final option in options) {
      expect(option.priceDeltaMinor, 0);
      expect(option.modifierId, group.id);
    }

    // The modifiers list refreshed like a manual add: the group renders.
    expect(find.text(l10n.menuTemplateDoneness), findsOneWidget);
    expect(find.text(l10n.menuSavedSnack), findsOneWidget);
  });

  testWidgets('applying the Extras template creates the paid integer-minor '
      'deltas (+300/+900/+700/+500)', (tester) async {
    final store = InMemoryMenuStore(categories: _categories, items: _items);
    final l10n = await _pump(tester, store);
    await _openItemEditor(tester);
    await _applyTemplate(tester, 'extras');

    final snapshot = await store.load(demoMenuScope);
    final group = snapshot.modifiersForItem('item-1').single;
    expect(group.name, l10n.menuTemplateExtras);
    expect(group.selectionType, 'multiple');
    expect(group.isRequired, isFalse);
    expect(group.minSelect, 0);
    expect(group.maxSelect, isNull);
    // Quantity settings reach the writer: extras is quantity-capable (the
    // cashier can add extra cheese ×2 etc.), capped at 5 units per option.
    expect(group.allowQuantity, isTrue);
    expect(group.maxQuantity, 5);

    final options = snapshot.optionsForModifier(group.id);
    expect(
      {for (final o in options) o.name: o.priceDeltaMinor},
      {
        l10n.menuTemplateOptExtraCheese: 300,
        l10n.menuTemplateOptExtraPatty: 900,
        l10n.menuTemplateOptFries: 700,
        l10n.menuTemplateOptDrink: 500,
      },
    );
    // Integer minor units end to end (D-007) — pinned as ints.
    for (final option in options) {
      expect(option.priceDeltaMinor, isA<int>());
    }
  });

  testWidgets('an Arabic-locale dashboard seeds Arabic names as DATA '
      '(names are copied in the active locale at apply time)', (tester) async {
    final store = InMemoryMenuStore(categories: _categories, items: _items);
    final l10n = await _pump(tester, store, locale: const Locale('ar'));
    await _openItemEditor(tester);
    await _applyTemplate(tester, 'patty-count');

    final snapshot = await store.load(demoMenuScope);
    final group = snapshot.modifiersForItem('item-1').single;
    // The stored row carries the Arabic string itself (tenant data, not a key).
    expect(group.name, l10n.menuTemplatePattyCount);
    final options = snapshot.optionsForModifier(group.id);
    expect(
      {for (final o in options) o.name: o.priceDeltaMinor},
      {
        l10n.menuTemplateOptSinglePatty: 0,
        l10n.menuTemplateOptDoublePatty: 900,
        l10n.menuTemplateOptTriplePatty: 1800,
      },
    );
  });

  testWidgets('a writer failure mid-apply surfaces the honest error + '
      'partial note and STOPS (no further writes, no rollback pretense)', (
    tester,
  ) async {
    // The group and the first option succeed; the SECOND option fails.
    final store = _FailingOptionStore(
      categories: _categories,
      items: _items,
      failAt: 1,
    );
    final l10n = await _pump(tester, store);
    await _openItemEditor(tester);
    await _applyTemplate(tester, 'burger-toppings');

    // Honest failure surface: the existing failure text + the partial note.
    expect(
      find.text('${l10n.menuWriteProblem}\n${l10n.menuTemplateApplyPartial}'),
      findsOneWidget,
    );
    expect(find.text(l10n.menuSavedSnack), findsNothing);

    // Stopped at the failure: 2 option calls total (1 ok + 1 failed), never
    // the remaining 3 recipe options.
    expect(store.optionCalls, 2);
    final snapshot = await store.load(demoMenuScope);
    final group = snapshot.modifiersForItem('item-1').single;
    expect(group.name, l10n.menuTemplateBurgerToppings);
    final options = snapshot.optionsForModifier(group.id);
    // The already-created row remains visible for manual cleanup.
    expect(options.map((o) => o.name).toList(), [l10n.menuTemplateOptLettuce]);
  });

  testWidgets('template-created rows are ordinary rows: deletable via the '
      'existing option flow', (tester) async {
    final store = InMemoryMenuStore(categories: _categories, items: _items);
    final l10n = await _pump(tester, store);
    await _openItemEditor(tester);
    await _applyTemplate(tester, 'doneness');

    // Delete the 'Rare' option through the existing popup + confirm flow.
    // Popup order inside the editor: 0 = the group card header, then one per
    // option row in display order (1 = Rare, 2 = Medium, 3 = Well done).
    final popups = find.byType(PopupMenuButton<String>);
    expect(popups, findsNWidgets(4));
    await tester.ensureVisible(popups.at(1));
    await tester.tap(popups.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.menuDeleteAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.menuConfirmDelete));
    await tester.pumpAndSettle();

    final snapshot = await store.load(demoMenuScope);
    final group = snapshot.modifiersForItem('item-1').single;
    // Tombstoned like any manually created option (soft delete, D-020).
    expect(snapshot.optionsForModifier(group.id).map((o) => o.name).toList(), [
      l10n.menuTemplateOptMediumDoneness,
      l10n.menuTemplateOptWellDone,
    ]);
  });
}
