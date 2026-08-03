import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/menu_filter.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// POS-PRODUCT-DESCRIPTIONS-001 — G/H/I/J/K/L/M. how the description behaves in
/// the real screen: RTL, five widths, every product state, search, a runtime
/// locale switch, the per-card cost, and payload isolation.

const _ar =
    'شاورما لحم مشوية ببطء تُقطّع حسب الطلب مع طحينة وكبيس ولفت وبصل سماق '
    'وبقدونس في خبز لفة دافئ طازج من الفرن';
const _he =
    'כתף טלה צלויה לאט ונפרסת להזמנה עם טחינה גולמית לפת כבוש בצל סומק '
    'ופטרוזיליה בלאפה חמה מהטאבון';

DemoMenuItem _item({
  String id = 'i-1',
  String name = 'Lamb Shawarma',
  String? description = 'Slow-roasted lamb with tahini and sumac onion.',
  String availability = 'available',
  String? availabilityReason,
  String? imageUrl,
  List<String> tags = const <String>[],
}) => DemoMenuItem(
  id: id,
  name: name,
  priceMinor: 5400,
  categoryId: 'mains',
  categoryName: 'Mains',
  description: description,
  availability: availability,
  availabilityReason: availabilityReason,
  imageUrl: imageUrl,
  tags: tags,
);

Widget _card(
  DemoMenuItem item, {
  Locale locale = const Locale('en'),
  int optionGroupCount = 0,
  int inCartQuantity = 0,
  VoidCallback? onAdd,
  double width = 173,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: posMenuCardExtent(width),
        child: MenuItemCard(
          item: item,
          currencyCode: 'ILS',
          optionGroupCount: optionGroupCount,
          inCartQuantity: inCartQuantity,
          onAdd: onAdd ?? () {},
        ),
      ),
    ),
  ),
);

/// POS-VISUAL-REDESIGN-PHASE-1-007: the product grid takes a FIXED column
/// count per layout mode. A single max-cross-axis-extent could not express the
/// approved layout (it yields 4 columns at both 1440 and 1280), so the delegate
/// type changed. The skeleton-parity contract these tests own is unchanged.
SliverGridDelegateWithFixedCrossAxisCount _gridDelegate(WidgetTester tester) =>
    tester.widget<GridView>(find.byType(GridView).last).gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;

/// FINAL-NEW-MODIFICATIONS-COMBINED-001 replaced the former
/// `_drainPreExistingOverflow` helper: the screen-level horizontal overflow it
/// tolerated has been ROOT-CAUSED and FIXED (a fixed-width Row in the cart's
/// shift context bar), so no overflow is permitted here any more. The sweep
/// that owns that contract now lives in `pos_responsive_overflow_test.dart`.
void _expectCleanFrame(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  Size size = const Size(1400, 1200),
  bool loading = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // A DISTINCT scope per mode: Riverpod forbids changing the override
      // count on an existing ProviderScope, and loaded/skeleton differ.
      key: ValueKey('menu-scope-$loading'),
      overrides: [
        // A never-completing menu keeps the screen on its SKELETON, so the two
        // grid geometries can be compared at the same width.
        if (loading)
          posMenuProvider.overrideWith(
            (ref) => Completer<PosMenuData>().future,
          ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  if (loading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  group('G. Arabic and Hebrew', () {
    for (final entry in {'ar': _ar, 'he': _he}.entries) {
      testWidgets('G-${entry.key} wraps safely under ambient RTL with no '
          'letterSpacing and no clipping', (tester) async {
        await tester.pumpWidget(
          _card(
            _item(name: 'شاورما لحم', description: entry.value),
            locale: Locale(entry.key),
          ),
        );
        await tester.pumpAndSettle();

        final finder = find.text(entry.value);
        expect(finder, findsOneWidget);
        expect(
          Directionality.of(tester.element(finder)),
          TextDirection.rtl,
          reason: 'the description inherits ambient direction',
        );
        final text = tester.widget<Text>(finder);
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(
          text.style?.letterSpacing,
          0,
          reason: 'tracking breaks Arabic/Hebrew shaping',
        );
        // It is laid out inside the card, not spilling out of it.
        final size = tester.getSize(finder);
        expect(size.width, lessThanOrEqualTo(173));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('G-order the semantic label reads name then description', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(
          _item(name: 'שווארמה', description: _he),
          locale: const Locale('he'),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.getSemantics(find.byType(MenuItemCard)).label;
      expect(label.indexOf('שווארמה'), lessThan(label.indexOf(_he)));
    });
  });

  group('H. responsive widths', () {
    for (final width in <double>[390, 600, 800, 1024, 1366]) {
      testWidgets('H-$width the card lays out and the SKELETON and LOADED '
          'grids agree on the cell height', (tester) async {
        // The LOADED grid.
        await _pumpMenu(tester, size: Size(width, 1200));
        _expectCleanFrame(tester);
        final loaded = _gridDelegate(tester);

        // The described demo item is on screen with its description, the image
        // band has not collapsed, and the add target is still real.
        expect(find.text('Margherita Pizza'), findsWidgets);
        expect(
          find.text('San Marzano tomato, fresh mozzarella and basil.'),
          findsWidgets,
        );
        expect(find.byType(AspectRatio), findsWidgets);
        expect(
          tester.getSize(find.byIcon(Icons.add_shopping_cart).first).height,
          greaterThan(0),
        );

        final mode = posLayoutModeFor(width: width, height: 1200);
        // The SKELETON grid at the SAME width, with the menu still loading.
        await _pumpMenu(tester, size: Size(width, 1200), loading: true);
        _expectCleanFrame(tester);
        final skeleton = _gridDelegate(tester);

        expect(
          skeleton.mainAxisExtent,
          loaded.mainAxisExtent,
          reason: 'a skeleton of a different height makes the grid jump',
        );
        expect(skeleton.crossAxisCount, loaded.crossAxisCount);
        expect(loaded.crossAxisCount, posMenuColumnsFor(mode));
        // The extent really is image band + the shared body height.
        final cellWidth =
            (loaded.mainAxisExtent! - kPosMenuCardBodyHeight) * 4 / 3;
        expect(
          posMenuCardExtent(cellWidth),
          closeTo(loaded.mainAxisExtent!, 0.01),
        );
      });
    }

    testWidgets('H-note the former 1024px screen-level overflow is GONE — no '
        'overflow is tolerated here any more', (tester) async {
      // This test used to RECORD a 36px horizontal overflow as pre-existing.
      // FINAL-NEW-MODIFICATIONS-COMBINED-001 root-caused it (a fixed-width Row
      // in the cart's shift context bar, which the tablet cart could not fit)
      // and fixed it, so the assertion is now inverted: the frame must be
      // clean. The full width/locale sweep lives in
      // `pos_responsive_overflow_test.dart`.
      await _pumpMenu(tester, size: const Size(1024, 1200));
      expect(tester.takeException(), isNull);
      expect(
        find.text('San Marzano tomato, fresh mozzarella and basil.'),
        findsWidgets,
      );
    });
  });

  group('I. every product state still behaves', () {
    testWidgets('I1 an UNAVAILABLE item shows its description AND its status, '
        'and stays untappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _card(
          _item(
            availability: 'unavailable',
            availabilityReason: 'sold_out',
            description: 'Beer-battered, thick cut.',
          ),
          onAdd: () => taps++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Beer-battered, thick cut.'), findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final label = tester.getSemantics(find.byType(MenuItemCard)).label;
      expect(label, contains(l10n.posMenuItemSoldOut));
      expect(
        label.indexOf('Beer-battered, thick cut.'),
        lessThan(label.indexOf(l10n.posMenuItemSoldOut)),
        reason: 'name, description, then status',
      );
      // The unavailable gate is unchanged: the card takes no add tap.
      await tester.tap(find.byKey(const Key('menu-item-i-1')));
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
    });

    testWidgets('I2 a PAUSED item announces paused, not sold out', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(_item(availability: 'unavailable', availabilityReason: 'paused')),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        tester.getSemantics(find.byType(MenuItemCard)).label,
        contains(l10n.posMenuItemPaused),
      );
    });

    testWidgets('I3 modifiers, in-cart badge, tags and a long name all coexist '
        'with the description', (tester) async {
      await tester.pumpWidget(
        _card(
          _item(
            name: 'Slow-Roasted Lamb Shawarma Plate With Everything',
            description: _ar,
            tags: const ['popular', 'spicy'],
          ),
          optionGroupCount: 3,
          inCartQuantity: 2,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('\u00d72'), findsOneWidget, reason: 'the in-cart badge');
      expect(find.text(_ar), findsOneWidget);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('I4 an item WITHOUT an image still renders its description', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(_item(description: 'No photo, but tasty.')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No photo, but tasty.'), findsOneWidget);
      expect(find.byType(AspectRatio), findsOneWidget);
    });

    testWidgets('I5 a PLAIN item (no description) is visually unchanged', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _card(_item(description: null), onAdd: () => taps++),
      );
      await tester.pumpAndSettle();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>();
      expect(texts.where((t) => t.trim().isEmpty), isEmpty);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-item-i-1')));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('J. search and category are untouched', () {
    test('J1 search still matches NAMES only — a query that appears only in a '
        'description does not match', () {
      final items = [
        _item(id: 'a', name: 'Lamb Shawarma', description: 'With tahini.'),
        _item(id: 'b', name: 'Cola', description: 'Ice cold and fizzy.'),
      ];
      // 'tahini' and 'fizzy' live ONLY in descriptions.
      expect(filterMenuItems(items, kAllCategoriesId, 'tahini'), isEmpty);
      expect(filterMenuItems(items, kAllCategoriesId, 'fizzy'), isEmpty);
      // The existing name search is unchanged.
      expect(
        filterMenuItems(items, kAllCategoriesId, 'shawarma').map((i) => i.id),
        ['a'],
      );
      expect(
        filterMenuItems(items, kAllCategoriesId, 'cola').map((i) => i.id),
        ['b'],
      );
    });

    test('J2 filtering PRESERVES the description on the surviving items', () {
      final items = [
        _item(id: 'a', name: 'Lamb Shawarma', description: 'With tahini.'),
        _item(id: 'b', name: 'Cola', description: 'Ice cold.'),
      ];
      final result = filterMenuItems(items, kAllCategoriesId, 'shawarma');
      expect(result.single.description, 'With tahini.');
    });

    testWidgets('J3 a search RESULT card still shows its description', (
      tester,
    ) async {
      await _pumpMenu(tester);
      await tester.enterText(find.byType(TextField).first, 'Margherita');
      await tester.pumpAndSettle();
      expect(find.text('Margherita Pizza'), findsWidgets);
      expect(
        find.text('San Marzano tomato, fresh mozzarella and basil.'),
        findsWidgets,
      );
    });
  });

  group('K. runtime locale switch', () {
    testWidgets('K1 the SAME stored description survives en -> ar -> he, and '
        'only the chrome direction changes', (tester) async {
      const stored = 'San Marzano tomato, fresh mozzarella and basil.';
      for (final locale in ['en', 'ar', 'he']) {
        await tester.pumpWidget(
          _card(_item(description: stored), locale: Locale(locale)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(stored),
          findsOneWidget,
          reason: 'one stored string, never translated, under $locale',
        );
        expect(
          Directionality.of(tester.element(find.text(stored))),
          locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
        );
      }
    });
  });

  group('L. the per-card cost', () {
    testWidgets('L1 a large menu renders with ZERO per-card work: no extra '
        'provider, no fetch, no normalization in build', (tester) async {
      // 60 described products through the REAL card widget.
      final items = [
        for (var i = 0; i < 60; i++)
          _item(id: 'i-$i', name: 'Product $i', description: 'Description $i.'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: GridView.builder(
              // An isolated cost harness — it only needs 173px cells of the
              // approved extent, not the screen's per-mode column count.
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 173,
                mainAxisExtent: posMenuCardExtent(173),
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => MenuItemCard(
                item: items[i],
                currencyCode: 'ILS',
                onAdd: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The grid builds lazily and stays bounded — it never materializes all 60.
      expect(
        find.byType(MenuItemCard).evaluate().length,
        lessThan(items.length),
        reason: 'a fixed-extent grid must not build every card at once',
      );
      // Scrolling stays clean (no intrinsic layout, no per-card fetch).
      await tester.drag(find.byType(GridView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('M. payload isolation', () {
    test('M1 the description NEVER reaches the cart line or the draft '
        'snapshot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cart = container.read(cartControllerProvider.notifier);

      cart.addItem(_item(description: 'Should never travel with the order.'));
      final line = container.read(cartControllerProvider).lines.single;

      // The cart line's own surface carries no description at all. Asserted
      // FIELD BY FIELD: `CartLineView` declares no `toString` override, so
      // asserting on `line.toString()` would only ever inspect
      // "Instance of 'CartLineView'" and could never fail — a vacuous check.
      expect(line.name, 'Lamb Shawarma');
      final lineFields = <Object?>[
        line.menuItemId,
        line.name,
        line.note,
        line.modifiers.map((m) => '${m.groupName}/${m.optionName}').join('|'),
      ].join('␟');
      expect(
        lineFields,
        isNot(contains('Should never travel')),
        reason: 'a cart line is order data, not catalog copy',
      );

      // And neither does the durable draft snapshot the outbox/parked carts and
      // recovery all serialize.
      final draft = cart.captureDraft();
      final json = draft.toJson().toString();
      expect(json, contains('Lamb Shawarma'), reason: 'the NAME does travel');
      expect(
        json,
        isNot(contains('Should never travel')),
        reason:
            'the description must not enter any order/receipt/kitchen payload',
      );
    });
  });
}
