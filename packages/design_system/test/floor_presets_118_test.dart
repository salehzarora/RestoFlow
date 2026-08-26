import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset, floorTableRoomRect;

/// TABLE-VISUAL-LAYOUT-118 — the SHARED floor/table preset rendering.
///
/// The default presets must render the pre-118 widget tree byte-for-byte (a
/// white canvas, the classic chair glyphs) so every existing golden and
/// matrix pin keeps holding; a non-default preset adds ONE painter under the
/// tables (floor) or ONE shape painter inside the fixed footprint (table) —
/// never a different footprint, never a different room rect.
Widget _app(Widget child, {double width = 760}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

RestoflowFloorTable _table(TableVisualPreset preset, {int seats = 4}) =>
    RestoflowFloorTable(
      label: 'T1',
      seats: seats,
      fill: Colors.white,
      onFill: Colors.black,
      border: Colors.grey,
      preset: preset,
    );

void main() {
  group('RestoflowFloorSectionCanvas floor preset', () {
    testWidgets('the default (plain light) paints NO preset painter and keeps '
        'the white canvas', (tester) async {
      await tester.pumpWidget(
        _app(
          RestoflowFloorSectionCanvas(
            placed: [
              RestoflowFloorPlacedTile(
                room: floorTableRoomRect(1000, 1000),
                child: _table(TableVisualPreset.classicRectTable),
              ),
            ],
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowFloorPresetPainter,
        ),
        findsNothing,
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(RestoflowFloorSectionCanvas),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, Colors.white);
    });

    for (final preset in FloorPreset.values.where(
      (p) => p != FloorPreset.plainLight,
    )) {
      testWidgets('${preset.wire} paints exactly one preset painter under the '
          'tables', (tester) async {
        await tester.pumpWidget(
          _app(
            RestoflowFloorSectionCanvas(
              floorPreset: preset,
              placed: [
                RestoflowFloorPlacedTile(
                  room: floorTableRoomRect(1000, 1000),
                  child: _table(TableVisualPreset.classicRectTable),
                ),
              ],
            ),
          ),
        );
        final painters = tester
            .widgetList<CustomPaint>(
              find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint &&
                    w.painter is RestoflowFloorPresetPainter,
              ),
            )
            .toList();
        expect(painters, hasLength(1));
        expect(
          (painters.single.painter! as RestoflowFloorPresetPainter).preset,
          preset,
        );
        // The floor never changes the geometry: the placed tile still lands
        // at the shared room rect.
        final canvasBox = tester.getRect(
          find
              .descendant(
                of: find.byType(RestoflowFloorSectionCanvas),
                matching: find.byType(Stack),
              )
              .first,
        );
        final tile = tester.getRect(find.byType(RestoflowFloorTable));
        final expected = RestoflowFloorSectionCanvas.pixelsForRoomRect(
          floorTableRoomRect(1000, 1000),
          canvasBox.size,
        ).shift(canvasBox.topLeft);
        expect((tile.left - expected.left).abs(), lessThan(0.5));
        expect((tile.top - expected.top).abs(), lessThan(0.5));
        expect((tile.width - expected.width).abs(), lessThan(0.5));
      });
    }

    test(
      'the palette gives every preset a distinct base and contrasting ink',
      () {
        final bases = <Color>{};
        for (final preset in FloorPreset.values) {
          final palette = RestoflowFloorPresetPalette.of(preset);
          bases.add(palette.base);
          expect(palette.isDark, preset.isDark, reason: preset.wire);
          // Ink contrasts with the base: light ink on dark floors and vice versa.
          expect(
            palette.ink.computeLuminance() > 0.5,
            preset.isDark,
            reason: '${preset.wire} ink must contrast its floor',
          );
          expect(
            palette.tableOnSurface.computeLuminance() < 0.5,
            palette.tableSurface.computeLuminance() >= 0.5,
            reason: '${preset.wire} table ink must contrast the table surface',
          );
        }
        expect(bases, hasLength(FloorPreset.values.length));
        expect(
          RestoflowFloorPresetPalette.of(FloorPreset.plainLight).base,
          Colors.white,
        );
      },
    );

    test('the preset painter repaints only when the preset changes', () {
      const a = RestoflowFloorPresetPainter(FloorPreset.woodDark);
      const b = RestoflowFloorPresetPainter(FloorPreset.woodDark);
      const c = RestoflowFloorPresetPainter(FloorPreset.tileModern);
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });
  });

  group('RestoflowFloorTable visual preset', () {
    testWidgets('the default classic preset draws NO shape painter (the '
        'pre-118 chair glyph tree)', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 120,
            height: 101,
            child: _table(TableVisualPreset.classicRectTable),
          ),
          width: 120,
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowTableShapePainter,
        ),
        findsNothing,
      );
      expect(find.text('T1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    for (final preset in TableVisualPreset.values.where(
      (p) => p != TableVisualPreset.classicRectTable,
    )) {
      testWidgets('${preset.wire} draws its shape painter inside the SAME '
          'footprint and keeps label + seats', (tester) async {
        await tester.pumpWidget(
          _app(
            SizedBox(width: 120, height: 101, child: _table(preset)),
            width: 120,
          ),
        );
        final painters = tester
            .widgetList<CustomPaint>(
              find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint && w.painter is RestoflowTableShapePainter,
              ),
            )
            .toList();
        expect(painters, hasLength(1), reason: preset.wire);
        expect(
          (painters.single.painter! as RestoflowTableShapePainter).preset,
          preset,
        );
        expect(
          tester.getSize(find.byType(RestoflowFloorTable)),
          const Size(120, 101),
        );
        expect(find.text('T1'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
      });
    }

    testWidgets('a 12-seat round table caps its chair glyphs but keeps the '
        'exact seat count', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 120,
            height: 101,
            child: _table(TableVisualPreset.roundTable, seats: 14),
          ),
          width: 120,
        ),
      );
      final painter =
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
      expect(painter.chairs, 12);
      expect(find.text('14'), findsOneWidget);
    });
  });
}
