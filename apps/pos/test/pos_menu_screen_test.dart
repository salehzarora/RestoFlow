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

  testWidgets('Send Order shows the local order confirmation', (tester) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    // Add Classic Burger (₪42.00) and submit.
    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Order'));
    await tester.pumpAndSettle();

    // Confirmation replaces the cart.
    expect(find.text('Order sent'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    // POS-ORDERS-AND-PAYMENT-001: the unpaid-branch reset action is now the
    // explicit "Pay later" (leaves the order unpaid + starts the next order).
    expect(find.text('Pay later'), findsOneWidget);
    expect(find.text('Send Order'), findsNothing);

    final orderNumber = tester.widget<Text>(
      find.byKey(const Key('order-number')),
    );
    expect(orderNumber.data, 'DEMO-0001');

    final subtotal = tester.widget<Text>(
      find.byKey(const Key('confirmation-subtotal')),
    );
    expect(subtotal.data, '₪42.00');

    expect(
      find.text('Demo order — not sent to a backend, kitchen, or printer.'),
      findsOneWidget,
    );
  });

  testWidgets('Pay later returns to the empty cart', (tester) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Order'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pay-later-button')));
    await tester.pumpAndSettle();

    expect(find.text('Order sent'), findsNothing);
    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Send Order'), findsOneWidget);
  });

  testWidgets('adding an item after confirmation starts a fresh order', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Order'));
    await tester.pumpAndSettle();
    expect(find.text('Order sent'), findsOneWidget);

    // Tapping a menu item dismisses the confirmation and starts a new cart.
    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();

    expect(find.text('Order sent'), findsNothing);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Send Order'), findsOneWidget);
  });
}
