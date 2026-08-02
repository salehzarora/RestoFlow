import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-019 — the corrected admin configuration.
///
/// The "Split by option" picker moves OFF the product's general preparation rows
/// (where Saleh would have had to duplicate 120g/240g/Meat pieces) and ONTO the
/// modifier option's own kitchen preparation contribution — beside the quantity
/// it re-buckets. A size option can then be split by Cheese from another group
/// on the same item.

class _RecordingStore extends InMemoryMenuStore {
  _RecordingStore({
    super.categories,
    super.items,
    super.modifiers,
    super.modifierOptions,
  });

  int optionCalls = 0;
  Map<String, dynamic>? lastKitchenMeat;
  Map<String, dynamic>? lastAttributes;

  @override
  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int? displayOrder,
    bool isActive = true,
    Map<String, dynamic>? kitchenMeat,
  }) {
    optionCalls++;
    lastKitchenMeat = kitchenMeat;
    return super.upsertModifierOption(
      scope: scope,
      id: id,
      modifierId: modifierId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
      kitchenMeat: kitchenMeat,
    );
  }

  @override
  Future<MenuWriteOutcome> upsertItem({
    required MenuScope scope,
    String? id,
    required String menuCategoryId,
    required String name,
    String? description,
    required int basePriceMinor,
    required String currencyCode,
    String? defaultStationId,
    int? displayOrder,
    bool isActive = true,
    String? imagePath,
    String? itemType,
    List<String> tags = const [],
    int? prepMinutes,
    String? sku,
    String? kitchenNote,
    Map<String, dynamic> attributes = const {},
  }) {
    lastAttributes = attributes;
    return super.upsertItem(
      scope: scope,
      id: id,
      menuCategoryId: menuCategoryId,
      name: name,
      description: description,
      basePriceMinor: basePriceMinor,
      currencyCode: currencyCode,
      defaultStationId: defaultStationId,
      displayOrder: displayOrder,
      isActive: isActive,
      imagePath: imagePath,
      itemType: itemType,
      tags: tags,
      prepMinutes: prepMinutes,
      sku: sku,
      kitchenNote: kitchenNote,
      attributes: attributes,
    );
  }
}

const _category = MenuCategory(
  id: 'cat-1',
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  name: 'Grill',
  displayOrder: 0,
  isActive: true,
);

MenuItem _item({
  required String id,
  required String name,
  List<Map<String, Object?>> prep = const [
    {'name': 'Bread', 'quantity': 1, 'unit': 'Piece'},
  ],
}) => MenuItem(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  menuCategoryId: 'cat-1',
  name: name,
  description: null,
  basePriceMinor: 4500,
  currencyCode: demoCurrencyCode,
  defaultStationId: null,
  displayOrder: 0,
  isActive: true,
  attributes: {'prep_components': prep},
);

Modifier _group({
  required String id,
  required String menuItemId,
  required String name,
  int displayOrder = 0,
}) => Modifier(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  menuItemId: menuItemId,
  name: name,
  selectionType: 'single',
  minSelect: 1,
  maxSelect: 1,
  isRequired: true,
  displayOrder: displayOrder,
  isActive: true,
);

ModifierOption _option({
  required String id,
  required String modifierId,
  required String name,
  Map<String, dynamic>? kitchenMeat,
  int displayOrder = 0,
}) => ModifierOption(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  modifierId: modifierId,
  name: name,
  priceDeltaMinor: 0,
  displayOrder: displayOrder,
  isActive: true,
  kitchenMeat: kitchenMeat,
);

/// Saleh's burger: Bread at product level, a Size group (120g/240g) whose
/// options carry the Meat contribution, and an Extras group holding Cheese.
_RecordingStore _burgerStore({Map<String, dynamic>? meat120}) =>
    _RecordingStore(
      categories: const [_category],
      items: [_item(id: 'item-1', name: 'Burger')],
      modifiers: [
        _group(id: 'mod-size', menuItemId: 'item-1', name: 'Size'),
        _group(
          id: 'mod-extras',
          menuItemId: 'item-1',
          name: 'Extras',
          displayOrder: 1,
        ),
      ],
      modifierOptions: [
        _option(
          id: 'opt-120',
          modifierId: 'mod-size',
          name: '120g',
          kitchenMeat:
              meat120 ??
              <String, dynamic>{'quantity': 1, 'unit': 'Meat pieces'},
        ),
        _option(
          id: 'opt-240',
          modifierId: 'mod-size',
          name: '240g',
          displayOrder: 1,
          kitchenMeat: <String, dynamic>{'quantity': 2, 'unit': 'Meat pieces'},
        ),
        _option(id: 'opt-cheese', modifierId: 'mod-extras', name: 'Cheese'),
      ],
    );

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _RecordingStore store,
) async {
  tester.view.physicalSize = const Size(1400, 1600);
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
        locale: const Locale('en'),
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

Future<void> _openItem(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

/// Opens the edit dialog of the option row labelled [optionName] through the
/// REAL affordance the operator uses: the row's overflow menu -> Edit.
Future<void> _editOption(
  WidgetTester tester,
  AppLocalizations l10n,
  String optionName,
) async {
  final row = find.ancestor(
    of: find.text(optionName),
    matching: find.byType(Row),
  );
  final menu = find.descendant(
    of: row.last,
    matching: find.byType(PopupMenuButton<String>),
  );
  await tester.ensureVisible(menu.first);
  await tester.pumpAndSettle();
  await tester.tap(menu.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.menuEditAction).last);
  await tester.pumpAndSettle();
}

Future<void> _saveDialog(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.text(l10n.menuSaveAction).last);
  await tester.pumpAndSettle();
}

void main() {
  // H1 — the wrong location is gone -----------------------------------------
  testWidgets('H1. product preparation rows no longer offer the picker', (
    tester,
  ) async {
    final store = _burgerStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger');

    // The prep section is still there (Bread lives here) …
    expect(find.text(l10n.menuKitchenPrepSection), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-prep-name-0')), findsOneWidget);
    // … but the 016 classifier picker and its hint are gone from it.
    expect(
      find.byKey(const ValueKey('menu-item-prep-classifier-0')),
      findsNothing,
    );
    expect(find.text(l10n.menuPrepClassifierHint), findsNothing);
  });

  testWidgets('H1b. a legacy product-level link is preserved, not destroyed', (
    tester,
  ) async {
    // 016 data configured in the old place must keep decoding + printing.
    final store = _RecordingStore(
      categories: const [_category],
      items: [
        _item(
          id: 'item-1',
          name: 'Burger',
          prep: const [
            {
              'name': 'Meat pieces',
              'quantity': 2,
              'unit': '',
              'classifier_option_id': 'opt-cheese',
              'classifier_option_name': 'Cheese',
            },
          ],
        ),
      ],
      modifiers: [
        _group(id: 'mod-extras', menuItemId: 'item-1', name: 'Extras'),
      ],
      modifierOptions: [
        _option(id: 'opt-cheese', modifierId: 'mod-extras', name: 'Cheese'),
      ],
    );
    await _pump(tester, store);
    await _openItem(tester, 'Burger');
    await tester.tap(find.byKey(const ValueKey('menu-item-save')));
    await tester.pumpAndSettle();

    expect(
      (store.lastAttributes!['prep_components'] as List).single,
      {
        'name': 'Meat pieces',
        'quantity': 2,
        'unit': '',
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': 'Cheese',
      },
      reason: 'an item save must not silently drop legacy 016 configuration',
    );
  });

  // H2 — the new location ----------------------------------------------------
  testWidgets('H2. 120g can be split by Cheese from another group', (
    tester,
  ) async {
    final store = _burgerStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger');
    await _editOption(tester, l10n, '120g');

    final picker = find.byKey(const ValueKey('menu-option-meat-classifier'));
    expect(picker, findsOneWidget, reason: 'shown under the prep contribution');

    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheese').last);
    await tester.pumpAndSettle();
    await _saveDialog(tester, l10n);

    expect(store.optionCalls, 1);
    expect(store.lastKitchenMeat, {
      'quantity': 1,
      'unit': 'Meat pieces',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
    });
  });

  testWidgets('H3. the saved link reloads, can be changed and removed', (
    tester,
  ) async {
    final store = _burgerStore(
      meat120: <String, dynamic>{
        'quantity': 1,
        'unit': 'Meat pieces',
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': 'Cheese',
      },
    );
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger');
    await _editOption(tester, l10n, '120g');

    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('menu-option-meat-classifier')),
    );
    expect(picker.initialValue, 'opt-cheese', reason: 'reloads');

    // Remove it.
    await tester.tap(find.byKey(const ValueKey('menu-option-meat-classifier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.menuPrepClassifierNone).last);
    await tester.pumpAndSettle();
    await _saveDialog(tester, l10n);

    expect(store.lastKitchenMeat, {'quantity': 1, 'unit': 'Meat pieces'});
  });

  testWidgets('H4. disabling the contribution clears the link on Save', (
    tester,
  ) async {
    final store = _burgerStore(
      meat120: <String, dynamic>{
        'quantity': 1,
        'unit': 'Meat pieces',
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': 'Cheese',
      },
    );
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger');
    await _editOption(tester, l10n, '120g');

    // Turning the contribution off hides the picker — nothing left to classify.
    await tester.tap(find.byKey(const ValueKey('menu-option-meat-enabled')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('menu-option-meat-classifier')),
      findsNothing,
    );

    await _saveDialog(tester, l10n);
    expect(
      store.lastKitchenMeat,
      isNull,
      reason: 'contribution + link cleared',
    );
  });

  testWidgets('H5. the option being edited is never its own split target', (
    tester,
  ) async {
    final store = _burgerStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger');
    await _editOption(tester, l10n, '120g');

    await tester.tap(find.byKey(const ValueKey('menu-option-meat-classifier')));
    await tester.pumpAndSettle();
    // The dropdown lists the item's OTHER options — never 120g itself.
    expect(find.text('240g'), findsWidgets);
    expect(find.text('Cheese'), findsWidgets);
    final selfEntries = find.descendant(
      of: find.byType(DropdownMenuItem<String>),
      matching: find.text('120g'),
    );
    expect(selfEntries, findsNothing, reason: 'no self-reference');
  });

  testWidgets('H6. another product\'s options never appear', (tester) async {
    final store = _RecordingStore(
      categories: const [_category],
      items: [
        _item(id: 'item-1', name: 'Burger'),
        _item(id: 'item-2', name: 'Chicken'),
      ],
      modifiers: [
        _group(id: 'mod-size', menuItemId: 'item-1', name: 'Size'),
        _group(id: 'mod-chicken', menuItemId: 'item-2', name: 'Extras'),
      ],
      modifierOptions: [
        _option(
          id: 'opt-240',
          modifierId: 'mod-size',
          name: '240g',
          kitchenMeat: <String, dynamic>{'quantity': 2, 'unit': 'Meat pieces'},
        ),
        // The CHICKEN's own "Cheese" — a different product.
        _option(
          id: 'opt-chicken-cheese',
          modifierId: 'mod-chicken',
          name: 'Cheese',
        ),
      ],
    );
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger');
    await _editOption(tester, l10n, '240g');

    // The burger has no sibling option at all, so no picker is offered — and
    // certainly not the chicken's Cheese.
    expect(
      find.byKey(const ValueKey('menu-option-meat-classifier')),
      findsNothing,
    );
    expect(find.text('Cheese'), findsNothing);
  });

  test('the parsed option model exposes the stored link', () {
    const option = ModifierOption(
      id: 'opt-240',
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      modifierId: 'mod-size',
      name: '240g',
      priceDeltaMinor: 0,
      displayOrder: 0,
      isActive: true,
      kitchenMeat: <String, dynamic>{
        'quantity': 2,
        'unit': 'Meat pieces',
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': 'Cheese',
      },
    );
    expect(option.kitchenMeatClassifierOptionId, 'opt-cheese');
    expect(option.kitchenMeatQuantity, 2);
    expect(option.kitchenMeatUnit, 'Meat pieces');
  });

  test('a non-string stored id is never treated as an identifier', () {
    const option = ModifierOption(
      id: 'opt-240',
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      modifierId: 'mod-size',
      name: '240g',
      priceDeltaMinor: 0,
      displayOrder: 0,
      isActive: true,
      kitchenMeat: <String, dynamic>{'quantity': 2, 'classifier_option_id': 42},
    );
    expect(option.kitchenMeatClassifierOptionId, '');
  });
}
