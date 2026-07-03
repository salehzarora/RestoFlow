import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Menu/media sprint (Part F): the dashboard item list reads like a product
/// catalog — rows carry localized tag TONE pills (wire strings never rendered
/// raw), a compact modifier-group count with a localized tooltip, and an image
/// thumbnail that resolves a signed URL through the surface's storage seam
/// (placeholder fallback when storage is missing, the item is imageless, or
/// any resolution/load step fails — images are never load-bearing).

const String _imagedPath =
    'demo-org/demo-restaurant/demo-branch/menu_item/item-imaged/img-1.png';

InMemoryMenuStore _seededStore() {
  MenuItem item(
    String id,
    String name, {
    List<String> tags = const [],
    String? imagePath,
  }) => MenuItem(
    id: id,
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: demoBranchId,
    menuCategoryId: 'cat-1',
    name: name,
    description: null,
    basePriceMinor: 4200,
    currencyCode: demoCurrencyCode,
    defaultStationId: null,
    displayOrder: 0,
    isActive: true,
    tags: tags,
    imagePath: imagePath,
  );

  return InMemoryMenuStore(
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
    items: [
      item('item-tagged', 'House Burger', tags: const ['spicy', 'popular']),
      item('item-plain', 'Plain Water'),
      item('item-imaged', 'Imaged Latte', imagePath: _imagedPath),
    ],
    modifiers: const [
      // One live modifier group on the tagged item only.
      Modifier(
        id: 'mod-1',
        organizationId: demoOrganizationId,
        restaurantId: demoRestaurantId,
        branchId: demoBranchId,
        menuItemId: 'item-tagged',
        name: 'Extras',
        selectionType: 'multiple',
        minSelect: 0,
        maxSelect: null,
        isRequired: false,
        displayOrder: 0,
        isActive: true,
      ),
    ],
  );
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  InMemoryMenuStore store, {
  MenuImageStorageConfig? imageStorage,
}) async {
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
        imageStorage: imageStorage,
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

void main() {
  testWidgets('rows render localized tag tone pills and a modifier-group '
      'count indicator (tagless/groupless rows stay clean)', (tester) async {
    final l10n = await _pump(tester, _seededStore());

    // The tagged item's pills — localized labels, one row each.
    expect(find.text(l10n.menuTagSpicy), findsOneWidget);
    expect(find.text(l10n.menuTagPopular), findsOneWidget);
    // No other tag leaks in from anywhere.
    expect(find.text(l10n.menuTagVegetarian), findsNothing);

    // Exactly ONE modifier-count indicator (only item-tagged carries a group),
    // with the localized tooltip.
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byTooltip(l10n.menuModifierGroupCount(1)), findsOneWidget);
  });

  testWidgets('without wired image storage every thumbnail is the quiet '
      'placeholder — even for an item that HAS an image path', (tester) async {
    await _pump(tester, _seededStore());

    // No storage seam on this surface: no Image is ever attempted.
    expect(find.byType(Image), findsNothing);
    // All three rows show the placeholder icon.
    expect(find.byIcon(Icons.image_outlined), findsNWidgets(3));
  });

  testWidgets('with wired storage the imaged row resolves a signed URL and '
      'renders an Image; a load failure still falls back quietly', (
    tester,
  ) async {
    await _pump(
      tester,
      _seededStore(),
      imageStorage: MenuImageStorageConfig(
        storage: FakeMenuImageStorage(),
        isDemo: true,
      ),
    );

    // Only the imaged item attempts an Image (the fake's synthetic signed URL
    // cannot actually load in the test harness, so the errorBuilder fallback
    // icon renders too — fail-soft, no exception, no error chrome).
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNWidgets(3));
  });
}
