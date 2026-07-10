import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';

/// TABLET-UX-001 (B): on the landscape/tablet side cart the line rows are DENSE
/// (the '× qty · unit' meta folds onto the controls row) so more of the order is
/// visible, the Edit/Remove/Send controls stay accessible, and nothing overflows
/// on common tablet sizes — in LTR and RTL.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
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

Future<void> _addPlain(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(Card, name).first,
      matching: find.byIcon(Icons.add_shopping_cart),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addConfiguredBurger(WidgetTester tester) async {
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
  await tester.tap(find.byKey(const Key('modifier-add-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the landscape side cart uses the dense row: the "× qty · unit" '
      'meta shares the controls row with the Edit action', (tester) async {
    final l10n = await _en();
    await _pump(tester, size: const Size(1280, 800)); // tablet landscape
    // The two-pane side cart is shown (not the phone bottom bar).
    expect(find.byType(CartPanel), findsOneWidget);

    await _addConfiguredBurger(tester);

    // Dense: the meta text and the Edit action sit on the SAME row (≈ same Y),
    // proving the folded compact layout (roomy would stack them vertically).
    final metaY = tester
        .getCenter(find.text(l10n.posCartQtyUnit(1, '₪48.00')))
        .dy;
    final editY = tester.getCenter(find.byIcon(Icons.edit_outlined)).dy;
    expect((metaY - editY).abs(), lessThan(8.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('several items fit the side cart without overflow, controls '
      'stay accessible (1280×800)', (tester) async {
    final l10n = await _en();
    await _pump(tester, size: const Size(1280, 800));

    // Top-row items so the menu cards stay on-screen at this short viewport.
    await _addPlain(tester, 'Classic Burger');
    await _addPlain(tester, 'Double Bacon Burger');
    await _addPlain(tester, 'Veggie Burger');
    await _addPlain(tester, 'Grilled Chicken');

    // No layout overflow, and the key controls remain on screen.
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.edit_outlined), findsWidgets); // Edit
    expect(find.byIcon(Icons.delete_outline), findsWidgets); // Remove
    expect(find.text(l10n.posSendOrder), findsOneWidget); // Submit
  });

  testWidgets('no overflow on a large tablet (1920×1200)', (tester) async {
    await _pump(tester, size: const Size(1920, 1200));
    await _addPlain(tester, 'Classic Burger');
    await _addPlain(tester, 'Double Bacon Burger');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dense side cart renders under Arabic RTL without overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(1280, 800),
      locale: const Locale('ar'),
    );
    await _addConfiguredBurger(tester);
    expect(
      Directionality.of(tester.element(find.byType(CartPanel))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
