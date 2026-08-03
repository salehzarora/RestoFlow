import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/menu_filter.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/category_chips.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// POS-VISUAL-REDESIGN-PHASE-1-007 — Step 1: the menu-side redesign.
///
/// Two planes instead of one: the menu navigation (heading, live count, search
/// and the category rail) is lifted onto ONE elevated white deck, and the
/// product grid keeps the warm canvas. The grid stops guessing its column count
/// from a max-extent formula — which could never produce 5 columns at 1440 and
/// 4 at 1280 — and takes the approved count from the resolved layout mode.
///
/// Everything these tests assert is presentation or geometry. The menu data,
/// the filter providers, the add gesture, the availability gate and the
/// addition lock are unchanged and are pinned here precisely so the redesign
/// cannot quietly move them.

// ── fixtures ───────────────────────────────────────────────────────────────

DemoMenuItem _item({
  String id = 'i-1',
  String name = 'Lamb Shawarma',
  String? description = 'Slow-roasted lamb with tahini and sumac onion.',
  String categoryId = 'mains',
  String availability = 'available',
  String? availabilityReason,
  String? imageUrl,
  List<String> tags = const <String>[],
}) => DemoMenuItem(
  id: id,
  name: name,
  priceMinor: 5400,
  categoryId: categoryId,
  categoryName: 'Mains',
  description: description,
  availability: availability,
  availabilityReason: availabilityReason,
  imageUrl: imageUrl,
  tags: tags,
);

PosMenuData _menu({int items = 12}) => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'mains',
      name: 'Mains',
      icon: Icons.lunch_dining,
      color: Color(0xFFC2410C),
    ),
    DemoCategory(
      id: 'sides',
      name: 'Sides',
      icon: Icons.local_pizza,
      color: Color(0xFF1B7A52),
    ),
  ],
  items: [
    for (var i = 0; i < items; i++)
      _item(
        id: 'i-$i',
        name: 'Product $i',
        categoryId: i.isEven ? 'mains' : 'sides',
      ),
  ],
  modifierGroups: const [],
  currencyCode: 'ILS',
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  Locale locale = const Locale('en'),
  bool loading = false,
  PosMenuData? menu,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (loading)
          posMenuProvider.overrideWith((ref) => Completer<PosMenuData>().future)
        else
          posMenuProvider.overrideWith((ref) async => menu ?? _menu()),
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

/// The PRODUCT grid — the last GridView in the tree (the deck's category rail
/// is a ListView, so this stays unambiguous).
SliverGridDelegateWithFixedCrossAxisCount _productGridDelegate(
  WidgetTester tester,
) =>
    tester.widget<GridView>(find.byType(GridView).last).gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;

void main() {
  group('A. layout-mode resolution and the approved column counts', () {
    // Pure-function contract — no pumping, so a breakpoint regression is
    // reported as a breakpoint failure rather than a layout failure.
    final cases = <(String, double, double, PosLayoutMode, int, double)>[
      ('1440x900 desktop', 1440, 900, PosLayoutMode.desktop, 5, 400),
      ('1280x800 tablet', 1280, 800, PosLayoutMode.tablet, 4, 360),
      ('1024x768 smallTablet', 1024, 768, PosLayoutMode.smallTablet, 3, 340),
      (
        '1024x600 compactLandscape',
        1024,
        600,
        PosLayoutMode.compactLandscape,
        3,
        320,
      ),
      ('860x1200 narrowTablet', 860, 1200, PosLayoutMode.narrowTablet, 3, 320),
      (
        '760x600 compactLandscape',
        760,
        600,
        PosLayoutMode.compactLandscape,
        3,
        320,
      ),
      ('390x844 phone', 390, 844, PosLayoutMode.phone, 2, 0),
    ];

    for (final (label, w, h, mode, columns, cartWidth) in cases) {
      test('007-A1. $label', () {
        expect(posLayoutModeFor(width: w, height: h), mode);
        expect(posMenuColumnsFor(mode), columns);
        expect(posCartWidthFor(mode), cartWidth);
      });
    }

    test('007-A2. the desktop threshold is 1360, not 1100', () {
      expect(posLayoutModeFor(width: 1359, height: 900), PosLayoutMode.tablet);
      expect(posLayoutModeFor(width: 1360, height: 900), PosLayoutMode.desktop);
    });

    test('007-A3. a SHORT landscape viewport is compact whatever its width — '
        'that is what makes 1024x600 compact while 1024x768 is not', () {
      expect(
        posLayoutModeFor(width: 1024, height: 640),
        PosLayoutMode.compactLandscape,
      );
      expect(
        posLayoutModeFor(width: 1024, height: 641),
        PosLayoutMode.smallTablet,
      );
    });

    test('007-A4. a small landscape PHONE is still a phone — the compact rule '
        'never reaches below the existing 700 floor', () {
      expect(posLayoutModeFor(width: 650, height: 400), PosLayoutMode.phone);
      expect(posLayoutModeFor(width: 699, height: 400), PosLayoutMode.phone);
    });
  });

  group('B. the product grid takes its column count from the mode', () {
    const viewports = <(String, Size, int)>[
      ('desktop 1440x900', Size(1440, 900), 5),
      ('tablet 1280x800', Size(1280, 800), 4),
      ('smallTablet 1024x768', Size(1024, 768), 3),
      ('compactLandscape 1024x600', Size(1024, 600), 3),
      ('narrowTablet 860x1200', Size(860, 1200), 3),
      ('phone 390x844', Size(390, 844), 2),
    ];

    for (final (label, size, columns) in viewports) {
      testWidgets('007-B1. $label renders $columns product columns', (
        tester,
      ) async {
        await _pumpScreen(tester, size: size);
        final delegate = _productGridDelegate(tester);
        expect(delegate.crossAxisCount, columns);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('007-B2. the card extent stays the 4:3 band plus the FIXED '
        '140px body', (tester) async {
      await _pumpScreen(tester, size: const Size(1440, 900));
      final delegate = _productGridDelegate(tester);
      expect(kPosMenuCardBodyHeight, 140);
      // extent = cellWidth * 3/4 + 140, so the implied cell width must be the
      // grid's real cell width.
      final cellWidth =
          (delegate.mainAxisExtent! - kPosMenuCardBodyHeight) * 4 / 3;
      expect(delegate.mainAxisExtent, posMenuCardExtent(cellWidth));
    });
  });

  group('C. the coordinated menu deck', () {
    testWidgets('007-C1. the category rail sits in the DECK, above the grid — '
        'never inside the product grid', (tester) async {
      await _pumpScreen(tester);

      expect(find.byType(CategoryChips), findsOneWidget);
      // The chips must no longer be built inside the scrolling product grid.
      expect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.byType(CategoryChips),
        ),
        findsNothing,
      );
      // ...and they sit ABOVE the grid on screen.
      expect(
        tester.getRect(find.byType(CategoryChips)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(GridView).last).top),
      );
    });

    testWidgets('007-C2. heading, live count, search and the rail share ONE '
        'deck', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpScreen(tester);

      expect(find.byKey(const Key('menu-search-field')), findsOneWidget);
      expect(find.text(l10n.posMenuHeading), findsOneWidget);
      // 12 items in the fixture — the live count, not a hardcoded string.
      expect(find.text(l10n.posMenuItemCount(12)), findsOneWidget);

      final deck = find.byKey(const Key('pos-menu-deck'));
      expect(deck, findsOneWidget);
      for (final child in <Finder>[
        find.byKey(const Key('menu-search-field')),
        find.text(l10n.posMenuHeading),
        find.byType(CategoryChips),
      ]) {
        expect(find.descendant(of: deck, matching: child), findsOneWidget);
      }
    });

    testWidgets(
      '007-C3. the rail is ONE horizontally scrolling line that never '
      'wraps, at every width',
      (tester) async {
        for (final size in const [Size(1440, 900), Size(860, 1200)]) {
          await _pumpScreen(tester, size: size);
          final rail = tester.widget<ListView>(
            find.descendant(
              of: find.byType(CategoryChips),
              matching: find.byType(ListView),
            ),
          );
          expect(rail.scrollDirection, Axis.horizontal);
          // One line: every chip shares the same vertical band.
          final tops = <double>{
            for (final label in const ['Mains', 'Sides'])
              tester.getRect(find.text(label)).top.roundToDouble(),
          };
          expect(tops.length, 1, reason: 'no chip may wrap to a second line');
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('007-C4. selecting a category still drives the SAME provider '
        'and still filters the grid', (tester) async {
      await _pumpScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PosMenuScreen)),
      );
      expect(container.read(selectedCategoryProvider), kAllCategoriesId);
      expect(find.byType(MenuItemCard), findsNWidgets(12));

      await tester.tap(find.text('Sides'));
      await tester.pumpAndSettle();

      expect(container.read(selectedCategoryProvider), 'sides');
      // 6 of the 12 fixture items are in `sides`.
      expect(find.byType(MenuItemCard), findsNWidgets(6));
    });

    testWidgets('007-C5. search still drives searchQueryProvider and still '
        'filters', (tester) async {
      await _pumpScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PosMenuScreen)),
      );

      await tester.enterText(
        find.byKey(const Key('menu-search-field')),
        'Product 1',
      );
      await tester.pumpAndSettle();

      expect(container.read(searchQueryProvider), 'Product 1');
      // Product 1, 10, 11 — the filter itself is unchanged.
      expect(find.byType(MenuItemCard), findsNWidgets(3));
    });

    testWidgets('007-C6. the deck produces no overflow in ar / he / en at the '
        'narrowest two-pane width', (tester) async {
      for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
        await _pumpScreen(tester, size: const Size(820, 1200), locale: locale);
        expect(
          tester.takeException(),
          isNull,
          reason: 'deck overflowed in ${locale.languageCode}',
        );
      }
    });
  });

  group('D. the product card', () {
    testWidgets('007-D1. the options chip and the in-cart badge live ON the '
        'image band, not in the price row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 213,
                height: posMenuCardExtent(213),
                child: MenuItemCard(
                  item: _item(),
                  currencyCode: 'ILS',
                  optionGroupCount: 2,
                  inCartQuantity: 3,
                  onAdd: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final band = find.byType(AspectRatio);
      expect(band, findsOneWidget);
      expect(
        find.descendant(of: band, matching: find.byIcon(Icons.tune)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: band, matching: find.text('×3')),
        findsOneWidget,
      );
      // Still exactly one canonical add gesture, and it is NOT Icons.add.
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('007-D2. the price keeps its exact formatted string while the '
        'currency symbol is demoted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 213,
              height: posMenuCardExtent(213),
              child: MenuItemCard(
                item: _item(),
                currencyCode: 'ILS',
                onAdd: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The money string itself is untouched — only its rendering splits.
      final price = find.byKey(const Key('menu-item-price-i-1'));
      expect(price, findsOneWidget);
      final rendered = tester.widget<Text>(price).textSpan!.toPlainText();
      expect(rendered, '₪54.00');

      // The digits carry the size; the symbol is smaller and muted.
      final span = tester.widget<Text>(price).textSpan! as TextSpan;
      final parts = <TextSpan>[...span.children!.cast<TextSpan>()];
      final symbol = parts.firstWhere((s) => s.text == '₪');
      final digits = parts.firstWhere((s) => s.text == '54.00');
      expect(digits.style!.fontSize, greaterThan(symbol.style!.fontSize!));
      expect(digits.style!.fontWeight, FontWeight.w800);
      expect(digits.style!.color, kRestoflowInk);
    });

    testWidgets('007-D3. the card add button keeps a >=44px target and loses '
        'the green glow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 213,
              height: posMenuCardExtent(213),
              child: MenuItemCard(
                item: _item(),
                currencyCode: 'ILS',
                onAdd: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final add = find.byIcon(Icons.add_shopping_cart);
      final size = tester.getSize(
        find.ancestor(of: add, matching: find.byType(IconButton)).first,
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      // No card-level green glow anywhere in the card any more.
      final glows = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (d) =>
                (d.decoration as BoxDecoration).boxShadow?.any(
                  (s) => s.color == kPosGreenGlow.first.color,
                ) ??
                false,
          );
      expect(glows, isEmpty);
    });

    testWidgets('007-D4. long ar / he / en names and a 2-line description stay '
        'inside the card', (tester) async {
      for (final (locale, name) in const [
        (Locale('ar'), 'شاورما لحم غنم مشوية ببطء مع طحينة وبصل سماق وبقدونس'),
        (
          Locale('he'),
          'כתף טלה צלויה לאט עם טחינה גולמית ובצל סומק ופטרוזיליה',
        ),
        (Locale('en'), 'Slow-roasted lamb shoulder shawarma with sumac onion'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 148, // the narrowest approved cell
                height: posMenuCardExtent(148),
                child: MenuItemCard(
                  item: _item(name: name),
                  currencyCode: 'ILS',
                  optionGroupCount: 2,
                  onAdd: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflowed in ${locale.languageCode}',
        );

        final nameText = tester.widget<Text>(find.text(name));
        expect(nameText.maxLines, 1);
        final desc = tester.widget<Text>(
          find.text('Slow-roasted lamb with tahini and sumac onion.'),
        );
        expect(desc.maxLines, 2);

        // The description never sits on top of the price row.
        expect(
          tester.getRect(find.text(name)).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const Key('menu-item-price-i-1'))).top,
          ),
        );
      }
    });

    testWidgets('007-D5. an unavailable card keeps its scrim, its reason and '
        'its closed tap gate', (tester) async {
      var added = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 213,
              height: posMenuCardExtent(213),
              child: MenuItemCard(
                item: _item(
                  availability: 'unavailable',
                  availabilityReason: 'sold_out',
                ),
                currencyCode: 'ILS',
                onAdd: () => added++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('menu-item-unavailable-i-1')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
      await tester.tap(find.byKey(const Key('menu-item-i-1')));
      await tester.pumpAndSettle();
      expect(added, 0, reason: 'the unavailable tap gate is unchanged');
    });

    testWidgets('007-D6. a locked cart still disables the add gesture', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 213,
              height: posMenuCardExtent(213),
              child: MenuItemCard(
                item: _item(),
                currencyCode: 'ILS',
                onAdd: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byIcon(Icons.add_shopping_cart),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(button.onPressed, isNull);
      expect(
        tester.widget<InkWell>(find.byKey(const Key('menu-item-i-1'))).onTap,
        isNull,
      );
    });
  });

  group('E. skeleton parity', () {
    testWidgets('007-E1. the skeleton grid uses the SAME column count and the '
        'SAME cell extent as the loaded grid', (tester) async {
      for (final (size, columns) in const [
        (Size(1440, 900), 5),
        (Size(1280, 800), 4),
        (Size(1024, 600), 3),
      ]) {
        await _pumpScreen(tester, size: size, loading: true);
        final skeleton = _productGridDelegate(tester);
        expect(skeleton.crossAxisCount, columns);

        await _pumpScreen(tester, size: size);
        final loaded = _productGridDelegate(tester);

        expect(skeleton.crossAxisCount, loaded.crossAxisCount);
        expect(skeleton.mainAxisExtent, loaded.mainAxisExtent);
        expect(skeleton.crossAxisSpacing, loaded.crossAxisSpacing);
        expect(skeleton.mainAxisSpacing, loaded.mainAxisSpacing);
      }
    });
  });
}
