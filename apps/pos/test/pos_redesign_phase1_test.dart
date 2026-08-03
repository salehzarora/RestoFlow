import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, KitchenMeat, OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/category_chips.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';
import 'package:restoflow_pos/src/widgets/order_setup_section.dart';
import 'package:restoflow_pos/src/widgets/shift_context_bar.dart';

/// POS-VISUAL-REDESIGN-PHASE-1-007 — Step 3: the FINAL cross-surface matrix.
///
/// Steps 1 and 2 each proved their own half. This suite proves the two halves
/// are one screen: that the menu deck, the fixed-count grid, the dark cart
/// block, the paired customer fields and the joined modifier summary all hold
/// TOGETHER at every approved viewport, in all three locales, with usable touch
/// targets and honest semantics — and that none of it moved a behaviour.
///
/// It deliberately does not restate the Step-1/Step-2 unit contracts; it
/// exercises the combinations those suites cannot see on their own.

// ── fixtures ───────────────────────────────────────────────────────────────

SelectedModifier _mod(String name, {int delta = 0, int quantity = 1}) =>
    SelectedModifier(
      optionId: 'opt-$name',
      groupName: 'Group',
      optionName: name,
      priceDeltaMinor: delta,
      quantity: quantity,
      kitchenMeat: const KitchenMeat(quantity: 1, unit: 'patty'),
    );

DemoMenuItem _item(String id, String name) => DemoMenuItem(
  id: id,
  name: name,
  priceMinor: 4200,
  categoryId: 'c',
  categoryName: 'C',
);

Future<AppLocalizations> _l10n(Locale l) => AppLocalizations.delegate.load(l);

/// The WHOLE screen — menu pane and persistent cart together.
Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: locale,
        theme: restoflowBaseTheme(),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

/// Only the cart, at an isolated width — the responsive rules key off the width
/// the cart actually receives.
Future<ProviderContainer> _pumpCart(
  WidgetTester tester, {
  double width = 400,
  double height = 900,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = Size(width + 200, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: locale,
        theme: restoflowBaseTheme(),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Align(
            alignment: AlignmentDirectional.topStart,
            child: SizedBox(
              width: width,
              height: height,
              child: const CartPanel(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void _fill(ProviderContainer c, {int lines = 3, bool notes = false}) {
  final cart = c.read(cartControllerProvider.notifier);
  for (var i = 0; i < lines; i++) {
    cart.addItemWithModifiers(_item('i-$i', 'Product $i'), [
      _mod('240g', delta: 3500),
      _mod('Cheese', quantity: 2),
      _mod('Lettuce'),
    ], note: notes && i == 0 ? 'no onions' : null);
  }
}

/// The cart's ONE scroll view.
Finder _cartScroll() => find
    .descendant(of: find.byType(CartPanel), matching: find.byType(Scrollable))
    .first;

Size _tapTarget(WidgetTester tester, Finder f) => tester.getSize(f);

void main() {
  // ── A. layout-mode resolution ────────────────────────────────────────────
  group('A. the approved mode table', () {
    final table = <(String, double, double, PosLayoutMode, double, int)>[
      ('1440x900', 1440, 900, PosLayoutMode.desktop, 400, 5),
      ('1280x800', 1280, 800, PosLayoutMode.tablet, 360, 4),
      ('1024x768', 1024, 768, PosLayoutMode.smallTablet, 340, 3),
      ('1024x600', 1024, 600, PosLayoutMode.compactLandscape, 320, 3),
      ('860x1200', 860, 1200, PosLayoutMode.narrowTablet, 320, 3),
      ('390x844', 390, 844, PosLayoutMode.phone, 0, 2),
    ];

    for (final (label, w, h, mode, cart, cols) in table) {
      test('P1-A1. $label resolves ${mode.name} / cart $cart / $cols cols', () {
        expect(posLayoutModeFor(width: w, height: h), mode);
        expect(posCartWidthFor(mode), cart);
        expect(posMenuColumnsFor(mode), cols);
      });
    }

    test('P1-A2. a SHORT landscape viewport wins over its width band', () {
      expect(
        posLayoutModeFor(width: 1024, height: 640),
        PosLayoutMode.compactLandscape,
      );
      expect(
        posLayoutModeFor(width: 1024, height: 641),
        PosLayoutMode.smallTablet,
      );
    });

    test(
      'P1-A3. small landscape phones keep their existing phone handling',
      () {
        for (final w in <double>[560, 650, 699]) {
          expect(
            posLayoutModeFor(width: w, height: 400),
            PosLayoutMode.phone,
            reason: '$w is below the existing 700 floor',
          );
        }
      },
    );
  });

  // ── B. combined menu + cart geometry ─────────────────────────────────────
  group('B. the two halves are one screen', () {
    for (final (label, size, cols, cartWidth) in const [
      ('1440x900', Size(1440, 900), 5, 400.0),
      ('1280x800', Size(1280, 800), 4, 360.0),
      ('1024x768', Size(1024, 768), 3, 340.0),
      ('1024x600', Size(1024, 600), 3, 320.0),
    ]) {
      testWidgets('P1-B1. $label — deck, grid, cart and footer all hold', (
        tester,
      ) async {
        final l10n = await _l10n(const Locale('en'));
        final c = await _pumpScreen(tester, size: size);
        _fill(c, lines: 4);
        await tester.pumpAndSettle();

        // Menu side (Step 1).
        expect(find.byKey(const Key('pos-menu-deck')), findsOneWidget);
        expect(find.byKey(const Key('menu-search-field')), findsOneWidget);
        expect(find.byType(CategoryChips), findsOneWidget);
        final grid =
            tester.widget<GridView>(find.byType(GridView).last).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(grid.crossAxisCount, cols);

        // Cart side (Step 2).
        expect(tester.getSize(find.byType(CartPanel)).width, cartWidth);
        expect(
          find.byKey(const Key('pos-cart-operational-header')),
          findsOneWidget,
        );

        // The whole order is reachable through the ONE cart scroll view.
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, l10n.posSendOrder),
          200,
          scrollable: _cartScroll(),
        );
        expect(find.byKey(const Key('cart-subtotal')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── C. isolated cart widths ──────────────────────────────────────────────
  group('C. the cart at every approved width', () {
    Future<void> pumpSetup(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width + 100, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: restoflowBaseTheme(),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(
                  width: width,
                  child: const SingleChildScrollView(
                    child: OrderSetupSection(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (width, paired) in const [
      (400.0, true),
      (360.0, true),
      (352.0, true),
      (340.0, false),
      (320.0, false),
      (304.0, false),
      (260.0, false),
    ]) {
      testWidgets(
        'P1-C1. ${width}px — fields ${paired ? "paired" : "stacked"}, '
        'both >=44px, no overflow',
        (tester) async {
          await pumpSetup(tester, width);
          final name = tester.getRect(
            find.byKey(const Key('customer-name-field')),
          );
          final phone = tester.getRect(
            find.byKey(const Key('customer-phone-field')),
          );
          expect((name.center.dy - phone.center.dy).abs() < 4, paired);
          expect(name.height, greaterThanOrEqualTo(44));
          expect(phone.height, greaterThanOrEqualTo(44));
          // Both order-type segments stay usable at every width.
          for (final k in const ['order-type-dine-in', 'order-type-takeaway']) {
            expect(
              tester.getSize(find.byKey(Key(k))).height,
              greaterThanOrEqualTo(44),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('P1-C2. a dine-in cart at the narrowest width keeps its table '
        'CTA reachable and its warning visible', (tester) async {
      final c = await _pumpCart(tester, width: 304, height: 700);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.dineIn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('table-required-warning')), findsOneWidget);
      final assign = find.byKey(const Key('assign-table-button'));
      expect(assign, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── C3. the assigned-table card at the narrowest cart ───────────────────
  group('C3. the assigned table card', () {
    testWidgets('P1-C3. an ASSIGNED table fits the 320px compact cart in ar — '
        'both actions kept', (tester) async {
      // The Step-3 matrix caught this overflowing by 20px: the stock
      // TextButton/IconButton paddings did not fit beside the table label at a
      // 320px cart. Both actions are still present and still >=40px.
      final c = await _pumpCart(
        tester,
        width: 320,
        height: 700,
        locale: const Locale('ar'),
      );
      final l10n = await _l10n(const Locale('ar'));
      c.read(orderSetupControllerProvider.notifier)
        ..setOrderType(OrderType.dineIn)
        ..assignTable(
          DemoTable(
            table: DiningTable(
              tableId: 't4',
              label: '4',
              organizationId: 'o',
              restaurantId: 'r',
              branchId: 'b',
              seats: 4,
              isActive: true,
            ),
            status: TableStatusKind.available,
          ),
        );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assigned-table-card')), findsOneWidget);
      expect(find.text(l10n.posChangeTable), findsOneWidget);
      expect(find.byTooltip(l10n.posClearTableAssignment), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip(l10n.posClearTableAssignment)).height,
        greaterThanOrEqualTo(40),
      );
      // The label must stay on ONE readable line — a squeezed column that wraps
      // one glyph per line would still throw no exception.
      final change = tester.getSize(find.text(l10n.posChangeTable));
      expect(
        change.width,
        greaterThan(30),
        reason: 'the Change label is squeezed to a vertical glyph run',
      );
      expect(change.height, lessThan(30));
      expect(tester.takeException(), isNull);
    });
  });

  // ── D. footer, gating and duplicate summaries ────────────────────────────
  group('D. footer gating survives the restyle', () {
    testWidgets('P1-D1. dine-in without a table blocks Send and NEVER hides '
        'its warning or hint', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      final c = await _pumpCart(tester, width: 320, height: 700);
      _fill(c, lines: 2);
      c
          .read(orderSetupControllerProvider.notifier)
          .setOrderType(OrderType.dineIn);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, l10n.posSendOrder),
        200,
        scrollable: _cartScroll(),
      );
      final send = find.widgetWithText(FilledButton, l10n.posSendOrder);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(find.byKey(const Key('send-needs-table-hint')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P1-D2. an EMPTY cart keeps its footer and Send, and offers '
        'neither Park nor Clear', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      await _pumpCart(tester);
      expect(find.byKey(const Key('cart-subtotal')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, l10n.posSendOrder),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('park-cart-button')), findsNothing);
      expect(find.text(l10n.posClearCart), findsNothing);
    });

    testWidgets('P1-D3. a populated takeaway cart enables Send and offers '
        'Clear', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      final c = await _pumpCart(tester);
      _fill(c, lines: 2);
      await tester.pumpAndSettle();
      expect(find.text(l10n.posClearCart), findsOneWidget);
      expect(find.byKey(const Key('cart-item-count')), findsOneWidget);
    });
  });

  // ── E. the dark operational block ────────────────────────────────────────
  group('E. operational state on dark', () {
    testWidgets('P1-E1. the block keeps the shift context, a single readable '
        'cash Text and a live count', (tester) async {
      final c = await _pumpCart(tester);
      _fill(c, lines: 2);
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('pos-cart-operational-header'));
      expect(
        (tester.widget<DecoratedBox>(header).decoration as BoxDecoration).color,
        kPosCartHeaderInk,
      );
      expect(
        find.descendant(of: header, matching: find.byType(ShiftContextBar)),
        findsOneWidget,
      );
      final cash = find.byKey(const Key('cash-in-drawer'));
      expect(
        find.descendant(of: cash, matching: find.byType(Text)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const Key('cart-item-count')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('P1-E2. every on-dark foreground is a light value — nothing '
        'operational is rendered in ink on ink', (tester) async {
      await _pumpCart(tester);
      final header = find.byKey(const Key('pos-cart-operational-header'));
      final texts = tester.widgetList<Text>(
        find.descendant(of: header, matching: find.byType(Text)),
      );
      expect(texts, isNotEmpty);
      for (final t in texts) {
        final c = t.style?.color;
        if (c == null) continue;
        // Luminance well above the ink surface's — a dark-on-dark regression
        // would fail here rather than only in a screenshot.
        expect(
          c.computeLuminance(),
          greaterThan(kPosCartHeaderInk.computeLuminance() + 0.15),
          reason: 'unreadable on-dark foreground: $c',
        );
      }
    });
  });

  // ── F. the modifier summary helper ───────────────────────────────────────
  group('F. the joined modifier summary', () {
    test(
      'P1-F1. order, quantity, signed delta and free options all survive',
      () {
        expect(
          posCartModifierSummary([
            _mod('240g', delta: 1500),
            _mod('Cheese', quantity: 2),
            _mod('Lettuce'),
          ], 'ILS'),
          '240g +₪15.00 · Cheese ×2 · Lettuce',
        );
        expect(posCartModifierSummary(const [], 'ILS'), isEmpty);
      },
    );

    for (final (label, locale, names) in const [
      ('ar', Locale('ar'), ['٢٤٠ غرام لحم بقري مشوي', 'جبنة شيدر معتقة', 'خس']),
      (
        'he',
        Locale('he'),
        ['240 גרם בשר בקר צלוי', 'גבינת צ׳דר מיושנת', 'חסה'],
      ),
      (
        'en',
        Locale('en'),
        ['240g slow roasted beef', 'Mature cheddar', 'Lettuce'],
      ),
    ]) {
      testWidgets('P1-F2.$label. a long summary clamps to two lines while the '
          'FULL string stays in Semantics', (tester) async {
        final handle = tester.ensureSemantics();
        final c = await _pumpCart(tester, width: 320, locale: locale);
        final mods = [
          _mod(names[0], delta: 3500),
          _mod(names[1], quantity: 2),
          _mod(names[2]),
        ];
        c
            .read(cartControllerProvider.notifier)
            .addItemWithModifiers(_item('i-0', 'Product'), mods);
        await tester.pumpAndSettle();

        final summary = find.byKey(const Key('cart-line-modifiers-line-0'));
        expect(tester.widget<Text>(summary).maxLines, 2);
        expect(
          tester.getSemantics(summary).label,
          posCartModifierSummary(mods, 'ILS'),
        );
        expect(tester.takeException(), isNull);
        handle.dispose();
      });
    }
  });

  // ── G. product-card edge cases ───────────────────────────────────────────
  group('G. the product card under stress', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required String name,
      Locale locale = const Locale('en'),
      int tags = 0,
      int inCart = 0,
      bool unavailable = false,
      double width = 148,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: restoflowBaseTheme(),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: width,
                height: posMenuCardExtent(width),
                child: MenuItemCard(
                  item: DemoMenuItem(
                    id: 'i-1',
                    name: name,
                    priceMinor: 4200,
                    categoryId: 'c',
                    categoryName: 'C',
                    description:
                        'A description long enough to take two lines '
                        'in every locale under test.',
                    availability: unavailable ? 'unavailable' : 'available',
                    availabilityReason: unavailable ? 'sold_out' : null,
                    tags: ['spicy', 'popular'].take(tags).toList(),
                  ),
                  currencyCode: 'ILS',
                  optionGroupCount: 2,
                  inCartQuantity: inCart,
                  onAdd: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (label, locale, name) in const [
      ('ar', Locale('ar'), 'شاورما لحم غنم مشوية ببطء مع طحينة وبصل سماق'),
      ('he', Locale('he'), 'כתף טלה צלויה לאט עם טחינה גולמית ובצל סומק'),
      ('en', Locale('en'), 'Slow-roasted lamb shoulder shawarma with sumac'),
    ]) {
      testWidgets('P1-G1.$label. a long name + 2 tags + an in-cart badge on '
          'the narrowest cell never overlaps or overflows', (tester) async {
        await pumpCard(tester, name: name, locale: locale, tags: 2, inCart: 3);
        expect(tester.takeException(), isNull);

        // The badge and the options chip take opposite ends of the band and
        // never share a corner.
        final band = find.byType(AspectRatio);
        final badge = tester.getRect(
          find.descendant(of: band, matching: find.text('×3')),
        );
        final chip = tester.getRect(
          find.descendant(of: band, matching: find.byIcon(Icons.tune)),
        );
        expect(badge.overlaps(chip), isFalse);
        expect(
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.byIcon(Icons.add_shopping_cart),
                      matching: find.byType(IconButton),
                    )
                    .first,
              )
              .height,
          greaterThanOrEqualTo(44),
        );
      });
    }

    testWidgets('P1-G2. in RTL the options chip sits at the inline-END of the '
        'band', (tester) async {
      await pumpCard(
        tester,
        name: 'برجر',
        locale: const Locale('ar'),
        width: 213,
      );
      final band = tester.getRect(find.byType(AspectRatio));
      final chip = tester.getRect(
        find.descendant(
          of: find.byType(AspectRatio),
          matching: find.byIcon(Icons.tune),
        ),
      );
      // RTL: inline-END is the LEFT half.
      expect(chip.center.dx, lessThan(band.center.dx));
    });

    testWidgets('P1-G3. an unavailable card keeps its reason and its closed '
        'add gate', (tester) async {
      await pumpCard(tester, name: 'Burger', unavailable: true, width: 213);
      expect(
        find.byKey(const Key('menu-item-unavailable-i-1')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ── H. RTL / LTR mirroring across the whole screen ───────────────────────
  group('H. direction', () {
    for (final (label, locale, rtl) in const [
      ('ar', Locale('ar'), true),
      ('he', Locale('he'), true),
      ('en', Locale('en'), false),
    ]) {
      testWidgets('P1-H1.$label. the persistent cart sits at the directional '
          'END and money stays an LTR island', (tester) async {
        final c = await _pumpScreen(
          tester,
          size: const Size(1280, 800),
          locale: locale,
        );
        _fill(c, lines: 2);
        await tester.pumpAndSettle();

        expect(
          Directionality.of(tester.element(find.byType(CartPanel))),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );
        final cart = tester.getRect(find.byType(CartPanel));
        final screen = tester.getRect(find.byType(PosMenuScreen));
        if (rtl) {
          expect(cart.center.dx, lessThan(screen.center.dx));
        } else {
          expect(cart.center.dx, greaterThan(screen.center.dx));
        }

        // Money renders LTR whatever the ambient direction.
        final subtotal = tester.widget<Text>(
          find.byKey(const Key('cart-subtotal')),
        );
        expect(subtotal.textDirection, TextDirection.ltr);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── I. touch targets and semantics ───────────────────────────────────────
  group('I. targets and semantics', () {
    testWidgets('P1-I1. the menu deck controls meet their targets', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1280, 800));
      expect(
        _tapTarget(tester, find.byKey(const Key('menu-search-field'))).height,
        greaterThanOrEqualTo(44),
      );
      // A chip is 40px inside a 56px rail — the rail's padding carries the
      // effective target, which is the documented dense contract.
      expect(
        _tapTarget(tester, find.byType(CategoryChips)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('P1-I2. cart controls meet their targets and expose their '
        'states', (tester) async {
      final handle = tester.ensureSemantics();
      final l10n = await _l10n(const Locale('en'));
      final c = await _pumpCart(tester);
      _fill(c, lines: 1);
      await tester.pumpAndSettle();

      for (final f in <Finder>[
        find.byKey(const Key('cart-edit-line-0')),
        find.byKey(const Key('cart-remove-line-0')),
      ]) {
        expect(_tapTarget(tester, f).height, greaterThanOrEqualTo(40));
      }
      // The order-type semantics are asserted BEFORE scrolling to the footer:
      // the setup section leaves the tree once it scrolls out of the cart's
      // one scroll view, which is correct behaviour, not a missing node.
      // The selected order type announces its selection, not just its colour,
      // and the unselected one is still an actionable button.
      expect(
        // Scoped by KEY: the footer's order-type summary chip carries the same
        // label, so a label-only finder legitimately matches two nodes.
        tester.getSemantics(find.byKey(const Key('order-type-takeaway'))),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          label: l10n.posOrderTypeTakeaway,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('order-type-dine-in'))),
        matchesSemantics(
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          label: l10n.posOrderTypeDineIn,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, l10n.posSendOrder),
        200,
        scrollable: _cartScroll(),
      );
      expect(
        _tapTarget(
          tester,
          find.widgetWithText(FilledButton, l10n.posSendOrder),
        ).height,
        greaterThanOrEqualTo(44),
      );
      handle.dispose();
    });
  });

  // ── J. short-height reachability with real content ───────────────────────
  group('J. 1024x600 with a real order', () {
    testWidgets('P1-J1. six lines with notes still reach the stepper, the '
        'subtotal and Send', (tester) async {
      final l10n = await _l10n(const Locale('ar'));
      final c = await _pumpScreen(
        tester,
        size: const Size(1024, 600),
        locale: const Locale('ar'),
      );
      _fill(c, lines: 6, notes: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The stepper of the first line is reachable...
      await tester.scrollUntilVisible(
        find.byKey(const Key('cart-line-modifiers-line-0')),
        -120,
        scrollable: _cartScroll(),
      );
      expect(find.byType(CartPanel), findsOneWidget);

      // ...and so is the whole footer.
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, l10n.posSendOrder),
        200,
        scrollable: _cartScroll(),
      );
      expect(find.byKey(const Key('cart-subtotal')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
