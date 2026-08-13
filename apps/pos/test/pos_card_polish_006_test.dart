import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart'
    show kPosTotalsBed, kPosImageTileRadius;
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

    testWidgets('A4. every ladder bucket fits the fixed body budget — the '
        'tight 1.15 and 1.6 scales stay overflow-free', (tester) async {
      // 007 verify finding: the tightest buckets (two 30px lines at 1.15;
      // one 19px line + a taller row at 1.6) had no coverage.
      for (final scale in const [1.0, 1.15, 1.3, 1.6, 2.0]) {
        await pump(tester, item(), scale: scale);
        expect(
          tester.takeException(),
          isNull,
          reason: 'card overflowed at textScale $scale',
        );
      }
    });
  });

  group('B. the full uncropped product image', () {
    testWidgets('B1. SMART CONTAIN (008): the crisp foreground stays the '
        'complete CONTAIN-fit photo; the SAME source fills the bands as a '
        'subordinate COVER echo under a scrim', (tester) async {
      await pump(tester, item(imageUrl: 'https://img.example/x.png'));
      // Exactly TWO layers of the ONE image.
      final images = tester
          .widgetList<Image>(find.byType(Image))
          .toList(growable: false);
      expect(images, hasLength(2));
      final background = images.first;
      final foreground = images.last;
      // Foreground = source of truth: contain, centered, never cropped.
      expect(foreground.fit, BoxFit.contain, reason: 'the POS must not crop');
      expect(foreground.alignment, Alignment.center);
      // Background = the fill echo: cover, painted UNDER the foreground.
      expect(background.fit, BoxFit.cover);
      // Both layers resolve the SAME provider (same URL, same cacheWidth →
      // one cached decode). cacheWidth wraps NetworkImage in ResizeImage.
      String urlOf(Image i) {
        final p = i.image;
        return p is ResizeImage
            ? (p.imageProvider as NetworkImage).url
            : (p as NetworkImage).url;
      }

      expect(urlOf(background), urlOf(foreground));
      expect(background.image, equals(foreground.image));
      // The subordination scrim sits BETWEEN the two layers.
      final stack = find
          .ancestor(of: find.byType(Image).first, matching: find.byType(Stack))
          .first;
      expect(
        find.descendant(
          of: stack,
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == const Color(0xB8FBFAF6),
          ),
        ),
        findsOneWidget,
      );
      // The warm bed remains the base under everything.
      final bed = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.byWidget(foreground),
              matching: find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == kPosTotalsBed,
              ),
            )
            .first,
      );
      expect(bed.color, kPosTotalsBed);
    });

    testWidgets('B2. a failed image still falls back to the designed '
        'category band (unchanged)', (tester) async {
      // The test HTTP client refuses every request, so the network image
      // errors — the FOREGROUND's errorBuilder must render the tinted
      // category scene (its composed soft circles) while the BACKGROUND
      // layer renders NOTHING (008: never two fallbacks), and the card
      // stays healthy.
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
      // Exactly ONE category glyph inside the band — the background layer
      // must not have produced a duplicate fallback scene.
      expect(
        find.descendant(
          of: find.byType(AspectRatio),
          matching: find.byWidgetPredicate((w) => w is Icon),
        ),
        findsOneWidget,
      );
    });

    testWidgets('B3. the no-image fallback is untouched', (tester) async {
      await pump(tester, item());
      expect(find.byType(AspectRatio), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('C. the frameless floating tile (POS-FRAMELESS-CARD-POLISH-007)', () {
    Card cardOf(WidgetTester tester) =>
        tester.widget<Card>(find.byType(Card).first);

    BoxDecoration shellDecoration(WidgetTester tester) =>
        tester
                .widget<AnimatedContainer>(
                  find
                      .ancestor(
                        of: find.byType(Card).first,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    testWidgets('C1. REST state: no fill, no perimeter border, no shadow — '
        'the workspace is the base', (tester) async {
      await pump(tester, item());
      final card = cardOf(tester);
      expect(card.color, Colors.transparent);
      final side = (card.shape! as RoundedRectangleBorder).side;
      expect(side.color, Colors.transparent, reason: 'no always-on frame');
      expect(shellDecoration(tester).boxShadow, isNull);
    });

    testWidgets('C2. HOVER introduces the lift + faint edge with ZERO '
        'geometry change', (tester) async {
      await pump(tester, item());
      final before = tester.getSize(find.byType(Card).first);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(MenuItemCard)));
      await tester.pumpAndSettle();

      final card = cardOf(tester);
      final side = (card.shape! as RoundedRectangleBorder).side;
      expect(side.color, isNot(Colors.transparent), reason: 'faint edge');
      expect(shellDecoration(tester).boxShadow, isNotNull, reason: 'lift');
      expect(
        tester.getSize(find.byType(Card).first),
        before,
        reason: 'hover must never move geometry under the finger',
      );
    });

    testWidgets('C3. the image tile wears the asymmetric directional '
        'silhouette + its own soft resting shadow, and the no-image fallback '
        'shares it', (tester) async {
      await pump(tester, item());
      final clip = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(AspectRatio),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      final radius = clip.borderRadius as BorderRadiusDirectional;
      expect(radius.topStart, const Radius.circular(16));
      expect(radius.topEnd, const Radius.circular(16));
      expect(radius.bottomEnd, const Radius.circular(16));
      expect(
        radius.bottomStart,
        const Radius.circular(5),
        reason: 'ONE small corner at the bottom inline-START — the signature',
      );
      // The tile floats: a soft rest shadow on the band's own decoration.
      final tile = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byWidget(clip),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((tile.decoration as BoxDecoration).boxShadow, isNotNull);
    });

    testWidgets('C4. the asymmetry is DIRECTIONAL: the small corner sits on '
        'the physical RIGHT in RTL and the LEFT in LTR', (tester) async {
      const radius = kPosImageTileRadius;
      final rtl = radius.resolve(TextDirection.rtl);
      final ltr = radius.resolve(TextDirection.ltr);
      expect(rtl.bottomRight, const Radius.circular(5));
      expect(rtl.bottomLeft, const Radius.circular(16));
      expect(ltr.bottomLeft, const Radius.circular(5));
      expect(ltr.bottomRight, const Radius.circular(16));
    });
  });
}
