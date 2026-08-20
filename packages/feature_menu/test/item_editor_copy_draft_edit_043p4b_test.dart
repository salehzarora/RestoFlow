import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// OPS-043 Phase 4B — THE COPIED CONFIGURATION IS A REAL DRAFT.
///
/// Phase 4 shipped the copy as a read-only preview: the operator could see what
/// would be created but had to save it first and fix it afterwards, on live
/// rows. That is the opposite of what a draft is for. These tests pin the two
/// properties that make it a real one:
///
///  1. **Editing writes nothing.** Every group field, every option field, the
///     kitchen count and the split-by link can all be changed with the store
///     still untouched — asserted against a spy that counts EVERY writer method,
///     because one that watched only `upsertItem` would miss a dozen modifier
///     writes.
///  2. **What you last typed is what gets written.** The flush reads the draft
///     at call time, so an edit made after Apply is what reaches the server —
///     including a renamed classifier, whose link survives the rename because it
///     is expressed as the option's stable source id and never as its name.
///
/// And the third, which is easy to get half-right: **Discard puts the form
/// back.** Applying a copy overwrites the price field and replaces the Kitchen
/// setup rows, so dropping the draft alone would leave those overwritten values
/// behind as if the operator had typed them.
class _Spy extends InMemoryMenuStore {
  _Spy({
    super.categories,
    super.items,
    super.sizes,
    super.variants,
    super.modifiers,
    super.modifierOptions,
  }) : super(newId: _ids());

  static String Function() _ids() {
    var n = 0;
    return () => 'new-${++n}';
  }

  final List<String> writes = <String>[];
  final List<Map<String, Object?>> groupArgs = <Map<String, Object?>>[];
  final List<Map<String, Object?>> optionArgs = <Map<String, Object?>>[];
  final List<Map<String, Object?>> itemArgs = <Map<String, Object?>>[];

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int? displayOrder,
    bool isActive = true,
    MenuIconKeyWrite iconKey = const MenuIconKeyWrite.preserve(),
  }) {
    writes.add('upsertCategory');
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
    writes.add('upsertItem');
    itemArgs.add(<String, Object?>{
      'id': id,
      'name': name,
      'basePriceMinor': basePriceMinor,
      'sku': sku,
      'prepMinutes': prepMinutes,
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
    writes.add('upsertSize');
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
    writes.add('upsertVariant');
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
  }) {
    writes.add('upsertModifier');
    groupArgs.add(<String, Object?>{
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
  }) {
    writes.add('upsertModifierOption');
    optionArgs.add(<String, Object?>{
      'id': id,
      'name': name,
      'priceDeltaMinor': priceDeltaMinor,
      'isActive': isActive,
      'kitchenMeat': kitchenMeat,
    });
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
    writes.add('softDelete');
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
    writes.add('reorder');
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
    writes.add('setItemAvailability');
    return super.setItemAvailability(
      scope: scope,
      menuItemId: menuItemId,
      availability: availability,
      reason: reason,
    );
  }
}

// ---------------------------------------------------------------------------
// Fixture: a Classic-Burger-shaped source, and a target that already carries
// its OWN price, Kitchen setup and Phase-3 hidden values (so "discard restores"
// and "no-wipe" both have something real to protect).
// ---------------------------------------------------------------------------

const Map<String, dynamic> _sourceAttributes = <String, dynamic>{
  'portion_label': 'Double',
  'patty_count': 2,
  'prep_components': [
    {'name': 'Bun', 'quantity': 1, 'unit': 'pc'},
    {
      'name': 'Meat',
      'quantity': 1,
      'unit': 'pc',
      'classifier_option_id': 'opt-cheese',
      'classifier_option_name': 'Cheese',
    },
  ],
};

const Map<String, dynamic> _targetAttributes = <String, dynamic>{
  'portion_label': 'Single',
  'patty_weight_grams': 90,
  'future_ticket_key': {'written_by': 'a later ticket', 'n': 7},
  'prep_components': [
    {'name': 'Own bun', 'quantity': 3, 'unit': 'pcs'},
  ],
};

_Spy _store() => _Spy(
  categories: const [
    MenuCategory(
      id: 'cat-grill',
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      name: 'Grill',
      displayOrder: 0,
      isActive: true,
    ),
  ],
  items: const [
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
      imagePath: 'menu/classic.jpg',
      sku: 'CB-1',
      prepMinutes: 9,
      kitchenNote: 'Toast the bun.',
      attributes: _sourceAttributes,
    ),
    MenuItem(
      id: 'item-plain',
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
      imagePath: 'menu/plain.jpg',
      sku: 'PB-9',
      prepMinutes: 4,
      kitchenNote: 'Keep it plain.',
      attributes: _targetAttributes,
    ),
  ],
  sizes: const [
    ItemSize(
      id: 'size-1',
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      menuItemId: 'item-plain',
      name: 'Legacy large',
      priceDeltaMinor: 700,
      displayOrder: 0,
      isActive: true,
    ),
  ],
  variants: const [
    ItemVariant(
      id: 'variant-1',
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      menuItemId: 'item-plain',
      name: 'Legacy spicy',
      priceDeltaMinor: 0,
      displayOrder: 0,
      isActive: true,
    ),
  ],
  modifiers: const [
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
  ],
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
      isActive: false,
    ),
  ],
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _Spy store, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
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

Future<void> _open(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _typeKey(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pumpAndSettle();
}

/// Applies Classic Burger to whatever item the editor is on, confirming the
/// replace prompt when the form already holds values.
Future<void> _applySource(
  WidgetTester tester,
  AppLocalizations l10n, {
  bool expectConfirm = true,
}) async {
  await _tapKey(tester, 'menu-copy-choose-source');
  await _tapKey(tester, 'menu-copy-source-item-classic');
  await _tapKey(tester, 'menu-copy-preview-apply');
  if (expectConfirm) {
    await _tapKey(tester, 'menu-copy-replace-accept');
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-item-save')));
  await tester.pumpAndSettle();
}

MenuItem _plain(MenuSnapshot s) =>
    s.items.firstWhere((i) => i.id == 'item-plain');
MenuItem _classic(MenuSnapshot s) =>
    s.items.firstWhere((i) => i.id == 'item-classic');

List<ModifierOption> _targetOptions(MenuSnapshot s) => <ModifierOption>[
  for (final group in s.modifiersForItem('item-plain'))
    ...s.optionsForModifier(group.id),
];

void main() {
  // =========================================================================
  group('A. editing the draft writes nothing', () {
    testWidgets('A1. rewriting a whole GROUP — name, selection, min/max, '
        'required, active, quantity — performs zero writes', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);
      expect(store.writes, isEmpty);

      await _tapKey(tester, 'menu-copy-draft-group-edit-mod-size');
      await _typeKey(tester, 'menu-copy-draft-group-name', 'Weight');
      await _typeKey(tester, 'menu-copy-draft-group-min', '0');
      await _typeKey(tester, 'menu-copy-draft-group-max', '2');
      await _tapKey(tester, 'menu-copy-draft-group-required');
      await _tapKey(tester, 'menu-copy-draft-group-active');
      await _tapKey(tester, 'menu-copy-draft-group-save');

      expect(find.text('Weight'), findsOneWidget);
      expect(
        store.writes,
        isEmpty,
        reason: 'the draft lives in memory; editing it touches no seam at all',
      );
      final snapshot = await store.load(demoMenuScope);
      expect(snapshot.modifiersForItem('item-plain'), isEmpty);
    });

    testWidgets('A2. rewriting an OPTION — name, delta, kitchen count and the '
        'split-by link — performs zero writes', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      await _tapKey(tester, 'menu-copy-draft-option-edit-opt-240');
      await _typeKey(tester, 'menu-copy-draft-option-name', 'Extra large');
      await _typeKey(tester, 'menu-copy-draft-option-delta', '18.00');
      await _typeKey(tester, 'menu-copy-draft-option-meat-quantity', '3');
      await _typeKey(tester, 'menu-copy-draft-option-meat-unit', 'patties');
      await _tapKey(tester, 'menu-copy-draft-option-save');

      expect(find.text('Extra large'), findsOneWidget);
      expect(store.writes, isEmpty);
      expect((await store.load(demoMenuScope)).modifierOptions, hasLength(4));
    });

    testWidgets('A3. removing a draft option is local too — and CLEARS the '
        'links that named it', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      // Cheese is the split-by target of both size options.
      await _tapKey(tester, 'menu-copy-draft-option-delete-opt-cheese');
      expect(
        find.textContaining(l10n.menuCopyDraftRemoveLinked),
        findsOneWidget,
        reason: 'the confirmation must say the links will be cleared',
      );
      await _tapKey(tester, 'menu-copy-draft-remove-accept');

      expect(
        find.byKey(const ValueKey('menu-copy-draft-option-opt-cheese')),
        findsNothing,
      );
      expect(store.writes, isEmpty);

      // Saving now must not write a single classifier anywhere.
      await _save(tester);
      for (final option in _targetOptions(await store.load(demoMenuScope))) {
        expect(
          option.kitchenMeatClassifierOptionId,
          isEmpty,
          reason: 'a removed target must leave no dangling link behind',
        );
        if (option.name == '120g') {
          expect(
            option.hasKitchenMeat,
            isTrue,
            reason: 'the COUNT survives; only the split is gone',
          );
        }
      }
    });
  });

  // =========================================================================
  group('B. the edited draft is what gets saved', () {
    testWidgets('B1. group rename + rule changes reach the writer', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      await _tapKey(tester, 'menu-copy-draft-group-edit-mod-size');
      await _typeKey(tester, 'menu-copy-draft-group-name', 'Weight');
      await _typeKey(tester, 'menu-copy-draft-group-min', '0');
      await _typeKey(tester, 'menu-copy-draft-group-max', '2');
      await _tapKey(tester, 'menu-copy-draft-group-required');
      await _tapKey(tester, 'menu-copy-draft-group-save');
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final groups = snapshot.modifiersForItem('item-plain');
      final weight = groups.firstWhere((g) => g.name == 'Weight');
      expect(weight.minSelect, 0);
      expect(weight.maxSelect, 2);
      expect(weight.isRequired, isFalse);
      expect(
        groups.any((g) => g.name == 'Size'),
        isFalse,
        reason: 'the ORIGINAL name must not be what was written',
      );
      // The source group is untouched.
      expect(snapshot.modifiersForItem('item-classic').first.name, 'Size');
    });

    testWidgets('B2. an edited price delta and option name reach the writer', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      await _tapKey(tester, 'menu-copy-draft-option-edit-opt-240');
      await _typeKey(tester, 'menu-copy-draft-option-name', 'Extra large');
      await _typeKey(tester, 'menu-copy-draft-option-delta', '18.00');
      await _tapKey(tester, 'menu-copy-draft-option-save');
      await _save(tester);

      final options = _targetOptions(await store.load(demoMenuScope));
      final edited = options.firstWhere((o) => o.name == 'Extra large');
      expect(edited.priceDeltaMinor, 1800);
      expect(options.any((o) => o.name == '240g'), isFalse);
      // Source untouched.
      final source = (await store.load(
        demoMenuScope,
      )).modifierOptions.firstWhere((o) => o.id == 'opt-240');
      expect(source.name, '240g');
      expect(source.priceDeltaMinor, 1500);
    });

    testWidgets('B3. an edited KITCHEN COUNT reaches the writer', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      await _tapKey(tester, 'menu-copy-draft-option-edit-opt-240');
      await _typeKey(tester, 'menu-copy-draft-option-meat-quantity', '3');
      await _typeKey(tester, 'menu-copy-draft-option-meat-unit', 'patties');
      await _tapKey(tester, 'menu-copy-draft-option-save');
      await _save(tester);

      final edited = _targetOptions(
        await store.load(demoMenuScope),
      ).firstWhere((o) => o.name == '240g');
      expect(edited.kitchenMeatQuantity, 3);
      expect(edited.kitchenMeatUnit, 'patties');
      // The source's own count is untouched.
      final source = (await store.load(
        demoMenuScope,
      )).modifierOptions.firstWhere((o) => o.id == 'opt-240');
      expect(source.kitchenMeatQuantity, 2);
      expect(source.kitchenMeatUnit, 'pcs');
    });

    testWidgets('B4. turning a kitchen count OFF removes it from the target '
        'without touching the option itself', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      await _tapKey(tester, 'menu-copy-draft-option-edit-opt-120');
      await _tapKey(tester, 'menu-copy-draft-option-meat-enabled');
      await _tapKey(tester, 'menu-copy-draft-option-save');
      await _save(tester);

      final saved = _targetOptions(
        await store.load(demoMenuScope),
      ).firstWhere((o) => o.name == '120g');
      expect(saved.hasKitchenMeat, isFalse);
      expect(saved.kitchenMeatClassifierOptionId, isEmpty);
      expect(saved.name, '120g');
    });
  });

  // =========================================================================
  group('C. the classifier survives edits and still remaps', () {
    testWidgets('C1. renaming the classifying option before Save keeps the '
        'link, and the target points at the NEW option under the NEW name', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      await _tapKey(tester, 'menu-copy-draft-option-edit-opt-cheese');
      await _typeKey(tester, 'menu-copy-draft-option-name', 'Yellow cheese');
      await _tapKey(tester, 'menu-copy-draft-option-save');
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final options = _targetOptions(snapshot);
      final cheese = options.firstWhere((o) => o.name == 'Yellow cheese');
      expect(cheese.id, isNot('opt-cheese'));
      for (final name in <String>['120g', '240g']) {
        final sized = options.firstWhere((o) => o.name == name);
        expect(
          sized.kitchenMeatClassifierOptionId,
          cheese.id,
          reason: 'a rename must not break the link — it is keyed on identity',
        );
        expect(
          sized.kitchenMeat!['classifier_option_name'],
          'Yellow cheese',
          reason: 'the label follows the draft, not what the source carried',
        );
      }
      // And the item's own Kitchen setup row too.
      final meatRow = (_plain(snapshot).attributes['prep_components']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((row) => row['name'] == 'Meat');
      expect(meatRow['classifier_option_id'], cheese.id);
      expect(meatRow['classifier_option_name'], 'Yellow cheese');
    });

    testWidgets('C2. re-pointing the split-by link at another draft option is '
        'honoured on Save', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);

      await _tapKey(tester, 'menu-copy-draft-option-edit-opt-120');
      await tester.tap(
        find.byKey(const ValueKey('menu-copy-draft-option-classifier')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lettuce').last);
      await tester.pumpAndSettle();
      await _tapKey(tester, 'menu-copy-draft-option-save');
      await _save(tester);

      final options = _targetOptions(await store.load(demoMenuScope));
      final lettuce = options.firstWhere((o) => o.name == 'Lettuce');
      final sized = options.firstWhere((o) => o.name == '120g');
      expect(sized.kitchenMeatClassifierOptionId, lettuce.id);
      expect(sized.kitchenMeat!['classifier_option_name'], 'Lettuce');
      // The other size option keeps its own (Cheese) link.
      final other = options.firstWhere((o) => o.name == '240g');
      final cheese = options.firstWhere((o) => o.name == 'Cheese');
      expect(other.kitchenMeatClassifierOptionId, cheese.id);
    });

    testWidgets('C3. no target row ever carries a SOURCE option id', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);
      await _tapKey(tester, 'menu-copy-draft-option-edit-opt-cheese');
      await _typeKey(tester, 'menu-copy-draft-option-name', 'Yellow cheese');
      await _tapKey(tester, 'menu-copy-draft-option-save');
      await _save(tester);

      for (final args in store.optionArgs) {
        final meat = args['kitchenMeat'] as Map<String, dynamic>?;
        final id = meat?['classifier_option_id'];
        expect(id, isNot('opt-cheese'), reason: 'not on the wire, on any pass');
      }
      final prepRows =
          (store.itemArgs.last['attributes']!
                  as Map<String, dynamic>)['prep_components']!
              as List;
      for (final row in prepRows.cast<Map<String, Object?>>()) {
        expect(row['classifier_option_id'], isNot('opt-cheese'));
      }
    });
  });

  // =========================================================================
  group('D. Discard puts the form back', () {
    testWidgets('D1. discarding restores the pre-copy price and Kitchen setup, '
        'with zero writes', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');

      String priceText() => tester
          .widget<TextField>(find.byKey(const ValueKey('menu-item-price')))
          .controller!
          .text;
      String prepName(int i) => tester
          .widget<TextField>(find.byKey(ValueKey('menu-item-prep-name-$i')))
          .controller!
          .text;

      expect(priceText(), '30.00');
      expect(prepName(0), 'Own bun');

      await _applySource(tester, l10n);
      expect(priceText(), '48.00');
      expect(prepName(0), 'Bun');
      expect(prepName(1), 'Meat');

      await _tapKey(tester, 'menu-copy-discard');

      expect(
        priceText(),
        '30.00',
        reason: 'the operator gets THEIR price back',
      );
      expect(prepName(0), 'Own bun');
      expect(
        find.byKey(const ValueKey('menu-item-prep-name-1')),
        findsNothing,
        reason: 'the copied second row is gone with the rest of the copy',
      );
      expect(find.byKey(const ValueKey('menu-copy-summary')), findsNothing);
      expect(store.writes, isEmpty);
    });

    testWidgets('D2. discard after CHANGING the source still restores the '
        'operator\'s own values, not the previous copy\'s', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);
      // Change source: the picker offers Classic again (the only candidate).
      await _applySource(tester, l10n);
      await _tapKey(tester, 'menu-copy-discard');

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('menu-item-price')))
            .controller!
            .text,
        '30.00',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('menu-item-prep-name-0')),
            )
            .controller!
            .text,
        'Own bun',
      );
      expect(store.writes, isEmpty);
    });

    testWidgets('D3. saving after a discard writes the operator\'s OWN values '
        '— no trace of the copy', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);
      await _tapKey(tester, 'menu-copy-discard');
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final target = _plain(snapshot);
      expect(target.basePriceMinor, 3000);
      expect(snapshot.modifiersForItem('item-plain'), isEmpty);
      expect(target.attributes['prep_components'], [
        {'name': 'Own bun', 'quantity': 3, 'unit': 'pcs'},
      ]);
    });
  });

  // =========================================================================
  group('E. closing without Save, and the source', () {
    testWidgets('E1. leaving the editor after editing the draft writes nothing '
        'and leaves the store identical', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      final before = await store.load(demoMenuScope);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);
      await _tapKey(tester, 'menu-copy-draft-group-edit-mod-size');
      await _typeKey(tester, 'menu-copy-draft-group-name', 'Weight');
      await _tapKey(tester, 'menu-copy-draft-group-save');
      await tester.tap(find.text(l10n.menuCancelAction).last);
      await tester.pumpAndSettle();

      expect(store.writes, isEmpty);
      final after = await store.load(demoMenuScope);
      expect(after.items.length, before.items.length);
      expect(after.modifiers.length, before.modifiers.length);
      expect(after.modifierOptions.length, before.modifierOptions.length);
      expect(_classic(after).attributes, _sourceAttributes);
      expect(_plain(after).attributes, _targetAttributes);
    });

    testWidgets('E2. the SOURCE is never written to, even after a full save', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);
      await _save(tester);

      expect(store.itemArgs.where((a) => a['id'] == 'item-classic'), isEmpty);
      final snapshot = await store.load(demoMenuScope);
      final source = _classic(snapshot);
      expect(source.basePriceMinor, 4800);
      expect(source.sku, 'CB-1');
      expect(source.attributes, _sourceAttributes);
      expect(snapshot.modifiersForItem('item-classic'), hasLength(2));
    });
  });

  // =========================================================================
  group('F. Phase-3 no-wipe survives a copy save', () {
    testWidgets('F1. the target keeps its own hidden values, its image and '
        'both legacy rows', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Plain Burger');
      await _applySource(tester, l10n);
      await _tapKey(tester, 'menu-copy-draft-group-edit-mod-size');
      await _typeKey(tester, 'menu-copy-draft-group-name', 'Weight');
      await _tapKey(tester, 'menu-copy-draft-group-save');
      await _save(tester);

      final snapshot = await store.load(demoMenuScope);
      final target = _plain(snapshot);
      expect(target.sku, 'PB-9');
      expect(target.prepMinutes, 4);
      expect(target.kitchenNote, 'Keep it plain.');
      expect(target.imagePath, 'menu/plain.jpg');
      expect(target.attributes['portion_label'], 'Single');
      expect(target.attributes['patty_weight_grams'], 90);
      expect(target.attributes['future_ticket_key'], {
        'written_by': 'a later ticket',
        'n': 7,
      });
      expect(snapshot.sizesForItem('item-plain'), hasLength(1));
      expect(snapshot.variantsForItem('item-plain'), hasLength(1));
      // Nothing was ever deleted to make room for the copy.
      expect(store.writes.where((w) => w == 'softDelete'), isEmpty);
      expect(store.writes.where((w) => w == 'upsertSize'), isEmpty);
      expect(store.writes.where((w) => w == 'upsertVariant'), isEmpty);
    });

    testWidgets('F2. an item that already has modifier groups stays safely '
        'blocked — no draft editor, no control', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'Classic Burger');

      expect(find.byKey(const ValueKey('menu-copy-blocked')), findsOneWidget);
      expect(find.text(l10n.menuCopyBlockedHasModifiers), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-copy-draft-editor')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('menu-copy-choose-source')),
            )
            .onPressed,
        isNull,
      );
      expect(store.writes, isEmpty);
    });
  });

  // =========================================================================
  group('G. the three locales', () {
    for (final locale in <String>['ar', 'he', 'en']) {
      testWidgets('G1-$locale. the draft editor and both of its dialogs render '
          'without overflow', (tester) async {
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) =>
            errors.add(details.exceptionAsString());
        addTearDown(() => FlutterError.onError = previous);

        final store = _store();
        final l10n = await _pump(tester, store, locale: Locale(locale));
        await _open(tester, 'Plain Burger');
        await _applySource(tester, l10n);
        expect(
          find.byKey(const ValueKey('menu-copy-draft-editor')),
          findsOneWidget,
        );
        await _tapKey(tester, 'menu-copy-draft-group-edit-mod-additions');
        expect(
          find.byKey(const ValueKey('menu-copy-draft-group-dialog')),
          findsOneWidget,
        );
        await _tapKey(tester, 'menu-copy-draft-group-save');
        await _tapKey(tester, 'menu-copy-draft-option-edit-opt-120');
        expect(
          find.byKey(const ValueKey('menu-copy-draft-option-dialog')),
          findsOneWidget,
        );
        await _tapKey(tester, 'menu-copy-draft-option-save');

        FlutterError.onError = previous;
        expect(
          errors.where((e) => e.contains('overflowed')),
          isEmpty,
          reason: 'RTL/LTR must not overflow in $locale: $errors',
        );
      });
    }
  });
}
