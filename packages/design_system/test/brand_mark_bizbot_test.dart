import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// BIZBOT-REBRAND — the shared brand mark renders the TEMPORARY typographic
/// `B` monogram on the brand-navy tile (no retired VEYRO artwork, no Material
/// glyph), never mirrors in RTL, and carries the exact public brand token as
/// its accessible label.
void main() {
  Widget host(Widget child, {TextDirection dir = TextDirection.ltr}) =>
      MaterialApp(
        home: Directionality(
          textDirection: dir,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('renders the B monogram, not an image asset or Material glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const RestoflowBrandMark(title: 'BIZBOT POS')),
    );
    final mark = find.byType(RestoflowBrandMark);
    // No bundled artwork at all: the retired VEYRO symbol must not ship.
    expect(
      find.descendant(of: mark, matching: find.byType(Image)),
      findsNothing,
    );
    expect(find.byIcon(Icons.restaurant_menu), findsNothing);
    // The monogram glyph is on the tile and the lockup carries the title.
    expect(
      find.descendant(
        of: mark,
        matching: find.text(RestoflowBrandMark.monogram),
      ),
      findsOneWidget,
    );
    expect(find.text('BIZBOT POS'), findsOneWidget);
    // The tile carries the exact public brand token as its accessible label.
    expect(RestoflowBrandMark.brand, 'BIZBOT');
    expect(find.bySemanticsLabel('BIZBOT'), findsOneWidget);
  });

  testWidgets('the mark is NEVER mirrored under RTL', (tester) async {
    await tester.pumpWidget(
      host(const RestoflowBrandMark(), dir: TextDirection.rtl),
    );
    final mark = find.byType(RestoflowBrandMark);
    // No horizontal flip is applied to the mark: any Transform in the subtree
    // must not negate the x scale (which is how a mirror is expressed).
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
    // The glyph is pinned to LTR regardless of the ambient direction.
    final glyph = tester.element(
      find.descendant(
        of: mark,
        matching: find.text(RestoflowBrandMark.monogram),
      ),
    );
    expect(Directionality.of(glyph), TextDirection.ltr);
  });

  testWidgets('presents the monogram on the brand-navy tile with a hairline', (
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
      kRestoflowSeedColor,
      reason: 'the tile is the frozen brand navy (same as the icon set)',
    );
    expect(
      decoration.border,
      isNotNull,
      reason: 'a hairline keeps the navy tile legible on dark surfaces',
    );
    final glyph = tester.widget<Text>(
      find.descendant(
        of: find.byType(RestoflowBrandMark),
        matching: find.text(RestoflowBrandMark.monogram),
      ),
    );
    expect(glyph.style?.color, Colors.white);
  });
}
