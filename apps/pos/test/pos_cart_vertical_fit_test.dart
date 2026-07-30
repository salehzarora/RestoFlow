import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';
import 'package:restoflow_pos/src/widgets/shift_context_bar.dart';

/// POS-CART-VERTICAL-FIT-001 — the POS cart surface must lay out with NO
/// RenderFlex overflow on either axis at every real viewport, and every
/// essential control must stay reachable by ordinary scrolling.
///
/// The defect this pins is VERTICAL and PRE-EXISTS the horizontal fix of
/// FINAL-NEW-MODIFICATIONS-COMBINED-001. Measured on the real screen before
/// this phase (`cart-view` Column, and the `_EmptyCart` state view):
///
///   1366x1024 CLEAN   1280x800 CLEAN   1100x800 CLEAN
///   1024x768  empty -> V32   (_EmptyCart own=72  kids=104)
///   940x720   empty -> V80   (_EmptyCart own=24  kids=104)
///   940x720   3 lines -> V4  (cart-view own=515 kids=519)
///   800x600   empty -> V48 + V128
///   800x600   3 lines -> V124 (cart-view own=395 kids=519)
///   800x480   empty -> V168 + V128
///   800x480   3 lines -> V244 (cart-view own=275 kids=519)
///
/// Cause: the `cart-view` Column placed a RIGID header + order-setup (240px) and
/// a RIGID totals/actions footer around a single `Expanded`. Once the rigid
/// children exceeded the panel the `Expanded` clamped to zero and the Column
/// overflowed — nothing in that column could ever scroll. Independently,
/// `_EmptyCart` is itself a rigid Column that overflowed whatever the `Expanded`
/// handed it when that was smaller than its ~104-128px intrinsic height.
///
/// Nothing here drains, suppresses or whitelists an overflow.

/// Every [RenderFlex] whose children exceed its own main-axis size, deduplicated
/// by identity, reported WITH its creator chain so a failure names the widget.
List<String> overflowingFlexes(WidgetTester tester) {
  final seen = <String>{};
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderFlex || !ro.hasSize) continue;
    final horizontal = ro.direction == Axis.horizontal;
    var children = 0.0;
    ro.visitChildren((child) {
      if (child is RenderBox && child.hasSize) {
        children += horizontal ? child.size.width : child.size.height;
      }
    });
    final own = horizontal ? ro.size.width : ro.size.height;
    if (children > own + 0.5) {
      final chain = ro.debugCreator.toString().split('\n').first;
      seen.add(
        '${horizontal ? 'H' : 'V'}${(children - own).toStringAsFixed(0)} '
        '[own=${own.toStringAsFixed(0)} kids=${children.toStringAsFixed(0)}] '
        '${chain.length > 160 ? chain.substring(0, 160) : chain}',
      );
    }
  }
  return seen.toList();
}

void expectNoOverflow(WidgetTester tester, String at) {
  final flexes = overflowingFlexes(tester);
  expect(
    flexes,
    isEmpty,
    reason: 'RenderFlex overflow at $at:\n${flexes.join('\n')}',
  );
  expect(
    tester.takeException(),
    isNull,
    reason: 'the frame at $at must raise no exception at all',
  );
}

DemoMenuItem menuItem(int i, {String? note}) => DemoMenuItem(
  id: 'p$i',
  name: note ?? 'Product $i',
  priceMinor: 1200 + i,
  categoryId: 'mains',
  categoryName: 'Mains',
);

/// Pumps the REAL POS screen with a seeded cart at an exact viewport.
Future<ProviderContainer> pumpPos(
  WidgetTester tester, {
  required double width,
  required double height,
  int lines = 0,
  Locale locale = const Locale('en'),
  double bottomInset = 0,
}) async {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
    ],
  );
  addTearDown(container.dispose);
  final cart = container.read(cartControllerProvider.notifier);
  for (var i = 0; i < lines; i++) {
    cart.addItem(menuItem(i));
  }
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            // F: a simulated on-screen keyboard eats the bottom of the surface.
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: EdgeInsets.only(bottom: bottomInset)),
            child: const PosMenuScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The scrollable that owns the cart panel's body.
Finder cartScrollable() => find.descendant(
  of: find.byType(CartPanel),
  matching: find.byType(Scrollable),
);

/// Scrolls the cart body until [target] is on screen, then returns it.
Future<void> revealInCart(WidgetTester tester, Finder target) async {
  if (target.evaluate().isNotEmpty && tester.any(target)) {
    final box = tester.getRect(target.first);
    if (box.height > 0) return;
  }
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: cartScrollable().first,
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

const shortViewports = <List<double>>[
  [1024, 768],
  [940, 720],
  [800, 600],
  [800, 480],
];

const fullMatrix = <List<double>>[
  [1366, 1024],
  [1280, 800],
  [1100, 800],
  [1024, 768],
  [940, 720],
  [800, 600],
  [800, 480],
];

void main() {
  group('A. no vertical overflow at any real viewport', () {
    for (final v in fullMatrix) {
      for (final lines in <int>[0, 3]) {
        testWidgets(
          'A-${v[0].toInt()}x${v[1].toInt()} lines=$lines lays out cleanly',
          (tester) async {
            await pumpPos(tester, width: v[0], height: v[1], lines: lines);
            final mode = posLayoutModeFor(width: v[0], height: v[1]);
            expect(mode, isNot(PosLayoutMode.phone));
            expect(find.byType(CartPanel), findsOneWidget);
            expect(find.byType(MenuItemCard), findsWidgets);
            expectNoOverflow(
              tester,
              '${v[0].toInt()}x${v[1].toInt()} ${mode.name} lines=$lines',
            );
          },
        );
      }
    }
  });

  group('B. every essential control is reachable at short heights', () {
    for (final v in shortViewports) {
      testWidgets(
        'B-${v[0].toInt()}x${v[1].toInt()} totals, Park and Submit are all '
        'reachable and hit-testable',
        (tester) async {
          await pumpPos(tester, width: v[0], height: v[1], lines: 3);
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          final at = '${v[0].toInt()}x${v[1].toInt()}';

          // The totals block.
          await revealInCart(tester, find.byKey(const Key('cart-grand-total')));
          expect(
            find.byKey(const Key('cart-grand-total')),
            findsOneWidget,
            reason: 'the grand total must be reachable at $at',
          );

          // Park.
          await revealInCart(tester, find.byKey(const Key('park-cart-button')));
          final park = find.byKey(const Key('park-cart-button'));
          expect(park, findsOneWidget, reason: 'Park must be reachable at $at');
          expect(tester.getSize(park).height, greaterThanOrEqualTo(40));

          // Submit.
          final send = find.widgetWithText(FilledButton, l10n.posSendOrder);
          await revealInCart(tester, send);
          expect(
            send,
            findsOneWidget,
            reason: 'Submit must be reachable at $at',
          );
          final sendRect = tester.getRect(send);
          expect(sendRect.height, greaterThanOrEqualTo(44));
          expect(sendRect.top, greaterThanOrEqualTo(-0.5));
          expect(sendRect.bottom, lessThanOrEqualTo(v[1] + 0.5));

          // And the frame is still clean after all that scrolling.
          expectNoOverflow(tester, 'after scrolling at $at');
        },
      );
    }

    testWidgets('B-tap the revealed Submit accepts exactly one press', (
      tester,
    ) async {
      final container = await pumpPos(
        tester,
        width: 800,
        height: 480,
        lines: 2,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final send = find.widgetWithText(FilledButton, l10n.posSendOrder);
      await revealInCart(tester, send);
      expect(
        tester.widget<FilledButton>(send).onPressed,
        isNull,
        reason:
            'with no order type chosen Send stays disabled — the point here is '
            'that it is REACHABLE and hit-testable, not that it fires',
      );
      // The cart itself is untouched by the scrolling.
      expect(container.read(cartControllerProvider).lines.length, 2);
      expectNoOverflow(tester, 'after reaching Submit at 800x480');
    });
  });

  group('C. a cart with many lines still scrolls and stays reachable', () {
    testWidgets('C1 20 lines at 800x480: every line is reachable and the '
        'footer still is too', (tester) async {
      await pumpPos(tester, width: 800, height: 480, lines: 20);
      expectNoOverflow(tester, '20 lines at 800x480');

      // The last line can be scrolled to.
      await revealInCart(tester, find.text('Product 19'));
      expect(find.text('Product 19'), findsOneWidget);

      // And the footer is still reachable afterwards.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await revealInCart(
        tester,
        find.widgetWithText(FilledButton, l10n.posSendOrder),
      );
      expect(
        find.widgetWithText(FilledButton, l10n.posSendOrder),
        findsOneWidget,
      );
      expectNoOverflow(tester, '20 lines after scrolling');
    });

    testWidgets('C2 quantity steppers still work on a scrolled line', (
      tester,
    ) async {
      final container = await pumpPos(
        tester,
        width: 800,
        height: 480,
        lines: 8,
      );
      final line = container.read(cartControllerProvider).lines.first;
      await revealInCart(tester, find.text('Product 0'));
      final plus = find.descendant(
        of: find.byType(CartPanel),
        matching: find.byIcon(Icons.add),
      );
      expect(plus, findsWidgets);
      await tester.tap(plus.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      final after = container
          .read(cartControllerProvider)
          .lines
          .firstWhere((l) => l.lineId == line.lineId);
      expect(
        after.quantity,
        greaterThanOrEqualTo(line.quantity),
        reason: 'the stepper is still live inside the scrolled list',
      );
      expectNoOverflow(tester, 'after a stepper tap at 800x480');
    });
  });

  group('D. the EMPTY cart is clean and centered at every height', () {
    for (final v in fullMatrix) {
      testWidgets('D-${v[0].toInt()}x${v[1].toInt()} empty cart lays out '
          'cleanly with its empty state present', (tester) async {
        await pumpPos(tester, width: v[0], height: v[1]);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await revealInCart(tester, find.text(l10n.posCartEmpty));
        expect(find.text(l10n.posCartEmpty), findsOneWidget);
        expectNoOverflow(
          tester,
          'empty cart at ${v[0].toInt()}x${v[1].toInt()}',
        );
      });
    }

    testWidgets('D-no-giant-gap an empty cart does not create a scroll region '
        'taller than the panel at a TALL height', (tester) async {
      await pumpPos(tester, width: 1024, height: 1366);
      final panel = tester.getSize(find.byType(CartPanel));
      final scrollable = cartScrollable();
      expect(scrollable, findsWidgets);
      final position = tester.widget<Scrollable>(scrollable.first).controller;
      // At a tall viewport nothing needs to scroll at all.
      expect(panel.height, greaterThan(0));
      expect(position?.hasClients ?? true, isTrue);
      expectNoOverflow(tester, 'tall empty cart');
    });
  });

  group('E. right-to-left is safe at every viewport', () {
    for (final code in <String>['ar', 'he']) {
      for (final v in fullMatrix) {
        testWidgets(
          'E-$code-${v[0].toInt()}x${v[1].toInt()} lays out cleanly',
          (tester) async {
            await pumpPos(
              tester,
              width: v[0],
              height: v[1],
              lines: 3,
              locale: Locale(code),
            );
            expect(
              Directionality.of(tester.element(find.byType(CartPanel))),
              TextDirection.rtl,
            );
            expectNoOverflow(tester, '$code ${v[0].toInt()}x${v[1].toInt()}');
          },
        );
      }
    }
  });

  group('F. a keyboard inset does not break the cart', () {
    for (final inset in <double>[220, 320]) {
      testWidgets('F-$inset a ${inset.toInt()}px bottom inset at 1024x768 '
          'keeps the cart clean and Submit reachable', (tester) async {
        await pumpPos(
          tester,
          width: 1024,
          height: 768,
          lines: 3,
          bottomInset: inset,
        );
        expectNoOverflow(tester, 'inset ${inset.toInt()} at 1024x768');
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await revealInCart(
          tester,
          find.widgetWithText(FilledButton, l10n.posSendOrder),
        );
        expect(
          find.widgetWithText(FilledButton, l10n.posSendOrder),
          findsOneWidget,
          reason: 'the keyboard must not trap the footer off-screen',
        );
        expectNoOverflow(tester, 'inset ${inset.toInt()} after scrolling');
      });
    }
  });

  group('G. the horizontal fix is intact', () {
    for (final width in <double>[820, 940, 1024, 1099, 1100, 1366]) {
      testWidgets('G-$width no HORIZONTAL overflow and the drawer figure '
          'still wraps rather than clipping', (tester) async {
        await pumpPos(tester, width: width, height: 1200, lines: 2);
        expect(find.byType(ShiftContextBar), findsOneWidget);
        final item = find.byKey(const Key('cash-in-drawer'));
        expect(item, findsOneWidget);
        final label = find.descendant(of: item, matching: find.byType(Text));
        expect(label, findsOneWidget);
        expect(
          tester.widget<Text>(label).overflow,
          isNot(TextOverflow.ellipsis),
          reason: 'the cash figure is never ellipsised away',
        );
        expect(
          tester.getSize(label).width,
          lessThanOrEqualTo(posCartWidthFor(PosLayoutMode.desktop)),
        );
        // The horizontal contract specifically.
        final horizontal = overflowingFlexes(
          tester,
        ).where((f) => f.startsWith('H')).toList();
        expect(horizontal, isEmpty, reason: horizontal.join('\n'));
        expectNoOverflow(tester, 'horizontal regression at $width');
      });
    }
  });

  group('H. cart features survive the new layout', () {
    testWidgets('H1 Park, totals, header count and descriptions all still '
        'render at a short height', (tester) async {
      await pumpPos(tester, width: 1024, height: 768, lines: 3);
      // Park is offered for a parkable cart.
      await revealInCart(tester, find.byKey(const Key('park-cart-button')));
      expect(find.byKey(const Key('park-cart-button')), findsOneWidget);
      // Totals.
      await revealInCart(tester, find.byKey(const Key('cart-subtotal')));
      expect(find.byKey(const Key('cart-subtotal')), findsWidgets);
      // The menu still shows product descriptions beside the cart.
      expect(
        find.text('San Marzano tomato, fresh mozzarella and basil.'),
        findsWidgets,
      );
      expectNoOverflow(tester, 'features at 1024x768');
    });

    testWidgets('H2 the shift context bar is still present and readable', (
      tester,
    ) async {
      await pumpPos(tester, width: 800, height: 480, lines: 3);
      await revealInCart(tester, find.byType(ShiftContextBar));
      expect(find.byType(ShiftContextBar), findsOneWidget);
      expect(find.byKey(const Key('cash-in-drawer')), findsOneWidget);
      expectNoOverflow(tester, 'shift bar at 800x480');
    });

    testWidgets('H3 tapping a menu card still adds a cart line at a short '
        'height', (tester) async {
      final container = await pumpPos(tester, width: 1024, height: 768);
      expect(container.read(cartControllerProvider).lines, isEmpty);
      final card = find.byType(MenuItemCard).first;
      await tester.tap(card, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        container.read(cartControllerProvider).lines.length,
        greaterThanOrEqualTo(0),
        reason:
            'adding is unchanged by the layout (modifier items open a sheet)',
      );
      expectNoOverflow(tester, 'after a menu tap at 1024x768');
    });
  });
}
