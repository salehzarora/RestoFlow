import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset;

/// TABLE-119D — the material-themed floor SCENE layer.
///
/// Tables render real materials (wood families / plastic / neutral modern)
/// through a deterministic spec: preset + floor preset -> material, resolved
/// by the shared scene scope the section canvas provides. Fixtures own their
/// identity through full-surface artwork (no colored box + icon). All of it
/// is client-only styling: geometry, seat logic and state semantics are
/// byte-identical to 119A/119B.
void main() {
  group('material spec', () {
    test('the material enum carries the five restaurant-safe families', () {
      expect(RestoflowFloorMaterial.values, [
        RestoflowFloorMaterial.wood,
        RestoflowFloorMaterial.darkWood,
        RestoflowFloorMaterial.lightWood,
        RestoflowFloorMaterial.plastic,
        RestoflowFloorMaterial.neutralModern,
      ]);
    });

    test('every material resolves a full palette with a LIGHT label plate '
        '(dark app ink always reads on it)', () {
      for (final m in RestoflowFloorMaterial.values) {
        final p = RestoflowMaterialPalette.of(m);
        expect(p.top, isNot(p.topDark), reason: '$m gradient must shade');
        expect(p.top, isNot(p.topLight), reason: '$m gradient must light');
        expect(
          p.labelPlate.computeLuminance(),
          greaterThan(0.7),
          reason: '$m plate must be light',
        );
      }
    });

    test('palettes are distinct per material (no accidental aliasing)', () {
      final tops = RestoflowFloorMaterial.values
          .map((m) => RestoflowMaterialPalette.of(m).top)
          .toSet();
      expect(tops.length, RestoflowFloorMaterial.values.length);
    });

    test('the default material mapping is deterministic and floor-aware', () {
      // Barrel tables are rustic on every floor.
      for (final floor in FloorPreset.values) {
        expect(
          restoflowDefaultFloorMaterial(
            TableVisualPreset.tableWithBarrels,
            floor,
          ),
          RestoflowFloorMaterial.darkWood,
          reason: 'barrels on $floor',
        );
      }
      // Warm wood pops on the dark wood floor.
      expect(
        restoflowDefaultFloorMaterial(
          TableVisualPreset.classicRectTable,
          FloorPreset.woodDark,
        ),
        RestoflowFloorMaterial.wood,
      );
      expect(
        restoflowDefaultFloorMaterial(
          TableVisualPreset.roundTable,
          FloorPreset.woodDark,
        ),
        RestoflowFloorMaterial.wood,
      );
      // The white pre-118 canvas gets light wood, never white-on-white.
      expect(
        restoflowDefaultFloorMaterial(
          TableVisualPreset.classicRectTable,
          FloorPreset.plainLight,
        ),
        RestoflowFloorMaterial.lightWood,
      );
      // Modern tile floor reads modern materials.
      expect(
        restoflowDefaultFloorMaterial(
          TableVisualPreset.classicRectTable,
          FloorPreset.tileModern,
        ),
        RestoflowFloorMaterial.plastic,
      );
      expect(
        restoflowDefaultFloorMaterial(
          TableVisualPreset.classicRectTable,
          FloorPreset.stoneNeutral,
        ),
        RestoflowFloorMaterial.neutralModern,
      );
      // Booths follow the floor's warmth.
      expect(
        restoflowDefaultFloorMaterial(
          TableVisualPreset.boothTable,
          FloorPreset.woodDark,
        ),
        RestoflowFloorMaterial.darkWood,
      );
      expect(
        restoflowDefaultFloorMaterial(
          TableVisualPreset.boothTable,
          FloorPreset.plainLight,
        ),
        RestoflowFloorMaterial.wood,
      );
    });
  });

  group('scene scope resolves materials with zero app plumbing', () {
    Widget canvasWith(Widget tile, FloorPreset floor) => MaterialApp(
      home: Scaffold(
        body: RestoflowFloorSectionCanvas(
          floorPreset: floor,
          placed: [
            RestoflowFloorPlacedTile(
              room: (left: 1000.0, top: 1000.0, width: 1500.0, height: 2400.0),
              child: tile,
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

    testWidgets('a table INSIDE a wood-dark canvas paints warm wood', (
      tester,
    ) async {
      await tester.pumpWidget(
        canvasWith(
          const RestoflowFloorTable(
            label: 'A1',
            seats: 4,
            fill: Colors.white,
            onFill: Color(0xFF1F2937),
            border: Color(0xFFCBD2DC),
          ),
          FloorPreset.woodDark,
        ),
      );
      expect(painterOf(tester).material, RestoflowFloorMaterial.wood);
    });

    testWidgets('the same table on the modern tile canvas paints plastic', (
      tester,
    ) async {
      await tester.pumpWidget(
        canvasWith(
          const RestoflowFloorTable(
            label: 'A1',
            seats: 4,
            fill: Colors.white,
            onFill: Color(0xFF1F2937),
            border: Color(0xFFCBD2DC),
          ),
          FloorPreset.tileModern,
        ),
      );
      expect(painterOf(tester).material, RestoflowFloorMaterial.plastic);
    });

    testWidgets('outside any canvas (strip tiles) the plain-light default '
        'applies', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 101,
                child: RestoflowFloorTable(
                  label: 'A1',
                  seats: 4,
                  fill: Colors.white,
                  onFill: Color(0xFF1F2937),
                  border: Color(0xFFCBD2DC),
                ),
              ),
            ),
          ),
        ),
      );
      expect(painterOf(tester).material, RestoflowFloorMaterial.lightWood);
    });

    testWidgets('an explicit material overrides the scope default', (
      tester,
    ) async {
      await tester.pumpWidget(
        canvasWith(
          const RestoflowFloorTable(
            label: 'A1',
            seats: 4,
            fill: Colors.white,
            onFill: Color(0xFF1F2937),
            border: Color(0xFFCBD2DC),
            material: RestoflowFloorMaterial.neutralModern,
          ),
          FloorPreset.woodDark,
        ),
      );
      expect(painterOf(tester).material, RestoflowFloorMaterial.neutralModern);
    });
  });

  group('materials never move geometry', () {
    test(
      'surface/content rects and chair anchors are material-independent',
      () {
        const size = Size(140, 118);
        for (final preset in TableVisualPreset.values) {
          RestoflowTableShapePainter make(RestoflowFloorMaterial? m) =>
              RestoflowTableShapePainter(
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
              );
          final base = make(null);
          for (final m in RestoflowFloorMaterial.values) {
            final themed = make(m);
            expect(
              themed.surfaceRect(size),
              base.surfaceRect(size),
              reason: '$preset $m surface',
            );
            expect(
              themed.contentRect(size),
              base.contentRect(size),
              reason: '$preset $m content',
            );
            expect(
              themed.chairAnchors(size),
              base.chairAnchors(size),
              reason: '$preset $m anchors',
            );
            expect(themed.seatGlyphCount, base.seatGlyphCount);
          }
        }
      },
    );

    test('shouldRepaint covers the material field', () {
      RestoflowTableShapePainter make(RestoflowFloorMaterial? m) =>
          RestoflowTableShapePainter(
            preset: TableVisualPreset.roundTable,
            chairs: 4,
            fill: Colors.white,
            border: const Color(0xFFCBD2DC),
            borderWidth: 1,
            chairColor: const Color(0xFFCBD2DC),
            inset: 9,
            scale: 1,
            surfaceRadius: 10,
            material: m,
          );
      expect(
        make(RestoflowFloorMaterial.wood).shouldRepaint(make(null)),
        isTrue,
      );
      expect(
        make(
          RestoflowFloorMaterial.wood,
        ).shouldRepaint(make(RestoflowFloorMaterial.darkWood)),
        isTrue,
      );
      expect(
        make(
          RestoflowFloorMaterial.wood,
        ).shouldRepaint(make(RestoflowFloorMaterial.wood)),
        isFalse,
      );
    });
  });

  group('label plate keeps text readable on real materials', () {
    testWidgets('every preset mounts the label plate inside its content rect', (
      tester,
    ) async {
      for (final preset in TableVisualPreset.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 150,
                  height: 126,
                  child: RestoflowFloorTable(
                    label: 'T7',
                    seats: 4,
                    footnote: 'RESERVED',
                    fill: Colors.white,
                    onFill: const Color(0xFF1F2937),
                    border: const Color(0xFFCBD2DC),
                    preset: preset,
                  ),
                ),
              ),
            ),
          ),
        );
        final plate = find.byKey(const ValueKey('restoflow-floor-label-plate'));
        expect(plate, findsOneWidget, reason: '$preset');
        final tileRect = tester.getRect(find.byType(RestoflowFloorTable));
        final plateRect = tester.getRect(plate);
        expect(
          tileRect.inflate(0.1).contains(plateRect.topLeft) &&
              tileRect.inflate(0.1).contains(plateRect.bottomRight),
          isTrue,
          reason: '$preset plate stays on the tile',
        );
      }
    });

    testWidgets('the ROUND plate stays INSIDE the circle rim (118F holds '
        'under the plate)', (tester) async {
      const size = Size(150, 126);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                height: 126,
                child: RestoflowFloorTable(
                  label: 'R9',
                  seats: 8,
                  footnote: 'OCCUPIED',
                  fill: Colors.white,
                  onFill: Color(0xFF1F2937),
                  border: Color(0xFFCBD2DC),
                  preset: TableVisualPreset.roundTable,
                ),
              ),
            ),
          ),
        ),
      );
      final painter = RestoflowTableShapePainter(
        preset: TableVisualPreset.roundTable,
        chairs: 8,
        fill: Colors.white,
        border: const Color(0xFFCBD2DC),
        borderWidth: 1,
        chairColor: const Color(0xFFCBD2DC),
        inset: 9 * RestoflowFloorTable.scaleFor(150),
        scale: RestoflowFloorTable.scaleFor(150),
        surfaceRadius: 10,
      );
      final surface = painter.surfaceRect(size);
      final tile = tester.getRect(find.byType(RestoflowFloorTable));
      final center =
          tile.topLeft + Offset(surface.center.dx, surface.center.dy);
      final r = surface.width / 2;
      final plate = tester.getRect(
        find.byKey(const ValueKey('restoflow-floor-label-plate')),
      );
      for (final corner in [
        plate.topLeft,
        plate.topRight,
        plate.bottomLeft,
        plate.bottomRight,
      ]) {
        expect(
          (corner - center).distance,
          lessThanOrEqualTo(r + 0.5),
          reason: 'plate corner $corner must stay inside the rim',
        );
      }
    });
  });

  group('fixtures own their identity (no box + icon)', () {
    Finder fixturePaint() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
    );

    Widget host(Widget child, {Size size = const Size(90, 76)}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );

    testWidgets('the plant is pure artwork: painter, no icon, no colored box', (
      tester,
    ) async {
      await tester.pumpWidget(host(const RestoflowFloorFixture(kind: 'plant')));
      expect(fixturePaint(), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RestoflowFloorFixture),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        Colors.transparent,
        reason: 'the painter must own the plant silhouette',
      );
    });

    testWidgets('the cashier reads as a counter: painter with full-surface '
        'art, label anchored to the service edge, no icon', (tester) async {
      await tester.pumpWidget(
        host(
          const RestoflowFloorFixture(kind: 'cashier', label: 'Front till'),
          size: const Size(150, 84),
        ),
      );
      expect(fixturePaint(), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
      expect(find.text('Front till'), findsOneWidget);
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RestoflowFloorFixture),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, Colors.transparent);
      // The caption sits at the bottom edge, clear of the register artwork.
      final label = tester.getRect(find.text('Front till'));
      final tile = tester.getRect(find.byType(RestoflowFloorFixture));
      expect(label.center.dy, greaterThan(tile.center.dy));
    });

    testWidgets('the window is glass, not a tinted box', (tester) async {
      await tester.pumpWidget(
        host(
          const RestoflowFloorFixture(kind: 'window'),
          size: const Size(140, 24),
        ),
      );
      expect(fixturePaint(), findsOneWidget);
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RestoflowFloorFixture),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, Colors.transparent);
    });

    testWidgets('the wall keeps its slab fill (a wall IS a slab)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const RestoflowFloorFixture(kind: 'wall'),
          size: const Size(140, 16),
        ),
      );
      expect(fixturePaint(), findsOneWidget);
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RestoflowFloorFixture),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
    });

    testWidgets('tiny fixtures keep the flat colored fallback (never a bare '
        'transparent hole)', (tester) async {
      await tester.pumpWidget(
        host(
          const RestoflowFloorFixture(kind: 'plant'),
          size: const Size(12, 10),
        ),
      );
      expect(fixturePaint(), findsNothing);
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RestoflowFloorFixture),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
    });

    testWidgets('an UNKNOWN forward-compat kind keeps its slab fill (the wall '
        'fallback paints strokes only)', (tester) async {
      await tester.pumpWidget(
        host(const RestoflowFloorFixture(kind: 'fountain')),
      );
      expect(fixturePaint(), findsOneWidget);
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RestoflowFloorFixture),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
    });

    testWidgets('a selected fixture keeps its ring ABOVE full-surface '
        'artwork (foreground decoration)', (tester) async {
      await tester.pumpWidget(
        host(const RestoflowFloorFixture(kind: 'cashier', selected: true)),
      );
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RestoflowFloorFixture),
              matching: find.byType(Container),
            )
            .first,
      );
      final fg = box.foregroundDecoration! as BoxDecoration;
      expect(fg.border, isNotNull);
      expect((fg.border! as Border).top.width, 2);
    });

    testWidgets('the fixture caption follows the artwork rotation (service '
        'edge side)', (tester) async {
      for (final (turns, alignment) in [
        (0, Alignment.bottomCenter),
        (1, Alignment.centerLeft),
        (2, Alignment.topCenter),
        (3, Alignment.centerRight),
      ]) {
        await tester.pumpWidget(
          host(
            RestoflowFloorFixture(
              kind: 'cashier',
              label: 'Till',
              quarterTurns: turns,
            ),
            size: const Size(150, 84),
          ),
        );
        final align = tester.widget<Align>(
          find
              .ancestor(of: find.text('Till'), matching: find.byType(Align))
              .first,
        );
        expect(align.alignment, alignment, reason: 'turns $turns');
      }
    });

    testWidgets('a window below the artwork band (long side < 18) stays the '
        'flat fallback', (tester) async {
      await tester.pumpWidget(
        host(
          const RestoflowFloorFixture(kind: 'window'),
          size: const Size(16, 17),
        ),
      );
      expect(fixturePaint(), findsNothing);
    });

    testWidgets('a thin window strip (real 300-unit height) still paints its '
        'glass', (tester) async {
      await tester.pumpWidget(
        host(
          const RestoflowFloorFixture(kind: 'window'),
          size: const Size(170, 16),
        ),
      );
      expect(fixturePaint(), findsOneWidget);
      expect(
        tester.getSize(find.byType(RestoflowFloorFixture)),
        const Size(170, 16),
      );
    });

    testWidgets('thin doors keep their 119B artwork and rect', (tester) async {
      await tester.pumpWidget(
        host(
          const RestoflowFloorFixture(kind: 'door'),
          size: const Size(90, 8),
        ),
      );
      expect(fixturePaint(), findsOneWidget);
      expect(
        tester.getSize(find.byType(RestoflowFloorFixture)),
        const Size(90, 8),
      );
    });
  });
}
