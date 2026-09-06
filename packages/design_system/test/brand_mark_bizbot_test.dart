import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// BIZBOT OFFICIAL IDENTITY — the shared brand mark renders the owner's
/// official symbol artwork (no temporary `B` monogram, no retired VEYRO art),
/// locks up with the official wordmark artwork on request, never mirrors in
/// RTL, and carries the exact public brand token as its accessible label.
void main() {
  Widget host(Widget child, {TextDirection dir = TextDirection.ltr}) =>
      MaterialApp(
        home: Directionality(
          textDirection: dir,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  Finder assetImage(String asset) => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == asset &&
        (w.image as AssetImage).package == RestoflowBrandMark.package,
  );

  testWidgets('renders the OFFICIAL symbol asset — not a drawn letter', (
    tester,
  ) async {
    await tester.pumpWidget(host(const RestoflowBrandMark()));
    final mark = find.byType(RestoflowBrandMark);
    expect(
      find.descendant(
        of: mark,
        matching: assetImage(RestoflowBrandMark.symbolAsset),
      ),
      findsOneWidget,
      reason: 'the symbol is the bundled official artwork',
    );
    // The temporary typographic monogram is gone: no Text at all in the
    // symbol-only mark, and no Material glyph standing in for a logo.
    expect(
      find.descendant(of: mark, matching: find.byType(Text)),
      findsNothing,
    );
    expect(find.byIcon(Icons.restaurant_menu), findsNothing);
    expect(
      RestoflowBrandMark.symbolAsset,
      'assets/brand/bizbot/bizbot_symbol.png',
    );
    expect(RestoflowBrandMark.symbolAsset, isNot(contains('veyro')));
  });

  testWidgets('carries the exact public brand token as its semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const RestoflowBrandMark(title: 'BIZBOT POS')),
    );
    expect(RestoflowBrandMark.brand, 'BIZBOT');
    expect(BizbotBrand.name, 'BIZBOT');
    expect(find.bySemanticsLabel('BIZBOT'), findsOneWidget);
    // A product-name lockup keeps the localized title as TEXT.
    expect(find.text('BIZBOT POS'), findsOneWidget);
  });

  testWidgets('a wordmark lockup renders the official wordmark artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const RestoflowBrandMark(
          wordmark: BizbotWordmark.latin,
          tagline: 'Dashboard',
        ),
      ),
    );
    final mark = find.byType(RestoflowBrandMark);
    expect(
      find.descendant(
        of: mark,
        matching: assetImage(RestoflowBrandMark.wordmarkLatinAsset),
      ),
      findsOneWidget,
    );
    expect(find.text('Dashboard'), findsOneWidget);
    // The brand is announced exactly once (the symbol); the wordmark image is
    // decorative for assistive tech.
    expect(find.bySemanticsLabel('BIZBOT'), findsOneWidget);
    expect(
      RestoflowBrandMark.assetFor(BizbotWordmark.arabic),
      'assets/brand/bizbot/bizbot_wordmark_ar.png',
    );
  });

  testWidgets('the mark is NEVER mirrored under RTL', (tester) async {
    await tester.pumpWidget(
      host(
        const RestoflowBrandMark(wordmark: BizbotWordmark.latin),
        dir: TextDirection.rtl,
      ),
    );
    final mark = find.byType(RestoflowBrandMark);
    for (final image in tester.widgetList<Image>(
      find.descendant(of: mark, matching: find.byType(Image)),
    )) {
      expect(
        image.matchTextDirection,
        isFalse,
        reason: 'brand artwork must not flip with the text direction',
      );
    }
    // No horizontal flip anywhere in the subtree: any Transform must not
    // negate the x scale (which is how a mirror is expressed).
    final transforms = tester.widgetList<Transform>(
      find.descendant(of: mark, matching: find.byType(Transform)),
    );
    for (final t in transforms) {
      expect(
        t.transform.storage[0],
        greaterThanOrEqualTo(0),
        reason: 'the BIZBOT mark must not be x-mirrored in RTL',
      );
    }
  });

  testWidgets('sizes the symbol to `size` and sits directly on the surface', (
    tester,
  ) async {
    await tester.pumpWidget(host(const RestoflowBrandMark(size: 40)));
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(RestoflowBrandMark),
        matching: assetImage(RestoflowBrandMark.symbolAsset),
      ),
    );
    expect(image.width, 40);
    expect(image.height, 40);
    expect(image.fit, BoxFit.contain);
    // No tile: the symbol is complete artwork and needs no navy/emerald bed.
    expect(
      find.descendant(
        of: find.byType(RestoflowBrandMark),
        matching: find.byType(Container),
      ),
      findsNothing,
    );
  });
  group('reverse rendition (dark surfaces)', () {
    List<double> apply(List<double> m, List<double> rgba) => List.generate(
      4,
      (r) =>
          (m[r * 5] * rgba[0] +
                  m[r * 5 + 1] * rgba[1] +
                  m[r * 5 + 2] * rgba[2] +
                  m[r * 5 + 3] * rgba[3] +
                  m[r * 5 + 4])
              .clamp(0, 255)
              .toDouble(),
    );

    test('the matrix maps the artwork\'s charcoal ink to white and keeps '
        'its emerald ink — alpha untouched', () {
      const m = RestoflowBrandMark.reverseWordmarkMatrix;
      expect(m.length, 20);
      // The two inks as they sit in the committed PNG (see the asset pin
      // below): charcoal ≈ (40, 49, 58), emerald ≈ (9, 149, 104).
      final charcoal = apply(m, [40, 49, 58, 255]);
      final emerald = apply(m, [9, 149, 104, 255]);
      for (var i = 0; i < 3; i++) {
        expect(charcoal[i], closeTo(255, 1), reason: 'charcoal → white');
      }
      expect(emerald[0], closeTo(5, 2));
      expect(emerald[1], closeTo(150, 2));
      expect(emerald[2], closeTo(105, 2));
      // Alpha passes through — anti-aliased edges keep their coverage.
      expect(apply(m, [40, 49, 58, 96])[3], 96);
      expect(apply(m, [9, 149, 104, 40])[3], 40);
      // A half-covered charcoal edge pixel is still white (not grey).
      expect(apply(m, [40, 49, 58, 128])[0], closeTo(255, 1));
    });

    testWidgets('reverse: only the wordmark goes through the filter; the '
        'symbol and the default lockup never do', (tester) async {
      await tester.pumpWidget(
        host(
          const RestoflowBrandMark(
            wordmark: BizbotWordmark.latin,
            tagline: 'Point of Sale',
            reverse: true,
          ),
        ),
      );
      final wordmark = assetImage(RestoflowBrandMark.wordmarkLatinAsset);
      final symbol = assetImage(RestoflowBrandMark.symbolAsset);
      expect(wordmark, findsOneWidget);
      expect(symbol, findsOneWidget);
      final filtered = find.ancestor(
        of: wordmark,
        matching: find.byType(ColorFiltered),
      );
      expect(filtered, findsOneWidget);
      expect(
        tester.widget<ColorFiltered>(filtered).colorFilter,
        RestoflowBrandMark.reverseWordmarkFilter,
      );
      expect(
        find.ancestor(of: symbol, matching: find.byType(ColorFiltered)),
        findsNothing,
        reason: 'the symbol carries its own paper and is never recoloured',
      );
      // Same asset, same geometry: the reverse rendition is a colour
      // treatment, not a second artwork.
      final image = tester.widget<Image>(wordmark);
      expect(image.height, closeTo(56 * 0.40, 0.01));
      expect(image.fit, BoxFit.contain);
      expect(image.matchTextDirection, isFalse);

      await tester.pumpWidget(
        host(const RestoflowBrandMark(wordmark: BizbotWordmark.latin)),
      );
      expect(find.byType(ColorFiltered), findsNothing);
    });

    testWidgets('the committed wordmark artwork still carries exactly the '
        'two inks the matrix is keyed on', (tester) async {
      var dir = Directory.current;
      while (!File('${dir.path}/melos.yaml').existsSync() &&
          !File('${dir.path}/vercel.json').existsSync()) {
        if (dir.parent.path == dir.path) fail('repo root not found');
        dir = dir.parent;
      }
      for (final asset in [
        RestoflowBrandMark.wordmarkLatinAsset,
        RestoflowBrandMark.wordmarkArabicAsset,
      ]) {
        final bytes = File(
          '${dir.path}/packages/design_system/$asset',
        ).readAsBytesSync();
        late final ByteData pixels;
        late final int count;
        await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          pixels = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          count = frame.image.width * frame.image.height;
        });
        var ink = 0, emerald = 0, other = 0;
        for (var i = 0; i < count; i++) {
          final a = pixels.getUint8(i * 4 + 3);
          if (a < 200) continue; // edges / fades are not an ink
          final g = pixels.getUint8(i * 4 + 1);
          // The master's own tonal noise spreads each ink over a band; the
          // matrix is anchored on the band centres (49 / 149) and stays
          // monotone across both bands.
          if ((g - RestoflowBrandMark.wordmarkInkGreen).abs() <= 20) {
            ink++;
          } else if ((g - RestoflowBrandMark.wordmarkEmeraldGreen).abs() <=
              30) {
            emerald++;
          } else {
            other++;
          }
        }
        expect(ink, greaterThan(0), reason: '$asset charcoal ink');
        expect(emerald, greaterThan(0), reason: '$asset emerald ink');
        // Anything else is residual master paper/noise, never a third ink.
        expect(
          other / (ink + emerald + other),
          lessThan(0.03),
          reason: '$asset: pixels that are neither ink',
        );
      }
    });
  });
}
