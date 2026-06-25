import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_feature_menu/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Pumps the menu management surface wired to [readSource] + [writer] via the
/// feature ProviderScope overrides, on a wide viewport (so the master/detail is
/// side-by-side). Returns the resolved localizations + text direction.
Future<({AppLocalizations l10n, TextDirection dir})> pumpMenu(
  WidgetTester tester, {
  required MenuReadSource readSource,
  required MenuWriter writer,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late AppLocalizations l10n;
  late TextDirection dir;
  await tester.pumpWidget(
    ProviderScope(
      overrides: menuFeatureOverrides(
        scope: demoMenuScope,
        readSource: readSource,
        writer: writer,
      ),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              dir = Directionality.of(context);
              return const MenuManagementScreen();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (l10n: l10n, dir: dir);
}

void main() {
  testWidgets(
    'renders the demo menu: categories, items, and an inactive badge',
    (tester) async {
      final store = buildDemoMenuStore();
      final result = await pumpMenu(tester, readSource: store, writer: store);

      expect(find.text(result.l10n.menuCategoriesHeading), findsOneWidget);
      expect(find.text('Hot Drinks'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget); // restaurant-scoped/global
      // The first category is auto-selected, so its items show.
      expect(find.text('Espresso'), findsWidgets);
      expect(find.text('Cappuccino'), findsWidgets);
      // The inactive demo item is listed and badged.
      expect(find.text('Seasonal Pumpkin Latte'), findsOneWidget);
      expect(find.text(result.l10n.menuInactiveBadge), findsWidgets);
    },
  );

  testWidgets('empty store shows the empty-categories state', (tester) async {
    final store = InMemoryMenuStore();
    final result = await pumpMenu(tester, readSource: store, writer: store);
    expect(find.text(result.l10n.menuEmptyCategories), findsOneWidget);
  });

  testWidgets('create category happy path adds it to the list', (tester) async {
    final store = buildDemoMenuStore();
    final result = await pumpMenu(tester, readSource: store, writer: store);

    await tester.tap(find.text(result.l10n.menuAddCategory));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('menu-category-name')),
      'Desserts',
    );
    await tester.tap(find.text(result.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(find.text('Desserts'), findsOneWidget);
  });

  testWidgets('blank category name shows a localized validation error', (
    tester,
  ) async {
    final store = buildDemoMenuStore();
    final result = await pumpMenu(tester, readSource: store, writer: store);

    await tester.tap(find.text(result.l10n.menuAddCategory));
    await tester.pumpAndSettle();
    await tester.tap(find.text(result.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(find.text(result.l10n.menuErrorRequired), findsOneWidget);
  });

  testWidgets('a denied write surfaces the permission-denied message', (
    tester,
  ) async {
    final readStore = buildDemoMenuStore();
    final writer = ScriptedMenuWriter(
      const Failure(MenuPermissionDenied(MenuEntityType.category)),
    );
    final result = await pumpMenu(
      tester,
      readSource: readStore,
      writer: writer,
    );

    await tester.tap(find.text(result.l10n.menuAddCategory));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('menu-category-name')),
      'Specials',
    );
    await tester.tap(find.text(result.l10n.menuSaveAction));
    await tester.pumpAndSettle();

    expect(find.text(result.l10n.menuWritePermissionDenied), findsOneWidget);
    expect(writer.lastOperation, 'upsertCategory');
  });

  testWidgets('soft-delete a category removes it after confirmation', (
    tester,
  ) async {
    final store = buildDemoMenuStore();
    final result = await pumpMenu(tester, readSource: store, writer: store);
    expect(find.text('Hot Drinks'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(result.l10n.menuDeleteAction).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(result.l10n.menuConfirmDelete));
    await tester.pumpAndSettle();

    expect(find.text('Hot Drinks'), findsNothing);
  });

  testWidgets('opening an item shows the editor and the gated image panel', (
    tester,
  ) async {
    final store = buildDemoMenuStore();
    final result = await pumpMenu(tester, readSource: store, writer: store);

    await tester.tap(find.text('Espresso').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-item-name')), findsOneWidget);
    expect(find.text(result.l10n.menuSizesHeading), findsOneWidget);
    // The image panel is the honest, gated deferral (no fake upload).
    expect(find.text(result.l10n.menuImageDeferredTitle), findsOneWidget);
  });

  testWidgets('creating an item validates the required fields', (tester) async {
    final store = buildDemoMenuStore();
    final result = await pumpMenu(tester, readSource: store, writer: store);

    await tester.tap(find.text(result.l10n.menuAddItem));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-item-save')));
    await tester.pumpAndSettle();

    expect(find.text(result.l10n.menuErrorRequired), findsOneWidget); // name
    expect(find.text(result.l10n.menuErrorAmount), findsOneWidget); // price
  });

  testWidgets('Arabic renders right-to-left with localized chrome', (
    tester,
  ) async {
    final store = buildDemoMenuStore();
    final result = await pumpMenu(
      tester,
      readSource: store,
      writer: store,
      locale: const Locale('ar'),
    );
    expect(result.dir, TextDirection.rtl);
    expect(find.text(result.l10n.menuCategoriesHeading), findsOneWidget);
  });

  testWidgets('Hebrew renders right-to-left with localized chrome', (
    tester,
  ) async {
    final store = buildDemoMenuStore();
    final result = await pumpMenu(
      tester,
      readSource: store,
      writer: store,
      locale: const Locale('he'),
    );
    expect(result.dir, TextDirection.rtl);
    expect(find.text(result.l10n.menuCategoriesHeading), findsOneWidget);
  });
}
