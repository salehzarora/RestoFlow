import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Menu/media sprint (Part C): the item editor's sectioned layout (basic info /
/// image / pricing / preparation / modifiers / collapsed advanced) and the
/// save payload — every rich attribute the operator sets must reach
/// MenuWriter.upsertItem (itemType, tags, prepMinutes, sku, kitchenNote, and
/// the snake_case attributes bag). Money stays integer minor (D-007) and the
/// attributes bag carries NO money — weight is grams, count is pieces.

/// An [InMemoryMenuStore] that records the last upsertItem arguments so the
/// widget test can assert the editor's save payload end to end.
class _RecordingStore extends InMemoryMenuStore {
  _RecordingStore({super.categories, super.items});

  int upsertItemCalls = 0;
  String? lastItemType;
  List<String>? lastTags;
  int? lastPrepMinutes;
  String? lastSku;
  String? lastKitchenNote;
  Map<String, dynamic>? lastAttributes;
  String? lastName;

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
    int displayOrder = 0,
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
}

_RecordingStore _seededStore() => _RecordingStore(
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
      description: null,
      basePriceMinor: 4800,
      currencyCode: demoCurrencyCode,
      defaultStationId: null,
      displayOrder: 0,
      isActive: true,
      itemType: 'food',
      tags: ['popular'],
      prepMinutes: 10,
      sku: 'HB-1',
      kitchenNote: 'Rest the patty.',
      attributes: {'patty_count': 1},
    ),
  ],
);

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _RecordingStore store,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
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

void main() {
  testWidgets('an existing item shows the six sections with the advanced '
      'section COLLAPSED (fields hidden until expanded)', (tester) async {
    final store = _seededStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'House Burger');

    // Section titles (built anywhere in the scroll view counts).
    expect(find.text(l10n.menuBasicInfoSection), findsOneWidget);
    expect(find.text(l10n.menuImageHeading), findsOneWidget);
    expect(find.text(l10n.menuPricingSection), findsOneWidget);
    expect(find.text(l10n.menuSizesHeading), findsOneWidget);
    expect(find.text(l10n.menuVariantsHeading), findsOneWidget);
    expect(find.text(l10n.menuPreparationSection), findsOneWidget);
    expect(find.text(l10n.menuModifiersHeading), findsOneWidget);
    expect(find.text(l10n.menuAdvancedSection), findsOneWidget);

    // Field keys present.
    expect(find.byKey(const ValueKey('menu-item-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-type')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-price')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('menu-item-prep-minutes')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('menu-item-kitchen-note')),
      findsOneWidget,
    );

    // Advanced starts collapsed — its fields are NOT built yet.
    expect(find.byKey(const ValueKey('menu-item-sku')), findsNothing);
    expect(find.byKey(const ValueKey('menu-item-portion')), findsNothing);

    // Expanding reveals the generic advanced fields.
    await tester.ensureVisible(
      find.byKey(const ValueKey('menu-item-advanced')),
    );
    await tester.tap(find.byKey(const ValueKey('menu-item-advanced')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-item-sku')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-portion')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-patty-count')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('menu-item-patty-weight')),
      findsOneWidget,
    );
  });

  testWidgets('a NEW item shows only the field sections (no image, sizes, '
      'variants, or modifiers)', (tester) async {
    final store = _seededStore();
    final l10n = await _pump(tester, store);

    await tester.tap(find.text(l10n.menuAddItem));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuBasicInfoSection), findsOneWidget);
    expect(find.text(l10n.menuPricingSection), findsOneWidget);
    expect(find.text(l10n.menuPreparationSection), findsOneWidget);
    expect(find.text(l10n.menuAdvancedSection), findsOneWidget);
    expect(find.text(l10n.menuImageHeading), findsNothing);
    expect(find.text(l10n.menuSizesHeading), findsNothing);
    expect(find.text(l10n.menuModifiersHeading), findsNothing);
  });

  testWidgets('saving sends every rich attribute to upsertItem (the save '
      'payload contract)', (tester) async {
    final store = _seededStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'House Burger');

    // Preparation.
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-prep-minutes')),
      '15',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-kitchen-note')),
      'Extra crispy.',
    );

    // Tags: add 'spicy' to the pre-selected 'popular'.
    await tester.ensureVisible(
      find.byKey(const ValueKey('menu-item-tag-spicy')),
    );
    await tester.tap(find.byKey(const ValueKey('menu-item-tag-spicy')));
    await tester.pump();

    // Item type: switch food -> combo through the dropdown.
    await tester.ensureVisible(find.byKey(const ValueKey('menu-item-type')));
    await tester.tap(find.byKey(const ValueKey('menu-item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.menuItemTypeCombo).last);
    await tester.pumpAndSettle();

    // Advanced: expand, then fill SKU/portion/count/weight.
    await tester.ensureVisible(
      find.byKey(const ValueKey('menu-item-advanced')),
    );
    await tester.tap(find.byKey(const ValueKey('menu-item-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('menu-item-sku')), 'HB-2');
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-portion')),
      'Double',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-patty-count')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-patty-weight')),
      '160',
    );

    // Save lives in the always-visible top bar.
    await tester.tap(find.byKey(const ValueKey('menu-item-save')));
    await tester.pumpAndSettle();

    expect(store.upsertItemCalls, 1);
    expect(store.lastName, 'House Burger');
    expect(store.lastItemType, 'combo');
    // Canonical vocabulary order, not click order.
    expect(store.lastTags, ['spicy', 'popular']);
    expect(store.lastPrepMinutes, 15);
    expect(store.lastSku, 'HB-2');
    expect(store.lastKitchenNote, 'Extra crispy.');
    expect(store.lastAttributes, {
      'portion_label': 'Double',
      'patty_count': 2,
      'patty_weight_grams': 160,
    });
  });

  testWidgets('a non-integer prep time is a field error and blocks the save', (
    tester,
  ) async {
    final store = _seededStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'House Burger');

    await tester.enterText(
      find.byKey(const ValueKey('menu-item-prep-minutes')),
      'abc',
    );
    await tester.tap(find.byKey(const ValueKey('menu-item-save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuErrorAmount), findsOneWidget);
    expect(store.upsertItemCalls, 0);
  });

  testWidgets('a negative advanced count is a field error and blocks the '
      'save', (tester) async {
    final store = _seededStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'House Burger');

    await tester.ensureVisible(
      find.byKey(const ValueKey('menu-item-advanced')),
    );
    await tester.tap(find.byKey(const ValueKey('menu-item-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-patty-count')),
      '-1',
    );
    await tester.tap(find.byKey(const ValueKey('menu-item-save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuErrorNegativePrice), findsOneWidget);
    expect(store.upsertItemCalls, 0);
  });

  testWidgets('an existing item shows the product summary strip (name, '
      'price, active pill, tag preview); a new item does not', (tester) async {
    final store = _seededStore();
    final l10n = await _pump(tester, store);
    await _openItem(tester, 'House Burger');

    final strip = find.byKey(const ValueKey('menu-item-summary'));
    expect(strip, findsOneWidget);
    expect(
      find.descendant(of: strip, matching: find.text('House Burger')),
      findsOneWidget,
    );
    // Integer-minor money rendered through formatMinorUnits (D-007).
    expect(
      find.descendant(of: strip, matching: find.text('48.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: strip, matching: find.text(l10n.menuFilterActive)),
      findsOneWidget,
    );
    // The stored tag previews as its LOCALIZED pill label.
    expect(
      find.descendant(of: strip, matching: find.text(l10n.menuTagPopular)),
      findsOneWidget,
    );

    // A NEW item has no persisted state to summarize — no strip.
    await tester.tap(find.byType(BackButtonIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.menuAddItem));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-item-summary')), findsNothing);
  });

  testWidgets('the editor initializes its fields from the stored rich '
      'attributes', (tester) async {
    final store = _seededStore();
    await _pump(tester, store);
    await _openItem(tester, 'House Burger');

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('menu-item-prep-minutes')),
          )
          .controller!
          .text,
      '10',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('menu-item-kitchen-note')),
          )
          .controller!
          .text,
      'Rest the patty.',
    );
    // The stored tag renders selected.
    final popularChip = tester.widget<FilterChip>(
      find.byKey(const ValueKey('menu-item-tag-popular')),
    );
    expect(popularChip.selected, isTrue);
    final spicyChip = tester.widget<FilterChip>(
      find.byKey(const ValueKey('menu-item-tag-spicy')),
    );
    expect(spicyChip.selected, isFalse);
  });
}
