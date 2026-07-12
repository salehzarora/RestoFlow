import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// POS customization V2 — the redesigned item-customization overlay, presented
/// as a MODAL BOTTOM SHEET at every width (the follow-up refinement: the wide
/// layout is a large sheet attached to the bottom edge, NOT a centered dialog).
/// Required single-choice groups render as a responsive card row; optional
/// checkbox groups as a two-column tile grid; a sticky footer never scrolls
/// away. Selection rules, pricing, notes, keys, and add/edit flows are the
/// existing ones — these tests pin the LAYOUT + PRESENTATION contract on top of
/// the frozen behavior corpus in modifier_flow_test.dart / cart_edit_test.dart.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1400, 1800),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the add affordance on the Cheeseburger card (has modifier groups:
/// Toppings = optional multi, Doneness = required single, Extras = steppers).
Future<void> _openBurgerSheet(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(Card, 'Cheeseburger').first,
      matching: find.byIcon(Icons.add_shopping_cart),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);
}

Rect _optionRect(WidgetTester tester, String optionId) =>
    tester.getRect(find.byKey(ValueKey('modifier-option-$optionId')));

// ── Fixtures for the semantics / long-label / widget-reuse cases ───────────
// Real model shapes (PosModifierGroup/PosModifierOption/DemoMenuItem); nothing
// here bypasses the widget's own pricing or selection rules.

DemoMenuItem _item({
  String id = 'item-a',
  String name = 'Burger',
  int priceMinor = 4000,
}) => DemoMenuItem(
  id: id,
  name: name,
  priceMinor: priceMinor,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);

PosModifierGroup _singleGroup({
  String id = 'g-size',
  String menuItemId = 'item-a',
  String name = 'Size',
  required List<PosModifierOption> options,
}) => PosModifierGroup(
  id: id,
  menuItemId: menuItemId,
  name: name,
  singleSelect: true,
  minSelect: 1,
  maxSelect: 1,
  isRequired: true,
  options: options,
);

PosModifierGroup _multiGroup({
  String id = 'g-extra',
  String menuItemId = 'item-a',
  String name = 'Extras',
  required List<PosModifierOption> options,
}) => PosModifierGroup(
  id: id,
  menuItemId: menuItemId,
  name: name,
  options: options,
);

/// Pumps the customization widget DIRECTLY inside a bounded host of [size] —
/// used where a bespoke item/modifier fixture is needed (long labels, widget
/// reuse). The widget has ONE layout (the sheet layout) at every width, so a
/// direct pump exercises exactly what the modal bottom sheet renders, minus
/// the Material sheet chrome (drag handle, scrim, rounded corners) that
/// [ModifierSelectionSheet.show] adds around it.
Future<void> _pumpDirect(
  WidgetTester tester, {
  required DemoMenuItem item,
  required List<PosModifierGroup> groups,
  Size size = const Size(1000, 1200),
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  List<SelectedModifier> initialSelections = const <SelectedModifier>[],
  String? initialNote,
  bool isEdit = false,
  void Function(List<SelectedModifier> selections, String? note)? onConfirm,
  Key? widgetKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Center(
          child: ModifierSelectionSheet(
            key: widgetKey,
            item: item,
            groups: groups,
            currencyCode: 'ILS',
            initialSelections: initialSelections,
            initialNote: initialNote,
            isEdit: isEdit,
            onConfirm: onConfirm ?? (selections, note) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Unicode LTR-isolated form of a money run, as the sheet embeds it into
/// localized phrases (LRI … PDI).
String _isolated(String money) => '\u2066$money\u2069';

void main() {
  // ── Presentation: a bottom sheet at EVERY width ─────────────────────────

  testWidgets('ADD flow, wide layout: the customization overlay is a BOTTOM '
      'SHEET attached to the bottom edge (never a centered dialog), using most '
      'of the width and horizontally centered', (tester) async {
    const size = Size(1400, 1800);
    await _pump(tester, size: size);
    await _openBurgerSheet(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // Attached to the BOTTOM edge: the sheet's own bottom sits on the
    // viewport's bottom, and it does NOT float in the middle.
    final sheetRect = tester.getRect(find.byType(ModifierSelectionSheet));
    expect(sheetRect.bottom, moreOrLessEquals(size.height, epsilon: 1));
    // Horizontally centered…
    expect(sheetRect.center.dx, moreOrLessEquals(size.width / 2, epsilon: 1));
    // …taking MOST of the available width — decisively more than Material's
    // 640dp default, and here capped at the sheet's 1200dp maximum so a wide
    // cashier screen keeps a readable option row.
    expect(sheetRect.width, greaterThan(size.width * 0.7));
    expect(sheetRect.width, moreOrLessEquals(1200, epsilon: 1));

    // Sheet chrome: a drag handle near the top, rounded TOP corners only
    // (a square bottom = attached to the edge).
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.showDragHandle, isTrue);
    expect(sheet.enableDrag, isTrue);
    final shape = sheet.shape! as RoundedRectangleBorder;
    final radius = shape.borderRadius as BorderRadius;
    expect(radius.topLeft.y, greaterThan(0));
    expect(radius.topRight.y, greaterThan(0));
    expect(radius.bottomLeft, Radius.zero);
    expect(radius.bottomRight, Radius.zero);

    // Dimmed background (scrim), with the POS still in the tree behind it.
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(find.byType(PosMenuScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet SLIDES UP from the bottom edge (it is not there at '
      'rest, enters from below, and settles bottom-attached)', (tester) async {
    const size = Size(1400, 1800);
    await _pump(tester, size: size);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Card, 'Cheeseburger').first,
        matching: find.byIcon(Icons.add_shopping_cart),
      ),
    );
    // First frame of the route's entry animation: the sheet is mounted but
    // still below its resting place (it travels bottom → top).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final entering = tester.getRect(find.byType(ModifierSelectionSheet));

    await tester.pumpAndSettle();
    final settled = tester.getRect(find.byType(ModifierSelectionSheet));

    expect(entering.top, greaterThan(settled.top));
    expect(entering.bottom, greaterThan(settled.bottom));
    expect(settled.bottom, moreOrLessEquals(size.height, epsilon: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('EDIT flow (reopening a cart line) is the same bottom sheet, '
      'prefilled — not a centered dialog', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    // Add a configured burger (Medium + Cheese), then reopen it for edit.
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('modifier-add-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.posCartEditItem));
    await tester.pumpAndSettle();

    expect(find.byType(ModifierSelectionSheet), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final sheetRect = tester.getRect(find.byType(ModifierSelectionSheet));
    expect(sheetRect.bottom, moreOrLessEquals(1800, epsilon: 1));
    // Still the EDIT payload: the save label and the prefilled ₪51.00 total.
    expect(find.text(l10n.posEditSaveChanges), findsOneWidget);
    expect(_sheetTextContaining('₪51.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout keeps the existing bottom-sheet presentation', (
    tester,
  ) async {
    const size = Size(600, 1000);
    await _pump(tester, size: size);
    await _openBurgerSheet(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    // Phone: the sheet spans the width and hugs the bottom edge, unchanged.
    final sheetRect = tester.getRect(find.byType(ModifierSelectionSheet));
    expect(sheetRect.width, moreOrLessEquals(size.width, epsilon: 1));
    expect(sheetRect.bottom, moreOrLessEquals(size.height, epsilon: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the width cap holds on a very wide screen: 1200dp, centered and '
      'bottom-attached (not stretched across 1920)', (tester) async {
    const size = Size(1920, 1080);
    await _pump(tester, size: size);
    await _openBurgerSheet(tester);

    final sheetRect = tester.getRect(find.byType(ModifierSelectionSheet));
    expect(sheetRect.width, moreOrLessEquals(1200, epsilon: 1));
    expect(sheetRect.center.dx, moreOrLessEquals(size.width / 2, epsilon: 1));
    expect(sheetRect.bottom, moreOrLessEquals(size.height, epsilon: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the OPEN sheet re-flows when the viewport grows (browser resize '
      '/ tablet rotation): its width follows the live viewport, it is never '
      'frozen at its open-time width', (tester) async {
    // Opened on a narrow-ish viewport…
    await _pump(tester, size: const Size(760, 900));
    await _openBurgerSheet(tester);
    expect(
      tester.getRect(find.byType(ModifierSelectionSheet)).width,
      moreOrLessEquals(760, epsilon: 1),
    );

    // …then the window is maximized / the tablet rotated to landscape while
    // the sheet stays open: it must grow to the capped sheet width, not stay
    // a narrow column stranded in the middle of a wide screen.
    tester.view.physicalSize = const Size(1600, 1000);
    await tester.pumpAndSettle();

    final grown = tester.getRect(find.byType(ModifierSelectionSheet));
    expect(grown.width, moreOrLessEquals(1200, epsilon: 1));
    expect(grown.center.dx, moreOrLessEquals(800, epsilon: 1));
    expect(grown.bottom, moreOrLessEquals(1000, epsilon: 1));

    // And back down: it clamps to the smaller viewport without overflowing.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(ModifierSelectionSheet)).width,
      moreOrLessEquals(700, epsilon: 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet stays clear of the status bar / notch (useSafeArea)', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 64);
    addTearDown(tester.view.resetPadding);
    // A tall menu on a short screen: without the safe area the sheet would
    // grow up underneath the status bar.
    await _pump(tester, size: const Size(600, 700));
    await _openBurgerSheet(tester);

    final sheetRect = tester.getRect(find.byType(BottomSheet));
    expect(sheetRect.top, greaterThanOrEqualTo(64));
    expect(sheetRect.bottom, moreOrLessEquals(700, epsilon: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the required single-choice group renders as ONE horizontal '
      'row of equal cards at wide width, with its helper line', (tester) async {
    await _pump(tester);
    await _openBurgerSheet(tester);
    final l10n = await _en();

    // Doneness options (rare/medium/well) sit on one row: same top, equal
    // widths, in the real option order.
    final rare = _optionRect(tester, 'demo-opt-rare');
    final medium = _optionRect(tester, 'demo-opt-medium');
    final well = _optionRect(tester, 'demo-opt-well');
    expect(rare.top, moreOrLessEquals(medium.top, epsilon: 0.5));
    expect(medium.top, moreOrLessEquals(well.top, epsilon: 0.5));
    expect(rare.width, moreOrLessEquals(medium.width, epsilon: 0.5));
    expect(medium.width, moreOrLessEquals(well.width, epsilon: 0.5));
    expect(rare.left, lessThan(medium.left));
    expect(medium.left, lessThan(well.left));

    // The localized helper appears exactly once — only Doneness is a
    // required single-choice group.
    expect(find.text(l10n.posModifierChooseOne), findsOneWidget);

    // The full card is tappable: tapping the card (by its key = its center)
    // selects it and the live counter reads 1/1.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.posModifierSelectedCount(1, 1)), findsOneWidget);
  });

  testWidgets('optional checkbox additions form a two-column grid at wide '
      'width; stepper groups keep full-width rows', (tester) async {
    await _pump(tester);
    await _openBurgerSheet(tester);

    // Toppings (4 checkbox options): 2×2 grid — first two share a row,
    // the third starts the next row.
    final onion = _optionRect(tester, 'demo-opt-onion');
    final lettuce = _optionRect(tester, 'demo-opt-lettuce');
    final tomato = _optionRect(tester, 'demo-opt-tomato');
    expect(onion.top, moreOrLessEquals(lettuce.top, epsilon: 0.5));
    expect(tomato.top, greaterThan(onion.top));
    expect(onion.width, moreOrLessEquals(lettuce.width, epsilon: 0.5));

    // Extras carries quantity steppers: its options stay full-width rows
    // (one per line) so the −/+ pill never cramps.
    final extraCheese = _optionRect(tester, 'demo-opt-extra-cheese');
    final extraPatty = _optionRect(tester, 'demo-opt-extra-patty');
    expect(
      extraCheese.top,
      isNot(moreOrLessEquals(extraPatty.top, epsilon: 1)),
    );
    expect(extraCheese.width, greaterThan(onion.width * 1.5));
  });

  testWidgets('single-choice cards wrap safely on the narrow sheet without '
      'horizontal overflow', (tester) async {
    // 500px: the narrowest width at which the BARE POS page lays out clean —
    // the page itself overflows below ~450px, which predates this task and is
    // out of its modal-only scope. The sheet presentation applies (<820).
    await _pump(tester, size: const Size(500, 1000));
    await _openBurgerSheet(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    // At this width the three cards wrap (two per row): the first and last
    // Doneness cards no longer share a row.
    final rare = _optionRect(tester, 'demo-opt-rare');
    final well = _optionRect(tester, 'demo-opt-well');
    expect(rare.top, isNot(moreOrLessEquals(well.top, epsilon: 1)));
  });

  testWidgets('the footer (total + confirm) stays put while the modifier '
      'body scrolls', (tester) async {
    await _pump(tester, size: const Size(1400, 900));
    await _openBurgerSheet(tester);

    final before = tester.getRect(find.byKey(const Key('modifier-add-button')));
    // Drag the scrollable body upward; the sticky footer must not move.
    await tester.drag(
      find.descendant(
        of: find.byType(ModifierSelectionSheet),
        matching: find.byType(ListView),
      ),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byKey(const Key('modifier-add-button')));
    expect(after, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet dismisses without adding via the close button, via '
      'Escape, and via the scrim', (tester) async {
    await _pump(tester);
    final l10n = await _en();

    await _openBurgerSheet(tester);
    expect(find.byKey(const Key('modifier-close-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('modifier-close-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ModifierSelectionSheet), findsNothing);
    expect(find.text(l10n.posCartEmpty), findsOneWidget);

    await _openBurgerSheet(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ModifierSelectionSheet), findsNothing);
    expect(find.text(l10n.posCartEmpty), findsOneWidget);

    // Scrim (barrier) tap: the sheet is dismissible by tapping the dimmed POS
    // above it — a tap well above the sheet's top edge.
    await _openBurgerSheet(tester);
    final sheetTop = tester.getRect(find.byType(ModifierSelectionSheet)).top;
    await tester.tapAt(Offset(700, sheetTop / 2));
    await tester.pumpAndSettle();
    expect(find.byType(ModifierSelectionSheet), findsNothing);
    expect(find.text(l10n.posCartEmpty), findsOneWidget);
  });

  testWidgets('the item note text survives selection changes in the card '
      'grid', (tester) async {
    await _pump(tester);
    await _openBurgerSheet(tester);

    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      'no onions',
    );
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('modifier-item-note')),
    );
    expect(field.controller!.text, 'no onions');
  });

  testWidgets('text scale 2.0: the customization widget renders and confirms '
      'without overflow (direct pump — the bare POS page behind it has '
      'pre-existing scale-2.0 overflows outside this modal-only task)', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const groups = [
      PosModifierGroup(
        id: 'g-size',
        menuItemId: 'item-1',
        name: 'Size',
        singleSelect: true,
        minSelect: 1,
        maxSelect: 1,
        isRequired: true,
        options: [
          PosModifierOption(id: 'opt-s', name: 'Small', priceDeltaMinor: 0),
          PosModifierOption(id: 'opt-m', name: 'Medium', priceDeltaMinor: 300),
          PosModifierOption(id: 'opt-l', name: 'Large', priceDeltaMinor: 600),
        ],
      ),
      PosModifierGroup(
        id: 'g-extra',
        menuItemId: 'item-1',
        name: 'Extras',
        options: [
          PosModifierOption(id: 'opt-a', name: 'Sauce', priceDeltaMinor: 0),
          PosModifierOption(id: 'opt-b', name: 'Cheese', priceDeltaMinor: 200),
        ],
      ),
    ];
    var confirmed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Center(
            child: ModifierSelectionSheet(
              item: const DemoMenuItem(
                id: 'item-1',
                name: 'Burger',
                priceMinor: 4000,
                categoryId: 'burgers',
                categoryName: 'Burgers',
              ),
              groups: groups,
              currencyCode: 'ILS',
              onConfirm: (selections, note) => confirmed++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-m')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modifier-add-button')));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('he'), Locale('ar')]) {
    testWidgets(
      'the sheet renders RTL (${locale.languageCode}) with the card row in '
      'logical order and no overflow',
      (tester) async {
        await _pump(tester, locale: locale);
        await _openBurgerSheet(tester);
        expect(
          Directionality.of(
            tester.element(find.byType(ModifierSelectionSheet)),
          ),
          TextDirection.rtl,
        );
        // Reading order mirrors: the FIRST option (rare) sits at the reading
        // start — the rightmost card under RTL.
        final rare = _optionRect(tester, 'demo-opt-rare');
        final well = _optionRect(tester, 'demo-opt-well');
        expect(rare.left, greaterThan(well.left));
        expect(tester.takeException(), isNull);
      },
    );
  }

  // ── Finding 1: option-selection semantics ───────────────────────────────

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets(
      'each option exposes ONE semantic node with its full name, real price '
      'label, checked state and radio/checkbox behaviour '
      '(${locale.languageCode})',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, locale: locale);
        await _openBurgerSheet(tester);
        final l10n = await AppLocalizations.delegate.load(locale);

        // Single-choice (Doneness → radio group), unchecked: the node carries
        // the full option name + its real free/price label, is tappable, and
        // is flagged mutually exclusive.
        final mediumLabel = 'Medium, ${l10n.posModifierFree}';
        expect(
          tester.getSemantics(find.bySemanticsLabel(mediumLabel)),
          isSemantics(
            label: mediumLabel,
            hasCheckedState: true,
            isChecked: false,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        // Exactly one node announces it (no duplicate icon/text nodes).
        expect(find.bySemanticsLabel(mediumLabel), findsOneWidget);

        // Multi-choice (Toppings → checkbox), unchecked, PAID option keeps
        // its real signed delta in the label.
        const cheeseLabel = 'Cheese, +₪3.00';
        expect(
          tester.getSemantics(find.bySemanticsLabel(cheeseLabel)),
          isSemantics(
            label: cheeseLabel,
            hasCheckedState: true,
            isChecked: false,
            isInMutuallyExclusiveGroup: false,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );

        // Selecting flips the checked state on BOTH kinds.
        await tester.tap(
          find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSemantics(find.bySemanticsLabel(mediumLabel)),
          isSemantics(
            label: mediumLabel,
            hasCheckedState: true,
            isChecked: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel(cheeseLabel)),
          isSemantics(
            label: cheeseLabel,
            hasCheckedState: true,
            isChecked: true,
            isInMutuallyExclusiveGroup: false,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        handle.dispose();
      },
    );
  }

  // ── Finding 2: long option labels wrap safely ───────────────────────────

  const longNames = <String, List<String>>{
    'en': [
      'Extra large double smashed patty',
      'Regular hand-pressed beef patty',
      'Half portion grilled chicken breast',
    ],
    'ar': [
      'قطعة لحم مشوية مضاعفة كبيرة جدًا',
      'قطعة لحم بقري مضغوطة يدويًا عادية',
      'نصف حصة صدر دجاج مشوي على الفحم',
    ],
    'he': [
      'קציצת בשר כפולה גדולה במיוחד',
      'קציצת בקר רגילה בלחיצת יד',
      'חצי מנה חזה עוף בגריל על האש',
    ],
  };

  for (final entry in longNames.entries) {
    for (final scale in const [1.0, 2.0]) {
      // Wide (3 cards), medium (2 cards), narrow (1 column) inner layouts.
      for (final size in const [
        Size(1000, 1400),
        Size(720, 1400),
        Size(420, 1600),
      ]) {
        testWidgets(
          'long ${entry.key} option names wrap without overflow or hidden '
          'price at ${size.width.toInt()}px, text scale $scale',
          (tester) async {
            final handle = tester.ensureSemantics();
            final names = entry.value;
            await _pumpDirect(
              tester,
              size: size,
              locale: Locale(entry.key),
              textScale: scale,
              item: _item(),
              groups: [
                _singleGroup(
                  options: [
                    for (var i = 0; i < names.length; i++)
                      PosModifierOption(
                        id: 'opt-$i',
                        name: names[i],
                        priceDeltaMinor: i * 300,
                      ),
                  ],
                ),
              ],
            );

            // No Flutter overflow anywhere in the modal.
            expect(tester.takeException(), isNull);

            final l10n = await AppLocalizations.delegate.load(
              Locale(entry.key),
            );
            for (var i = 0; i < names.length; i++) {
              // The card is present and its price/free label is VISIBLE
              // (never hidden behind an ellipsized name).
              final card = find.byKey(ValueKey('modifier-option-opt-$i'));
              expect(card, findsOneWidget);
              final priceText = i == 0
                  ? l10n.posModifierFree
                  : '+₪${(i * 3).toStringAsFixed(2)}';
              expect(
                find.descendant(of: card, matching: find.text(priceText)),
                findsOneWidget,
              );
              // The FULL name survives in the accessible label, even when the
              // visual text wraps/ellipsizes at extreme scales.
              expect(
                find.bySemanticsLabel('${names[i]}, $priceText'),
                findsOneWidget,
              );
            }
            handle.dispose();
          },
        );
      }
    }
  }

  // ── Finding 3: stale state resets when the widget identity changes ───────

  testWidgets('reusing the same widget position for a DIFFERENT item rebuilds '
      'from the new initial payload (old selection/note dropped, total from '
      'the new item only)', (tester) async {
    const key = ValueKey('customization');
    final itemA = _item(id: 'item-a', name: 'Burger A', priceMinor: 4000);
    final groupsA = [
      _singleGroup(
        menuItemId: 'item-a',
        options: const [
          PosModifierOption(id: 'a-1', name: 'Small', priceDeltaMinor: 0),
          PosModifierOption(id: 'a-2', name: 'Large', priceDeltaMinor: 500),
        ],
      ),
    ];
    await _pumpDirect(tester, widgetKey: key, item: itemA, groups: groupsA);

    // Cashier picks a paid option on A and types a note.
    await tester.tap(find.byKey(const ValueKey('modifier-option-a-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      'note for A',
    );
    await tester.pumpAndSettle();
    // A's total = 40.00 + 5.00.
    expect(find.textContaining('₪45.00'), findsWidgets);

    // The SAME widget position now represents item B with its own groups and
    // an edit payload (B's medium preselected + B's note).
    final itemB = _item(id: 'item-b', name: 'Burger B', priceMinor: 6000);
    final groupsB = [
      _singleGroup(
        id: 'g-b-size',
        menuItemId: 'item-b',
        options: const [
          PosModifierOption(id: 'b-1', name: 'Regular', priceDeltaMinor: 0),
          PosModifierOption(id: 'b-2', name: 'Double', priceDeltaMinor: 900),
        ],
      ),
    ];
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: itemB,
      groups: groupsB,
      isEdit: true,
      initialNote: 'note for B',
      initialSelections: const [
        SelectedModifier(
          optionId: 'b-2',
          groupName: 'Size',
          optionName: 'Double',
          priceDeltaMinor: 900,
        ),
      ],
    );

    // A's state is gone; only B's payload remains.
    expect(find.byKey(const ValueKey('modifier-option-a-2')), findsNothing);
    final note = tester.widget<TextField>(
      find.byKey(const Key('modifier-item-note')),
    );
    expect(note.controller!.text, 'note for B');
    // The total is computed from B only: 60.00 + 9.00 (never A's 40/5).
    expect(find.textContaining('₪69.00'), findsWidgets);
    expect(find.textContaining('₪45.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ordinary rebuild (same item + same groups, new locale) does '
      'NOT clear the cashier\'s in-progress selection or note', (tester) async {
    const key = ValueKey('customization');
    final item = _item();
    final groups = [
      _singleGroup(
        options: const [
          PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
          PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 500),
        ],
      ),
    ];
    await _pumpDirect(tester, widgetKey: key, item: item, groups: groups);
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      'keep me',
    );
    await tester.pumpAndSettle();

    // Same product + configuration, different locale (and a fresh but EQUAL
    // group list instance) — the in-progress input must survive.
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: [
        _singleGroup(
          options: const [
            PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
            PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 500),
          ],
        ),
      ],
      locale: const Locale('ar'),
    );

    final note = tester.widget<TextField>(
      find.byKey(const Key('modifier-item-note')),
    );
    expect(note.controller!.text, 'keep me');
    // Still selected: the running total keeps the +₪5.00 delta.
    expect(find.textContaining('₪45.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // ── Finding 4: money direction is stable under RTL ──────────────────────

  for (final locale in const [Locale('ar'), Locale('he')]) {
    testWidgets(
      'RTL (${locale.languageCode}) keeps signed deltas, the base price, the '
      'running total and the add-button total in LTR money order',
      (tester) async {
        await _pump(tester, locale: locale);
        await _openBurgerSheet(tester);
        final l10n = await AppLocalizations.delegate.load(locale);

        // The signed delta renders exactly as '+₪3.00' (never '₪3.00+') and
        // every delta Text is forced LTR so bidi cannot reorder it. (The demo
        // menu has two +₪3.00 options: the Cheese topping and Extra cheese.)
        final delta = find.descendant(
          of: find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
          matching: find.text('+₪3.00'),
        );
        expect(delta, findsOneWidget);
        expect(tester.widget<Text>(delta).textDirection, TextDirection.ltr);
        for (final t in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(ModifierSelectionSheet),
            matching: find.text('+₪3.00'),
          ),
        )) {
          expect(t.textDirection, TextDirection.ltr);
        }

        // Base price: currency + digits stay together as one isolated run
        // inside the localized phrase.
        expect(
          find.text(l10n.posModifierBasePrice(_isolated('₪48.00'))),
          findsOneWidget,
        );

        // The running total is a standalone LTR money Text…
        final total = find.descendant(
          of: find.byType(ModifierSelectionSheet),
          matching: find.text('₪48.00'),
        );
        expect(total, findsOneWidget);
        expect(tester.widget<Text>(total).textDirection, TextDirection.ltr);
        // …and the add button's total is isolated inside its phrase.
        expect(
          find.text(l10n.posAddToCartWithTotal(_isolated('₪48.00'))),
          findsOneWidget,
        );
        // No duplicated money renders: exactly the two total surfaces.
        expect(_sheetTextContaining('₪48.00'), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('English money output is unchanged (no isolation artefacts in '
      'the rendered strings)', (tester) async {
    await _pump(tester);
    await _openBurgerSheet(tester);
    final l10n = await _en();

    expect(
      find.text(l10n.posModifierBasePrice(_isolated('₪48.00'))),
      findsOneWidget,
    );
    expect(
      find.text(l10n.posAddToCartWithTotal(_isolated('₪48.00'))),
      findsOneWidget,
    );
    // The plain money runs render verbatim.
    expect(
      find.descendant(
        of: find.byType(ModifierSelectionSheet),
        matching: find.text('₪48.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
        matching: find.text('+₪3.00'),
      ),
      findsOneWidget,
    );
  });

  // ── Finding 5: short viewports + keyboard insets ────────────────────────

  for (final size in const [Size(1320, 620)]) {
    testWidgets(
      'short wide sheet at ${size.width.toInt()}×${size.height.toInt()}: the '
      'footer stays visible, the body scrolls under a fixed header, and the '
      'last option + note are reachable',
      (tester) async {
        await _pump(tester, size: size);
        await _openBurgerSheet(tester);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        // Short screen: the sheet is capped, so the scrim above it stays
        // visible — it never becomes a full-screen page.
        final sheetRect = tester.getRect(find.byType(BottomSheet));
        expect(sheetRect.top, greaterThan(0));
        expect(tester.takeException(), isNull);

        // The confirm action is on screen from the start.
        final footer = find.byKey(const Key('modifier-add-button'));
        final footerRect = tester.getRect(footer);
        expect(footerRect.bottom, lessThanOrEqualTo(size.height));
        expect(footerRect.top, greaterThanOrEqualTo(0));

        final header = find.descendant(
          of: find.byType(ModifierSelectionSheet),
          matching: find.text('Cheeseburger'),
        );
        final headerBefore = tester.getRect(header);
        final body = find.descendant(
          of: find.byType(ModifierSelectionSheet),
          matching: find.byType(ListView),
        );

        // Scroll to the END of the body: the last option and the note come
        // into view while header + footer do not move.
        await tester.drag(body, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(footer), footerRect);
        expect(tester.getRect(header), headerBefore);

        final lastOption = _optionRect(tester, 'demo-opt-extra-patty');
        expect(lastOption.bottom, lessThanOrEqualTo(size.height));
        final noteRect = tester.getRect(
          find.byKey(const Key('modifier-item-note')),
        );
        expect(noteRect.bottom, lessThanOrEqualTo(size.height));
        expect(noteRect.top, greaterThanOrEqualTo(0));
      },
    );
  }

  testWidgets('short wide sheet at 1024×600: the footer stays visible, the '
      'body scrolls under a fixed header, and the last option + note are '
      'reachable (modal isolated on a 1024×600 host — the POS PAGE itself '
      'overflows 36px at this width WITHOUT any modal, so a full-app pump '
      'cannot attribute an overflow to the modal)', (tester) async {
    await _pumpDirect(
      tester,
      size: const Size(1024, 600),
      item: _item(name: 'Cheeseburger'),
      groups: [
        _multiGroup(
          id: 'g-toppings',
          name: 'Toppings',
          options: const [
            PosModifierOption(id: 't-1', name: 'Onion', priceDeltaMinor: 0),
            PosModifierOption(id: 't-2', name: 'Lettuce', priceDeltaMinor: 0),
            PosModifierOption(id: 't-3', name: 'Tomato', priceDeltaMinor: 0),
            PosModifierOption(id: 't-4', name: 'Cheese', priceDeltaMinor: 300),
          ],
        ),
        _singleGroup(
          id: 'g-doneness',
          name: 'Doneness',
          options: const [
            PosModifierOption(id: 'd-1', name: 'Rare', priceDeltaMinor: 0),
            PosModifierOption(id: 'd-2', name: 'Medium', priceDeltaMinor: 0),
            PosModifierOption(id: 'd-3', name: 'Well done', priceDeltaMinor: 0),
          ],
        ),
        _multiGroup(
          id: 'g-extras',
          name: 'Extras',
          options: const [
            PosModifierOption(
              id: 'x-1',
              name: 'Extra cheese',
              priceDeltaMinor: 300,
            ),
            PosModifierOption(
              id: 'x-2',
              name: 'Extra patty',
              priceDeltaMinor: 900,
            ),
          ],
        ),
      ],
    );
    // The modal itself lays out clean at this short, narrow-ish size.
    expect(tester.takeException(), isNull);

    final footer = find.byKey(const Key('modifier-add-button'));
    final footerRect = tester.getRect(footer);
    expect(footerRect.bottom, lessThanOrEqualTo(600));
    expect(footerRect.top, greaterThanOrEqualTo(0));
    final header = find.descendant(
      of: find.byType(ModifierSelectionSheet),
      matching: find.text('Cheeseburger'),
    );
    final headerBefore = tester.getRect(header);

    // The body — and only the body — scrolls; the last option and the note
    // become reachable while header and footer hold their positions.
    final body = find.descendant(
      of: find.byType(ModifierSelectionSheet),
      matching: find.byType(ListView),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('modifier-item-note')),
      200,
      scrollable: find.descendant(of: body, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(footer), footerRect);
    expect(tester.getRect(header), headerBefore);

    final lastOption = tester.getRect(
      find.byKey(const ValueKey('modifier-option-x-2')),
    );
    expect(lastOption.bottom, lessThanOrEqualTo(600));
    final noteRect = tester.getRect(
      find.byKey(const Key('modifier-item-note')),
    );
    expect(noteRect.bottom, lessThanOrEqualTo(600));
    expect(noteRect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('with a non-zero bottom viewInset (on-screen keyboard) the note '
      'field and the confirm action stay reachable, and Escape dismisses '
      'without confirming', (tester) async {
    var confirmed = 0;
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1.0;
    // A keyboard occupying the bottom of the viewport.
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => ModifierSelectionSheet.show(
                  context,
                  item: _item(name: 'Burger'),
                  groups: [
                    _singleGroup(
                      options: const [
                        PosModifierOption(
                          id: 'opt-1',
                          name: 'Small',
                          priceDeltaMinor: 0,
                        ),
                        PosModifierOption(
                          id: 'opt-2',
                          name: 'Large',
                          priceDeltaMinor: 500,
                        ),
                      ],
                    ),
                    _multiGroup(
                      options: const [
                        PosModifierOption(
                          id: 'opt-3',
                          name: 'Sauce',
                          priceDeltaMinor: 0,
                        ),
                      ],
                    ),
                  ],
                  currencyCode: 'ILS',
                  onConfirm: (selections, note) => confirmed++,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The keyboard case runs on the real presentation: a modal bottom sheet.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);

    // Focus the note field with the keyboard up: the cashier scrolls the body
    // to it (the modifier list is the only scrolling region), and it stays on
    // screen above the inset and can take text.
    final noteField = find.byKey(const Key('modifier-item-note'));
    await tester.scrollUntilVisible(
      noteField,
      200,
      scrollable: find.descendant(
        of: find.descendant(
          of: find.byType(ModifierSelectionSheet),
          matching: find.byType(ListView),
        ),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(noteField);
    await tester.pumpAndSettle();
    await tester.enterText(noteField, 'no onions');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final visibleBottom = 600.0 - 260.0;
    final noteRect = tester.getRect(noteField);
    expect(noteRect.bottom, lessThanOrEqualTo(visibleBottom));
    // The confirm action is likewise clear of the keyboard.
    final footerRect = tester.getRect(
      find.byKey(const Key('modifier-add-button')),
    );
    expect(footerRect.bottom, lessThanOrEqualTo(visibleBottom));

    // Escape dismisses WITHOUT confirming (nothing added to the cart).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ModifierSelectionSheet), findsNothing);
    expect(confirmed, 0);
    expect(tester.takeException(), isNull);
  });

  // ── Squeezed sheet: short landscape tablet + on-screen keyboard ─────────
  // The sheet is laid out over the FULL viewport height and lifts its content
  // above the keyboard itself, so a short landscape tablet with the keyboard up
  // can leave under 200dp of usable height. The fixed header then joins the
  // scrolling body and the footer's padding tightens, so nothing overflows and
  // the confirm action stays clear of the keyboard.

  for (final probe in const [
    // (viewport, keyboard) — real postures: a 10" landscape tablet, an 8"
    // landscape tablet, a wide short landscape screen, and a deliberately
    // extreme keyboard (63% of the viewport) as the worst case.
    (Size(1024, 600), 300.0),
    (Size(853, 533), 280.0),
    (Size(1320, 620), 360.0),
    (Size(1024, 600), 380.0),
  ]) {
    final size = probe.$1;
    final keyboard = probe.$2;
    testWidgets(
      'keyboard up on ${size.width.toInt()}×${size.height.toInt()} with a '
      '${keyboard.toInt()}dp keyboard: no overflow, and the confirm action '
      'stays fully above the keyboard',
      (tester) async {
        var confirmed = 0;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => ModifierSelectionSheet.show(
                      context,
                      item: _item(name: 'Cheeseburger'),
                      groups: [
                        _singleGroup(
                          name: 'Doneness',
                          options: const [
                            PosModifierOption(
                              id: 'd-1',
                              name: 'Rare',
                              priceDeltaMinor: 0,
                            ),
                            PosModifierOption(
                              id: 'd-2',
                              name: 'Medium',
                              priceDeltaMinor: 0,
                            ),
                          ],
                        ),
                        _multiGroup(
                          name: 'Toppings',
                          options: const [
                            PosModifierOption(
                              id: 't-1',
                              name: 'Onion',
                              priceDeltaMinor: 0,
                            ),
                            PosModifierOption(
                              id: 't-2',
                              name: 'Cheese',
                              priceDeltaMinor: 300,
                            ),
                          ],
                        ),
                      ],
                      currencyCode: 'ILS',
                      onConfirm: (selections, note) => confirmed++,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // No RenderFlex overflow anywhere in the squeezed sheet.
        expect(tester.takeException(), isNull);
        expect(find.byType(BottomSheet), findsOneWidget);

        final keyboardTop = size.height - keyboard;
        // The confirm button is FULLY above the keyboard and still full-size.
        final button = tester.getRect(
          find.byKey(const Key('modifier-add-button')),
        );
        expect(button.bottom, lessThanOrEqualTo(keyboardTop));
        expect(button.top, greaterThanOrEqualTo(0));
        expect(button.height, greaterThanOrEqualTo(44));
        // The running total is still on screen next to it.
        expect(_sheetTextContaining('₪40.00'), findsWidgets);

        // The body is the only scrolling region: every option and the note the
        // cashier is typing into can be reached through it (the squeezed sheet
        // scrolls its header away rather than pinching the body shut).
        final scrollable = find.descendant(
          of: find.descendant(
            of: find.byType(ModifierSelectionSheet),
            matching: find.byType(ListView),
          ),
          matching: find.byType(Scrollable),
        );

        // Pick the required option (scrolled into view), with the keyboard up.
        const option = ValueKey('modifier-option-d-2');
        await tester.scrollUntilVisible(
          find.byKey(option),
          80,
          scrollable: scrollable,
          maxScrolls: 120,
        );
        await tester.ensureVisible(find.byKey(option));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(option));
        await tester.pumpAndSettle();

        // The note lands above the keyboard once scrolled to.
        final note = find.byKey(const Key('modifier-item-note'));
        await tester.scrollUntilVisible(
          note,
          80,
          scrollable: scrollable,
          maxScrolls: 120,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(note).top, lessThan(keyboardTop));

        // The confirm action is still clear of the keyboard, and commits.
        final buttonAfter = tester.getRect(
          find.byKey(const Key('modifier-add-button')),
        );
        expect(buttonAfter.bottom, lessThanOrEqualTo(keyboardTop));
        await tester.tap(find.byKey(const Key('modifier-add-button')));
        await tester.pumpAndSettle();
        expect(confirmed, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a squeezed sheet keeps the item header reachable (it scrolls '
      'with the body instead of eating the height), and a roomy sheet keeps it '
      'fixed above the body', (tester) async {
    // Roomy: the header is OUTSIDE the scrolling body (it does not move).
    await _pump(tester, size: const Size(1320, 900));
    await _openBurgerSheet(tester);
    final body = find.descendant(
      of: find.byType(ModifierSelectionSheet),
      matching: find.byType(ListView),
    );
    final headerText = find.descendant(
      of: find.byType(ModifierSelectionSheet),
      matching: find.text('Cheeseburger'),
    );
    expect(
      find.descendant(of: body, matching: headerText),
      findsNothing,
      reason: 'a roomy sheet keeps the header fixed above the scrolling body',
    );
    final before = tester.getRect(headerText);
    await tester.drag(body, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getRect(headerText), before);
    expect(tester.takeException(), isNull);
  });

  // ── Final audit A: configuration identity ───────────────────────────────
  // The reset decision compares a deterministic signature of every field that
  // can change which selections are valid, what they cost, or how the cashier
  // interacts (item id; per group IN ORDER: id, owning item, single/multi,
  // min/max, required, quantity support + cap; per option IN ORDER: id and
  // signed price delta).

  testWidgets('A1: same item + same group id but CHANGED option ids resets the '
      'stale selection and applies only the new payload', (tester) async {
    const key = ValueKey('customization');
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: [
        _singleGroup(
          options: const [
            PosModifierOption(id: 'old-1', name: 'Small', priceDeltaMinor: 0),
            PosModifierOption(id: 'old-2', name: 'Large', priceDeltaMinor: 500),
          ],
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('modifier-option-old-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('₪45.00'), findsWidgets);

    // Same item id, same group id — but a different OPTION SET.
    final handle = tester.ensureSemantics();
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: [
        _singleGroup(
          options: const [
            PosModifierOption(id: 'new-1', name: 'Regular', priceDeltaMinor: 0),
            PosModifierOption(
              id: 'new-2',
              name: 'Double',
              priceDeltaMinor: 900,
            ),
          ],
        ),
      ],
      initialSelections: const [
        SelectedModifier(
          optionId: 'new-1',
          groupName: 'Size',
          optionName: 'Regular',
          priceDeltaMinor: 0,
        ),
      ],
    );

    // The old option is gone from the tree AND from the selection; only the
    // new initial payload is selected, and the old delta cannot survive.
    expect(find.byKey(const ValueKey('modifier-option-old-2')), findsNothing);
    expect(find.textContaining('₪45.00'), findsNothing);
    expect(find.textContaining('₪40.00'), findsWidgets);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Regular, Free')),
      isSemantics(isChecked: true, hasCheckedState: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Double, +₪9.00')),
      isSemantics(isChecked: false, hasCheckedState: true),
    );
    handle.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('A2: same ids but a CHANGED price delta resets the stale total '
      'and prices the new payload from the new configuration', (tester) async {
    const key = ValueKey('customization');
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: [
        _singleGroup(
          options: const [
            PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
            PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 500),
          ],
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('₪45.00'), findsWidgets);

    // Identical ids; Large now costs +₪7.00 instead of +₪5.00.
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: [
        _singleGroup(
          options: const [
            PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
            PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 700),
          ],
        ),
      ],
      initialSelections: const [
        SelectedModifier(
          optionId: 'opt-2',
          groupName: 'Size',
          optionName: 'Large',
          priceDeltaMinor: 700,
        ),
      ],
    );

    // The stale ₪45.00 total is gone; the REAL new price (+₪7.00) is used.
    expect(find.textContaining('₪45.00'), findsNothing);
    expect(find.textContaining('₪47.00'), findsWidgets);
    expect(find.text('+₪7.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A3: same ids but CHANGED selection rules (optional multi -> '
      'required single) resets state and validation follows the new '
      'configuration', (tester) async {
    const key = ValueKey('customization');
    // Start OPTIONAL multi-select: nothing required, so Add is enabled.
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: [
        _multiGroup(
          id: 'g-size',
          name: 'Size',
          options: const [
            PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
            PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 500),
          ],
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('modifier-add-button')))
          .onPressed,
      isNotNull,
    );

    // The SAME group id is now a REQUIRED single-select: the old selection is
    // stale, so the button must be disabled until the cashier picks again.
    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: [
        _singleGroup(
          options: const [
            PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
            PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 500),
          ],
        ),
      ],
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('modifier-add-button')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('₪45.00'), findsNothing);

    // Picking under the NEW rules re-enables it.
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('modifier-add-button')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A4: freshly allocated but EQUIVALENT model objects preserve the '
      'in-progress selection and note', (tester) async {
    const key = ValueKey('customization');
    List<PosModifierGroup> groups() => [
      _singleGroup(
        options: const [
          PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
          PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 500),
        ],
      ),
      _multiGroup(
        options: const [
          PosModifierOption(id: 'x-1', name: 'Sauce', priceDeltaMinor: 0),
        ],
      ),
    ];
    await _pumpDirect(tester, widgetKey: key, item: _item(), groups: groups());
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      'keep me',
    );
    await tester.pumpAndSettle();

    // Brand-new item / group / option instances, identical configuration.
    await _pumpDirect(tester, widgetKey: key, item: _item(), groups: groups());

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('modifier-item-note')))
          .controller!
          .text,
      'keep me',
    );
    expect(find.textContaining('₪45.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A5: a locale + text-scale + size (MediaQuery) rebuild preserves '
      'the in-progress selection and note', (tester) async {
    const key = ValueKey('customization');
    List<PosModifierGroup> groups() => [
      _singleGroup(
        options: const [
          PosModifierOption(id: 'opt-1', name: 'Small', priceDeltaMinor: 0),
          PosModifierOption(id: 'opt-2', name: 'Large', priceDeltaMinor: 500),
        ],
      ),
    ];
    await _pumpDirect(tester, widgetKey: key, item: _item(), groups: groups());
    await tester.tap(find.byKey(const ValueKey('modifier-option-opt-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      'no onions',
    );
    await tester.pumpAndSettle();

    await _pumpDirect(
      tester,
      widgetKey: key,
      item: _item(),
      groups: groups(),
      locale: const Locale('he'),
      textScale: 1.3,
      size: const Size(900, 1400),
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('modifier-item-note')))
          .controller!
          .text,
      'no onions',
    );
    expect(find.textContaining('₪45.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // ── Final audit B: enabled / disabled semantics ─────────────────────────
  // PosModifierOption carries NO disabled/unavailable flag (id, name, signed
  // price delta, optional kitchen-meat only), so no such state is invented.
  // The one REAL "cannot be activated right now" state the product has is a
  // multi-select group at its distinct-option capacity — the semantics and the
  // affordance now follow it instead of hardcoding `enabled: true`.

  testWidgets('B1: enabled single-choice and checkbox options announce '
      'enabled + tappable with a truthful checked state', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await _openBurgerSheet(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Medium, Free')),
      isSemantics(
        label: 'Medium, Free',
        hasCheckedState: true,
        isChecked: false,
        isInMutuallyExclusiveGroup: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Cheese, +₪3.00')),
      isSemantics(
        label: 'Cheese, +₪3.00',
        hasCheckedState: true,
        isChecked: false,
        isInMutuallyExclusiveGroup: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('B2: a capacity-blocked checkbox option is DISABLED with no tap '
      'action and stays inert; the selected one remains deselectable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var confirmed = <SelectedModifier>[];
    // A multi-select group capped at ONE distinct option.
    await _pumpDirect(
      tester,
      item: _item(),
      groups: const [
        PosModifierGroup(
          id: 'g-one',
          menuItemId: 'item-a',
          name: 'Pick one extra',
          maxSelect: 1,
          options: [
            PosModifierOption(id: 'e-1', name: 'Sauce', priceDeltaMinor: 0),
            PosModifierOption(id: 'e-2', name: 'Cheese', priceDeltaMinor: 300),
          ],
        ),
      ],
      onConfirm: (selections, note) => confirmed = selections,
    );

    await tester.tap(find.byKey(const ValueKey('modifier-option-e-1')));
    await tester.pumpAndSettle();

    // At capacity: the OTHER option cannot be activated — disabled, no tap.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Cheese, +₪3.00')),
      isSemantics(
        label: 'Cheese, +₪3.00',
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    // Tapping it still changes nothing (the existing no-op is preserved).
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-e-2')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Cheese, +₪3.00')),
      isSemantics(isChecked: false, hasCheckedState: true, isEnabled: false),
    );
    // The selected option is never trapped: it stays enabled + deselectable.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sauce, Free')),
      isSemantics(
        isChecked: true,
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('modifier-option-e-1')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sauce, Free')),
      isSemantics(isChecked: false, hasCheckedState: true, isEnabled: true),
    );
    // …and with the group under capacity again, the other option re-enables.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Cheese, +₪3.00')),
      isSemantics(isEnabled: true, hasEnabledState: true, hasTapAction: true),
    );

    await tester.tap(find.byKey(const ValueKey('modifier-option-e-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modifier-add-button')));
    await tester.pumpAndSettle();
    expect(confirmed.map((s) => s.optionId).toList(), ['e-2']);
    handle.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('B3: the quantity stepper exposes its own REAL enabled states — '
      'minus disabled at 0, plus disabled at the per-option cap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await _openBurgerSheet(tester);

    IconButton stepper(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));

    // Extras: allowQuantity, maxQuantity 5, maxSelect 2. At 0 units the − is
    // disabled and the + is enabled.
    expect(stepper('modifier-qty-dec-demo-opt-extra-cheese').onPressed, isNull);
    expect(
      stepper('modifier-qty-inc-demo-opt-extra-cheese').onPressed,
      isNotNull,
    );

    // Count up to the per-option cap (5): + goes disabled, − stays enabled.
    for (var i = 0; i < 5; i++) {
      await tester.tap(
        find.byKey(const ValueKey('modifier-qty-inc-demo-opt-extra-cheese')),
      );
      await tester.pumpAndSettle();
    }
    expect(stepper('modifier-qty-inc-demo-opt-extra-cheese').onPressed, isNull);
    expect(
      stepper('modifier-qty-dec-demo-opt-extra-cheese').onPressed,
      isNotNull,
    );

    // The option node carries exactly ONE tap action of its own; the stepper
    // buttons are separate nodes (no duplicate announcements).
    expect(
      find.bySemanticsLabel(RegExp(r'^Extra cheese, \+₪3\.00')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^Extra cheese, \+₪3\.00')),
      ),
      isSemantics(hasTapAction: true, isEnabled: true, hasEnabledState: true),
    );
    handle.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('B4: in a stepper group at capacity an unselected option is '
      'disabled and its +/− announce no available action', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpDirect(
      tester,
      item: _item(),
      groups: const [
        PosModifierGroup(
          id: 'g-extras',
          menuItemId: 'item-a',
          name: 'Extras',
          maxSelect: 1,
          allowQuantity: true,
          maxQuantity: 3,
          options: [
            PosModifierOption(id: 'q-1', name: 'Bacon', priceDeltaMinor: 400),
            PosModifierOption(id: 'q-2', name: 'Egg', priceDeltaMinor: 300),
          ],
        ),
      ],
    );

    IconButton stepper(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));

    // Take one unit of Bacon: the group (max 1 distinct option) is now full.
    await tester.tap(find.byKey(const ValueKey('modifier-qty-inc-q-1')));
    await tester.pumpAndSettle();

    // Egg cannot be activated: disabled node, no tap action, and its + must
    // NOT announce an available action (selecting it is blocked).
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Egg, \+₪3\.00'))),
      isSemantics(
        isChecked: false,
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    // (The stepper-group option node also carries its live unit count, so the
    // label is matched by prefix above rather than pinned exactly.)
    expect(stepper('modifier-qty-inc-q-2').onPressed, isNull);
    expect(stepper('modifier-qty-dec-q-2').onPressed, isNull);

    // Bacon keeps its real stepper states (− enabled at 1, + enabled below 3).
    expect(stepper('modifier-qty-dec-q-1').onPressed, isNotNull);
    expect(stepper('modifier-qty-inc-q-1').onPressed, isNotNull);

    // Counting Bacon back to 0 frees the capacity and re-enables Egg.
    await tester.tap(find.byKey(const ValueKey('modifier-qty-dec-q-1')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Egg, \+₪3\.00'))),
      isSemantics(isEnabled: true, hasEnabledState: true, hasTapAction: true),
    );
    expect(stepper('modifier-qty-inc-q-2').onPressed, isNotNull);
    handle.dispose();
    expect(tester.takeException(), isNull);
  });
}

/// Text containing [needle] anywhere inside the open customization widget.
Finder _sheetTextContaining(String needle) => find.descendant(
  of: find.byType(ModifierSelectionSheet),
  matching: find.textContaining(needle),
);
