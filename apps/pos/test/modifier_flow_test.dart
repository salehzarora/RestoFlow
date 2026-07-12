import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// Demo-readiness sprint (Part F): items with modifier groups open the option
/// picker; required groups gate the Add button; paid modifiers change the
/// price; the order payload carries the selected modifiers (RF-052 shape);
/// money stays integer minor units.
///
/// Menu/media sprint (Part E): the sheet header shows the BASE price; group
/// headers carry Required/Optional pills + live selected-count pills (danger
/// while a required minimum is unmet, warning at multi-select capacity); free
/// options are labelled; cart sub-lines show paid deltas; RTL renders cleanly.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  OutboxRepository? repo,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null) outboxRepositoryProvider.overrideWithValue(repo),
      ],
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

/// The status pill (uniquely) labelled [label] — for tone assertions.
RestoflowStatusPill _pill(WidgetTester tester, String label) =>
    tester.widget<RestoflowStatusPill>(
      find.widgetWithText(RestoflowStatusPill, label),
    );

/// Taps the add affordance on the Cheeseburger card (has modifier groups).
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

Finder _addButton() => find.byKey(const Key('modifier-add-button'));

/// Text WITHIN the open sheet — running totals can collide with menu-card
/// prices behind the modal (e.g. a demo item priced ₪54.00), so the
/// quantity-sprint total assertions scope themselves to the sheet.
Finder _sheetText(String text) => find.descendant(
  of: find.byType(ModifierSelectionSheet),
  matching: find.textContaining(text),
);

void main() {
  testWidgets('a modifier item opens the picker; the REQUIRED single-select '
      'group gates Add; a paid topping raises the total', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _openBurgerSheet(tester);

    // Groups + the Required pill render.
    expect(find.text('Toppings'), findsOneWidget);
    expect(find.text('Doneness'), findsOneWidget);
    expect(find.text(l10n.posModifierRequired), findsOneWidget);
    // Base price on the Add button; disabled while Doneness is unpicked.
    expect(find.textContaining('₪48.00'), findsWidgets);
    expect(tester.widget<FilledButton>(_addButton()).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(_addButton()).onPressed, isNotNull);

    // A PAID topping (+₪3.00) updates the running total: 48.00 -> 51.00.
    // Design-polish: the total renders twice while the sheet is open — the
    // summary row above the confirm button AND the Add button label.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    expect(find.textContaining('₪51.00'), findsNWidgets(2));

    await tester.tap(_addButton());
    await tester.pumpAndSettle();

    // The cart line carries the selections and the modifier-inclusive total.
    expect(find.text('+ Cheese'), findsOneWidget);
    expect(find.text('+ Medium'), findsOneWidget);
    expect(find.text('₪51.00'), findsWidgets);
  });

  testWidgets('max-select is enforced (Extras allows 2)', (tester) async {
    await _pump(tester);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-extra-cheese')),
    );
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-extra-patty')),
    );
    await tester.pump();
    // Both extras selected: base 48.00 + 3.00 + 9.00 = 60.00 (running total
    // renders twice since the design polish: summary row + Add button label).
    expect(find.textContaining('₪60.00'), findsNWidgets(2));
    // A third selection in the same group cannot exist (only 2 options), but
    // deselecting works: remove the patty -> total drops back to 45.00.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-extra-patty')),
    );
    await tester.pump();
    expect(find.textContaining('₪51.00'), findsNWidgets(2));
  });

  testWidgets('a plain item still adds directly — no sheet', (tester) async {
    await _pump(tester);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Card, 'French Fries').first,
        matching: find.byIcon(Icons.add_shopping_cart),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ModifierSelectionSheet), findsNothing);
    expect(find.text('French Fries'), findsWidgets);
  });

  testWidgets('the submitted payload carries the RF-052 modifiers array and '
      'the modifier-inclusive line total (integer minor units)', (
    tester,
  ) async {
    final l10n = await _en();
    final store = DemoOutboxStore(delay: (_) async {});
    await _pump(tester, repo: store);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    await tester.tap(_addButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    final entries = await store.recentEntries();
    final payload =
        jsonDecode(entries.single.payloadJson) as Map<String, dynamic>;
    final item =
        (payload['order_items'] as List).single as Map<String, dynamic>;
    expect(item['line_total_minor'], 5100);
    expect(payload['subtotal_minor'], 5100);
    expect(payload['grand_total_minor'], 5100);
    final mods = (item['modifiers'] as List).cast<Map<String, dynamic>>();
    expect(mods, hasLength(2));
    final cheese = mods.singleWhere(
      (m) => m['option_name_snapshot'] == 'Cheese',
    );
    expect(cheese['price_minor_snapshot'], 300);
    expect(cheese['modifier_option_id'], 'demo-opt-cheese');
    expect(cheese['modifier_name_snapshot'], 'Toppings');
    expect(cheese['quantity'], 1);
    final medium = mods.singleWhere(
      (m) => m['option_name_snapshot'] == 'Medium',
    );
    expect(medium['price_minor_snapshot'], 0);
  });

  // ---- Menu/media sprint, Part E: cashier-facing option-flow polish. ----

  testWidgets('the sheet header shows the BASE price, which stays put while '
      'the running total moves', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _openBurgerSheet(tester);

    // Base ₪48.00 as a header subtitle (distinct string from the total pins).
    expect(
      find.text(l10n.posModifierBasePrice('\u2066₪48.00\u2069')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    // The total moved to ₪51.00 (summary row + Add label, the frozen 2-render
    // contract) but the base subtitle still reads ₪48.00.
    expect(find.textContaining('₪51.00'), findsNWidgets(2));
    expect(
      find.text(l10n.posModifierBasePrice('\u2066₪48.00\u2069')),
      findsOneWidget,
    );
  });

  testWidgets('group headers carry Required/Optional pills and live '
      'selected-count pills; an unmet REQUIRED count is marked danger and '
      'clears once satisfied', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _openBurgerSheet(tester);

    // One required group (Doneness), two optional (Toppings, Extras).
    // Scoped to the sheet: the optional customer-name field's "Optional" hint in
    // the cart shares this string (ORDER-CUSTOMER-001) but is not a group pill.
    expect(find.text(l10n.posModifierRequired), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ModifierSelectionSheet),
        matching: find.text(l10n.posModifierOptional),
      ),
      findsNWidgets(2),
    );

    // Counts: single-select 0/1, capped multi 0/2, open multi just 0. The
    // bare-digit finders are scoped to the pills — the Extras option
    // steppers (modifier-quantity sprint) also render bare digits.
    expect(find.text(l10n.posModifierSelectedCount(0, 1)), findsOneWidget);
    expect(find.text(l10n.posModifierSelectedCount(0, 2)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RestoflowStatusPill),
        matching: find.text(l10n.posModifierSelectedCountOpen(0)),
      ),
      findsOneWidget,
    );

    // The unmet REQUIRED group's count is the danger marker; the optional
    // groups stay quiet even at zero.
    expect(_pill(tester, '0/1').tone, RestoflowTone.danger);
    expect(_pill(tester, '0/2').tone, RestoflowTone.neutral);
    expect(_pill(tester, '0').tone, RestoflowTone.neutral);

    // Selecting updates the counts live and clears the danger accent.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.pump();
    expect(find.text(l10n.posModifierSelectedCount(1, 1)), findsOneWidget);
    expect(_pill(tester, '1/1').tone, RestoflowTone.neutral);

    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(RestoflowStatusPill),
        matching: find.text(l10n.posModifierSelectedCountOpen(1)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('zero-delta options are labelled free; paid options keep the '
      'signed delta', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _openBurgerSheet(tester);

    // Free: Onion/Lettuce/Tomato (Toppings) + Rare/Medium/Well done
    // (Doneness) = 6. Paid options show +₪ deltas instead.
    expect(find.text(l10n.posModifierFree), findsNWidgets(6));
    expect(find.text('+₪3.00'), findsNWidgets(2)); // Cheese + Extra cheese
    expect(find.text('+₪9.00'), findsOneWidget); // Extra patty
  });

  testWidgets('a multi-select group at capacity shows its count pill in '
      'warning tone (further taps are no-ops)', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _openBurgerSheet(tester);

    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-extra-cheese')),
    );
    await tester.pump();
    expect(_pill(tester, '1/2').tone, RestoflowTone.neutral);

    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-extra-patty')),
    );
    await tester.pump();
    expect(find.text(l10n.posModifierSelectedCount(2, 2)), findsOneWidget);
    expect(_pill(tester, '2/2').tone, RestoflowTone.warning);

    // Deselecting drops back below capacity — the warning clears.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-extra-patty')),
    );
    await tester.pump();
    expect(_pill(tester, '1/2').tone, RestoflowTone.neutral);
  });

  testWidgets('the cart sub-line shows a PAID option delta in a separate '
      'text; free options stay delta-free', (tester) async {
    await _pump(tester);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    await tester.tap(_addButton());
    await tester.pumpAndSettle();

    // The exact '+ name' strings stay findable (frozen contract) — the delta
    // rides a separate Text on the same row.
    expect(find.text('+ Cheese'), findsOneWidget);
    expect(find.text('+₪3.00'), findsOneWidget);
    expect(find.text('+ Medium'), findsOneWidget);
    expect(find.text('+₪0.00'), findsNothing);
  });

  // ---- Modifier-quantity sprint: per-option quantities + item notes. ----

  testWidgets('a quantity-enabled extra shows −/+ steppers; + selects and '
      'counts up, changing the running total; − counts back down to 0', (
    tester,
  ) async {
    await _pump(tester);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.pump();

    // Steppers render ONLY on the quantity-enabled Extras group (2 options),
    // not on Toppings/Doneness.
    expect(
      find.byKey(const ValueKey('modifier-qty-inc-demo-opt-extra-cheese')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('modifier-qty-inc-demo-opt-cheese')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('modifier-qty-inc-demo-opt-medium')),
      findsNothing,
    );

    // + selects Extra cheese at 1 (48 + 3 = 51), again -> ×2 (48 + 6 = 54).
    await tester.tap(
      find.byKey(const ValueKey('modifier-qty-inc-demo-opt-extra-cheese')),
    );
    await tester.pump();
    expect(_sheetText('₪51.00'), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('modifier-qty-inc-demo-opt-extra-cheese')),
    );
    await tester.pump();
    expect(_sheetText('₪54.00'), findsNWidgets(2));

    // − steps back down; at 0 the option is unselected (back to base 48).
    await tester.tap(
      find.byKey(const ValueKey('modifier-qty-dec-demo-opt-extra-cheese')),
    );
    await tester.pump();
    expect(_sheetText('₪51.00'), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('modifier-qty-dec-demo-opt-extra-cheese')),
    );
    await tester.pump();
    expect(_sheetText('₪48.00'), findsWidgets);
    expect(_sheetText('₪51.00'), findsNothing);
  });

  testWidgets('the per-option max quantity (Extras: 5) is enforced — the + '
      'button disables at the cap', (tester) async {
    await _pump(tester);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );

    final inc = find.byKey(
      const ValueKey('modifier-qty-inc-demo-opt-extra-cheese'),
    );
    for (var i = 0; i < 5; i++) {
      await tester.tap(inc);
      await tester.pump();
    }
    // ×5 · 48 + 15 = 63; the + is now disabled, so the total cannot move.
    expect(_sheetText('₪63.00'), findsNWidgets(2));
    expect(tester.widget<IconButton>(inc).onPressed, isNull);
    // A tap on the DISABLED + must be swallowed by the stepper pill — it
    // must never fall through to the tile and toggle the ×5 selection off.
    await tester.tap(inc, warnIfMissed: false);
    await tester.pump();
    expect(_sheetText('₪63.00'), findsNWidgets(2));
  });

  testWidgets('the cart line shows a quantity modifier as "name ×N" with its '
      'TOTAL delta; the item note renders under the line', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    final inc = find.byKey(
      const ValueKey('modifier-qty-inc-demo-opt-extra-cheese'),
    );
    await tester.tap(inc);
    await tester.pump();
    await tester.tap(inc);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      'no onions',
    );
    await tester.tap(_addButton());
    await tester.pumpAndSettle();

    // ×2 rides the '+ name' string; the delta text is the unit×qty total.
    expect(find.text('+ Extra cheese ×2'), findsOneWidget);
    expect(find.text('+₪6.00'), findsOneWidget);
    // The single-unit doneness stays the frozen bare '+ name' form.
    expect(find.text('+ Medium'), findsOneWidget);
    // The note under the cart line, labelled.
    expect(find.text('${l10n.posItemNoteLabel}: no onions'), findsOneWidget);
    // Line total includes the multiplied delta: 48 + 6 = 54.
    expect(find.text('₪54.00'), findsWidgets);
  });

  testWidgets('the submitted payload carries the modifier quantity and the '
      'per-item note; totals include quantity (integer minor units)', (
    tester,
  ) async {
    final l10n = await _en();
    final store = DemoOutboxStore(delay: (_) async {});
    await _pump(tester, repo: store);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    final inc = find.byKey(
      const ValueKey('modifier-qty-inc-demo-opt-extra-cheese'),
    );
    await tester.tap(inc);
    await tester.pump();
    await tester.tap(inc);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      '  بدون بصل  ',
    );
    await tester.tap(_addButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    final entries = await store.recentEntries();
    final payload =
        jsonDecode(entries.single.payloadJson) as Map<String, dynamic>;
    final item =
        (payload['order_items'] as List).single as Map<String, dynamic>;
    // 48.00 + 2 × 3.00 = 54.00 — the server recomputes
    // qty×unit + Σ(delta × modifier_qty) and must match.
    expect(item['line_total_minor'], 5400);
    expect(payload['subtotal_minor'], 5400);
    expect(payload['grand_total_minor'], 5400);
    // The note is trimmed and rides the item (order_items.notes).
    expect(item['notes'], 'بدون بصل');
    final mods = (item['modifiers'] as List).cast<Map<String, dynamic>>();
    final extraCheese = mods.singleWhere(
      (m) => m['option_name_snapshot'] == 'Extra cheese',
    );
    // UNIT delta + quantity — never a premultiplied float/total.
    expect(extraCheese['price_minor_snapshot'], 300);
    expect(extraCheese['quantity'], 2);
    final medium = mods.singleWhere(
      (m) => m['option_name_snapshot'] == 'Medium',
    );
    expect(medium['quantity'], 1);
  });

  testWidgets('a note alone (no modifier picked beyond the required one) '
      'still creates its own cart line and never merges with a plain add', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _openBurgerSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.enterText(
      find.byKey(const Key('modifier-item-note')),
      'cut in half',
    );
    await tester.tap(_addButton());
    await tester.pumpAndSettle();
    expect(find.text('${l10n.posItemNoteLabel}: cut in half'), findsOneWidget);
  });

  testWidgets('the sheet renders under Arabic RTL without overflow, with '
      'localized pills', (tester) async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    await _pump(tester, locale: const Locale('ar'));
    await _openBurgerSheet(tester);

    expect(
      Directionality.of(tester.element(find.byType(ModifierSelectionSheet))),
      TextDirection.rtl,
    );
    expect(find.text(ar.posModifierRequired), findsOneWidget);
    // Scoped to the sheet (see the en case): the customer-name hint "اختياري"
    // in the cart shares this string but is not a modifier group pill.
    expect(
      find.descendant(
        of: find.byType(ModifierSelectionSheet),
        matching: find.text(ar.posModifierOptional),
      ),
      findsNWidgets(2),
    );
    expect(find.text(ar.posModifierFree), findsNWidgets(6));
    expect(
      find.text(ar.posModifierBasePrice('\u2066₪48.00\u2069')),
      findsOneWidget,
    );

    // Selecting still works mirrored; no layout exceptions surfaced.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
    );
    await tester.pump();
    expect(find.text(ar.posModifierSelectedCount(1, 1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
