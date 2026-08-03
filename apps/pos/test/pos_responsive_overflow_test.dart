import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';
import 'package:restoflow_pos/src/widgets/shift_context_bar.dart';

/// FINAL-NEW-MODIFICATIONS-COMBINED-001 — the POS two-pane surface must lay out
/// with NO horizontal RenderFlex overflow at any real width.
///
/// The defect was reported at "exactly 1024px". Measured, it is not a 1024-only
/// defect at all: it spans the ENTIRE tablet band and is clean from 1100 up,
/// because [posCartWidthFor] hands the side cart 340px on tablet and 380px on
/// desktop. Nothing about 1024 is special — it was simply the only tablet-band
/// width anyone had pumped.
///
/// These tests therefore sweep the band and both sides of every breakpoint, and
/// they NEVER drain the overflow: an overflow here is a failure.

/// Every [RenderFlex] whose children are larger along its own main axis than
/// the box it was given, as `own|children|excess` plus its creator chain.
/// Reported instead of merely asserting `takeException()` so a failure NAMES
/// the widget. Both axes are checked: a horizontal fix that silently traded the
/// defect for a vertical one would otherwise read as success.
List<String> _overflowingFlexes(WidgetTester tester) {
  final found = <String>[];
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
      found.add(
        '${horizontal ? 'H' : 'V'} own=${own.toStringAsFixed(1)} '
        'children=${children.toStringAsFixed(1)} '
        'excess=${(children - own).toStringAsFixed(1)} :: $chain',
      );
    }
  }
  return found;
}

void _expectNoOverflow(WidgetTester tester, String at) {
  final flexes = _overflowingFlexes(tester);
  expect(
    flexes,
    isEmpty,
    reason: 'horizontal RenderFlex overflow at $at:\n${flexes.join('\n')}',
  );
  expect(
    tester.takeException(),
    isNull,
    reason: 'the frame at $at must raise no exception at all',
  );
}

Future<void> _pumpPos(
  WidgetTester tester, {
  required double width,
  double height = 1200,
  bool loading = false,
  Locale locale = const Locale('en'),
  bool demo = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod forbids changing the override COUNT on a live ProviderScope,
      // so each configuration gets its own scope element.
      key: ValueKey('pos-$width-$height-$loading-${locale.languageCode}-$demo'),
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: demo),
        ),
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

Future<void> _pumpCartAt(
  WidgetTester tester,
  double cartWidth, {
  Locale locale = const Locale('en'),
  bool demo = true,
  bool compact = true,
}) async {
  // A REALISTIC two-pane viewport height. The default 600px test window is
  // shorter than any real POS surface and hits a SEPARATE, PRE-EXISTING
  // vertical fit limit of the cart content — measured on the baseline as well
  // as here (e.g. 380px cart at 600px tall overflows vertically by 104px with
  // and without this phase's change). That defect is not this phase's scope, so
  // it is neither fixed nor suppressed here: these tests simply run at a height
  // where the horizontal contract under test can be read cleanly.
  tester.view.physicalSize = Size(cartWidth + 200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey('cart-$cartWidth-${locale.languageCode}-$demo-$compact'),
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: demo),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox.expand()),
              SizedBox(
                width: cartWidth,
                height: 1200,
                child: CartPanel(compact: compact),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Both sides of BOTH two-pane breakpoints (820 phone/tablet, 1100
  // tablet/desktop), the reported 1024, and the widths named in the phase.
  const sweep = <double>[820, 900, 940, 1023, 1024, 1025, 1099, 1100, 1366];

  group('A. no horizontal overflow anywhere in the two-pane band', () {
    for (final width in sweep) {
      testWidgets('A-$width the LOADED POS surface lays out cleanly', (
        tester,
      ) async {
        await _pumpPos(tester, width: width);

        // The surface really is the two-pane one under test, with live content
        // in BOTH panes — not an empty or collapsed frame that cannot overflow.
        expect(
          posLayoutModeFor(width: width, height: 1200),
          isNot(PosLayoutMode.phone),
        );
        expect(find.byType(CartPanel), findsOneWidget);
        expect(find.byType(ShiftContextBar), findsOneWidget);
        expect(find.byType(MenuItemCard), findsWidgets);
        expect(find.byKey(const Key('menu-search-field')), findsOneWidget);
        expect(find.text('Margherita Pizza'), findsWidgets);
        expect(
          find.text('San Marzano tomato, fresh mozzarella and basil.'),
          findsWidgets,
        );
        expect(find.byIcon(Icons.add_shopping_cart), findsWidgets);

        _expectNoOverflow(tester, 'loaded ${width}px');
      });

      testWidgets('A-$width the SKELETON POS surface lays out cleanly', (
        tester,
      ) async {
        await _pumpPos(tester, width: width, loading: true);
        expect(find.byType(CartPanel), findsOneWidget);
        _expectNoOverflow(tester, 'skeleton ${width}px');
      });
    }
  });

  group('B. the cart pane stays usable and reachable', () {
    testWidgets('B1 at 1024 the cart keeps its small-tablet width and the '
        'primary send control is present and hit-testable', (tester) async {
      await _pumpPos(tester, width: 1024);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // POS-VISUAL-REDESIGN-PHASE-1-007 split the old 820-1099 "tablet" band
      // into tablet (1100-1359) / smallTablet (900-1099) / narrowTablet
      // (820-899), so 1024 now resolves to smallTablet. Its cart is still 340 —
      // the width this test has always pinned — and the reachability contract
      // below is unchanged.
      final cart = tester.getSize(find.byType(CartPanel));
      expect(cart.width, posCartWidthFor(PosLayoutMode.smallTablet));
      expect(cart.width, 340, reason: 'small-tablet cart width is 340');

      // The menu pane keeps the remaining width — nothing scrolls sideways.
      expect(tester.getSize(find.byType(GridView).last).width, 1024 - 340);

      final send = find.widgetWithText(FilledButton, l10n.posSendOrder);
      expect(send, findsOneWidget);
      final sendBox = tester.getRect(send);
      expect(sendBox.width, greaterThan(0));
      expect(sendBox.height, greaterThanOrEqualTo(44));
      expect(sendBox.right, lessThanOrEqualTo(1024 + 0.5));
      expect(sendBox.left, greaterThanOrEqualTo(-0.5));
      _expectNoOverflow(tester, 'cart usability 1024px');
    });

    testWidgets('B2 the shift bar reports the same drawer figure it did '
        'before — the fix reflows, it does not truncate', (tester) async {
      await _pumpPos(tester, width: 1024);
      // The cash figure the cashier reads is still ONE Text with the full
      // string, so a text-equality finder still matches it.
      final item = find.byKey(const Key('cash-in-drawer'));
      expect(item, findsOneWidget);
      final label = find.descendant(of: item, matching: find.byType(Text));
      expect(label, findsOneWidget);
      final text = tester.widget<Text>(label);
      expect(text.data, isNotNull);
      expect(text.data, contains(':'));
      expect(
        text.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'the drawer figure must never be ellipsised away',
      );
      expect(tester.getSize(label).width, lessThanOrEqualTo(340));
    });
  });

  group('C. the real cause: every two-pane cart width fits its shift bar', () {
    // The overflow was a fixed-width Row inside the shift context bar, not the
    // menu card and not the grid. compactLandscape (304) is the NARROWEST real
    // side cart and was never covered by a screen test.
    for (final mode in PosLayoutMode.values) {
      if (mode == PosLayoutMode.phone) continue;
      testWidgets('C-${mode.name} cart ${posCartWidthFor(mode)}px lays out '
          'the shift bar cleanly', (tester) async {
        await _pumpCartAt(tester, posCartWidthFor(mode));
        expect(find.byType(ShiftContextBar), findsOneWidget);
        expect(find.byKey(const Key('cash-in-drawer')), findsOneWidget);
        _expectNoOverflow(tester, '${mode.name} cart');
      });
    }

    testWidgets('C-real a REAL-mode shift bar also fits the narrowest cart', (
      tester,
    ) async {
      await _pumpCartAt(
        tester,
        posCartWidthFor(PosLayoutMode.compactLandscape),
        demo: false,
      );
      expect(find.byType(ShiftContextBar), findsOneWidget);
      _expectNoOverflow(tester, 'real-mode compact cart');
    });
  });

  group('D. right-to-left is safe at the same widths', () {
    for (final code in <String>['ar', 'he']) {
      testWidgets('D-$code the POS surface lays out cleanly at 1024', (
        tester,
      ) async {
        await _pumpPos(tester, width: 1024, locale: Locale(code));
        expect(
          Directionality.of(tester.element(find.byType(CartPanel))),
          TextDirection.rtl,
        );
        expect(find.byType(ShiftContextBar), findsOneWidget);
        _expectNoOverflow(tester, '$code 1024px');
      });

      testWidgets('D-$code the narrowest side cart lays out cleanly', (
        tester,
      ) async {
        await _pumpCartAt(
          tester,
          posCartWidthFor(PosLayoutMode.compactLandscape),
          locale: Locale(code),
        );
        _expectNoOverflow(tester, '$code compact cart');
      });
    }
  });

  group('E. the fix is structural, not a 1024-only conditional', () {
    testWidgets('E1 the layout mode and cart width at 1023/1024/1025 are '
        'IDENTICAL — no width is special-cased', (tester) async {
      // The CONTRACT is that no single width is special-cased — 1024 must be
      // an ordinary member of whichever band contains it, exactly like its
      // neighbours. 007 renamed that band (tablet -> smallTablet) but the
      // contract is unchanged, so this asserts the three are IDENTICAL rather
      // than naming one band.
      for (final w in <double>[1023, 1024, 1025]) {
        expect(
          posLayoutModeFor(width: w, height: 1200),
          posLayoutModeFor(width: 1024, height: 1200),
          reason: '$w must resolve exactly like its neighbours',
        );
      }
      expect(
        posLayoutModeFor(width: 1024, height: 1200),
        PosLayoutMode.smallTablet,
      );
      // The approved 007 two-pane widths.
      expect(posCartWidthFor(PosLayoutMode.desktop), 400);
      expect(posCartWidthFor(PosLayoutMode.tablet), 360);
      expect(posCartWidthFor(PosLayoutMode.smallTablet), 340);
      expect(posCartWidthFor(PosLayoutMode.narrowTablet), 320);
      expect(posCartWidthFor(PosLayoutMode.compactLandscape), 320);
      expect(posCartWidthFor(PosLayoutMode.phone), 0);
    });

    testWidgets('E2 a cart far narrower than any real breakpoint still does '
        'not overflow', (tester) async {
      // Proves the shift bar reflows from its own constraints rather than from
      // a width the screen happens to hand it.
      await _pumpCartAt(tester, 240);
      _expectNoOverflow(tester, '240px cart');
    });
  });
}
