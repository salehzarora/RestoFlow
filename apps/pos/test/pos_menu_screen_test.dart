import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

Widget _wrap(Locale locale) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const PosMenuScreen(),
  ),
);

void _useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders the demo menu grid and an empty cart', (tester) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Classic Burger'), findsOneWidget);
    expect(find.text('Cola'), findsOneWidget);
    expect(find.byIcon(Icons.add_shopping_cart), findsWidgets);
    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Send Order'), findsOneWidget);
  });

  testWidgets('tapping add puts the item in the cart and shows the subtotal', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    // First card is Classic Burger (₪42.00).
    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsNothing);
    // Appears in both the menu card and the cart line.
    expect(find.text('Classic Burger'), findsNWidgets(2));
    expect(find.text('Subtotal'), findsOneWidget);
    final subtotal = tester.widget<Text>(
      find.byKey(const Key('cart-subtotal')),
    );
    expect(subtotal.data, '₪42.00');
  });

  testWidgets('quantity stepper and clear update the cart', (tester) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();

    // The cart stepper "+" is the only Icons.add in the tree.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    final subtotal = tester.widget<Text>(
      find.byKey(const Key('cart-subtotal')),
    );
    expect(subtotal.data, '₪84.00');

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('category chips filter the menu grid', (tester) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Classic Burger'), findsOneWidget);
    expect(find.text('Espresso'), findsOneWidget);

    // Filter to Coffee only.
    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Burger'), findsNothing);
    expect(find.text('Espresso'), findsOneWidget);
    expect(find.text('Cappuccino'), findsOneWidget);
  });

  testWidgets('Send Order shows a demo notice and does not submit', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send Order'));
    await tester.pump(); // surface the snackbar

    expect(
      find.text('Demo only — order submission comes in a later step.'),
      findsOneWidget,
    );
    // The cart is untouched — no backend submit cleared it.
    expect(find.text('Classic Burger'), findsNWidgets(2));
  });
}
