import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent;
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — the PRODUCT-LEVEL classifier.
///
/// KITCHEN-MODIFIER-PREP-CLASSIFIER-019 moved the configuration UI: Saleh's meat
/// comes from the selected SIZE option, not from a fixed product resource, so
/// the "Split by option" picker now lives beside the modifier option's own
/// preparation contribution (see menu_modifier_prep_classifier_019_test.dart).
///
/// What this suite now pins is the COMPATIBILITY half of that move:
///  * the picker is GONE from the product's general preparation rows, so nobody
///    is steered into configuring the relation in the wrong place; and
///  * a product-level link ALREADY stored by 016 keeps decoding, keeps
///    round-tripping through an item save, and is never silently destroyed.
///
/// The 016 picker-driving tests were REPLACED, not deleted: their persistence,
/// no-leak and dangling-link contracts are now enforced — and tested — on the
/// option-level surface that actually owns them.

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

_RecordingStore _burgerStore({List<Map<String, Object?>>? prep}) =>
    _RecordingStore(
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
      modifierOptions: [
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

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-item-save')));
  await tester.pumpAndSettle();
}

void main() {
  // 019: the wrong configuration surface is gone -----------------------------
  testWidgets('019. the product prep rows no longer offer the picker', (
    tester,
  ) async {
    final store = _burgerStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    // The preparation section itself is untouched — Bread still lives here.
    expect(find.text(l10n.menuKitchenPrepSection), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-prep-name-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-prep-qty-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-prep-unit-0')), findsOneWidget);

    // The 016 picker, its hint and its dangling warning are all gone.
    expect(
      find.byKey(const ValueKey('menu-item-prep-classifier-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('menu-item-prep-classifier-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('menu-item-prep-classifier-dangling-0')),
      findsNothing,
    );
    expect(find.text(l10n.menuPrepClassifierHint), findsNothing);
  });

  // Compatibility: 016 data configured in the old place is not destroyed -----
  testWidgets('019. a stored product-level link survives an item save', (
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
    await _save(tester);

    expect(store.upsertItemCalls, 1);
    expect(
      store.lastAttributes!['prep_components'],
      [
        {'name': 'Bread', 'quantity': 1, 'unit': ''},
        {
          'name': 'Meat pieces',
          'quantity': 2,
          'unit': '',
          'classifier_option_id': 'opt-cheese',
          'classifier_option_name': 'Cheese',
        },
      ],
      reason: 'legacy 016 configuration must not be silently dropped',
    );
  });

  testWidgets('019. editing a prep row keeps the stored link intact', (
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
    await _pump(tester, store);
    await _openItem(tester, 'Burger 240g');

    // Change the QUANTITY the owner is still allowed to edit here …
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-prep-qty-0')),
      '3',
    );
    await _save(tester);

    // … the edit lands, and the link rides along untouched.
    expect((store.lastAttributes!['prep_components'] as List).single, {
      'name': 'Meat pieces',
      'quantity': 3,
      'unit': '',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
    });
  });

  testWidgets('019. an unclassified item still saves the pre-016 shape', (
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

  // The runtime model still decodes legacy product-level data ---------------
  test('the parsed model exposes a stored product-level link', () {
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
