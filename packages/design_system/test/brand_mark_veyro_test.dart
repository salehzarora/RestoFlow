import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// VEYRO-REBRAND — the shared brand mark renders the approved VEYRO symbol
/// (not the old restaurant glyph), never mirrors in RTL, and presents the
/// full-colour mark on a clean neutral tile so it stays legible on light and
/// dark surfaces.
void main() {
  Widget host(Widget child, {TextDirection dir = TextDirection.ltr}) =>
      MaterialApp(
        home: Directionality(
          textDirection: dir,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('renders the VEYRO mark asset, not a Material glyph', (
    tester,
  ) async {
    await tester.pumpWidget(host(const RestoflowBrandMark(title: 'VEYRO POS')));
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(RestoflowBrandMark),
        matching: find.byType(Image),
      ),
    );
    final provider = image.image as AssetImage;
    expect(provider.assetName, RestoflowBrandMark.markAsset);
    expect(provider.package, 'restoflow_design_system');
    // The old generic restaurant glyph must be gone.
    expect(find.byIcon(Icons.restaurant_menu), findsNothing);
    // The tile carries an accessible brand label.
    expect(find.bySemanticsLabel('VEYRO'), findsOneWidget);
  });

  testWidgets('the mark is NEVER mirrored under RTL', (tester) async {
    await tester.pumpWidget(
      host(const RestoflowBrandMark(), dir: TextDirection.rtl),
    );
    // No horizontal flip is applied to the mark: any Transform in the subtree
    // must not negate the x scale (which is how a mirror is expressed).
    final transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(RestoflowBrandMark),
        matching: find.byType(Transform),
      ),
    );
    for (final t in transforms) {
      expect(
        t.transform.storage[0],
        greaterThanOrEqualTo(0),
        reason: 'the VEYRO mark must not be x-mirrored in RTL',
      );
    }
    // The mark renders identically to LTR (same asset, upright).
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('presents the mark on a light tile for dark-surface contrast', (
    tester,
  ) async {
    await tester.pumpWidget(host(const RestoflowBrandMark()));
    final tile = tester.widget<Container>(
      find.descendant(
        of: find.byType(RestoflowBrandMark),
        matching: find.byType(Container),
      ),
    );
    final decoration = tile.decoration as BoxDecoration;
    expect(
      decoration.color,
      Colors.white,
      reason: 'the neutral tile keeps the full-colour mark legible on navy',
    );
  });
}
