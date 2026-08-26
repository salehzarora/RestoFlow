import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset;

/// TABLE-VISUAL-LAYOUT-118 — the SHARED rendering of the floor/table presets.
///
/// One palette + two painters, consumed by the Dashboard editor, the POS
/// picker/move sheet and the kiosk floor through [RestoflowFloorSectionCanvas]
/// and [RestoflowFloorTable]. The painters are pure functions of their
/// fields (no theme, no locale, no randomness at paint time — the stone
/// pattern uses a FIXED seed), so the same section paints identically on
/// every surface and every frame, and `shouldRepaint` is false while nothing
/// changed (the canvas wraps the floor painter in a RepaintBoundary so table
/// state repaints never re-run it).
///
/// The DEFAULT presets draw nothing new: a plain-light floor is the pre-118
/// white canvas and a classic table keeps its chair-glyph widget tree, so the
/// existing goldens and geometry pins keep holding byte-for-byte.

/// TABLE-119A — the deterministic rendering DETAIL tier, derived from the
/// tile's rendered pixel width only (never from app identity): the same table
/// at the same size looks the same on every surface. Compact keeps tiny tiles
/// crisp and cheap (POS-like sizes get standard, kiosk/dashboard get rich).
enum RestoflowFloorDetail { compact, standard, rich }

/// The one shared size→detail rule (pinned by tests).
RestoflowFloorDetail restoflowFloorDetailFor(double tileWidth) => tileWidth < 64
    ? RestoflowFloorDetail.compact
    : tileWidth < 130
    ? RestoflowFloorDetail.standard
    : RestoflowFloorDetail.rich;

/// Chairs per (top, bottom, start, end) — the shared [top, bottom, top,
/// bottom, start, end] fill pattern (a 2-top reads 1+1 across, a 4-top 2+2).
/// Moved here from RestoflowFloorTable (TABLE-119A) so the painter, the
/// widget and the tests share ONE distribution; the numeric seat count is
/// always exact.
(int, int, int, int) floorChairSides(int seats, int cap) {
  final shown = seats < 0 ? 0 : (seats > cap ? cap : seats);
  const pattern = [0, 1, 0, 1, 2, 3];
  final out = [0, 0, 0, 0];
  for (var i = 0; i < shown; i++) {
    out[pattern[i % pattern.length]] += 1;
  }
  return (out[0], out[1], out[2], out[3]);
}

Color _darken(Color c, double t) => Color.lerp(c, const Color(0xFF000000), t)!;
Color _lighten(Color c, double t) => Color.lerp(c, const Color(0xFFFFFFFF), t)!;

/// The resolved paint colors of a [FloorPreset]: the canvas base, its pattern
/// line, an ink that contrasts the floor (labels drawn directly on it), and a
/// default table surface/ink/border that stays legible on that floor.
class RestoflowFloorPresetPalette {
  const RestoflowFloorPresetPalette({
    required this.preset,
    required this.base,
    required this.line,
    required this.ink,
    required this.tableSurface,
    required this.tableOnSurface,
    required this.tableBorder,
  });

  final FloorPreset preset;
  final Color base;
  final Color line;
  final Color ink;
  final Color tableSurface;
  final Color tableOnSurface;
  final Color tableBorder;

  bool get isDark => preset.isDark;

  static const _plainLight = RestoflowFloorPresetPalette(
    preset: FloorPreset.plainLight,
    // EXACTLY the pre-118 canvas color (golden/matrix parity).
    base: Colors.white,
    line: Color(0xFFE6E9EF),
    ink: Color(0xFF1F2937),
    tableSurface: Colors.white,
    tableOnSurface: Color(0xFF111827),
    tableBorder: Color(0xFFCBD2DC),
  );

  static const _woodDark = RestoflowFloorPresetPalette(
    preset: FloorPreset.woodDark,
    base: Color(0xFF3E2A1E),
    line: Color(0xFF261811),
    ink: Color(0xFFF5EDE4),
    tableSurface: Color(0xFFF7F3EE),
    tableOnSurface: Color(0xFF1F1A14),
    tableBorder: Color(0xFF9C7A5A),
  );

  static const _tileModern = RestoflowFloorPresetPalette(
    preset: FloorPreset.tileModern,
    base: Color(0xFFF1F4F7),
    line: Color(0xFFD2D9E1),
    ink: Color(0xFF1F2937),
    tableSurface: Colors.white,
    tableOnSurface: Color(0xFF111827),
    tableBorder: Color(0xFFB8C2CE),
  );

  static const _stoneNeutral = RestoflowFloorPresetPalette(
    preset: FloorPreset.stoneNeutral,
    base: Color(0xFFE7E1D7),
    line: Color(0xFFCFC5B7),
    ink: Color(0xFF2B2520),
    tableSurface: Color(0xFFFFFCF8),
    tableOnSurface: Color(0xFF1F1A14),
    tableBorder: Color(0xFFB9AD9C),
  );

  static RestoflowFloorPresetPalette of(FloorPreset preset) => switch (preset) {
    FloorPreset.plainLight => _plainLight,
    FloorPreset.woodDark => _woodDark,
    FloorPreset.tileModern => _tileModern,
    FloorPreset.stoneNeutral => _stoneNeutral,
  };
}

/// Paints one section floor pattern edge to edge (the canvas clips it to its
/// rounded rect). Plain light paints nothing (the canvas base color is the
/// whole look); the canvas does not even mount this painter for it.
class RestoflowFloorPresetPainter extends CustomPainter {
  const RestoflowFloorPresetPainter(this.preset);

  final FloorPreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final palette = RestoflowFloorPresetPalette.of(preset);
    switch (preset) {
      case FloorPreset.plainLight:
        return;
      case FloorPreset.woodDark:
        _paintWood(canvas, size, palette);
      case FloorPreset.tileModern:
        _paintTiles(canvas, size, palette);
      case FloorPreset.stoneNeutral:
        _paintStone(canvas, size, palette);
    }
  }

  void _paintWood(Canvas canvas, Size size, RestoflowFloorPresetPalette p) {
    final rows = math.max(6, (size.height / 34).round());
    final plankH = size.height / rows;
    final plankW = size.width / 3;
    final light = Paint()..color = Colors.white.withValues(alpha: 0.045);
    final grain = Paint()
      ..color = p.line.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final seam = Paint()
      ..color = p.line
      ..strokeWidth = 1.2;
    for (var r = 0; r < rows; r++) {
      final top = r * plankH;
      if (r.isEven) {
        canvas.drawRect(Rect.fromLTWH(0, top, size.width, plankH), light);
      }
      // Two faint grain lines per plank.
      for (var g = 1; g <= 2; g++) {
        final y = top + plankH * g / 3;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grain);
      }
      canvas.drawLine(Offset(0, top), Offset(size.width, top), seam);
      // Staggered end joints.
      final offset = (r % 3) * plankW / 3;
      for (var x = offset; x < size.width; x += plankW) {
        canvas.drawLine(Offset(x, top), Offset(x, top + plankH), seam);
      }
    }
  }

  void _paintTiles(Canvas canvas, Size size, RestoflowFloorPresetPalette p) {
    final cols = math.max(8, (size.width / 56).round());
    final cell = size.width / cols;
    final rows = (size.height / cell).ceil();
    final shade = Paint()..color = p.line.withValues(alpha: 0.28);
    final line = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c).isOdd) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), shade);
        }
      }
    }
    for (var c = 0; c <= cols; c++) {
      canvas.drawLine(Offset(c * cell, 0), Offset(c * cell, size.height), line);
    }
    for (var r = 0; r <= rows; r++) {
      canvas.drawLine(Offset(0, r * cell), Offset(size.width, r * cell), line);
    }
  }

  void _paintStone(Canvas canvas, Size size, RestoflowFloorPresetPalette p) {
    // Deterministic flagstones: a jittered grid driven by a FIXED-seed LCG so
    // every surface paints the same stones.
    final cols = math.max(6, (size.width / 92).round());
    final cell = size.width / cols;
    final rows = (size.height / (cell * 0.78)).ceil();
    final cellH = size.height / rows;
    var seed = 118;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed % 1000) / 1000;
    }

    final stroke = Paint()
      ..color = p.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final jx = (next() - 0.5) * cell * 0.18;
        final jy = (next() - 0.5) * cellH * 0.18;
        final shade = next();
        final rect = Rect.fromLTWH(
          c * cell + 2 + jx,
          r * cellH + 2 + jy,
          cell - 4,
          cellH - 4,
        );
        final fill = Paint()
          ..color = shade < 0.5
              ? Colors.white.withValues(alpha: 0.22)
              : p.line.withValues(alpha: 0.18);
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.16));
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(RestoflowFloorPresetPainter old) => old.preset != preset;
}

/// Paints one NON-classic table shape inside the tile's fixed footprint: the
/// surface (fill + border) plus its preset adornments — radial chairs for a
/// round top, barrels for a standing table, bench slabs for a booth. The
/// label column is a widget layered above by [RestoflowFloorTable].
class RestoflowTableShapePainter extends CustomPainter {
  const RestoflowTableShapePainter({
    required this.preset,
    required this.chairs,
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.chairColor,
    required this.inset,
    required this.scale,
    required this.surfaceRadius,
    this.detail = RestoflowFloorDetail.standard,
  });

  /// TABLE-119A: how much decoration to paint (shadows/gradients/extras).
  /// NEVER changes geometry - surface/content rects and anchors are
  /// detail-independent (pinned).
  final RestoflowFloorDetail detail;

  /// TABLE-119A: how many of a barrel table's configured seats the two
  /// barrels themselves represent; the rest render as stools.
  static const int kBarrelSeatCount = 2;

  final TableVisualPreset preset;

  /// Chair GLYPHS to draw (already capped by the caller; the numeric seat
  /// count is always exact and is rendered by the widget).
  final int chairs;
  final Color fill;
  final Color border;
  final double borderWidth;
  final Color chairColor;

  /// The chair ring thickness (the classic tile's chair inset), in pixels.
  final double inset;
  final double scale;
  final double surfaceRadius;

  /// TABLE-119A: how many SEAT GLYPHS (chairs/stools) this painter draws.
  /// classic/round: one chair per capped seat; booth: the benches ARE the
  /// seating (zero loose chairs); barrels: the two barrels seat
  /// [kBarrelSeatCount], extra capped seats become stools. The exact numeric
  /// seat count always stays visible in the label column.
  int get seatGlyphCount => switch (preset) {
    TableVisualPreset.classicRectTable => chairs,
    TableVisualPreset.roundTable => chairs,
    TableVisualPreset.boothTable => 0,
    TableVisualPreset.tableWithBarrels =>
      chairs > kBarrelSeatCount ? chairs - kBarrelSeatCount : 0,
  };

  /// TABLE-119A: the deterministic CENTRE of every seat glyph for [size]
  /// (physical coordinates — never mirrored). Pinned by tests; geometry is
  /// detail-independent.
  List<Offset> chairAnchors(Size size) {
    switch (preset) {
      case TableVisualPreset.boothTable:
        return const [];
      case TableVisualPreset.classicRectTable:
        final (top, bottom, start, end) = floorChairSides(chairs, 12);
        final out = <Offset>[];
        void side(int count, bool horizontal, bool leading) {
          if (count <= 0) return;
          final span = (horizontal ? size.width : size.height) - 2 * inset;
          for (var i = 0; i < count; i++) {
            final along = inset + (i + 1) * span / (count + 1);
            out.add(
              horizontal
                  ? Offset(
                      along,
                      leading ? inset * 0.5 : size.height - inset * 0.5,
                    )
                  : Offset(
                      leading ? inset * 0.5 : size.width - inset * 0.5,
                      along,
                    ),
            );
          }
        }

        side(top, true, true);
        side(bottom, true, false);
        side(start, false, true);
        side(end, false, false);
        return out;
      case TableVisualPreset.roundTable:
        if (chairs <= 0) return const [];
        final surface = surfaceRect(size);
        final c = surface.center;
        final ring = surface.width / 2 + inset * 0.5;
        return [
          for (var i = 0; i < chairs; i++)
            c +
                Offset(
                      math.cos(-math.pi / 2 + i * 2 * math.pi / chairs),
                      math.sin(-math.pi / 2 + i * 2 * math.pi / chairs),
                    ) *
                    ring,
        ];
      case TableVisualPreset.tableWithBarrels:
        final stools = seatGlyphCount;
        if (stools <= 0) return const [];
        final surface = surfaceRect(size);
        final topCount = (stools + 1) ~/ 2;
        final bottomCount = stools - topCount;
        final out = <Offset>[];
        void row(int count, bool top) {
          for (var i = 0; i < count; i++) {
            final x = surface.left + (i + 1) * surface.width / (count + 1);
            out.add(
              Offset(
                x,
                top ? surface.top - 2.6 * scale : surface.bottom + 2.6 * scale,
              ),
            );
          }
        }

        row(topCount, true);
        row(bottomCount, false);
        return out;
    }
  }

  /// The surface rect (where the label column lives) for [size]. Shared with
  /// the widget so the text sits exactly on the painted surface.
  Rect surfaceRect(Size size) {
    switch (preset) {
      case TableVisualPreset.classicRectTable:
        return Rect.fromLTWH(
          inset,
          inset,
          size.width - 2 * inset,
          size.height - 2 * inset,
        );
      case TableVisualPreset.roundTable:
        final d = math.min(size.width, size.height) - 2 * inset;
        return Rect.fromCenter(
          center: size.center(Offset.zero),
          width: d,
          height: d,
        );
      case TableVisualPreset.tableWithBarrels:
        final d = _barrelDiameter(size);
        return Rect.fromLTRB(
          d * 0.82 + 2 * scale,
          inset * 0.6,
          size.width - d * 0.82 - 2 * scale,
          size.height - inset * 0.6,
        );
      case TableVisualPreset.boothTable:
        return Rect.fromLTRB(
          inset * 0.7,
          inset * 1.15,
          size.width - inset * 0.7,
          size.height - inset * 1.15,
        );
    }
  }

  /// TABLE-118F: where the label column may live. For the rectangular
  /// presets this is the painted surface itself; for a ROUND table it is a
  /// rectangle INSCRIBED in the circle (width 0.66·d, height 0.70·d — its
  /// corners sit 0.481·d from the centre, inside the 0.5·d rim), so a long
  /// status footnote can never cross the visible round edge. The painted
  /// circle ([surfaceRect]) and the tile footprint are unchanged.
  Rect contentRect(Size size) {
    final surface = surfaceRect(size);
    if (preset != TableVisualPreset.roundTable) return surface;
    return Rect.fromCenter(
      center: surface.center,
      width: surface.width * 0.66,
      height: surface.height * 0.70,
    );
  }

  double _barrelDiameter(Size size) =>
      math.min(size.height - inset * 0.8, size.width * 0.27);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final surface = surfaceRect(size);
    final fillPaint = Paint()..color = fill;
    final borderPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    switch (preset) {
      case TableVisualPreset.classicRectTable:
        _paintChairs(canvas, size);
        final rr = RRect.fromRectAndRadius(
          surface,
          Radius.circular(surfaceRadius),
        );
        _paintShadow(canvas, (c, p) => c.drawRRect(rr.shift(_shadowOffset), p));
        canvas.drawRRect(rr, _surfacePaint(surface) ?? fillPaint);
        canvas.drawRRect(rr, borderPaint);
        _paintEdgeHighlight(canvas, (c, p) {
          c.drawRRect(rr.deflate(1.6 * scale), p);
        });
      case TableVisualPreset.roundTable:
        _paintChairs(canvas, size);
        final center = surface.center;
        final r = surface.width / 2;
        _paintShadow(
          canvas,
          (c, p) => c.drawCircle(center + _shadowOffset, r, p),
        );
        canvas.drawCircle(center, r, _roundSurfacePaint(surface) ?? fillPaint);
        canvas.drawCircle(center, r, borderPaint);
        // The inner ring reads as a round top even at small scales; at rich
        // it doubles as a place-setting hint.
        canvas.drawCircle(
          center,
          r * 0.72,
          Paint()
            ..color = border.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      case TableVisualPreset.tableWithBarrels:
        final d = _barrelDiameter(size);
        for (final cx in [d / 2 + 1, size.width - d / 2 - 1]) {
          _paintBarrel(canvas, Offset(cx, size.height / 2), d);
        }
        _paintStools(canvas, size);
        final rr = RRect.fromRectAndRadius(
          surface,
          Radius.circular(surfaceRadius),
        );
        _paintShadow(canvas, (c, p) => c.drawRRect(rr.shift(_shadowOffset), p));
        canvas.drawRRect(rr, _surfacePaint(surface) ?? fillPaint);
        canvas.drawRRect(rr, borderPaint);
        if (detail == RestoflowFloorDetail.rich) {
          // Two plank grain strokes along the tabletop.
          final grain = Paint()
            ..color = _darken(fill, 0.06)
            ..strokeWidth = 1;
          for (final t in [0.38, 0.62]) {
            final y = surface.top + surface.height * t;
            canvas.drawLine(
              Offset(surface.left + 2 * scale, y),
              Offset(surface.right - 2 * scale, y),
              grain,
            );
          }
        }
      case TableVisualPreset.boothTable:
        final benchInset = inset * 0.5;
        final benchH = inset * 0.85;
        final backH = inset * 0.32;
        for (final top in [true, false]) {
          final benchTop = top
              ? 1.0 + backH
              : size.height - benchH - 1.0 - backH;
          final backTop = top ? 1.0 : size.height - backH - 1.0;
          final bench = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              benchInset,
              benchTop,
              size.width - 2 * benchInset,
              benchH,
            ),
            Radius.circular(3 * scale),
          );
          // The darker back edge on the OUTWARD side of each bench.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                benchInset,
                backTop,
                size.width - 2 * benchInset,
                backH,
              ),
              Radius.circular(1.5 * scale),
            ),
            Paint()..color = _darken(chairColor, 0.35).withValues(alpha: 0.75),
          );
          canvas.drawRRect(
            bench,
            Paint()..color = chairColor.withValues(alpha: 0.65),
          );
          if (detail == RestoflowFloorDetail.rich) {
            // Upholstery tuft notches.
            final tuft = Paint()
              ..color = _darken(chairColor, 0.25).withValues(alpha: 0.6)
              ..strokeWidth = 1;
            for (final t in [0.3, 0.5, 0.7]) {
              final x = bench.left + bench.width * t;
              canvas.drawLine(
                Offset(x, bench.top + 1.5 * scale),
                Offset(x, bench.bottom - 1.5 * scale),
                tuft,
              );
            }
          }
        }
        final rr = RRect.fromRectAndRadius(
          surface,
          Radius.circular(surfaceRadius),
        );
        _paintShadow(canvas, (c, p) => c.drawRRect(rr.shift(_shadowOffset), p));
        canvas.drawRRect(rr, _surfacePaint(surface) ?? fillPaint);
        canvas.drawRRect(rr, borderPaint);
    }
  }

  Offset get _shadowOffset => Offset(1.0 * scale, 1.5 * scale);

  /// Solid two-tone depth shadow — deliberately NO blur (PowerVR/Skia: blur
  /// and saveLayer are the jank drivers; a crisp offset shade reads fine
  /// top-down). Skipped entirely at compact.
  void _paintShadow(Canvas canvas, void Function(Canvas, Paint) draw) {
    if (detail == RestoflowFloorDetail.compact) return;
    draw(
      canvas,
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.14),
    );
  }

  /// Linear top-left light on rectangular tops (standard+); null = flat fill.
  Paint? _surfacePaint(Rect surface) {
    if (detail == RestoflowFloorDetail.compact) return null;
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_lighten(fill, 0.09), fill, _darken(fill, 0.05)],
      ).createShader(surface);
  }

  /// Radial light for the round top (standard+).
  Paint? _roundSurfacePaint(Rect surface) {
    if (detail == RestoflowFloorDetail.compact) return null;
    return Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 1.1,
        colors: [_lighten(fill, 0.11), fill, _darken(fill, 0.05)],
      ).createShader(surface);
  }

  void _paintEdgeHighlight(Canvas canvas, void Function(Canvas, Paint) draw) {
    if (detail != RestoflowFloorDetail.rich) return;
    draw(
      canvas,
      Paint()
        ..color = _lighten(fill, 0.35).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// One REAL chair: seat pad + outward backrest, rotated so the backrest
  /// faces AWAY from the table ([outwardAngle] = direction the sitter's back
  /// points; 0 = up). Physical coordinates — never mirrored.
  void _paintChair(Canvas canvas, Offset center, double outwardAngle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(outwardAngle);
    final seatW = 7.4 * scale;
    final seatH = 6.4 * scale;
    final seat = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, 0.6 * scale),
        width: seatW,
        height: seatH,
      ),
      Radius.circular(1.8 * scale),
    );
    final back = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, -seatH / 2 - 0.4 * scale),
        width: seatW * 1.08,
        height: 2.2 * scale,
      ),
      Radius.circular(1.1 * scale),
    );
    canvas.drawRRect(back, Paint()..color = _darken(chairColor, 0.28));
    canvas.drawRRect(seat, Paint()..color = chairColor.withValues(alpha: 0.85));
    if (detail != RestoflowFloorDetail.compact) {
      canvas.drawRRect(
        seat,
        Paint()
          ..color = _darken(chairColor, 0.3).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
    if (detail == RestoflowFloorDetail.rich) {
      // Cushion crease.
      canvas.drawLine(
        Offset(-seatW * 0.28, 1.2 * scale),
        Offset(seatW * 0.28, 1.2 * scale),
        Paint()
          ..color = _darken(chairColor, 0.2).withValues(alpha: 0.5)
          ..strokeWidth = 0.8,
      );
    }
    canvas.restore();
  }

  /// All chair glyphs for classic/round from the shared anchors.
  void _paintChairs(Canvas canvas, Size size) {
    final anchors = chairAnchors(size);
    if (anchors.isEmpty) return;
    if (preset == TableVisualPreset.roundTable) {
      final c = surfaceRect(size).center;
      for (final a in anchors) {
        final dir = a - c;
        _paintChair(canvas, a, math.atan2(dir.dy, dir.dx) + math.pi / 2);
      }
      return;
    }
    for (final a in anchors) {
      final double angle;
      if (a.dy <= inset) {
        angle = 0; // top side, backrest up
      } else if (a.dy >= size.height - inset) {
        angle = math.pi; // bottom side
      } else if (a.dx <= inset) {
        angle = -math.pi / 2; // start side, backrest left
      } else {
        angle = math.pi / 2; // end side
      }
      _paintChair(canvas, a, angle);
    }
  }

  /// One barrel: shadow, body, stave lines, hoops, top-rim hint.
  void _paintBarrel(Canvas canvas, Offset c, double d) {
    final r = d / 2;
    _paintShadow(
      canvas,
      (cv, p) => cv.drawCircle(c + _shadowOffset * 0.7, r, p),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()..color = _darken(chairColor, 0.12).withValues(alpha: 0.55),
    );
    final hoopPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(c, r, hoopPaint);
    if (detail != RestoflowFloorDetail.compact) {
      // Vertical stave seams (chords).
      final stave = Paint()
        ..color = _darken(chairColor, 0.35).withValues(alpha: 0.55)
        ..strokeWidth = 1;
      for (final k in [-0.45, 0.0, 0.45]) {
        final x = c.dx + r * k;
        final half = math.sqrt(math.max(0, r * r - (x - c.dx) * (x - c.dx)));
        canvas.drawLine(Offset(x, c.dy - half), Offset(x, c.dy + half), stave);
      }
      // Two hoops.
      for (final k in [-0.42, 0.42]) {
        final y = c.dy + d * k / 2;
        final half = math.sqrt(math.max(0, r * r - (y - c.dy) * (y - c.dy)));
        canvas.drawLine(
          Offset(c.dx - half, y),
          Offset(c.dx + half, y),
          hoopPaint,
        );
      }
    }
    if (detail == RestoflowFloorDetail.rich) {
      canvas.drawCircle(
        c,
        r * 0.55,
        Paint()
          ..color = _lighten(chairColor, 0.25).withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  /// Round bar stools for a barrel table's extra seats.
  void _paintStools(Canvas canvas, Size size) {
    final r = 3.2 * scale;
    for (final a in chairAnchors(size)) {
      canvas.drawCircle(
        a,
        r,
        Paint()..color = chairColor.withValues(alpha: 0.85),
      );
      if (detail != RestoflowFloorDetail.compact) {
        canvas.drawCircle(
          a,
          r,
          Paint()
            ..color = _darken(chairColor, 0.3).withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }
  }

  @override
  bool shouldRepaint(RestoflowTableShapePainter old) =>
      old.preset != preset ||
      old.chairs != chairs ||
      old.fill != fill ||
      old.border != border ||
      old.borderWidth != borderWidth ||
      old.chairColor != chairColor ||
      old.inset != inset ||
      old.scale != scale ||
      old.surfaceRadius != surfaceRadius ||
      old.detail != detail;
}

/// TABLE-119A — paints one floor fixture's recognizable interior (the flat
/// slab + border stays on the widget's DecoratedBox): a door leaf with its
/// swing arc, a window frame with mullions and glare, wall joints, a cashier
/// counter with register, a potted plant with leaves. Orientation comes from
/// the AUTHORITATIVE `orientation_quarter_turns` on the wire (never inferred
/// from aspect); painting rotates while the outer room rect stays untouched.
/// Vector-only, palette-derived, no blur / saveLayer / images.
class RestoflowFixturePainter extends CustomPainter {
  const RestoflowFixturePainter({
    required this.kind,
    required this.fill,
    required this.ink,
    required this.outline,
    this.quarterTurns = 0,
    this.detail = RestoflowFloorDetail.standard,
  });

  /// `wall` / `door` / `window` / `cashier` / `plant`; an unknown kind
  /// degrades to the wall look (forward-compatible, never a crash).
  final String kind;
  final Color fill;
  final Color ink;
  final Color outline;
  final int quarterTurns;
  final RestoflowFloorDetail detail;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Rotate the ARTWORK by the authoritative quarter turns; the room rect
    // already carries the swapped footprint, so odd turns paint into a local
    // frame with swapped axes.
    final odd = quarterTurns.isOdd;
    final local = odd ? Size(size.height, size.width) : size;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(quarterTurns * math.pi / 2);
    canvas.translate(-local.width / 2, -local.height / 2);
    switch (kind) {
      case 'door':
        _paintDoor(canvas, local);
      case 'window':
        _paintWindow(canvas, local);
      case 'cashier':
        _paintCashier(canvas, local);
      case 'plant':
        _paintPlant(canvas, local);
      default:
        _paintWall(canvas, local);
    }
    canvas.restore();
  }

  void _paintWall(Canvas canvas, Size s) {
    final joint = Paint()
      ..color = ink.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    final n = (s.width / 26).clamp(1, 8).floor();
    for (var i = 1; i <= n; i++) {
      final x = i * s.width / (n + 1);
      canvas.drawLine(Offset(x, 1), Offset(x, s.height - 1), joint);
    }
    // Slightly darker long edge for depth.
    canvas.drawLine(
      Offset(0, s.height - 0.8),
      Offset(s.width, s.height - 0.8),
      Paint()
        ..color = ink.withValues(alpha: 0.22)
        ..strokeWidth = 1.2,
    );
  }

  void _paintDoor(Canvas canvas, Size s) {
    final leafW = math.min(s.width * 0.42, s.height * 2.4);
    // Door LEAF along the frame from the hinge end.
    final leaf = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, s.height * 0.15, leafW, s.height * 0.7),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(leaf, Paint()..color = ink.withValues(alpha: 0.85));
    // Swing arc sweeping INTO the room from the hinge (bottom-left corner of
    // the frame); CustomPaint does not clip, so the arc reads on the floor.
    final sweep = math.min(s.width * 0.9, s.height * 6.0);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(1, s.height), radius: sweep),
      0,
      math.pi / 2,
      false,
      Paint()
        ..color = ink.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (detail == RestoflowFloorDetail.rich) {
      canvas.drawCircle(
        Offset(1 + leafW - 2.5, s.height * 0.5),
        1.6,
        Paint()..color = _lighten(ink, 0.4),
      );
    }
  }

  void _paintWindow(Canvas canvas, Size s) {
    final frame = Paint()
      ..color = ink.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final r = Rect.fromLTWH(0.8, 0.8, s.width - 1.6, s.height - 1.6);
    canvas.drawRect(r, frame);
    // Mullions along the length.
    final n = (s.width / 30).clamp(1, 6).floor();
    for (var i = 1; i <= n; i++) {
      final x = r.left + i * r.width / (n + 1);
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), frame);
    }
    if (detail != RestoflowFloorDetail.compact) {
      // Two diagonal glare strokes.
      final glare = Paint()
        ..color = _lighten(ink, 0.55).withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (final t in [0.18, 0.3]) {
        canvas.drawLine(
          Offset(r.left + r.width * t, r.bottom - 1),
          Offset(r.left + r.width * (t + 0.08), r.top + 1),
          glare,
        );
      }
      // Sill on the room-facing edge.
      canvas.drawLine(
        Offset(r.left, r.bottom),
        Offset(r.right, r.bottom),
        Paint()
          ..color = ink.withValues(alpha: 0.5)
          ..strokeWidth = 2,
      );
    }
  }

  void _paintCashier(Canvas canvas, Size s) {
    // Counter shade along the service edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, s.height * 0.62, s.width - 2, s.height * 0.34),
        const Radius.circular(2),
      ),
      Paint()..color = ink.withValues(alpha: 0.18),
    );
    // Register block + screen.
    final regW = math.min(s.width * 0.34, s.height * 0.8);
    final reg = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        s.width * 0.5 - regW / 2,
        s.height * 0.14,
        regW,
        s.height * 0.42,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(reg, Paint()..color = ink.withValues(alpha: 0.85));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          reg.left + regW * 0.18,
          reg.top + 2,
          regW * 0.64,
          math.max(2.0, s.height * 0.14),
        ),
        const Radius.circular(1),
      ),
      Paint()..color = _lighten(ink, 0.55),
    );
    if (detail == RestoflowFloorDetail.rich) {
      canvas.drawLine(
        Offset(reg.left + 2, reg.bottom - 3),
        Offset(reg.right - 2, reg.bottom - 3),
        Paint()
          ..color = _lighten(ink, 0.35)
          ..strokeWidth = 1,
      );
    }
  }

  void _paintPlant(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final side = math.min(s.width, s.height);
    // Pot: a small trapezoid at the centre-bottom third.
    final potW = side * 0.34;
    final potTop = s.height * 0.55;
    final pot = Path()
      ..moveTo(cx - potW / 2, potTop)
      ..lineTo(cx + potW / 2, potTop)
      ..lineTo(cx + potW * 0.36, s.height * 0.86)
      ..lineTo(cx - potW * 0.36, s.height * 0.86)
      ..close();
    canvas.drawPath(pot, Paint()..color = _darken(ink, 0.25));
    // Leaves: bezier fronds fanning up from the pot rim.
    final leafInk = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, side * 0.045)
      ..strokeCap = StrokeCap.round;
    final leafSoft = Paint()
      ..color = _lighten(ink, 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, side * 0.035)
      ..strokeCap = StrokeCap.round;
    final origin = Offset(cx, potTop);
    final reach = side * 0.34;
    final count = detail == RestoflowFloorDetail.compact ? 3 : 6;
    for (var i = 0; i < count; i++) {
      final a = -math.pi / 2 + (i - (count - 1) / 2) * (math.pi / (count + 1));
      final tip = origin + Offset(math.cos(a), math.sin(a)) * reach;
      final ctrl =
          origin + Offset(math.cos(a) * 0.4, math.sin(a) - 0.55) * reach;
      canvas.drawPath(
        Path()
          ..moveTo(origin.dx, origin.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy),
        i.isEven ? leafInk : leafSoft,
      );
    }
  }

  @override
  bool shouldRepaint(RestoflowFixturePainter old) =>
      old.kind != kind ||
      old.fill != fill ||
      old.ink != ink ||
      old.outline != outline ||
      old.quarterTurns != quarterTurns ||
      old.detail != detail;
}
