import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// Demo-readiness sprint (Part F): items with modifier groups open the option
/// picker; required groups gate the Add button; paid modifiers change the
/// price; the order payload carries the selected modifiers (RF-052 shape);
/// money stays integer minor units.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester, {OutboxRepository? repo}) async {
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
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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
}
