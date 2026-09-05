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
}
