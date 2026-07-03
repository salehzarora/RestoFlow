import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// Menu/media sprint (Part F): POS cards read like sellable products — up to
/// TWO tiny localized tag pills overlay the image/icon band (spicy/popular
/// prioritized; wire strings never rendered raw) and a compact has-options
/// indicator (tune icon + group count) sits by the price for items whose add
/// opens the modifier sheet. Contracts stay frozen: the tile is a Card, the
/// canonical add gesture is the single Icons.add_shopping_cart per card,
/// Classic Burger stays the FIRST and PLAIN grid item, and no new Icons.add
/// enters the tree.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void _useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrapCard(Widget card) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: Scaffold(body: SizedBox(width: 220, height: 188, child: card)),
);

void main() {
  testWidgets('demo grid: Cheeseburger shows a localized tag pill + the '
      'has-options indicator; Classic Burger stays first and plain', (
    tester,
  ) async {
    final l10n = await _en();
    _useWideSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const PosMenuScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cheeseburger = find.widgetWithText(Card, 'Cheeseburger').first;
    // The demo Cheeseburger carries the 'popular' tag -> its LOCALIZED pill.
    expect(
      find.descendant(
        of: cheeseburger,
        matching: find.text(l10n.menuTagPopular),
      ),
      findsOneWidget,
    );
    // Three demo modifier groups -> tune icon + count + localized tooltip.
    expect(
      find.descendant(of: cheeseburger, matching: find.byIcon(Icons.tune)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cheeseburger, matching: find.text('3')),
      findsOneWidget,
    );
    expect(find.byTooltip(l10n.menuModifierGroupCount(3)), findsOneWidget);

    // Classic Burger: no tags, no groups -> nothing extra, and it keeps the
    // canonical single add icon (the .first add-tap corpus relies on it).
    final classic = find.widgetWithText(Card, 'Classic Burger').first;
    expect(
      find.descendant(of: classic, matching: find.byIcon(Icons.tune)),
      findsNothing,
    );
    expect(
      find.descendant(of: classic, matching: find.byType(RestoflowStatusPill)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: classic,
        matching: find.byIcon(Icons.add_shopping_cart),
      ),
      findsOneWidget,
    );
    // The indicator introduces NO Icons.add (the cart stepper must stay the
    // only one once a line exists).
    expect(find.byIcon(Icons.add), findsNothing);

    // The first grid add is STILL the plain Classic Burger one-tap add (no
    // sheet in the way).
    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();
    final subtotal = tester.widget<Text>(
      find.byKey(const Key('cart-subtotal')),
    );
    expect(subtotal.data, '₪42.00');
  });

  testWidgets('tag pills cap at TWO with spicy/popular prioritized', (
    tester,
  ) async {
    final l10n = await _en();
    const item = DemoMenuItem(
      id: 'loaded',
      name: 'Loaded Burger',
      priceMinor: 5000,
      categoryId: 'burgers',
      categoryName: 'Burgers',
      // Deliberately listed in reverse priority + an unknown wire value that
      // must NEVER render raw.
      tags: <String>['new', 'vegetarian', 'popular', 'spicy', 'mystery-tag'],
    );
    await tester.pumpWidget(_wrapCard(MenuItemCard(item: item, onAdd: () {})));
    await tester.pumpAndSettle();

    expect(find.text(l10n.menuTagSpicy), findsOneWidget);
    expect(find.text(l10n.menuTagPopular), findsOneWidget);
    expect(find.text(l10n.menuTagVegetarian), findsNothing);
    expect(find.text(l10n.menuTagNew), findsNothing);
    expect(find.text('mystery-tag'), findsNothing);
    expect(find.byType(RestoflowStatusPill), findsNWidgets(2));
  });

  testWidgets('an imaged card keeps pills + indicator over the fallback band '
      'when the image cannot load, and price/add contracts hold', (
    tester,
  ) async {
    final l10n = await _en();
    const item = DemoMenuItem(
      id: 'spicy-burger',
      name: 'Spicy Burger',
      priceMinor: 4600,
      categoryId: 'burgers',
      categoryName: 'Burgers',
      // The test HTTP client rejects every request -> errorBuilder fallback.
      imageUrl: 'https://storage.example/signed/img-9.png',
      tags: <String>['spicy'],
    );
    await tester.pumpWidget(
      _wrapCard(MenuItemCard(item: item, onAdd: () {}, optionGroupCount: 2)),
    );
    await tester.pumpAndSettle();

    // Fallback icon band rendered; pill and indicator still overlay/attach.
    expect(find.byIcon(Icons.lunch_dining), findsOneWidget);
    expect(find.text(l10n.menuTagSpicy), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // Frozen contracts: Card, name, integer-minor price, the single add icon.
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Spicy Burger'), findsOneWidget);
    expect(find.text('₪46.00'), findsOneWidget);
    expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
  });
}
