import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// OPS-043 Phase 3 — THE NO-WIPE CONTRACT.
///
/// `menu_upsert_item` is a FULL-STATE upsert: a field the editor stops sending
/// is CLEARED on the server. Phase 3 removed four sections from the editor, so
/// without a carry-through an operator who renamed an item would silently erase
/// its SKU, prep time, kitchen note and legacy attributes — and nothing on
/// screen would say so, because the fields are no longer on screen.
///
/// Every test here therefore asserts on what reaches the WRITER, not on what
/// the screen shows. The fixture carries every retired field plus an unknown
/// future key, because "unknown keys survive" is the property that decides
/// whether this change is safe for data nobody has written yet.
class _RecordingStore extends InMemoryMenuStore {
  _RecordingStore({super.categories, super.items});

  int upsertItemCalls = 0;
  int upsertSizeCalls = 0;
  int upsertVariantCalls = 0;
  int softDeleteCalls = 0;
  final List<MenuEntityType> softDeleted = [];

  String? lastName;
  String? lastDescription;
  int? lastBasePriceMinor;
  String? lastImagePath;
  String? lastItemType;
  List<String>? lastTags;
  int? lastPrepMinutes;
  String? lastSku;
  String? lastKitchenNote;
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
    lastName = name;
    lastDescription = description;
    lastBasePriceMinor = basePriceMinor;
    lastImagePath = imagePath;
    lastItemType = itemType;
    lastTags = tags;
    lastPrepMinutes = prepMinutes;
    lastSku = sku;
    lastKitchenNote = kitchenNote;
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
    upsertSizeCalls++;
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
    upsertVariantCalls++;
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
  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  }) {
    softDeleteCalls++;
    softDeleted.add(entity);
    return super.softDelete(
      organizationId: organizationId,
      entity: entity,
      id: id,
    );
  }
}

// ---------------------------------------------------------------------------
// The fixture: an item carrying EVERY retired field, an unknown future key, a
// size row, a variant row, prep components and a modifier with kitchen_meat.
// ---------------------------------------------------------------------------

const _unknownKey = 'future_ticket_key';

const _legacyAttributes = <String, dynamic>{
  'portion_label': 'Double',
  'patty_count': 2,
  'patty_weight_grams': 160,
  _unknownKey: {'written_by': 'a later ticket', 'n': 7},
  'prep_components': [
    {'name': 'Beef patty', 'quantity': 2, 'unit': 'pcs'},
  ],
};

_RecordingStore _store() => _RecordingStore(
  categories: const [
    MenuCategory(
      id: 'cat-1',
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
      id: 'item-1',
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      menuCategoryId: 'cat-1',
      name: 'House Burger',
      description: 'The one everybody orders.',
      basePriceMinor: 4800,
      currencyCode: demoCurrencyCode,
      defaultStationId: null,
      displayOrder: 0,
      isActive: true,
      imagePath: 'menu/house-burger.jpg',
      itemType: 'food',
      tags: ['popular'],
      prepMinutes: 10,
      sku: 'HB-1',
      kitchenNote: 'Rest the patty.',
      attributes: _legacyAttributes,
    ),
  ],
);

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _RecordingStore store, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 1800);
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

Future<void> _open(WidgetTester tester, [String name = 'House Burger']) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-item-save')));
  await tester.pumpAndSettle();
}

/// Every hidden field, asserted at the writer boundary in one place.
void _expectLegacyIntact(_RecordingStore store) {
  expect(store.lastSku, 'HB-1', reason: 'SKU must survive an unrelated edit');
  expect(store.lastPrepMinutes, 10, reason: 'prep minutes must survive');
  expect(store.lastKitchenNote, 'Rest the patty.', reason: 'note must survive');
  final attrs = store.lastAttributes!;
  expect(attrs['portion_label'], 'Double');
  expect(attrs['patty_count'], 2);
  expect(attrs['patty_weight_grams'], 160);
  expect(
    attrs[_unknownKey],
    {'written_by': 'a later ticket', 'n': 7},
    reason: 'a key this editor never knew about must be passed through whole',
  );
  expect(
    attrs['prep_components'],
    [
      {'name': 'Beef patty', 'quantity': 2, 'unit': 'pcs'},
    ],
    reason: 'Kitchen setup is the one bag this editor owns — and it is intact',
  );
}

void main() {
  group('A. every legacy value survives a name-only edit', () {
    testWidgets('A1. rename and save — SKU, prep minutes, kitchen note, the '
        'three retired attributes and an UNKNOWN key all reach the writer '
        'unchanged', (tester) async {
      final store = _store();
      await _pump(tester, store);
      await _open(tester);

      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'House Burger Deluxe',
      );
      await tester.pumpAndSettle();
      await _save(tester);

      expect(store.upsertItemCalls, 1);
      expect(store.lastName, 'House Burger Deluxe');
      _expectLegacyIntact(store);
    });

    testWidgets('A2. the image is carried through too — a details save must '
        'not clear a picture the operator cannot see from here', (
      tester,
    ) async {
      final store = _store();
      await _pump(tester, store);
      await _open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'Renamed',
      );
      await tester.pumpAndSettle();
      await _save(tester);

      expect(store.lastImagePath, 'menu/house-burger.jpg');
    });

    testWidgets('A3. saving touches ONLY the item: no size or variant write, '
        'and no soft-delete of anything', (tester) async {
      final store = _store();
      await _pump(tester, store);
      await _open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'Renamed',
      );
      await tester.pumpAndSettle();
      await _save(tester);

      expect(store.upsertSizeCalls, 0);
      expect(store.upsertVariantCalls, 0);
      expect(store.softDeleteCalls, 0);
      expect(store.softDeleted, isEmpty);
    });
  });

  group('B. a price-only edit is just as safe', () {
    testWidgets('B1. change the price — the legacy values are untouched and '
        'the new price is the only thing that moved', (tester) async {
      final store = _store();
      await _pump(tester, store);
      await _open(tester);

      await tester.enterText(
        find.byKey(const ValueKey('menu-item-price')),
        '52.50',
      );
      await tester.pumpAndSettle();
      await _save(tester);

      expect(store.lastBasePriceMinor, 5250);
      expect(store.lastName, 'House Burger', reason: 'name untouched');
      _expectLegacyIntact(store);
    });
  });

  group('C. Kitchen setup edits change ONLY Kitchen setup', () {
    testWidgets('C1. adding a prep component rewrites prep_components and '
        'leaves every other attribute alone', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('menu-item-add-prep-component')),
      );
      await tester.tap(
        find.byKey(const ValueKey('menu-item-add-prep-component')),
      );
      await tester.pumpAndSettle();
      final nameField = find.byKey(const ValueKey('menu-item-prep-name-1'));
      expect(nameField, findsOneWidget, reason: l10n.menuKitchenPrepSection);
      await tester.enterText(nameField, 'Brioche bun');
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-prep-qty-1')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-prep-unit-1')),
        'pcs',
      );
      await tester.pumpAndSettle();
      await _save(tester);

      final attrs = store.lastAttributes!;
      final prep = (attrs['prep_components'] as List).cast<Map>();
      expect(prep, hasLength(2));
      expect(prep.first['name'], 'Beef patty');
      expect(prep.last['name'], 'Brioche bun');
      // The retired keys and the unknown key are bystanders here.
      expect(attrs['portion_label'], 'Double');
      expect(attrs['patty_count'], 2);
      expect(attrs['patty_weight_grams'], 160);
      expect(attrs[_unknownKey], {'written_by': 'a later ticket', 'n': 7});
      expect(store.lastSku, 'HB-1');
      expect(store.lastPrepMinutes, 10);
      expect(store.lastKitchenNote, 'Rest the patty.');
    });

    testWidgets('C2. clearing every prep row still clears the stored list — '
        'the one key this editor owns is genuinely editable', (tester) async {
      final store = _store();
      await _pump(tester, store);
      await _open(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('menu-item-prep-remove-0')),
      );
      await tester.tap(find.byKey(const ValueKey('menu-item-prep-remove-0')));
      await tester.pumpAndSettle();
      await _save(tester);

      final attrs = store.lastAttributes!;
      expect(attrs.containsKey('prep_components'), isFalse);
      // …while everything it does NOT own is still there.
      expect(attrs['portion_label'], 'Double');
      expect(attrs[_unknownKey], isNotNull);
      expect(store.lastSku, 'HB-1');
    });
  });

  group('D. a brand-new item still works', () {
    testWidgets('D1. creating an item sends the safe nulls the RPC contract '
        'expects, and an empty attributes bag', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await tester.tap(find.text(l10n.menuAddItem));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'New Item',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-price')),
        '12.00',
      );
      await tester.pumpAndSettle();
      await _save(tester);

      expect(store.upsertItemCalls, 1, reason: l10n.menuSavedSnack);
      expect(store.lastName, 'New Item');
      expect(store.lastBasePriceMinor, 1200);
      expect(store.lastSku, isNull);
      expect(store.lastPrepMinutes, isNull);
      expect(store.lastKitchenNote, isNull);
      expect(store.lastImagePath, isNull);
      expect(store.lastAttributes, isEmpty);
    });
  });

  group('E. the retired sections are gone from the editor', () {
    testWidgets('E1. no Sizes, Types, Preparation inputs or Advanced panel', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester);

      expect(find.text(l10n.menuSizesHeading), findsNothing);
      expect(find.text(l10n.menuVariantsHeading), findsNothing);
      expect(find.text(l10n.menuPreparationSection), findsNothing);
      expect(find.text(l10n.menuAdvancedSection), findsNothing);
      for (final key in const [
        'menu-item-prep-minutes',
        'menu-item-kitchen-note',
        'menu-item-advanced',
        'menu-item-sku',
        'menu-item-portion',
        'menu-item-patty-count',
        'menu-item-patty-weight',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
    });

    testWidgets('E2. what the restaurant actually uses is still there', (
      tester,
    ) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester);

      expect(find.text(l10n.menuBasicInfoSection), findsOneWidget);
      expect(find.text(l10n.menuImageHeading), findsOneWidget);
      expect(find.text(l10n.menuPricingSection), findsOneWidget);
      expect(find.text(l10n.menuKitchenPrepSection), findsOneWidget);
      expect(find.text(l10n.menuModifiersHeading), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-item-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-item-type')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-item-price')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-item-currency-inherited')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('menu-item-add-prep-component')),
        findsOneWidget,
      );
    });
  });

  group('F. locales', () {
    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      testWidgets('F1. ${locale.languageCode}: the simplified editor renders '
          'without overflow', (tester) async {
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        final store = _store();
        final l10n = await _pump(tester, store, locale: locale);
        await _open(tester);
        FlutterError.onError = prior;

        expect(find.text(l10n.menuKitchenPrepSection), findsOneWidget);
        expect(find.text(l10n.menuAdvancedSection), findsNothing);
        expect(
          overflows.where((o) => o.contains('item_editor_screen.dart')),
          isEmpty,
        );
      });
    }
  });
}
