import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show TableVisualPreset;

/// TABLE-119A — realistic shared floor rendering, pinned SEMANTICALLY (never
/// by pixels): the deterministic size→detail tiers, the seat-count → visible
/// seating mapping per preset (glyph counts + anchor distribution), the
/// fixture painter per kind with authoritative orientation, repaint hygiene,
/// and the invariant that richer painting NEVER changes tile geometry.
const _tile = Size(120, 101);

RestoflowTableShapePainter _painter(
  TableVisualPreset preset, {
  int seats = 4,
  Size size = _tile,
  RestoflowFloorDetail detail = RestoflowFloorDetail.standard,
}) {
  final s = RestoflowFloorTable.scaleFor(size.width);
  return RestoflowTableShapePainter(
    preset: preset,
    chairs: seats < 0 ? 0 : (seats > 12 ? 12 : seats),
    fill: Colors.white,
    border: Colors.grey,
    borderWidth: 2,
    chairColor: Colors.grey,
    inset: 9.0 * s,
    scale: s,
    surfaceRadius: RestoflowRadii.md,
    detail: detail,
  );
}

Widget _app(Widget child, {double width = 120}) => MaterialApp(
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
  group('deterministic detail tiers (size-driven, never app-driven)', () {
    test('thresholds', () {
      expect(restoflowFloorDetailFor(40), RestoflowFloorDetail.compact);
      expect(restoflowFloorDetailFor(63.9), RestoflowFloorDetail.compact);
      expect(restoflowFloorDetailFor(64), RestoflowFloorDetail.standard);
      expect(restoflowFloorDetailFor(87), RestoflowFloorDetail.standard);
      expect(restoflowFloorDetailFor(120), RestoflowFloorDetail.standard);
      expect(restoflowFloorDetailFor(130), RestoflowFloorDetail.rich);
      expect(restoflowFloorDetailFor(146), RestoflowFloorDetail.rich);
      expect(restoflowFloorDetailFor(205), RestoflowFloorDetail.rich);
    });
  });

  group('seat count → visible seating (shared deterministic mapping)', () {
    test(
      'classic: side distribution follows the shared pattern, capped at 12',
      () {
        expect(floorChairSides(1, 12), (1, 0, 0, 0));
        expect(floorChairSides(2, 12), (1, 1, 0, 0));
        expect(floorChairSides(4, 12), (2, 2, 0, 0)); // 4-top seats 2+2 across
        expect(floorChairSides(6, 12), (2, 2, 1, 1));
        expect(floorChairSides(12, 12), (4, 4, 2, 2));
        expect(floorChairSides(13, 12), (4, 4, 2, 2)); // capped
        expect(floorChairSides(0, 12), (0, 0, 0, 0));
        expect(floorChairSides(-3, 12), (0, 0, 0, 0));
      },
    );

    for (final (seats, glyphs) in [
      (1, 1),
      (2, 2),
      (4, 4),
      (6, 6),
      (12, 12),
      (13, 12),
      (0, 0),
    ]) {
      test(
        'classic $seats seats → $glyphs chair glyphs at matching anchors',
        () {
          final p = _painter(TableVisualPreset.classicRectTable, seats: seats);
          expect(p.seatGlyphCount, glyphs);
          expect(p.chairAnchors(_tile), hasLength(glyphs));
        },
      );
      test('round $seats seats → $glyphs radial chair glyphs on the ring', () {
        final p = _painter(TableVisualPreset.roundTable, seats: seats);
        expect(p.seatGlyphCount, glyphs);
        final anchors = p.chairAnchors(_tile);
        expect(anchors, hasLength(glyphs));
        final surface = p.surfaceRect(_tile);
        final c = surface.center;
        final ring = surface.width / 2 + p.inset * 0.5;
        for (final a in anchors) {
          expect(
            ((a - c).distance - ring).abs(),
            lessThan(0.01),
            reason: 'radial anchor sits on the chair ring',
          );
        }
        if (glyphs > 0) {
          // Evenly spread, first chair at 12 o'clock.
          final first = anchors.first - c;
          expect(first.dx.abs(), lessThan(0.01));
          expect(first.dy, isNegative);
        }
      });
    }

    test('booth: benches ARE the seating — zero loose chair glyphs at any '
        'seat count', () {
      for (final seats in [0, 2, 4, 6, 12, 13]) {
        final p = _painter(TableVisualPreset.boothTable, seats: seats);
        expect(p.seatGlyphCount, 0, reason: 'seats=$seats');
        expect(p.chairAnchors(_tile), isEmpty);
      }
    });

    test(
      'barrels: the two barrels seat ${RestoflowTableShapePainter.kBarrelSeatCount}; '
      'extra configured seats become stools on the free sides (shared cap 12)',
      () {
        const barrelSeats = RestoflowTableShapePainter.kBarrelSeatCount;
        expect(barrelSeats, 2);
        for (final (seats, stools) in [
          (0, 0),
          (1, 0),
          (2, 0),
          (4, 2),
          (6, 4),
          (8, 6),
          (14, 10),
        ]) {
          final p = _painter(TableVisualPreset.tableWithBarrels, seats: seats);
          expect(p.seatGlyphCount, stools, reason: 'seats=$seats');
          final anchors = p.chairAnchors(_tile);
          expect(anchors, hasLength(stools));
          // Stools sit on the free (top/bottom) sides, clear of the barrels.
          final d = p.surfaceRect(_tile);
          for (final a in anchors) {
            expect(
              a.dy < d.top || a.dy > d.bottom,
              isTrue,
              reason: 'stool $a sits above/below the tabletop',
            );
          }
        }
      },
    );

    testWidgets('the EXACT numeric seat count stays visible even when glyphs '
        'cap (classic 14-seat)', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox.fromSize(
            size: _tile,
            child: _table(TableVisualPreset.classicRectTable, seats: 14),
          ),
        ),
      );
      expect(find.text('14'), findsOneWidget);
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
      expect(painter.seatGlyphCount, 12);
    });
  });

  group('every preset now paints through the ONE shared painter', () {
    for (final preset in TableVisualPreset.values) {
      testWidgets('${preset.wire} mounts one RepaintBoundary-isolated painter '
          'and keeps the fixed footprint', (tester) async {
        await tester.pumpWidget(
          _app(SizedBox.fromSize(size: _tile, child: _table(preset))),
        );
        final paintFinder = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowTableShapePainter,
        );
        expect(paintFinder, findsOneWidget);
        expect(
          (tester.widget<CustomPaint>(paintFinder).painter!
                  as RestoflowTableShapePainter)
              .preset,
          preset,
        );
        // Per-tile repaint isolation (118 deferred debt closed).
        expect(
          find.descendant(
            of: find.byType(RestoflowFloorTable),
            matching: find.ancestor(
              of: paintFinder,
              matching: find.byType(RepaintBoundary),
            ),
          ),
          findsWidgets,
        );
        expect(tester.getSize(find.byType(RestoflowFloorTable)), _tile);
        expect(find.text('T1'), findsOneWidget);
      });
    }

    testWidgets('detail level NEVER changes geometry: same tile size, same '
        'surface/content rects at every tier', (tester) async {
      for (final preset in TableVisualPreset.values) {
        Rect? surface0;
        Rect? content0;
        for (final detail in RestoflowFloorDetail.values) {
          final p = _painter(preset, detail: detail);
          surface0 ??= p.surfaceRect(_tile);
          content0 ??= p.contentRect(_tile);
          expect(p.surfaceRect(_tile), surface0, reason: '$preset $detail');
          expect(p.contentRect(_tile), content0, reason: '$preset $detail');
        }
      }
    });
  });

  group('fixture painter per kind + authoritative orientation', () {
    for (final kind in ['plant', 'door', 'window', 'cashier', 'wall']) {
      testWidgets('$kind mounts RestoflowFixturePainter at standard size', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 100,
              height: 80,
              child: RestoflowFloorFixture(kind: kind, quarterTurns: 1),
            ),
            width: 100,
          ),
        );
        final finder = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
        );
        expect(finder, findsOneWidget, reason: kind);
        final p =
            tester.widget<CustomPaint>(finder).painter!
                as RestoflowFixturePainter;
        expect(p.kind, kind);
        expect(
          p.quarterTurns,
          1,
          reason:
              'authoritative orientation reaches '
              'the painter — never inferred from aspect',
        );
      });
    }

    testWidgets('a TINY fixture keeps the lightweight flat fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 14,
            height: 8,
            child: RestoflowFloorFixture(kind: 'door'),
          ),
          width: 14,
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
        ),
        findsNothing,
      );
    });

    testWidgets('an unknown kind degrades to the wall look inside the painter '
        '(never a crash)', (tester) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 100,
            height: 80,
            child: RestoflowFloorFixture(kind: 'aquarium'),
          ),
          width: 100,
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
        ),
        findsOneWidget,
      );
    });

    testWidgets('the label gate is unchanged (cashier keeps its caption)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 100,
            height: 80,
            child: RestoflowFloorFixture(kind: 'cashier', label: 'Front till'),
          ),
          width: 100,
        ),
      );
      expect(find.text('Front till'), findsOneWidget);
    });
  });

  group('repaint hygiene', () {
    test('table painter: shouldRepaint false for identical inputs, true per '
        'changed field', () {
      final a = _painter(TableVisualPreset.roundTable, seats: 4);
      final b = _painter(TableVisualPreset.roundTable, seats: 4);
      expect(a.shouldRepaint(b), isFalse);
      expect(
        _painter(TableVisualPreset.roundTable, seats: 6).shouldRepaint(a),
        isTrue,
      );
      expect(
        _painter(TableVisualPreset.boothTable, seats: 4).shouldRepaint(a),
        isTrue,
      );
      expect(
        _painter(
          TableVisualPreset.roundTable,
          seats: 4,
          detail: RestoflowFloorDetail.rich,
        ).shouldRepaint(a),
        isTrue,
      );
    });

    test('fixture painter: shouldRepaint false for identical inputs, true per '
        'changed field', () {
      const base = RestoflowFixturePainter(
        kind: 'door',
        fill: Colors.white,
        ink: Colors.black,
        outline: Colors.grey,
        quarterTurns: 0,
        detail: RestoflowFloorDetail.standard,
      );
      const same = RestoflowFixturePainter(
        kind: 'door',
        fill: Colors.white,
        ink: Colors.black,
        outline: Colors.grey,
        quarterTurns: 0,
        detail: RestoflowFloorDetail.standard,
      );
      expect(base.shouldRepaint(same), isFalse);
      const turned = RestoflowFixturePainter(
        kind: 'door',
        fill: Colors.white,
        ink: Colors.black,
        outline: Colors.grey,
        quarterTurns: 2,
        detail: RestoflowFloorDetail.standard,
      );
      expect(base.shouldRepaint(turned), isTrue);
      const other = RestoflowFixturePainter(
        kind: 'plant',
        fill: Colors.white,
        ink: Colors.black,
        outline: Colors.grey,
        quarterTurns: 0,
        detail: RestoflowFloorDetail.standard,
      );
      expect(base.shouldRepaint(other), isTrue);
    });

    test('round chair-ring radius stays clear of the content rect', () {
      final p = _painter(TableVisualPreset.roundTable, seats: 12);
      final surface = p.surfaceRect(_tile);
      final content = p.contentRect(_tile);
      final ring = surface.width / 2 + p.inset * 0.5;
      final contentCorner = math.sqrt(
        math.pow(content.width / 2, 2) + math.pow(content.height / 2, 2),
      );
      expect(contentCorner, lessThan(ring));
    });
  });
}
