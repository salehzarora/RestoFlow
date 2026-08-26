import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show TableVisualPreset;

/// TABLE-118F — a ROUND table keeps every piece of label/status content
/// inside the visible round surface. The 118 painter handed the label column
/// the circle's bounding SQUARE, so a footnote as wide as the square
/// ("RESERVED", "OCCUPIED", "2 open orders") crossed the rim at the bottom
/// chord. The fix inscribes the content rect; the painted circle, the tile
/// Size (footprint) and the other presets are unchanged.
const _tileSizes = <String, Size>{
  // POS picker tile (~580 px canvas), kiosk tile (~970 px canvas, 1.35×
  // text), dashboard tile (~1050 px canvas), the strip reference tile.
  'pos': Size(87, 73),
  'kiosk': Size(146, 123),
  'dashboard': Size(205, 172),
  'strip': Size(120, 101),
};

const _footnotes = ['RESERVED', 'OCCUPIED', '2 open orders'];

RestoflowTableShapePainter _painter(TableVisualPreset preset, Size size) {
  final s = RestoflowFloorTable.scaleFor(size.width);
  return RestoflowTableShapePainter(
    preset: preset,
    chairs: 4,
    fill: Colors.white,
    border: Colors.grey,
    borderWidth: 2,
    chairColor: Colors.grey,
    inset: 9.0 * s,
    scale: s,
    surfaceRadius: RestoflowRadii.md,
  );
}

Widget _app(Widget child, Size size, {double textScale = 1.0}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  ),
);

/// Every corner of [rect] must lie inside the circle painted for [size]
/// (centre + radius from the painter's own surface rect), with [margin] px
/// of clearance from the rim.
void _expectInsideCircle(
  Rect rect,
  Rect tile,
  RestoflowTableShapePainter painter,
  Size size, {
  required String reason,
  double margin = 0.5,
}) {
  final surface = painter.surfaceRect(size).shift(tile.topLeft);
  final r = surface.width / 2;
  final c = surface.center;
  for (final corner in [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ]) {
    final dist = (corner - c).distance;
    expect(
      dist,
      lessThanOrEqualTo(r - margin),
      reason:
          '$reason: corner $corner is ${dist.toStringAsFixed(1)}px from '
          'the centre but the rim is at ${r.toStringAsFixed(1)}px',
    );
  }
}

void main() {
  group('round table content stays inside the rim', () {
    for (final entry in _tileSizes.entries) {
      for (final footnote in _footnotes) {
        final textScale = entry.key == 'kiosk' ? 1.35 : 1.0;
        testWidgets('${entry.key} tile ${entry.value} · "$footnote"', (
          tester,
        ) async {
          final size = entry.value;
          final painter = _painter(TableVisualPreset.roundTable, size);
          await tester.pumpWidget(
            _app(
              RestoflowFloorTable(
                label: 'T8',
                seats: 6,
                fill: Colors.white,
                onFill: Colors.black,
                border: Colors.grey,
                borderWidth: 2,
                preset: TableVisualPreset.roundTable,
                footnote: footnote,
              ),
              size,
              textScale: textScale,
            ),
          );
          final tile = tester.getRect(find.byType(RestoflowFloorTable));
          expect(tile.size, size, reason: 'the footprint never changes');
          // The footnote is still rendered (never hidden to mask the bug).
          expect(find.text(footnote), findsOneWidget);
          _expectInsideCircle(
            tester.getRect(find.text(footnote)),
            tile,
            painter,
            size,
            reason: 'footnote "$footnote" on the ${entry.key} tile',
          );
          _expectInsideCircle(
            tester.getRect(find.text('T8')),
            tile,
            painter,
            size,
            reason: 'label on the ${entry.key} tile',
          );
          _expectInsideCircle(
            tester.getRect(find.text('6')),
            tile,
            painter,
            size,
            reason: 'seats on the ${entry.key} tile',
          );
        });
      }
    }

    test('the painted circle itself is unchanged (surfaceRect = bounding '
        'square of the inset circle)', () {
      for (final size in _tileSizes.values) {
        final painter = _painter(TableVisualPreset.roundTable, size);
        final d = math.min(size.width, size.height) - 2 * painter.inset;
        expect(
          painter.surfaceRect(size),
          Rect.fromCenter(
            center: size.center(Offset.zero),
            width: d,
            height: d,
          ),
        );
      }
    });
  });

  group('other presets are untouched', () {
    for (final size in _tileSizes.values) {
      test('classic / barrels / booth surface rects at $size', () {
        final s = RestoflowFloorTable.scaleFor(size.width);
        final inset = 9.0 * s;
        expect(
          _painter(TableVisualPreset.classicRectTable, size).surfaceRect(size),
          Rect.fromLTWH(
            inset,
            inset,
            size.width - 2 * inset,
            size.height - 2 * inset,
          ),
        );
        final barrel = math.min(size.height - inset * 0.8, size.width * 0.27);
        expect(
          _painter(TableVisualPreset.tableWithBarrels, size).surfaceRect(size),
          Rect.fromLTRB(
            barrel * 0.82 + 2 * s,
            inset * 0.6,
            size.width - barrel * 0.82 - 2 * s,
            size.height - inset * 0.6,
          ),
        );
        expect(
          _painter(TableVisualPreset.boothTable, size).surfaceRect(size),
          Rect.fromLTRB(
            inset * 0.7,
            inset * 1.15,
            size.width - inset * 0.7,
            size.height - inset * 1.15,
          ),
        );
      });
    }

    testWidgets('a booth footnote still renders inside its rectangular '
        'surface at the POS size', (tester) async {
      const size = Size(87, 73);
      final painter = _painter(TableVisualPreset.boothTable, size);
      await tester.pumpWidget(
        _app(
          RestoflowFloorTable(
            label: 'A3',
            seats: 4,
            fill: Colors.white,
            onFill: Colors.black,
            border: Colors.grey,
            preset: TableVisualPreset.boothTable,
            footnote: 'RESERVED',
          ),
          size,
        ),
      );
      final tile = tester.getRect(find.byType(RestoflowFloorTable));
      final surface = painter.surfaceRect(size).shift(tile.topLeft);
      final text = tester.getRect(find.text('RESERVED'));
      expect(surface.contains(text.topLeft), isTrue);
      expect(surface.contains(text.bottomRight), isTrue);
    });
  });
}
