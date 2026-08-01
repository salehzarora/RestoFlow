import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent;
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — the admin configuration.
///
/// A preparation resource may be SPLIT BY one of the item's own modifier
/// options. The relation is persisted at the narrowest existing product-scoped
/// home — the item's `attributes.prep_components` bag — beside the quantity it
/// re-buckets, so no reusable/shared row can ever carry one product's target
/// into another.

/// An [InMemoryMenuStore] recording the last upsertItem attributes.
class _RecordingStore extends InMemoryMenuStore {
  _RecordingStore({
    super.categories,
    super.items,
    super.modifiers,
    super.modifierOptions,
  });

  int upsertItemCalls = 0;
  Map<String, dynamic>? lastAttributes;

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
    upsertItemCalls++;
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
  required List<Map<String, Object?>> prep,
}) => MenuItem(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  menuCategoryId: 'cat-1',
  name: name,
  description: null,
  basePriceMinor: 4800,
  currencyCode: demoCurrencyCode,
  defaultStationId: null,
  displayOrder: 0,
  isActive: true,
  attributes: {'prep_components': prep},
);

Modifier _group({required String id, required String menuItemId}) => Modifier(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  menuItemId: menuItemId,
  name: 'Extras',
  selectionType: 'multiple',
  minSelect: 0,
  maxSelect: null,
  isRequired: false,
  displayOrder: 0,
  isActive: true,
);

ModifierOption _option({
  required String id,
  required String modifierId,
  required String name,
}) => ModifierOption(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  modifierId: modifierId,
  name: name,
  priceDeltaMinor: 300,
  displayOrder: 0,
  isActive: true,
);

/// The 240g burger: Bread 1 + Meat pieces 2, with Cheese and Onion options.
_RecordingStore _burgerStore({
  List<Map<String, Object?>>? prep,
  List<ModifierOption>? options,
}) => _RecordingStore(
  categories: const [_category],
  items: [
    _item(
      id: 'item-1',
      name: 'Burger 240g',
      prep:
          prep ??
          const [
            {'name': 'Bread', 'quantity': 1, 'unit': ''},
            {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
          ],
    ),
  ],
  modifiers: [_group(id: 'mod-1', menuItemId: 'item-1')],
  modifierOptions:
      options ??
      [
        _option(id: 'opt-cheese', modifierId: 'mod-1', name: 'Cheese'),
        _option(id: 'opt-onion', modifierId: 'mod-1', name: 'Onion'),
      ],
);

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _RecordingStore store,
) async {
  tester.view.physicalSize = const Size(1400, 1400);
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

/// Picks [optionName] in the split-by-option dropdown of prep row [index].
Future<void> _pickClassifier(
  WidgetTester tester,
  int index,
  String optionName,
) async {
  final picker = find.byKey(ValueKey('menu-item-prep-classifier-$index'));
  await tester.ensureVisible(picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionName).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-item-save')));
  await tester.pumpAndSettle();
}

void main() {
  // K. persistence ------------------------------------------------------------
  testWidgets('K1. saving a classifier writes it beside the resource', (
    tester,
  ) async {
    final store = _burgerStore();
    await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    // Row 1 is "Meat pieces" — split it by Cheese.
    await _pickClassifier(tester, 1, 'Cheese');
    await _save(tester);

    expect(store.upsertItemCalls, 1);
    expect(store.lastAttributes!['prep_components'], [
      // Bread is untouched — no classifier keys at all.
      {'name': 'Bread', 'quantity': 1, 'unit': ''},
      {
        'name': 'Meat pieces',
        'quantity': 2,
        'unit': '',
        'classifier_option_id': 'opt-cheese',
        'classifier_option_name': 'Cheese',
      },
    ]);
    // Non-money (D-007) and no unrelated field invented.
    final rows = (store.lastAttributes!['prep_components'] as List).cast<Map>();
    for (final row in rows) {
      expect(row.keys.any((k) => '$k'.contains('minor')), isFalse);
    }
  });

  testWidgets('K2. the saved classifier reloads into the editor', (
    tester,
  ) async {
    final store = _burgerStore(
      prep: const [
        {'name': 'Bread', 'quantity': 1, 'unit': ''},
        {
          'name': 'Meat pieces',
          'quantity': 2,
          'unit': '',
          'classifier_option_id': 'opt-cheese',
          'classifier_option_name': 'Cheese',
        },
      ],
    );
    await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('menu-item-prep-classifier-1')),
    );
    expect(picker.initialValue, 'opt-cheese');

    // An untouched round-trip save preserves the link byte for byte.
    await _save(tester);
    expect((store.lastAttributes!['prep_components'] as List)[1], {
      'name': 'Meat pieces',
      'quantity': 2,
      'unit': '',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
    });
  });

  testWidgets('K3. the link can be edited to another option', (tester) async {
    final store = _burgerStore(
      prep: const [
        {'name': 'Bread', 'quantity': 1, 'unit': ''},
        {
          'name': 'Meat pieces',
          'quantity': 2,
          'unit': '',
          'classifier_option_id': 'opt-cheese',
          'classifier_option_name': 'Cheese',
        },
      ],
    );
    await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    await _pickClassifier(tester, 1, 'Onion');
    await _save(tester);

    expect((store.lastAttributes!['prep_components'] as List)[1], {
      'name': 'Meat pieces',
      'quantity': 2,
      'unit': '',
      'classifier_option_id': 'opt-onion',
      'classifier_option_name': 'Onion',
    });
  });

  testWidgets('K4. the link can be removed, returning to one total', (
    tester,
  ) async {
    final store = _burgerStore(
      prep: const [
        {
          'name': 'Meat pieces',
          'quantity': 2,
          'unit': '',
          'classifier_option_id': 'opt-cheese',
          'classifier_option_name': 'Cheese',
        },
      ],
    );
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    await _pickClassifier(tester, 0, l10n.menuPrepClassifierNone);
    await _save(tester);

    expect(store.lastAttributes!['prep_components'], [
      {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
    ]);
  });

  testWidgets('K5. an unclassified item saves exactly the pre-016 shape', (
    tester,
  ) async {
    final store = _burgerStore();
    await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');
    await _save(tester);

    expect(store.lastAttributes!['prep_components'], [
      {'name': 'Bread', 'quantity': 1, 'unit': ''},
      {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
    ]);
  });

  testWidgets('K6. the resource quantity and name are never touched by the '
      'classifier', (tester) async {
    final store = _burgerStore();
    await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    await _pickClassifier(tester, 1, 'Cheese');
    await _save(tester);

    final meat = (store.lastAttributes!['prep_components'] as List)[1] as Map;
    expect(meat['name'], 'Meat pieces');
    expect(meat['quantity'], 2, reason: 'the option adds no quantity');
    expect(meat['unit'], '');
  });

  // 9. invalid target ---------------------------------------------------------
  testWidgets('a link to a deleted option surfaces an error and clears', (
    tester,
  ) async {
    final store = _burgerStore(
      prep: const [
        {
          'name': 'Meat pieces',
          'quantity': 2,
          'unit': '',
          'classifier_option_id': 'opt-gone',
          'classifier_option_name': 'Bacon',
        },
      ],
    );
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    // The picker cannot show a value that no longer exists — it falls back to
    // "Not split" rather than crashing.
    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('menu-item-prep-classifier-0')),
    );
    expect(picker.initialValue, '');

    await _save(tester);

    // Saved WITHOUT the dangling link (the resource keeps one total) …
    expect(store.lastAttributes!['prep_components'], [
      {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
    ]);
    // … and the admin is told why.
    expect(find.text(l10n.menuPrepClassifierMissing), findsOneWidget);
  });

  testWidgets('the picker is hidden when the item has no options to split by', (
    tester,
  ) async {
    final store = _RecordingStore(
      categories: const [_category],
      items: [
        _item(
          id: 'item-1',
          name: 'Burger 240g',
          prep: const [
            {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
          ],
        ),
      ],
    );
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    expect(
      find.byKey(const ValueKey('menu-item-prep-classifier-0')),
      findsNothing,
    );
    expect(find.text(l10n.menuPrepClassifierHint), findsNothing);
  });

  // L. reusable-modifier safety ----------------------------------------------
  testWidgets('L. a template-shaped option name shared by two products does '
      'NOT leak the link', (tester) async {
    // Both burgers carry a "Cheese" option — but they are SEPARATE rows, because
    // modifier groups belong to one menu item and templates are copy-on-attach.
    final store = _RecordingStore(
      categories: const [_category],
      items: [
        _item(
          id: 'item-1',
          name: 'Burger 240g',
          prep: const [
            {'name': 'Meat pieces', 'quantity': 2, 'unit': ''},
          ],
        ),
        _item(
          id: 'item-2',
          name: 'Chicken 200g',
          prep: const [
            {'name': 'Meat pieces', 'quantity': 1, 'unit': ''},
          ],
        ),
      ],
      modifiers: [
        _group(id: 'mod-1', menuItemId: 'item-1'),
        _group(id: 'mod-2', menuItemId: 'item-2'),
      ],
      modifierOptions: [
        _option(id: 'opt-cheese-burger', modifierId: 'mod-1', name: 'Cheese'),
        _option(id: 'opt-cheese-chicken', modifierId: 'mod-2', name: 'Cheese'),
      ],
    );
    await _pump(tester, store);

    // Configure the BURGER only.
    await _openItem(tester, 'Burger 240g');
    await _pickClassifier(tester, 0, 'Cheese');
    await _save(tester);
    expect((store.lastAttributes!['prep_components'] as List)[0], {
      'name': 'Meat pieces',
      'quantity': 2,
      'unit': '',
      'classifier_option_id': 'opt-cheese-burger',
      'classifier_option_name': 'Cheese',
    });

    // The CHICKEN is untouched: its resource still saves unsplit, and its own
    // picker offers only ITS option id.
    await tester.tap(find.byType(BackButtonIcon));
    await tester.pumpAndSettle();
    await _openItem(tester, 'Chicken 200g');

    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('menu-item-prep-classifier-0')),
    );
    expect(picker.initialValue, '', reason: 'no link leaked from the burger');

    // Saving untouched keeps the chicken's resource unsplit.
    await _save(tester);
    expect(store.lastAttributes!['prep_components'], [
      {'name': 'Meat pieces', 'quantity': 1, 'unit': ''},
    ]);

    // Splitting the chicken by ITS "Cheese" stores the CHICKEN's option id —
    // the identically-named burger option is not even a candidate here.
    await _pickClassifier(tester, 0, 'Cheese');
    await _save(tester);
    expect((store.lastAttributes!['prep_components'] as List)[0], {
      'name': 'Meat pieces',
      'quantity': 1,
      'unit': '',
      'classifier_option_id': 'opt-cheese-chicken',
      'classifier_option_name': 'Cheese',
    });
  });

  test('the parsed model exposes the stored link', () {
    const item = MenuItem(
      id: 'item-1',
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      menuCategoryId: 'cat-1',
      name: 'Burger 240g',
      description: null,
      basePriceMinor: 4800,
      currencyCode: demoCurrencyCode,
      defaultStationId: null,
      displayOrder: 0,
      isActive: true,
      attributes: {
        'prep_components': [
          {
            'name': 'Meat pieces',
            'quantity': 2,
            'unit': '',
            'classifier_option_id': 'opt-cheese',
            'classifier_option_name': 'Cheese',
          },
        ],
      },
    );
    expect(item.prepComponents, const [
      KitchenPrepComponent(
        name: 'Meat pieces',
        quantity: 2,
        classifierOptionId: 'opt-cheese',
        classifierOptionName: 'Cheese',
      ),
    ]);
    // Config only — the order-time answer is not part of the menu.
    expect(item.prepComponents.single.classifierSelected, isNull);
  });
}
