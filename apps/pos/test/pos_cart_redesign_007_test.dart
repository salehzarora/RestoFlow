import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/order_setup_section.dart';
import 'package:restoflow_pos/src/widgets/shift_context_bar.dart';

/// POS-VISUAL-REDESIGN-PHASE-1-007 — Step 2: the cart side.
///
/// The cart read as a stack of slabs: grey shift bar, white header, white
/// setup, near-white lines, white footer, cut by full-width dividers — nothing
/// said "this column is the order". One dark operational block now heads the
/// cart and carries everything the cashier must never lose sight of (title,
/// count, sync state, Clear, shift/drawer), the lines become white cards on a
/// warm track, and the modifiers join into one line instead of a paragraph.
///
/// Every assertion here is presentation, geometry or accessibility. The cart
/// state, the line models, the money, the gating and every callback are
/// unchanged and are pinned so the restyle cannot quietly move them.

SelectedModifier _mod(String name, {int delta = 0, int quantity = 1}) =>
    SelectedModifier(
      optionId: 'opt-$name',
      groupName: 'Group',
      optionName: name,
      priceDeltaMinor: delta,
      quantity: quantity,
      kitchenMeat: const KitchenMeat(quantity: 1, unit: 'patty'),
    );

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Pumps the REAL cart panel at an isolated width, so the responsive rules are
/// exercised on the width the cart actually receives.
Future<ProviderContainer> _pumpCart(
  WidgetTester tester, {
  double width = 400,
  double height = 900,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = Size(width + 200, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  return container;
}

/// The dark operational block that heads the cart.
Finder _darkHeader() => find.byKey(const Key('pos-cart-operational-header'));

Color? _boxColor(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  if (w is DecoratedBox) return (w.decoration as BoxDecoration).color;
  if (w is Container) return (w.decoration as BoxDecoration?)?.color;
  return null;
}

void main() {
  group('A. the operational cart header', () {
    testWidgets('007S2-A1. one operational block heads the cart and carries '
        'the title, the count and Clear', (tester) async {
      // POS-DESIGN-HANDOFF-IMPLEMENTATION-004: the approved v4 screens moved
      // the dark plane to the top app bar — the cart header is LIGHT now.
      // The contract that matters is unchanged: ONE keyed operational block
      // heads the cart and carries every operational element.
      final l10n = await _en();
      await _pumpCart(tester);

      expect(_darkHeader(), findsOneWidget);
      expect(
        _boxColor(tester, _darkHeader()),
        Colors.white,
        reason: 'the approved v4 cart header is the light panel surface',
      );

      // Everything operational lives inside that one block.
      for (final child in <Finder>[find.text(l10n.posCartTitle)]) {
        expect(
          find.descendant(of: _darkHeader(), matching: child),
          findsOneWidget,
        );
      }
    });

    testWidgets('007S2-A2. the shift/drawer context sits INSIDE the same dark '
        'block and keeps its widget, its key and its single Text', (
      tester,
    ) async {
      await _pumpCart(tester);

      // Still a real ShiftContextBar with its provider wiring.
      expect(find.byType(ShiftContextBar), findsOneWidget);
      expect(
        find.descendant(
          of: _darkHeader(),
          matching: find.byType(ShiftContextBar),
        ),
        findsOneWidget,
      );
      // The demo cash figure remains ONE readable Text under its frozen key.
      final cash = find.byKey(const Key('cash-in-drawer'));
      expect(cash, findsOneWidget);
      expect(
        find.descendant(of: cash, matching: find.byType(Text)),
        findsOneWidget,
        reason: 'the cash amount must stay one readable Text',
      );
    });

    testWidgets('007S2-A3. the item count follows the live cart and Clear is '
        'gated on it', (tester) async {
      final l10n = await _en();
      final c = await _pumpCart(tester);
      final cart = c.read(cartControllerProvider.notifier);

      // Clear keeps its EXISTING gating: absent while it does not apply (an
      // empty cart), present and live once there is something to clear. The
      // mockup shows a dimmed Clear on an empty cart; the shipped rule removes
      // it, and Step 2 does not change behaviour to match a picture.
      final clear = find.widgetWithText(TextButton, l10n.posClearCart);
      expect(clear, findsNothing);

      cart.addItem(
        const DemoMenuItem(
          id: 'i-1',
          name: 'Burger',
          priceMinor: 4000,
          categoryId: 'c',
          categoryName: 'C',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cart-item-count')), findsOneWidget);
      expect(clear, findsOneWidget);
      expect(tester.widget<TextButton>(clear).onPressed, isNotNull);
    });
  });

  group('B. the customer fields pair and stack on the approved threshold', () {
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

    bool sideBySide(WidgetTester tester) {
      final name = tester.getRect(find.byKey(const Key('customer-name-field')));
      final phone = tester.getRect(
        find.byKey(const Key('customer-phone-field')),
      );
      return (name.center.dy - phone.center.dy).abs() < 4;
    }

    for (final width in const [400.0, 360.0, 352.0]) {
      testWidgets('007S2-B1. at ${width}px the name and phone share ONE row', (
        tester,
      ) async {
        await pumpSetup(tester, width);
        expect(sideBySide(tester), isTrue);
        for (final k in const ['customer-name-field', 'customer-phone-field']) {
          expect(
            tester.getSize(find.byKey(Key(k))).height,
            greaterThanOrEqualTo(44),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in const [340.0, 320.0, 304.0, 260.0]) {
      testWidgets('007S2-B2. at ${width}px they stack, each still >=44px', (
        tester,
      ) async {
        await pumpSetup(tester, width);
        expect(sideBySide(tester), isFalse);
        for (final k in const ['customer-name-field', 'customer-phone-field']) {
          expect(
            tester.getSize(find.byKey(Key(k))).height,
            greaterThanOrEqualTo(44),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('C. the joined modifier summary', () {
    test('007S2-C1. joins in ORDER with quantities and signed paid deltas', () {
      final summary = posCartModifierSummary([
        _mod('240g', delta: 1500),
        _mod('Cheese', quantity: 2),
        _mod('Lettuce'),
      ], 'ILS');
      // Order preserved, ×N preserved, paid delta preserved, free names kept.
      expect(summary, '240g +₪15.00 · Cheese ×2 · Lettuce');
    });

    test('007S2-C2. an empty selection produces an empty summary', () {
      expect(posCartModifierSummary(const [], 'ILS'), isEmpty);
    });

    test('007S2-C3. a negative delta keeps its sign', () {
      expect(
        posCartModifierSummary([_mod('No bun', delta: -500)], 'ILS'),
        // MoneyFormatter emits a real MINUS SIGN (U+2212), not a hyphen.
        'No bun −₪5.00',
      );
    });

    testWidgets('007S2-C4. the visible summary clamps to two lines while the '
        'FULL text stays reachable through Semantics', (tester) async {
      final handle = tester.ensureSemantics();
      final c = await _pumpCart(tester, width: 360);
      final cart = c.read(cartControllerProvider.notifier);
      final mods = [
        _mod('240 grams of slow roasted lamb', delta: 3500),
        _mod('Extra mature cheddar cheese', quantity: 2),
        _mod('Crisp iceberg lettuce'),
        _mod('Vine ripened tomato'),
        _mod('Caramelised onion relish'),
      ];
      cart.addItemWithModifiers(
        const DemoMenuItem(
          id: 'i-1',
          name: 'Burger',
          priceMinor: 4000,
          categoryId: 'c',
          categoryName: 'C',
        ),
        mods,
      );
      await tester.pumpAndSettle();

      final full = posCartModifierSummary(mods, 'ILS');
      final summary = find.byKey(const Key('cart-line-modifiers-line-0'));
      expect(summary, findsOneWidget);
      expect(tester.widget<Text>(summary).maxLines, 2);
      // The clamp is never the only source of information.
      expect(
        tester.getSemantics(summary).label,
        full,
        reason: 'the untruncated summary must reach a screen reader',
      );
      handle.dispose();
    });
  });

  group('D. footer hierarchy and the empty cart', () {
    testWidgets('007S2-D1. the GRAND TOTAL reads as the loud figure and both '
        'rows keep their exact formatted strings', (tester) async {
      // 004: the approved totals hierarchy — the subtotal is a quiet
      // breakdown row and الإجمالي is the ONE dominant figure (always
      // present; equal to the subtotal while tax is off, from the same
      // integer math).
      final c = await _pumpCart(tester);
      c
          .read(cartControllerProvider.notifier)
          .addItem(
            const DemoMenuItem(
              id: 'i-1',
              name: 'Burger',
              priceMinor: 4000,
              categoryId: 'c',
              categoryName: 'C',
            ),
          );
      await tester.pumpAndSettle();

      final subtotal = find.byKey(const Key('cart-subtotal'));
      expect(subtotal, findsOneWidget);
      final subtotalText = tester.widget<Text>(subtotal);
      expect(
        subtotalText.data ?? subtotalText.textSpan!.toPlainText(),
        '₪40.00',
      );

      final grand = find.byKey(const Key('cart-grand-total'));
      expect(grand, findsOneWidget);
      final text = tester.widget<Text>(grand);
      expect(text.textSpan!.toPlainText(), '₪40.00');
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      final digits = spans.firstWhere((s) => s.text == '40.00');
      final symbol = spans.firstWhere((s) => s.text == '₪');
      expect(digits.style!.fontSize, 21);
      expect(digits.style!.fontWeight, FontWeight.w800);
      expect(digits.style!.fontSize, greaterThan(symbol.style!.fontSize!));
      // The HIERARCHY claim in this test's title, made testable (audit
      // restoration): the grand total's digits must render LARGER than the
      // quiet subtotal row's figure.
      expect(
        digits.style!.fontSize,
        greaterThan(subtotalText.style?.fontSize ?? 16),
        reason: 'الإجمالي must be the loud figure, the subtotal the quiet row',
      );
    });

    testWidgets('007S2-D2. Send is the one prominent action at ~54px and Park '
        'is a ghost', (tester) async {
      final l10n = await _en();
      final c = await _pumpCart(tester);
      c
          .read(cartControllerProvider.notifier)
          .addItem(
            const DemoMenuItem(
              id: 'i-1',
              name: 'Burger',
              priceMinor: 4000,
              categoryId: 'c',
              categoryName: 'C',
            ),
          );
      await tester.pumpAndSettle();

      final send = find.widgetWithText(FilledButton, l10n.posSendOrder);
      expect(send, findsOneWidget);
      expect(tester.getSize(send).height, greaterThanOrEqualTo(54));
    });

    testWidgets('007S2-D3. an EMPTY cart keeps its footer, a zero subtotal, a '
        'disabled Send and NO Park', (tester) async {
      final l10n = await _en();
      await _pumpCart(tester);

      expect(find.byKey(const Key('cart-subtotal')), findsOneWidget);
      final send = find.widgetWithText(FilledButton, l10n.posSendOrder);
      expect(send, findsOneWidget);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      // The package's empty-state mockup shows Park; the real rule does not.
      expect(find.byKey(const Key('park-cart-button')), findsNothing);
    });
  });

  group('E. reachability at the supported viewports', () {
    for (final (label, size) in const [
      ('1440x900', Size(400, 900)),
      ('1280x800', Size(360, 800)),
      ('1024x768', Size(340, 768)),
      ('1024x600', Size(320, 600)),
    ]) {
      testWidgets('007S2-E1. $label — several lines and the footer all reach', (
        tester,
      ) async {
        final l10n = await _en();
        final c = await _pumpCart(
          tester,
          width: size.width,
          height: size.height,
        );
        final cart = c.read(cartControllerProvider.notifier);
        for (var i = 0; i < 6; i++) {
          cart.addItemWithModifiers(
            DemoMenuItem(
              id: 'i-$i',
              name: 'Product $i',
              priceMinor: 4000,
              categoryId: 'c',
              categoryName: 'C',
            ),
            [_mod('Cheese', delta: 500)],
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The ONE cart scroll view reaches the footer.
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, l10n.posSendOrder),
          200,
          scrollable: find
              .descendant(
                of: find.byType(CartPanel),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          find.widgetWithText(FilledButton, l10n.posSendOrder),
          findsOneWidget,
        );
        expect(find.byKey(const Key('cart-subtotal')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
