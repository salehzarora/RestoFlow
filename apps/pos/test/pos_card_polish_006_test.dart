import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart'
    show kPosTotalsBed;
import 'package:restoflow_pos/src/pos_menu_screen.dart' show posMenuCardExtent;
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// POS-THEME-NAVBAR-POLISH-006 — the two product-card refinements:
///  A. the COMPACT action footer: a 38px visible bar inside an unchanged
///     44px layout/hit zone, with every add behavior and gate intact;
///  B. the FULL uncropped product image: `BoxFit.contain` (the POS was the
///     cropper via `cover`), original aspect preserved, quiet letterbox
///     bands, fallback/error behavior unchanged.
void main() {
  DemoMenuItem item({
    String id = 'p-1',
    String? imageUrl,
    String? description = 'Slow-roasted with tahini and sumac onion relish.',
    String availability = 'available',
    String? reason,
  }) => DemoMenuItem(
    id: id,
    name: 'Lamb Shawarma',
    priceMinor: 5400,
    categoryId: 'mains',
    categoryName: 'Mains',
    description: description,
    imageUrl: imageUrl,
    availability: availability,
    availabilityReason: reason,
  );

  Future<AppLocalizations> pump(
    WidgetTester tester,
    DemoMenuItem card, {
    VoidCallback? onAdd,
    int inCartQuantity = 0,
    double width = 220,
    double scale = 1.0,
  }) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: app!,
        ),
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: posMenuCardExtent(width),
                  child: MenuItemCard(
                    item: card,
                    onAdd: onAdd ?? () {},
                    inCartQuantity: inCartQuantity,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return l10n;
  }

  group('A. the compact action footer', () {
    testWidgets('A1. the visible bar is 38px inside an unchanged 44px hit '
        'zone', (tester) async {
      await pump(tester, item());
      // The hit/layout zone: the FilledButton still measures >=44 tall.
      final button = find.ancestor(
        of: find.byIcon(Icons.add_shopping_cart),
        matching: find.byType(FilledButton),
      );
      expect(tester.getSize(button.first).height, greaterThanOrEqualTo(44));
      // The visible bar: the decorated sibling is exactly the zone minus the
      // two 3px transparent insets — visually ~38px.
      final zone = find
          .ancestor(of: button.first, matching: find.byType(Stack))
          .first;
      final bar = find.descendant(
        of: zone,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              ((w.decoration as BoxDecoration).gradient != null ||
                  (w.decoration as BoxDecoration).color != null),
        ),
      );
      expect(tester.getSize(bar.first).height, 38);
    });

    testWidgets('A2. Add / Add More / Unavailable behavior is unchanged', (
      tester,
    ) async {
      var added = 0;
      final l10n = await pump(tester, item(), onAdd: () => added++);
      await tester.tap(find.byIcon(Icons.add_shopping_cart));
      expect(added, 1);
      expect(find.text(l10n.posAddToCart), findsOneWidget);

      // In cart: the tonal Add-more treatment, same callback.
      await pump(tester, item(), onAdd: () => added++, inCartQuantity: 2);
      expect(find.text(l10n.posAddMore), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_shopping_cart));
      expect(added, 2);

      // Unavailable: no add glyph, dead tap, same 44px footer zone.
      var blocked = 0;
      await pump(
        tester,
        item(availability: 'unavailable', reason: 'sold_out'),
        onAdd: () => blocked++,
      );
      expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
      await tester.tap(find.byKey(const Key('menu-item-p-1')));
      expect(blocked, 0);
    });

    testWidgets('A3. the description gets TWO lines at ordinary scale and the '
        'card stays overflow-free at 2x', (tester) async {
      await pump(tester, item());
      final desc = tester.widget<Text>(
        find.text('Slow-roasted with tahini and sumac onion relish.'),
      );
      expect(desc.maxLines, 2, reason: 'the compact footer bought a line');
      expect(tester.takeException(), isNull);

      // 2x: the slot yields entirely; nothing overflows.
      await pump(tester, item(), scale: 2.0);
      expect(
        find.text('Slow-roasted with tahini and sumac onion relish.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('B. the full uncropped product image', () {
    testWidgets('B1. the card photo uses CONTAIN — never cover/crop/zoom — '
        'centered on a quiet letterbox bed', (tester) async {
      await pump(tester, item(imageUrl: 'https://img.example/x.png'));
      // (cacheWidth wraps the NetworkImage in a ResizeImage — find by type.)
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain, reason: 'the POS must not crop');
      expect(image.alignment, Alignment.center);
      // The letterbox bed behind the photo is the quiet warm neutral.
      final bed = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.byWidget(image),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(bed.color, kPosTotalsBed);
    });

    testWidgets('B2. a failed image still falls back to the designed '
        'category band (unchanged)', (tester) async {
      // The test HTTP client refuses every request, so the network image
      // errors — the errorBuilder must render the tinted category scene
      // (its composed soft circles), and the card stays healthy.
      await pump(tester, item(imageUrl: 'https://img.example/broken.png'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final circles = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
      expect(circles, findsWidgets, reason: 'the designed fallback scene');
      expect(find.text('Lamb Shawarma'), findsOneWidget);
    });

    testWidgets('B3. the no-image fallback is untouched', (tester) async {
      await pump(tester, item());
      expect(find.byType(AspectRatio), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
