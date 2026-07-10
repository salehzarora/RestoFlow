import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// TABLET-UX-001 (A): every cart line carries an Edit action that reopens the
/// SAME customization sheet prefilled with the line's current modifiers/note;
/// saving REPLACES the line (never a duplicate) and the total recomputes, while
/// Cancel leaves the cart unchanged and Remove still works.

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

Finder _addButton() => find.byKey(const Key('modifier-add-button'));

/// The EXACT running-total string inside the sheet (the summary row). Exact —
/// not `textContaining` — so a total that equals the base price never also
/// matches the "Base price · ₪…" header subtitle.
Finder _sheetTotal(String text) => find.descendant(
  of: find.byType(ModifierSelectionSheet),
  matching: find.text(text),
);

/// Adds a Cheeseburger configured as Medium + Cheese (₪48 + ₪3 = ₪51), with an
/// optional [note], leaving a single cart line.
Future<void> _addConfiguredBurger(WidgetTester tester, {String? note}) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(Card, 'Cheeseburger').first,
      matching: find.byIcon(Icons.add_shopping_cart),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('modifier-option-demo-opt-medium')),
  );
  await tester.tap(
    find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
  );
  await tester.pump();
  if (note != null) {
    await tester.enterText(find.byKey(const Key('modifier-item-note')), note);
  }
  await tester.tap(_addButton());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every cart line shows an Edit action', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _addConfiguredBurger(tester);

    expect(find.byTooltip(l10n.posCartEditItem), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('tapping Edit opens the sheet prefilled with the current '
      'modifiers + note, with a Save label', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _addConfiguredBurger(tester, note: 'no onions');

    await tester.tap(find.byTooltip(l10n.posCartEditItem));
    await tester.pumpAndSettle();

    // The customization sheet reopened, prefilled.
    expect(find.byType(ModifierSelectionSheet), findsOneWidget);
    // Prefilled total = base ₪48 + Cheese ₪3 = ₪51 (edit shows it once, in the
    // summary row — the button now reads "Save changes", not the total).
    expect(_sheetTotal('₪51.00'), findsOneWidget);
    expect(find.text(l10n.posEditSaveChanges), findsOneWidget);
    // The note is restored into the field.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('modifier-item-note')))
          .controller!
          .text,
      'no onions',
    );
  });

  testWidgets('saving an edit updates the SAME line, not a duplicate, and the '
      'total recomputes', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _addConfiguredBurger(tester);
    expect(find.text('+ Cheese'), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.posCartEditItem));
    await tester.pumpAndSettle();
    // Deselect Cheese -> back to ₪48.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    expect(_sheetTotal('₪48.00'), findsOneWidget);
    await tester.tap(_addButton());
    await tester.pumpAndSettle();

    // Still ONE cart line (one Edit button), the Cheese sub-line is gone, and
    // the total dropped to ₪48.
    expect(find.byTooltip(l10n.posCartEditItem), findsOneWidget);
    expect(find.text('+ Cheese'), findsNothing);
    expect(find.text('₪48.00'), findsWidgets);
  });

  testWidgets('cancelling the edit (dismiss) leaves the cart unchanged', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _addConfiguredBurger(tester);

    await tester.tap(find.byTooltip(l10n.posCartEditItem));
    await tester.pumpAndSettle();
    // Change a selection in the sheet…
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-cheese')),
    );
    await tester.pump();
    expect(_sheetTotal('₪48.00'), findsOneWidget);
    // …then dismiss WITHOUT saving (tap the modal scrim above the sheet).
    await tester.tapAt(const Offset(30, 30));
    await tester.pumpAndSettle();

    // The cart line is unchanged: Cheese still there, total still ₪51.
    expect(find.byType(ModifierSelectionSheet), findsNothing);
    expect(find.text('+ Cheese'), findsOneWidget);
    expect(find.text('₪51.00'), findsWidgets);
  });

  testWidgets('remove still works from a cart line', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _addConfiguredBurger(tester);

    await tester.tap(find.byTooltip(l10n.posRemoveItem));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posCartEmpty), findsOneWidget);
    expect(find.byTooltip(l10n.posCartEditItem), findsNothing);
  });

  testWidgets('editing to a paid option updates the total and the submitted '
      'payload (integer minor units)', (tester) async {
    final l10n = await _en();
    final store = DemoOutboxStore(delay: (_) async {});
    await _pump(tester, repo: store);
    await _addConfiguredBurger(tester); // Medium + Cheese = ₪51

    await tester.tap(find.byTooltip(l10n.posCartEditItem));
    await tester.pumpAndSettle();
    // Add Extra patty (+₪9) -> ₪60.
    await tester.tap(
      find.byKey(const ValueKey('modifier-option-demo-opt-extra-patty')),
    );
    await tester.pump();
    expect(_sheetTotal('₪60.00'), findsOneWidget);
    await tester.tap(_addButton());
    await tester.pumpAndSettle();
    expect(find.text('₪60.00'), findsWidgets);

    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    final entries = await store.recentEntries();
    final payload =
        jsonDecode(entries.single.payloadJson) as Map<String, dynamic>;
    final item =
        (payload['order_items'] as List).single as Map<String, dynamic>;
    expect(item['line_total_minor'], 6000); // 4800 + 300 + 900
    expect(payload['subtotal_minor'], 6000);
    final mods = (item['modifiers'] as List).cast<Map<String, dynamic>>();
    expect(
      mods.map((m) => m['option_name_snapshot']),
      containsAll(<String>['Medium', 'Cheese', 'Extra patty']),
    );
  });

  testWidgets('the Edit action renders under Arabic RTL', (tester) async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    await _pump(tester, locale: const Locale('ar'));
    await _addConfiguredBurger(tester);

    expect(find.byTooltip(ar.posCartEditItem), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byIcon(Icons.edit_outlined))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
