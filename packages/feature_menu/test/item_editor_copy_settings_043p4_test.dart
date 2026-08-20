import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// OPS-043 Phase 4 — COPY SETTINGS FROM AN EXISTING ITEM.
///
/// Two properties decide whether this feature is safe, and neither is visible
/// on screen:
///
///  1. **Apply writes nothing.** The copy is a local draft until the normal
///     Save. So the zero-write tests assert on a store that counts EVERY write
///     method, not just the item ones — a spy that only watched `upsertItem`
///     would happily miss a dozen modifier writes.
///  2. **Classifier ids are remapped.** `kitchen_meat.classifier_option_id` and
///     `prep_components[].classifier_option_id` name ANOTHER OPTION OF THE SAME
///     ITEM. Copied verbatim they would name the SOURCE's options, and the
///     trust boundary would strip them at read time — the kitchen would just
///     stop seeing the with/without split, silently, with no error anywhere. So
///     the remap tests assert the NEW ids, never merely "it did not crash".
///
/// Ids are injected deterministically (`newId:`) so the remap can be asserted
/// literally rather than inferred.
// ---------------------------------------------------------------------------
// A store that counts every write, and can be told to fail one of them.
// ---------------------------------------------------------------------------
class _RecordingStore extends InMemoryMenuStore {
  _RecordingStore({
    super.categories,
    super.items,
    super.sizes,
    super.variants,
    super.modifiers,
    super.modifierOptions,
    this.failGroupAt,
    this.failOptionAt,
  }) : super(newId: _sequentialIds());

  static String Function() _sequentialIds() {
    var n = 0;
    return () => 'new-${++n}';
  }

  /// Fails the Nth (0-based) group / option write with a server failure.
  final int? failGroupAt;
  final int? failOptionAt;

  /// Every write, in order, as `<method>:<name-or-id>` — the one place a
  /// "zero writes" claim can actually be checked.
  final List<String> writes = <String>[];

  int groupCalls = 0;
  int optionCalls = 0;

  /// The arguments of every modifier-group write.
  final List<Map<String, Object?>> groupArgs = <Map<String, Object?>>[];

  /// The arguments of every option write, including its kitchen_meat.
  final List<Map<String, Object?>> optionArgs = <Map<String, Object?>>[];

  /// The arguments of every item write.
  final List<Map<String, Object?>> itemArgs = <Map<String, Object?>>[];

  int get writeCount => writes.length;

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int? displayOrder,
    bool isActive = true,
    MenuIconKeyWrite iconKey = const MenuIconKeyWrite.preserve(),
  }) {
    writes.add('upsertCategory:$name');
    return super.upsertCategory(
      scope: scope,
      id: id,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
      iconKey: iconKey,
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
    writes.add('upsertItem:$name');
    itemArgs.add(<String, Object?>{
      'id': id,
      'menuCategoryId': menuCategoryId,
      'name': name,
      'description': description,
      'basePriceMinor': basePriceMinor,
      'currencyCode': currencyCode,
      'imagePath': imagePath,
      'itemType': itemType,
      'tags': tags,
      'prepMinutes': prepMinutes,
      'sku': sku,
      'kitchenNote': kitchenNote,
      'attributes': attributes,
    });
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

  @override
  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int? displayOrder,
    bool isActive = true,
  }) {
    writes.add('upsertSize:$name');
    return super.upsertSize(
      scope: scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }

  @override
  Future<MenuWriteOutcome> upsertVariant({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int? displayOrder,
    bool isActive = true,
  }) {
    writes.add('upsertVariant:$name');
    return super.upsertVariant(
      scope: scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }

  @override
  Future<MenuWriteOutcome> upsertModifier({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    String selectionType = 'single',
    int minSelect = 0,
    int? maxSelect,
    bool isRequired = false,
    int? displayOrder,
    bool isActive = true,
    bool allowQuantity = false,
    int? maxQuantity,
  }) async {
    writes.add('upsertModifier:$name');
    groupArgs.add(<String, Object?>{
      'id': id,
      'menuItemId': menuItemId,
      'name': name,
      'selectionType': selectionType,
      'minSelect': minSelect,
      'maxSelect': maxSelect,
      'isRequired': isRequired,
      'displayOrder': displayOrder,
      'isActive': isActive,
      'allowQuantity': allowQuantity,
      'maxQuantity': maxQuantity,
    });
    if (groupCalls++ == failGroupAt) return const Failure(MenuServerFailure());
    return super.upsertModifier(
      scope: scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      selectionType: selectionType,
      minSelect: minSelect,
      maxSelect: maxSelect,
      isRequired: isRequired,
      displayOrder: displayOrder,
      isActive: isActive,
      allowQuantity: allowQuantity,
      maxQuantity: maxQuantity,
    );
  }

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
  }) async {
    writes.add('upsertModifierOption:$name');
    optionArgs.add(<String, Object?>{
      'id': id,
      'modifierId': modifierId,
      'name': name,
      'priceDeltaMinor': priceDeltaMinor,
      'displayOrder': displayOrder,
      'isActive': isActive,
      'kitchenMeat': kitchenMeat,
    });
    if (optionCalls++ == failOptionAt)
      return const Failure(MenuServerFailure());
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
  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  }) {
    writes.add('softDelete:${entity.wire}');
    return super.softDelete(
      organizationId: organizationId,
      entity: entity,
      id: id,
    );
  }

  @override
  Future<MenuWriteOutcome> reorder({
    required String organizationId,
    String? restaurantId,
    String? branchId,
    required MenuEntityType entity,
    required List<String> orderedIds,
  }) {
    writes.add('reorder:${entity.wire}');
    return super.reorder(
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      entity: entity,
      orderedIds: orderedIds,
    );
  }

  @override
  Future<MenuWriteOutcome> setItemAvailability({
    required MenuScope scope,
    required String menuItemId,
    required String availability,
    String? reason,
  }) {
    writes.add('setItemAvailability:$availability');
    return super.setItemAvailability(
      scope: scope,
      menuItemId: menuItemId,
      availability: availability,
      reason: reason,
    );
  }
}

// ---------------------------------------------------------------------------
// The fixture: a Classic-Burger-shaped source carrying everything that must
// copy AND everything that must not.
// ---------------------------------------------------------------------------

const String _otherRestaurantId = 'other-restaurant';

const Map<String, dynamic> _sourceAttributes = <String, dynamic>{
  // Phase-3 hidden legacy values — must NEVER be copied, and must survive on
  // the SOURCE untouched.
  'portion_label': 'Double',
  'patty_count': 2,
  'patty_weight_grams': 160,
  'future_ticket_key': {'written_by': 'a later ticket'},
  'prep_components': [
    {'name': 'Bun', 'quantity': 1, 'unit': 'pc'},
    {
      'name': 'Meat',
      'quantity': 1,
      'unit': 'pc',
      // A LEGACY 016 link on a product resource: split by the Cheese option.
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
    },
  ],
};

List<MenuCategory> get _categories => const [
  MenuCategory(
    id: 'cat-grill',
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
    id: 'item-classic',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    menuCategoryId: 'cat-grill',
    name: 'Classic Burger',
    description: 'The original.',
    basePriceMinor: 4800,
    currencyCode: demoCurrencyCode,
    defaultStationId: null,
    displayOrder: 0,
    isActive: true,
    imagePath: 'menu/classic-burger.jpg',
    itemType: 'food',
    tags: ['popular'],
    prepMinutes: 9,
    sku: 'CB-1',
    kitchenNote: 'Toast the bun.',
    attributes: _sourceAttributes,
  ),
  // Another restaurant of the SAME organization: it must never be offered as a
  // source, because the loaded snapshot never contains it.
  MenuItem(
    id: 'item-foreign',
    organizationId: demoOrganizationId,
    restaurantId: _otherRestaurantId,
    branchId: null,
    menuCategoryId: 'cat-foreign',
    name: 'Foreign Pizza',
    description: null,
    basePriceMinor: 5500,
    currencyCode: demoCurrencyCode,
    defaultStationId: null,
    displayOrder: 0,
    isActive: true,
  ),
];

/// Legacy Sizes/Types on the source — retired from the editor in Phase 3 and
/// never copied (D6).
List<ItemSize> get _sizes => const [
  ItemSize(
    id: 'size-1',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    menuItemId: 'item-classic',
    name: 'Legacy large',
    priceDeltaMinor: 700,
    displayOrder: 0,
    isActive: true,
  ),
];

List<ItemVariant> get _variants => const [
  ItemVariant(
    id: 'variant-1',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    menuItemId: 'item-classic',
    name: 'Legacy spicy',
    priceDeltaMinor: 0,
    displayOrder: 0,
    isActive: true,
  ),
];

List<Modifier> get _modifiers => const [
  Modifier(
    id: 'mod-size',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    menuItemId: 'item-classic',
    name: 'Size',
    selectionType: 'single',
    minSelect: 1,
    maxSelect: 1,
    isRequired: true,
    displayOrder: 0,
    isActive: true,
  ),
  Modifier(
    id: 'mod-additions',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    menuItemId: 'item-classic',
    name: 'Additions',
    selectionType: 'multiple',
    minSelect: 0,
    maxSelect: null,
    isRequired: false,
    displayOrder: 1,
    isActive: true,
    allowQuantity: true,
    maxQuantity: 3,
  ),
];

List<ModifierOption> get _options => const [
  ModifierOption(
    id: 'opt-120',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    modifierId: 'mod-size',
    name: '120g',
    priceDeltaMinor: 0,
    displayOrder: 0,
    isActive: true,
    kitchenMeat: <String, dynamic>{
      'quantity': 1,
      'unit': 'pcs',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
    },
  ),
  ModifierOption(
    id: 'opt-240',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    modifierId: 'mod-size',
    name: '240g',
    priceDeltaMinor: 1500,
    displayOrder: 1,
    isActive: true,
    kitchenMeat: <String, dynamic>{
      'quantity': 2,
      'unit': 'pcs',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
    },
  ),
  ModifierOption(
    id: 'opt-cheese',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    modifierId: 'mod-additions',
    name: 'Cheese',
    priceDeltaMinor: 300,
    displayOrder: 0,
    isActive: true,
  ),
  ModifierOption(
    id: 'opt-lettuce',
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    modifierId: 'mod-additions',
    name: 'Lettuce',
    priceDeltaMinor: 0,
    displayOrder: 1,
    // Deliberately INACTIVE: `is_active` is part of the copy contract.
    isActive: false,
  ),
];

_RecordingStore _store({int? failGroupAt, int? failOptionAt}) =>
    _RecordingStore(
      categories: _categories,
      items: _items,
      sizes: _sizes,
      variants: _variants,
      modifiers: _modifiers,
      modifierOptions: _options,
      failGroupAt: failGroupAt,
      failOptionAt: failOptionAt,
    );

// ---------------------------------------------------------------------------
// Harness.
// ---------------------------------------------------------------------------

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _RecordingStore store, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
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

/// Opens the editor for a BRAND NEW item.
Future<void> _openNewItem(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.text(l10n.menuAddItem).first);
  await tester.pumpAndSettle();
}

/// Opens the editor for an existing item.
Future<void> _openItem(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

/// Opens the source picker and applies `Classic Burger`, confirming the
/// replace prompt when the form already holds values.
Future<void> _applyClassicBurger(
  WidgetTester tester,
  AppLocalizations l10n, {
  bool expectConfirm = false,
}) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('menu-copy-choose-source')),
  );
  await tester.tap(find.byKey(const ValueKey('menu-copy-choose-source')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-copy-source-item-classic')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-copy-preview-apply')));
  await tester.pumpAndSettle();
  if (expectConfirm) {
    expect(find.byKey(const ValueKey('menu-copy-replace-confirm')), findsOne);
    await tester.tap(find.byKey(const ValueKey('menu-copy-replace-accept')));
    await tester.pumpAndSettle();
  }
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-item-save')));
  await tester.pumpAndSettle();
}

/// The target item created by a copy save (the only item that is not a fixture).
MenuItem _target(MenuSnapshot snapshot) =>
    snapshot.items.firstWhere((i) => i.id.startsWith('new-'));

MenuItem _source(MenuSnapshot snapshot) =>
    snapshot.items.firstWhere((i) => i.id == 'item-classic');

void main() {
  // =========================================================================
  group('A. Apply is a DRAFT — it writes nothing, anywhere', () {
    testWidgets('A1. applying a copy to a new item performs ZERO writes of any '
        'kind, and leaves the source untouched', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _applyClassicBurger(tester, l10n);

      expect(
        store.writes,
        isEmpty,
        reason:
            'Apply must not write an item, a group, an option or anything '
            'else — it only fills the form',
      );

      final snapshot = await store.load(demoMenuScope);
      expect(snapshot.items.where((i) => i.id.startsWith('new-')), isEmpty);
      expect(snapshot.modifiers, hasLength(2), reason: 'source groups only');
      expect(snapshot.modifierOptions, hasLength(4));
      expect(_source(snapshot).attributes, _sourceAttributes);
    });

    testWidgets('A2. the summary shows what was copied, and the form is '
        'prefilled — with still zero writes', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _applyClassicBurger(tester, l10n);

      expect(find.byKey(const ValueKey('menu-copy-summary')), findsOne);
      expect(find.text(l10n.menuCopyAppliedFrom('Classic Burger')), findsOne);
      // D5: the base price is prefilled and editable.
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('menu-item-price')))
            .controller!
            .text,
        '48.00',
      );
      // The copied Kitchen setup landed in the ordinary editable rows.
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('menu-item-prep-name-0')),
            )
            .controller!
            .text,
        'Bun',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('menu-item-prep-name-1')),
            )
            .controller!
            .text,
        'Meat',
      );
      expect(store.writes, isEmpty);
    });

    testWidgets('A3. cancelling the picker, and discarding an applied copy, '
        'both write nothing', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);

      await tester.tap(find.byKey(const ValueKey('menu-copy-choose-source')));
      await tester.pumpAndSettle();
      // `.last`: the editor top bar has its own Cancel behind the dialog.
      await tester.tap(find.text(l10n.menuCancelAction).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-copy-summary')), findsNothing);
      expect(store.writes, isEmpty);

      await _applyClassicBurger(tester, l10n);
      await tester.tap(find.byKey(const ValueKey('menu-copy-discard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-copy-summary')), findsNothing);
      expect(store.writes, isEmpty);

      final snapshot = await store.load(demoMenuScope);
      expect(snapshot.modifiers, hasLength(2));
      expect(snapshot.modifierOptions, hasLength(4));
    });

    testWidgets(
      'A4. closing the editor after an Apply leaves the store exactly '
      'as it was',
      (tester) async {
        final store = _store();
        final l10n = await _pump(tester, store);
        await _openNewItem(tester, l10n);
        await _applyClassicBurger(tester, l10n);
        await tester.tap(find.text(l10n.menuCancelAction).last);
        await tester.pumpAndSettle();

        expect(store.writes, isEmpty);
        final snapshot = await store.load(demoMenuScope);
        expect(snapshot.items.map((i) => i.id), <String>['item-classic']);
      },
    );
  });

  // =========================================================================
  group('B. what the copy brings over', () {
    test(
      'B1. the draft carries every runtime-consumed group and option field',
      () {
        final snapshot = MenuSnapshot(
          categories: _categories,
          items: _items,
          modifiers: _modifiers,
          modifierOptions: _options,
        );
        final config = buildMenuCopiedConfig(
          snapshot: snapshot,
          source: _source(snapshot),
        );

        expect(config.basePriceMinor, 4800);
        expect(config.groupCount, 2);
        expect(config.optionCount, 4);

        final size = config.groups.first;
        expect(size.name, 'Size');
        expect(size.selectionType, 'single');
        expect(size.minSelect, 1);
        expect(size.maxSelect, 1);
        expect(size.isRequired, isTrue);
        expect(size.displayOrder, 0);
        expect(size.isActive, isTrue);
        expect(size.allowQuantity, isFalse);
        expect(size.maxQuantity, isNull);

        final additions = config.groups[1];
        expect(additions.name, 'Additions');
        expect(additions.selectionType, 'multiple');
        expect(additions.allowQuantity, isTrue);
        expect(additions.maxQuantity, 3);
        expect(additions.isRequired, isFalse);
        expect(additions.displayOrder, 1);

        final g120 = size.options.first;
        expect(g120.name, '120g');
        expect(g120.priceDeltaMinor, 0);
        expect(g120.displayOrder, 0);
        expect(g120.isActive, isTrue);
        expect(g120.kitchenMeatQuantity, 1);
        expect(g120.kitchenMeatUnit, 'pcs');
        expect(g120.classifierSourceOptionId, 'opt-cheese');

        expect(size.options[1].priceDeltaMinor, 1500);
        expect(size.options[1].kitchenMeatQuantity, 2);

        final lettuce = additions.options[1];
        expect(lettuce.name, 'Lettuce');
        expect(
          lettuce.isActive,
          isFalse,
          reason: 'an inactive option copies as inactive, not silently revived',
        );
        expect(lettuce.hasKitchenMeat, isFalse);

        // Kitchen setup, including the legacy 016 link.
        expect(config.prepComponents, hasLength(2));
        expect(config.prepComponents.first['name'], 'Bun');
        expect(config.prepComponents[1]['classifier_option_id'], 'opt-cheese');
        expect(config.prepComponents[1]['classifier_option_name'], 'Cheese');
        expect(config.classifierLinkCount, 3, reason: '2 options + 1 prep row');
      },
    );

    test('B2. a classifier the SOURCE cannot justify is dropped at build time, '
        'never copied into something unremappable', () {
      final snapshot = MenuSnapshot(
        categories: _categories,
        items: <MenuItem>[
          MenuItem(
            id: 'item-classic',
            organizationId: demoOrganizationId,
            restaurantId: demoRestaurantId,
            branchId: demoBranchId,
            menuCategoryId: 'cat-grill',
            name: 'Classic Burger',
            description: null,
            basePriceMinor: 4800,
            currencyCode: demoCurrencyCode,
            defaultStationId: null,
            displayOrder: 0,
            isActive: true,
            attributes: const <String, dynamic>{
              'prep_components': [
                {
                  'name': 'Meat',
                  'quantity': 1,
                  'unit': 'pc',
                  // Names an option of ANOTHER product.
                  'classifier_option_id': 'opt-somewhere-else',
                  'classifier_option_name': 'Ghost',
                },
              ],
            },
          ),
        ],
        modifiers: _modifiers,
        modifierOptions: const [
          ModifierOption(
            id: 'opt-120',
            organizationId: demoOrganizationId,
            restaurantId: demoRestaurantId,
            branchId: demoBranchId,
            modifierId: 'mod-size',
            name: '120g',
            priceDeltaMinor: 0,
            displayOrder: 0,
            isActive: true,
            kitchenMeat: <String, dynamic>{
              'quantity': 1,
              'unit': 'pcs',
              'classifier_option_id': 'opt-gone',
              'classifier_option_name': 'Deleted',
            },
          ),
        ],
      );
      final config = buildMenuCopiedConfig(
        snapshot: snapshot,
        source: _source(snapshot),
      );

      // The contribution and the resource survive; only the unjustifiable link
      // is gone — exactly what the trust boundary would have forced at read
      // time, done up front so nothing unremappable is ever carried.
      final option = config.groups.first.options.first;
      expect(option.kitchenMeatQuantity, 1);
      expect(option.carriesClassifier, isFalse);
      expect(config.prepComponents.first['name'], 'Meat');
      expect(config.prepComponents.first['classifier_option_id'], isNull);
      expect(config.classifierLinkCount, 0);
    });

    test('B3. remapPrepComponents swaps known ids and STRIPS unknown ones — a '
        'foreign id is never left behind', () {
      final rows = <Map<String, Object?>>[
        {'name': 'Bun', 'quantity': 1, 'unit': 'pc'},
        {
          'name': 'Meat',
          'quantity': 1,
          'unit': 'pc',
          'classifier_option_id': 'opt-cheese',
          'classifier_option_name': 'Cheese',
        },
        {
          'name': 'Sauce',
          'quantity': 1,
          'unit': 'pc',
          'classifier_option_id': 'opt-unmapped',
          'classifier_option_name': 'Nowhere',
        },
      ];
      final out = remapPrepComponents(rows, <String, String>{
        'opt-cheese': 'new-cheese',
      });

      expect(out.first.containsKey('classifier_option_id'), isFalse);
      expect(out[1]['classifier_option_id'], 'new-cheese');
      expect(out[1]['classifier_option_name'], 'Cheese');
      expect(out[2].containsKey('classifier_option_id'), isFalse);
      expect(out[2].containsKey('classifier_option_name'), isFalse);
      expect(out[2]['name'], 'Sauce', reason: 'the resource itself survives');
      // The input is not mutated.
      expect(rows[1]['classifier_option_id'], 'opt-cheese');
    });
  });

  // =========================================================================
  group('C. classifier ids are REMAPPED to the new options', () {
    testWidgets('C1. after Save the target holds only NEW option ids — no '
        'source id survives anywhere', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final target = _target(snapshot);
      final groups = snapshot.modifiersForItem(target.id);
      expect(groups, hasLength(2));
      final targetOptions = <String, ModifierOption>{
        for (final group in groups)
          for (final option in snapshot.optionsForModifier(group.id))
            option.name: option,
      };
      expect(
        targetOptions.keys,
        containsAll(<String>['120g', '240g', 'Cheese']),
      );

      final newCheeseId = targetOptions['Cheese']!.id;
      expect(newCheeseId, isNot('opt-cheese'));

      // The two size options point at the TARGET's Cheese.
      for (final name in <String>['120g', '240g']) {
        expect(
          targetOptions[name]!.kitchenMeatClassifierOptionId,
          newCheeseId,
          reason: '$name must be split by the copy\'s own Cheese option',
        );
      }
      // ...and the item's Kitchen setup row too.
      final meatRow = (target.attributes['prep_components']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((row) => row['name'] == 'Meat');
      expect(meatRow['classifier_option_id'], newCheeseId);
      expect(meatRow['classifier_option_name'], 'Cheese');

      // The whole-store proof: no target row mentions a source option id.
      for (final option in snapshot.modifierOptions) {
        if (option.modifierId == 'mod-size') continue;
        expect(
          option.kitchenMeatClassifierOptionId,
          isNot('opt-cheese'),
          reason: 'a copied option must never carry the SOURCE id',
        );
      }
    });

    testWidgets('C2. the remapped config survives the trust boundary — the '
        'kitchen keeps its with/without split', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final target = _target(snapshot);
      final groups = snapshot.modifiersForItem(target.id);
      final optionNames = <String, String>{
        for (final group in groups)
          for (final option in snapshot.optionsForModifier(group.id))
            option.id: option.name,
      };

      // resolveTrustedPrepClassifiers/resolveTrustedMeatClassifier STRIP a link
      // whose id is not an option of this item. Surviving them is the property
      // that decides whether the kitchen still sees the split.
      final resolvedPrep = resolveTrustedPrepClassifiers(
        target.prepComponents,
        optionNames,
      );
      final meat = resolvedPrep.firstWhere((c) => c.name == 'Meat');
      expect(meat.classifierOptionName, 'Cheese');
      expect(meat.classifierOptionId, isNotEmpty);

      final option120 = snapshot.modifierOptions.firstWhere(
        (o) => o.name == '120g' && o.modifierId != 'mod-size',
      );
      final resolvedMeat = resolveTrustedMeatClassifier(
        KitchenMeat.tryFromJson(option120.kitchenMeat),
        optionNamesById: optionNames,
        selfOptionId: option120.id,
      );
      expect(resolvedMeat!.classifierOptionName, 'Cheese');
      expect(resolvedMeat.quantity, 1);
    });

    testWidgets(
      'C3. the FIRST pass never writes a source id — it is added only '
      'once the new options exist',
      (tester) async {
        final store = _store();
        final l10n = await _pump(tester, store);
        await _openNewItem(tester, l10n);
        await _type(tester, 'menu-item-name', 'Double Burger');
        await _applyClassicBurger(tester, l10n);
        await _save(tester);

        // Creates (id == null) must carry the count WITHOUT any classifier key.
        final creates = store.optionArgs.where((a) => a['id'] == null);
        for (final args in creates) {
          final meat = args['kitchenMeat'] as Map<String, dynamic>?;
          if (meat == null) continue;
          expect(
            meat.containsKey('classifier_option_id'),
            isFalse,
            reason: 'pass 1 must not put a source id on the wire',
          );
          expect(
            meat['quantity'],
            isNotNull,
            reason: 'the count itself is kept',
          );
        }
        // And the first item write must carry the prep rows unclassified.
        final firstPrep =
            (store.itemArgs.first['attributes']!
                    as Map<String, dynamic>)['prep_components']!
                as List;
        for (final row in firstPrep.cast<Map<String, Object?>>()) {
          expect(row.containsKey('classifier_option_id'), isFalse);
        }
      },
    );
  });

  // =========================================================================
  group('D. base price', () {
    testWidgets('D1. the copied price is used when untouched', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);

      expect(store.itemArgs.first['basePriceMinor'], 4800);
    });

    testWidgets('D2. an edited price WINS over the copied one', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _type(tester, 'menu-item-price', '62.50');
      await _save(tester);

      expect(store.itemArgs.first['basePriceMinor'], 6250);
      final snapshot = await store.load(demoMenuScope);
      expect(_target(snapshot).basePriceMinor, 6250);
      expect(
        _source(snapshot).basePriceMinor,
        4800,
        reason: 'the source price is never touched',
      );
    });
  });

  // =========================================================================
  group('E. what the copy must NEVER bring over', () {
    testWidgets('E1. identity, image, SKU, hidden legacy attributes, sizes and '
        'variants all stay with the source', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);

      final args = store.itemArgs.first;
      expect(args['name'], 'Double Burger');
      expect(args['description'], isNull);
      expect(args['imagePath'], isNull);
      expect(args['sku'], isNull);
      expect(args['prepMinutes'], isNull);
      expect(args['kitchenNote'], isNull);
      expect(args['itemType'], isNull);
      expect(args['tags'], isEmpty);

      final attributes = args['attributes']! as Map<String, dynamic>;
      expect(attributes.containsKey('portion_label'), isFalse);
      expect(attributes.containsKey('patty_count'), isFalse);
      expect(attributes.containsKey('patty_weight_grams'), isFalse);
      expect(attributes.containsKey('future_ticket_key'), isFalse);
      expect(
        attributes.keys,
        <String>['prep_components'],
        reason: 'only the Kitchen setup travels in the attribute bag',
      );

      // D6: no size and no variant write happened at all.
      expect(store.writes.where((w) => w.startsWith('upsertSize')), isEmpty);
      expect(store.writes.where((w) => w.startsWith('upsertVariant')), isEmpty);
      final snapshot = await store.load(demoMenuScope);
      final target = _target(snapshot);
      expect(snapshot.sizesForItem(target.id), isEmpty);
      expect(snapshot.variantsForItem(target.id), isEmpty);
      expect(snapshot.sizesForItem('item-classic'), hasLength(1));
      expect(snapshot.variantsForItem('item-classic'), hasLength(1));
    });

    testWidgets('E2. nothing is ever deleted — the copy only creates', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);

      expect(store.writes.where((w) => w.startsWith('softDelete')), isEmpty);
      expect(store.writes.where((w) => w.startsWith('reorder')), isEmpty);
    });
  });

  // =========================================================================
  group('F. the copy is independent of its source', () {
    testWidgets(
      'F1. editing the source afterwards changes nothing on the copy',
      (tester) async {
        final store = _store();
        final l10n = await _pump(tester, store);
        await _openNewItem(tester, l10n);
        await _type(tester, 'menu-item-name', 'Double Burger');
        await _applyClassicBurger(tester, l10n);
        await _save(tester);

        final before = await store.load(demoMenuScope);
        final target = _target(before);
        final targetGroupNames = before
            .modifiersForItem(target.id)
            .map((m) => m.name)
            .toList();
        final targetCheese = before.modifierOptions.firstWhere(
          (o) => o.name == 'Cheese' && o.modifierId != 'mod-additions',
        );

        // Rename a source group and a source option, and move its price.
        await store.upsertModifier(
          scope: demoMenuScope,
          id: 'mod-size',
          menuItemId: 'item-classic',
          name: 'RENAMED Size',
          selectionType: 'single',
          minSelect: 1,
          maxSelect: 1,
          isRequired: true,
        );
        await store.upsertModifierOption(
          scope: demoMenuScope,
          id: 'opt-cheese',
          modifierId: 'mod-additions',
          name: 'RENAMED Cheese',
          priceDeltaMinor: 999,
        );

        final after = await store.load(demoMenuScope);
        expect(
          after.modifiersForItem(target.id).map((m) => m.name),
          targetGroupNames,
        );
        final cheeseAfter = after.modifierOptions.firstWhere(
          (o) => o.id == targetCheese.id,
        );
        expect(cheeseAfter.name, 'Cheese');
        expect(cheeseAfter.priceDeltaMinor, 300);
      },
    );
  });

  // =========================================================================
  group('G. an EXISTING target', () {
    testWidgets('G1. copying is REFUSED on an item that already has modifier '
        'groups, in words, before anything happens', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openItem(tester, 'Classic Burger');

      expect(find.byKey(const ValueKey('menu-copy-blocked')), findsOne);
      expect(find.text(l10n.menuCopyBlockedHasModifiers), findsOne);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('menu-copy-choose-source')),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'a disabled control, not a hidden failure',
      );
      expect(store.writes, isEmpty);
    });

    testWidgets('G2. an existing item with NO groups accepts a copy: the '
        'confirmation appears, Cancel changes nothing, Save creates', (
      tester,
    ) async {
      final store = _RecordingStore(
        categories: _categories,
        items: <MenuItem>[
          ..._items,
          const MenuItem(
            id: 'item-empty',
            organizationId: demoOrganizationId,
            restaurantId: demoRestaurantId,
            branchId: demoBranchId,
            menuCategoryId: 'cat-grill',
            name: 'Plain Burger',
            description: null,
            basePriceMinor: 3000,
            currencyCode: demoCurrencyCode,
            defaultStationId: null,
            displayOrder: 1,
            isActive: true,
            sku: 'PB-9',
            prepMinutes: 4,
            kitchenNote: 'Keep it plain.',
            attributes: <String, dynamic>{'portion_label': 'Single'},
          ),
        ],
        modifiers: _modifiers,
        modifierOptions: _options,
      );
      final l10n = await _pump(tester, store);
      await _openItem(tester, 'Plain Burger');
      expect(find.byKey(const ValueKey('menu-copy-blocked')), findsNothing);

      // Cancelling the confirmation leaves the form (and the store) alone.
      await tester.tap(find.byKey(const ValueKey('menu-copy-choose-source')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('menu-copy-source-item-classic')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-copy-preview-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-copy-replace-confirm')), findsOne);
      await tester.tap(find.text(l10n.menuCancelAction).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-copy-summary')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('menu-item-price')))
            .controller!
            .text,
        '30.00',
      );
      expect(store.writes, isEmpty);

      // Applying for real, then saving.
      await _applyClassicBurger(tester, l10n, expectConfirm: true);
      expect(store.writes, isEmpty);
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final target = snapshot.items.firstWhere((i) => i.id == 'item-empty');
      expect(snapshot.modifiersForItem('item-empty'), hasLength(2));
      expect(target.basePriceMinor, 4800);
      // I. Phase-3 no-wipe: the target's OWN hidden values survived.
      expect(target.sku, 'PB-9');
      expect(target.prepMinutes, 4);
      expect(target.kitchenNote, 'Keep it plain.');
      expect(target.attributes['portion_label'], 'Single');
    });
  });

  // =========================================================================
  group('H. a mid-save failure is honest, and a retry RESUMES', () {
    testWidgets('H1. a failing option write stops the sequence, reports it, '
        'keeps the editor open and never claims success', (tester) async {
      final store = _store(failOptionAt: 2);
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);

      expect(
        find.textContaining(l10n.menuCopyFlushPartial(2, 2)),
        findsOne,
        reason: 'the operator is told exactly how far it got',
      );
      expect(find.text(l10n.menuSavedSnack), findsNothing);
      // The editor is STILL open with the draft, so Save can resume.
      expect(find.byKey(const ValueKey('menu-copy-summary')), findsOne);

      final snapshot = await store.load(demoMenuScope);
      // The source is untouched, and no half-written row carries a source id.
      expect(_source(snapshot).attributes, _sourceAttributes);
      expect(snapshot.modifiersForItem('item-classic'), hasLength(2));
      for (final option in snapshot.modifierOptions) {
        if (option.modifierId.startsWith('mod-')) continue;
        expect(option.kitchenMeatClassifierOptionId, isNot('opt-cheese'));
      }
    });

    testWidgets('H2. saving again after a failure RESUMES — one item, one set '
        'of groups, no duplicates', (tester) async {
      final store = _store(failOptionAt: 2);
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);
      // Let the failure snackbar time out: a second showSnackBar QUEUES behind
      // a visible one, so without this the resume's summary is never on screen
      // and the assertion below would fail for a reason that has nothing to do
      // with the copy.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final created = snapshot.items.where((i) => i.id.startsWith('new-'));
      expect(created, hasLength(1), reason: 'never a second item');
      final target = created.first;
      expect(
        snapshot.modifiersForItem(target.id),
        hasLength(2),
        reason: 'never a second set of groups',
      );
      final optionNames = <String>[
        for (final group in snapshot.modifiersForItem(target.id))
          for (final option in snapshot.optionsForModifier(group.id))
            option.name,
      ];
      expect(optionNames..sort(), <String>[
        '120g',
        '240g',
        'Cheese',
        'Lettuce',
      ]);
      expect(find.text(l10n.menuCopySavedSummary(2, 4)), findsOne);
    });

    testWidgets(
      'H3. a failing GROUP write stops before any option is created',
      (tester) async {
        final store = _store(failGroupAt: 0);
        final l10n = await _pump(tester, store);
        await _openNewItem(tester, l10n);
        await _type(tester, 'menu-item-name', 'Double Burger');
        await _applyClassicBurger(tester, l10n);
        await _save(tester);

        expect(
          store.writes.where((w) => w.startsWith('upsertModifierOption')),
          isEmpty,
        );
        expect(find.text(l10n.menuSavedSnack), findsNothing);
        expect(find.textContaining(l10n.menuCopyFlushPartial(0, 0)), findsOne);
      },
    );
  });

  // =========================================================================
  group('I. Phase-3 no-wipe compatibility', () {
    testWidgets('I1. the SOURCE keeps every hidden value and both legacy rows '
        'after being copied from', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await _type(tester, 'menu-item-name', 'Double Burger');
      await _applyClassicBurger(tester, l10n);
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final source = _source(snapshot);
      expect(source.sku, 'CB-1');
      expect(source.prepMinutes, 9);
      expect(source.kitchenNote, 'Toast the bun.');
      expect(source.imagePath, 'menu/classic-burger.jpg');
      expect(source.attributes, _sourceAttributes);
      expect(snapshot.sizesForItem('item-classic'), hasLength(1));
      expect(snapshot.variantsForItem('item-classic'), hasLength(1));
      // Being a source is a READ. Not one write mentions the source item.
      expect(store.itemArgs.where((a) => a['id'] == 'item-classic'), isEmpty);
    });

    testWidgets('I2. a later ordinary save of the copied item keeps the '
        'remapped Kitchen setup link', (tester) async {
      final store = _RecordingStore(
        categories: _categories,
        items: <MenuItem>[
          ..._items,
          const MenuItem(
            id: 'item-empty',
            organizationId: demoOrganizationId,
            restaurantId: demoRestaurantId,
            branchId: demoBranchId,
            menuCategoryId: 'cat-grill',
            name: 'Plain Burger',
            description: null,
            basePriceMinor: 3000,
            currencyCode: demoCurrencyCode,
            defaultStationId: null,
            displayOrder: 1,
            isActive: true,
          ),
        ],
        modifiers: _modifiers,
        modifierOptions: _options,
      );
      final l10n = await _pump(tester, store);
      await _openItem(tester, 'Plain Burger');
      await _applyClassicBurger(tester, l10n, expectConfirm: true);
      await _save(tester);

      final afterCopy = await store.load(demoMenuScope);
      final newCheese = afterCopy.modifierOptions.firstWhere(
        (o) =>
            o.name == 'Cheese' &&
            afterCopy
                .modifiersForItem('item-empty')
                .any((m) => m.id == o.modifierId),
      );

      // An ordinary rename + save, with the copy draft already cleared.
      await _type(tester, 'menu-item-name', 'Plain Burger v2');
      await _save(tester);

      final afterEdit = await store.load(demoMenuScope);
      final target = afterEdit.items.firstWhere((i) => i.id == 'item-empty');
      expect(target.name, 'Plain Burger v2');
      final meatRow = (target.attributes['prep_components']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((row) => row['name'] == 'Meat');
      expect(
        meatRow['classifier_option_id'],
        newCheese.id,
        reason: 'the remapped link must survive the NEXT ordinary save too',
      );
    });
  });

  // =========================================================================
  group('J. tenancy', () {
    testWidgets('J1. another restaurant\'s item is not offered as a source', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await tester.tap(find.byKey(const ValueKey('menu-copy-choose-source')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('menu-copy-source-item-classic')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('menu-copy-source-item-foreign')),
        findsNothing,
      );
      expect(find.text('Foreign Pizza'), findsNothing);

      // The candidate builder itself refuses to see it, whatever the UI does.
      final snapshot = await store.load(demoMenuScope);
      expect(menuCopySourceCandidates(snapshot).map((i) => i.id), <String>[
        'item-classic',
      ]);
    });

    testWidgets('J2. an item is never offered as its own source', (
      tester,
    ) async {
      final store = _RecordingStore(
        categories: _categories,
        items: _items,
        modifiers: const [],
        modifierOptions: const [],
      );
      await _pump(tester, store);
      await _openItem(tester, 'Classic Burger');
      await tester.ensureVisible(
        find.byKey(const ValueKey('menu-copy-choose-source')),
      );
      await tester.tap(find.byKey(const ValueKey('menu-copy-choose-source')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('menu-copy-source-item-classic')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('menu-copy-source-empty')), findsOne);
    });

    test('J3. the candidate list excludes the target by id', () {
      final snapshot = MenuSnapshot(
        categories: _categories,
        items: _items,
        modifiers: _modifiers,
        modifierOptions: _options,
      );
      expect(
        menuCopySourceCandidates(snapshot, excludeItemId: 'item-classic'),
        isEmpty,
      );
    });
  });

  // =========================================================================
  group('K. search, and the three locales', () {
    testWidgets('K1. the picker searches by name and by category', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _openNewItem(tester, l10n);
      await tester.tap(find.byKey(const ValueKey('menu-copy-choose-source')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('menu-copy-source-search')),
        'grill',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-copy-source-item-classic')),
        findsOne,
      );

      await tester.enterText(
        find.byKey(const ValueKey('menu-copy-source-search')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-copy-source-no-match')), findsOne);
    });

    for (final locale in <String>['ar', 'he', 'en']) {
      testWidgets('K2-$locale. the card, picker and preview render with no '
          'overflow', (tester) async {
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details.exceptionAsString());
        };
        addTearDown(() => FlutterError.onError = previous);

        final store = _store();
        final l10n = await _pump(tester, store, locale: Locale(locale));
        await _openNewItem(tester, l10n);
        expect(find.byKey(const ValueKey('menu-copy-card')), findsOne);
        await _applyClassicBurger(tester, l10n);
        expect(find.byKey(const ValueKey('menu-copy-summary')), findsOne);

        FlutterError.onError = previous;
        expect(
          errors.where((e) => e.contains('overflowed')),
          isEmpty,
          reason: 'RTL/LTR layout must not overflow in $locale: $errors',
        );
      });
    }
  });

  // =========================================================================
  group('L. the hardcoded template experience is gone', () {
    testWidgets('L1. the Add-template entry point no longer exists', (
      tester,
    ) async {
      final store = _store();
      await _pump(tester, store);
      await _openItem(tester, 'Classic Burger');

      expect(find.byKey(const ValueKey('menu-template-add')), findsNothing);
      // The manual "add modifier" path is untouched.
      expect(
        find.text(
          AppLocalizations.of(
            tester.element(find.byType(MenuManagementScreen)),
          ).menuAddModifier,
        ),
        findsOne,
      );
    });
  });
}
