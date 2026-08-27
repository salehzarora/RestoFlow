import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPreset,
        TableVisualMaterial,
        TableVisualPreset,
        kFloorElementStyleRegistry;

/// TABLE-VISUAL-CONFIGURATION-120B — the VARIANT rendering behind the 120A
/// seams: every persisted material overrides Auto identically on every
/// surface, every registered fixture style resolves to its own deterministic
/// artwork branch, NULL/unknown fall back safely, and none of it moves a
/// single geometry value.
void main() {
  group('A. explicit material overrides Auto', () {
    Widget canvasTable(TableVisualMaterial? material) => MaterialApp(
      home: Scaffold(
        body: RestoflowFloorSectionCanvas(
          floorPreset: FloorPreset.woodDark,
          placed: [
            RestoflowFloorPlacedTile(
              room: (left: 1000.0, top: 1000.0, width: 1500.0, height: 2400.0),
              child: RestoflowFloorTable(
                label: 'A1',
                seats: 4,
                fill: Colors.white,
                onFill: const Color(0xFF1F2937),
                border: const Color(0xFFCBD2DC),
                material: material,
              ),
            ),
          ],
        ),
      ),
    );

    RestoflowTableShapePainter painterOf(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is CustomPaint &&
                        w.painter is RestoflowTableShapePainter,
                  ),
                )
                .painter!
            as RestoflowTableShapePainter;

    for (final m in TableVisualMaterial.values) {
      testWidgets('explicit ${m.wire} wins over the wood-dark Auto mapping', (
        tester,
      ) async {
        await tester.pumpWidget(canvasTable(m));
        expect(painterOf(tester).material, m);
      });
    }

    testWidgets('NULL stays the exact 119D Auto mapping', (tester) async {
      await tester.pumpWidget(canvasTable(null));
      expect(
        painterOf(tester).material,
        restoflowDefaultFloorMaterial(
          TableVisualPreset.classicRectTable,
          FloorPreset.woodDark,
        ),
      );
    });
  });

  group('B. the six materials are meaningfully distinct', () {
    test('surface tops, grains and chair seats are pairwise distinct', () {
      final palettes = {
        for (final m in TableVisualMaterial.values)
          m: RestoflowMaterialPalette.of(m),
      };
      for (final a in TableVisualMaterial.values) {
        for (final b in TableVisualMaterial.values) {
          if (a.index >= b.index) continue;
          expect(
            palettes[a]!.top,
            isNot(palettes[b]!.top),
            reason: '$a vs $b top',
          );
          expect(
            palettes[a]!.chairSeat,
            isNot(palettes[b]!.chairSeat),
            reason: '$a vs $b chairSeat',
          );
        }
      }
    });

    test(
      'the wood family orders by luminance: dark < rustic < wood < light',
      () {
        double lum(TableVisualMaterial m) =>
            RestoflowMaterialPalette.of(m).top.computeLuminance();
        expect(
          lum(TableVisualMaterial.darkWood),
          lessThan(lum(TableVisualMaterial.rusticWood)),
        );
        expect(
          lum(TableVisualMaterial.rusticWood),
          lessThan(lum(TableVisualMaterial.wood)),
        );
        expect(
          lum(TableVisualMaterial.wood),
          lessThan(lum(TableVisualMaterial.lightWood)),
        );
      },
    );

    test('plastic is grainless; rustic paints the STRONGEST grain alpha', () {
      expect(
        RestoflowMaterialPalette.of(TableVisualMaterial.plastic).grain.a,
        0,
      );
      for (final m in [
        TableVisualMaterial.wood,
        TableVisualMaterial.lightWood,
        TableVisualMaterial.darkWood,
        TableVisualMaterial.neutralModern,
      ]) {
        expect(
          RestoflowTableShapePainter.grainAlpha(TableVisualMaterial.rusticWood),
          greaterThan(RestoflowTableShapePainter.grainAlpha(m)),
          reason: 'rustic must out-grain ${m.wire}',
        );
      }
    });

    test('rustic paints MORE grain strokes than wood (the weathered plank '
        'character)', () {
      expect(
        RestoflowTableShapePainter.grainLineCount(
          TableVisualMaterial.rusticWood,
          RestoflowFloorDetail.rich,
        ),
        greaterThan(
          RestoflowTableShapePainter.grainLineCount(
            TableVisualMaterial.wood,
            RestoflowFloorDetail.rich,
          ),
        ),
      );
      // Compact stays bounded and clean for the POS.
      expect(
        RestoflowTableShapePainter.grainLineCount(
          TableVisualMaterial.rusticWood,
          RestoflowFloorDetail.compact,
        ),
        0,
      );
    });
  });

  group('C+D. fixture style resolution (the ONE deterministic switch)', () {
    test('every registered style resolves to itself', () {
      kFloorElementStyleRegistry.forEach((kind, styles) {
        for (final s in styles) {
          expect(
            RestoflowFixturePainter.resolveStyle(kind, s),
            s,
            reason: '$kind/$s',
          );
        }
      });
    });

    test('NULL, unknown and cross-kind styles resolve to the kind default', () {
      expect(RestoflowFixturePainter.resolveStyle('plant', null), 'default');
      expect(
        RestoflowFixturePainter.resolveStyle('plant', 'banana'),
        'default',
      );
      expect(RestoflowFixturePainter.resolveStyle('plant', 'glass'), 'default');
      expect(RestoflowFixturePainter.resolveStyle('door', 'leafy'), 'default');
      expect(
        RestoflowFixturePainter.resolveStyle('cashier', 'brick'),
        'default',
      );
      expect(
        RestoflowFixturePainter.resolveStyle('fountain', 'plain'),
        'default',
        reason: 'unknown kinds have no variants',
      );
    });

    Finder fixturePaint() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
    );

    testWidgets('every registered style mounts the painter with the style '
        'plumbed through', (tester) async {
      for (final entry in kFloorElementStyleRegistry.entries) {
        for (final style in entry.value) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 120,
                    height: 80,
                    child: RestoflowFloorFixture(kind: entry.key, style: style),
                  ),
                ),
              ),
            ),
          );
          expect(fixturePaint(), findsOneWidget, reason: '${entry.key}/$style');
          final painter =
              tester.widget<CustomPaint>(fixturePaint()).painter!
                  as RestoflowFixturePainter;
          expect(painter.style, style, reason: '${entry.key}/$style');
          expect(
            tester.getSize(find.byType(RestoflowFloorFixture)),
            const Size(120, 80),
            reason: 'geometry is style-independent',
          );
        }
      }
    });
  });

  group('E2. styled walls render at REAL strip thickness', () {
    Finder fixturePaint() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
    );

    Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 170, height: 5, child: child)),
      ),
    );

    testWidgets('a STYLED wall mounts its painter even at ~5px thickness '
        '(the standard 3000x150 strip on the POS)', (tester) async {
      for (final style in ['brick', 'wood_partition', 'plain']) {
        await tester.pumpWidget(
          host(RestoflowFloorFixture(kind: 'wall', style: style)),
        );
        expect(fixturePaint(), findsOneWidget, reason: style);
        expect(
          tester.getSize(find.byType(RestoflowFloorFixture)),
          const Size(170, 5),
        );
      }
    });

    testWidgets('the DEFAULT (null-style) wall keeps the exact 119D gate — '
        'still the flat slab at that thickness', (tester) async {
      await tester.pumpWidget(host(const RestoflowFloorFixture(kind: 'wall')));
      expect(fixturePaint(), findsNothing);
    });
  });

  group('F. thin doors stay recognizable in EVERY door style', () {
    Finder fixturePaint() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
    );

    for (final style in ['wood', 'glass', 'modern']) {
      for (final (size, turns) in const [
        (Size(52, 5), 0),
        (Size(90, 8), 2),
        (Size(60, 12), 0),
        (Size(8, 90), 1),
        (Size(8, 90), 3),
      ]) {
        testWidgets('door/$style $size turns $turns keeps the thin branch, '
            'orientation and rect', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: RestoflowFloorFixture(
                      kind: 'door',
                      style: style,
                      quarterTurns: turns,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(fixturePaint(), findsOneWidget);
          final painter =
              tester.widget<CustomPaint>(fixturePaint()).painter!
                  as RestoflowFixturePainter;
          expect(painter.quarterTurns, turns);
          expect(painter.style, style);
          expect(
            RestoflowFixturePainter.rendersThinDoor(size, turns),
            isTrue,
            reason: 'the dedicated thin branch must engage',
          );
          expect(tester.getSize(find.byType(RestoflowFloorFixture)), size);
        });
      }
    }
  });

  group('H. styles and materials never move geometry', () {
    test('surface/content rects and anchors are identical across every '
        'material', () {
      const size = Size(140, 118);
      for (final preset in TableVisualPreset.values) {
        Rect surfaceFor(TableVisualMaterial? m) => RestoflowTableShapePainter(
          preset: preset,
          chairs: 6,
          fill: Colors.white,
          border: const Color(0xFFCBD2DC),
          borderWidth: 1,
          chairColor: const Color(0xFFCBD2DC),
          inset: 9,
          scale: 1,
          surfaceRadius: 10,
          material: m,
        ).surfaceRect(size);
        final base = surfaceFor(null);
        for (final m in TableVisualMaterial.values) {
          expect(surfaceFor(m), base, reason: '$preset/$m');
        }
      }
    });
  });
}
