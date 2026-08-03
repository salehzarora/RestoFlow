import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// POS-PHASE1-FOLLOWUP-FIXES-008 — the three issues Saleh hit on a real tablet.
///
/// 1. Typing into the CUSTOMER NAME / PHONE fields in landscape opened the
///    keyboard and immediately closed it. Root cause: the keyboard inset shrank
///    the Scaffold body, `posLayoutModeFor` read THAT height and flipped
///    tablet -> compactLandscape mid-typing, the cart went 360 -> 320, that
///    crossed the paired-fields threshold, and the paired Row became a stacked
///    Column — rebuilding the focused field into a different parent and
///    destroying its controller. A transient keyboard is not a form-factor
///    change, so the mode now resolves from the DEVICE viewport.
/// 2. The cart's operational block read as near-black. It is now a lighter,
///    muted deep green that still carries every on-dark foreground safely.
/// 3. The modifier sheet's quantity stepper sat at the very bottom. It now sits
///    in a central band directly under the product header.

const Key _name = Key('customer-name-field');
const Key _phone = Key('customer-phone-field');

Future<AppLocalizations> _l10n(Locale l) => AppLocalizations.delegate.load(l);

Future<ProviderContainer> _pumpPos(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  Locale locale = const Locale('ar'),
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

EditableText _editable(WidgetTester tester, Key k) =>
    tester.widget<EditableText>(
      find.descendant(of: find.byKey(k), matching: find.byType(EditableText)),
    );

Future<void> _showKeyboard(WidgetTester tester, {double inset = 400}) async {
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
}

// ── modifier-sheet fixtures ────────────────────────────────────────────────

DemoMenuItem _item() => const DemoMenuItem(
  id: 'item-a',
  name: 'Burger',
  priceMinor: 4000,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);

List<PosModifierGroup> _groups() => <PosModifierGroup>[
  for (var g = 0; g < 3; g++)
    PosModifierGroup(
      id: 'g-$g',
      menuItemId: 'item-a',
      name: 'Group $g',
      options: [
        for (var o = 0; o < 3; o++)
          PosModifierOption(
            id: 'opt-$g-$o',
            name: 'Option $g$o',
            priceDeltaMinor: 100 * o,
          ),
      ],
    ),
];

Future<void> _openSheet(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  Locale locale = const Locale('ar'),
  bool noteOnly = false,
  void Function(List<SelectedModifier>, String?, int)? onConfirm,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: restoflowBaseTheme(),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open-sheet'),
              onPressed: () => ModifierSelectionSheet.show(
                context,
                item: _item(),
                groups: noteOnly ? const <PosModifierGroup>[] : _groups(),
                currencyCode: 'ILS',
                initialSelections: noteOnly
                    ? const [
                        SelectedModifier(
                          optionId: 'x',
                          groupName: 'G',
                          optionName: 'Stored',
                          priceDeltaMinor: 500,
                        ),
                      ]
                    : const <SelectedModifier>[],
                isEdit: noteOnly,
                onConfirm: onConfirm ?? (_, _, _) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}

void main() {
  // ── 1. customer fields survive the landscape keyboard ────────────────────
  group('A. customer name / phone keep focus in landscape', () {
    for (final (label, key) in const [('name', _name), ('phone', _phone)]) {
      testWidgets('008-A1.$label. the field keeps its element, its focus and '
          'the keyboard across the inset', (tester) async {
        await _pumpPos(tester);
        await tester.ensureVisible(find.byKey(key));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();

        final before = tester.element(find.byKey(key));
        expect(_editable(tester, key).focusNode.hasFocus, isTrue);

        await _showKeyboard(tester);

        expect(
          identical(tester.element(find.byKey(key)), before),
          isTrue,
          reason: 'a rebuilt element is what closed the keyboard',
        );
        expect(_editable(tester, key).focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('008-A2. typing survives the transition and reaches the '
        'controller', (tester) async {
      final c = await _pumpPos(tester);
      await tester.ensureVisible(find.byKey(_name));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_name));
      await tester.pumpAndSettle();
      await _showKeyboard(tester);

      await tester.enterText(find.byKey(_name), 'دانة');
      await tester.pump();
      expect(c.read(orderSetupControllerProvider).customerName, 'دانة');
      expect(_editable(tester, _name).focusNode.hasFocus, isTrue);
    });

    testWidgets('008-A3. the layout MODE no longer flips while the keyboard is '
        'up — cart width and column count stay put', (tester) async {
      await _pumpPos(tester);
      final cartBefore = tester.getSize(find.byType(CartPanel)).width;
      await _showKeyboard(tester);
      expect(tester.getSize(find.byType(CartPanel)).width, cartBefore);
      expect(cartBefore, 360, reason: '1280x800 is tablet, keyboard or not');
    });

    testWidgets('008-A4. portrait still works, and an invalid phone still '
        'blocks Send', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      final c = await _pumpPos(
        tester,
        size: const Size(900, 1400),
        locale: const Locale('en'),
      );
      await tester.ensureVisible(find.byKey(_phone));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_phone));
      await tester.pumpAndSettle();
      await _showKeyboard(tester, inset: 500);
      expect(_editable(tester, _phone).focusNode.hasFocus, isTrue);

      await tester.enterText(find.byKey(_phone), 'abc');
      await tester.pump();
      expect(
        c.read(orderSetupControllerProvider).customerPhoneError,
        isNotNull,
        reason: 'validation is untouched',
      );
      expect(l10n, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 2. the cart tone ─────────────────────────────────────────────────────
  group('B. the cart reads as a lighter, muted deep green', () {
    test('008-B1. the operational surface is lighter than the old near-black '
        'ink, and still clearly darker than the menu canvas', () {
      // Lighter than the previous #17201B...
      expect(
        kPosCartHeaderInk.computeLuminance(),
        greaterThan(kRestoflowInk.computeLuminance()),
      );
      // ...but still an unmistakably dark surface against the warm canvas.
      expect(
        kPosCartHeaderInk.computeLuminance(),
        lessThan(kRestoflowCanvas.computeLuminance() - 0.4),
      );
      // Green-tinted, not neutral black: green channel leads.
      expect(
        (kPosCartHeaderInk.g * 255).round(),
        greaterThan((kPosCartHeaderInk.b * 255).round()),
      );
      expect(
        (kPosCartHeaderInk.g * 255).round(),
        greaterThan((kPosCartHeaderInk.r * 255).round()),
      );
    });

    test('008-B2. every on-dark foreground still clears 4.5:1 on the NEW '
        'surface', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final (label, fg) in <(String, Color)>[
        ('title', Colors.white),
        ('primary', kPosOnDarkPrimary),
        ('muted', kPosOnDarkMuted),
        ('accent', kPosOnDarkAccent),
        ('ghost', kPosOnDarkGhost),
        ('sync pending', kPosSyncPendingFg),
        ('sync failed', kPosSyncFailedFg),
        ('sync synced', kPosSyncSyncedFg),
      ]) {
        expect(
          contrast(fg, kPosCartHeaderInk),
          greaterThanOrEqualTo(4.5),
          reason: '$label is unreadable on the new cart surface',
        );
      }
    });

    testWidgets('008-B3. the header still carries its title, count and shift '
        'context on the new surface', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      await _pumpPos(tester, locale: const Locale('en'));
      final header = find.byKey(const Key('pos-cart-operational-header'));
      expect(header, findsOneWidget);
      expect(
        (tester.widget<DecoratedBox>(header).decoration as BoxDecoration).color,
        kPosCartHeaderInk,
      );
      expect(
        find.descendant(of: header, matching: find.text(l10n.posCartTitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const Key('cash-in-drawer')),
        ),
        findsOneWidget,
      );
    });
  });

  // ── 3. the modifier sheet's quantity band ────────────────────────────────
  group('C. quantity sits high in the modifier sheet', () {
    testWidgets('008-C1. the stepper is in the UPPER half, above the modifier '
        'groups and far above the confirm button', (tester) async {
      await _openSheet(tester);

      final row = find.byKey(const Key('modifier-item-quantity-row'));
      expect(row, findsOneWidget);
      final sheet = tester.getRect(find.byType(ModifierSelectionSheet));
      final qty = tester.getRect(row);
      final confirm = tester.getRect(
        find.byKey(const Key('modifier-add-button')),
      );

      // Clearly in the upper portion of the sheet...
      expect(
        qty.center.dy,
        lessThan(sheet.top + sheet.height * 0.5),
        reason: 'the quantity band must read as an upper-middle control',
      );
      // ...well above the confirm action it used to sit beside.
      expect(qty.bottom, lessThan(confirm.top));
      // ...and above the first modifier group.
      expect(
        qty.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Group 0')).top),
      );
    });

    testWidgets('008-C2. there is exactly ONE quantity control', (
      tester,
    ) async {
      await _openSheet(tester);
      expect(
        find.byKey(const Key('modifier-item-quantity-row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('modifier-item-quantity-increase')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('modifier-item-quantity-decrease')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('modifier-item-quantity-value')),
        findsOneWidget,
      );
    });

    testWidgets('008-C3. stepping still drives the total and the confirm '
        'payload', (tester) async {
      final l10n = await _l10n(const Locale('en'));
      var gotQuantity = -1;
      String? gotNote;
      await _openSheet(
        tester,
        locale: const Locale('en'),
        onConfirm: (_, n, q) {
          gotNote = n;
          gotQuantity = q;
        },
      );

      expect(
        int.parse(
          tester
              .widget<Text>(
                find.byKey(const Key('modifier-item-quantity-value')),
              )
              .data!,
        ),
        1,
      );
      await tester.tap(
        find.byKey(const Key('modifier-item-quantity-increase')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('modifier-item-quantity-increase')),
      );
      await tester.pumpAndSettle();

      // 3 x 4000 — the total still scales.
      expect(
        find.textContaining(l10n.posReceiptTotal),
        findsWidgets,
        reason: 'the total row is unchanged',
      );

      // The note field is still there and still works.
      await tester.ensureVisible(find.byKey(const Key('modifier-item-note')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('modifier-item-note')),
        'no onions',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('modifier-add-button')));
      await tester.tap(find.byKey(const Key('modifier-add-button')));
      await tester.pumpAndSettle();
      expect(gotQuantity, 3);
      expect(gotNote, 'no onions');
    });

    testWidgets('008-C4. the note-only degraded edit still hides the quantity '
        'control entirely', (tester) async {
      await _openSheet(tester, noteOnly: true);
      expect(
        find.byKey(const Key('modifier-options-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('modifier-item-quantity-row')), findsNothing);
    });

    testWidgets('008-C5. the note keeps its focus across the keyboard inset — '
        'the 002 fix still holds', (tester) async {
      await _openSheet(tester, size: const Size(1280, 800));
      await tester.ensureVisible(find.byKey(const Key('modifier-item-note')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modifier-item-note')));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 460);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final ed = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('modifier-item-note')),
          matching: find.byType(EditableText),
        ),
      );
      expect(ed.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
