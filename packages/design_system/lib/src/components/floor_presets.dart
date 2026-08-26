import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset, floorElementStylesFor;

import 'floor_scene_theme.dart';

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
    this.material,
  });

  /// TABLE-119D: the table's surface MATERIAL. When set, the top renders the
  /// material palette (wood grain, bevel, themed chairs) and [fill] becomes a
  /// translucent STATE WASH layered over it, so status/selection tints stay
  /// visible without erasing the material. `null` keeps the exact pre-119D
  /// flat rendering (legacy pins). Never changes geometry.
  final RestoflowFloorMaterial? material;

  RestoflowMaterialPalette? get _pal =>
      material == null ? null : RestoflowMaterialPalette.of(material!);

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
        _paintMaterialOverlays(
          canvas,
          surface,
          (c, p) => c.drawRRect(rr, p),
          round: false,
        );
        _paintGrain(canvas, surface, round: false);
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
        _paintMaterialOverlays(
          canvas,
          surface,
          (c, p) => c.drawCircle(center, r, p),
          round: true,
        );
        _paintGrain(canvas, surface, round: true);
        canvas.drawCircle(center, r, borderPaint);
        if (_pal == null) {
          // Legacy inner ring: reads as a round top even at small scales.
          canvas.drawCircle(
            center,
            r * 0.72,
            Paint()
              ..color = border.withValues(alpha: 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        } else {
          // 119D: a themed rim bevel plus per-seat place settings at rich —
          // the table reads as SET for dining, not a disc with text.
          canvas.drawCircle(
            center,
            r - 1.2 * scale,
            Paint()
              ..color = _pal!.edge.withValues(alpha: 0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
          _paintPlaceSettings(canvas, surface);
        }
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
        _paintMaterialOverlays(
          canvas,
          surface,
          (c, p) => c.drawRRect(rr, p),
          round: false,
        );
        _paintGrain(canvas, surface, round: false);
        canvas.drawRRect(rr, borderPaint);
        if (_pal == null && detail == RestoflowFloorDetail.rich) {
          // Legacy: two plank grain strokes along the tabletop.
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
        // 119D: upholstered bench + frame colors from the material palette;
        // legacy keeps the border-derived tones exactly.
        final benchSeat = _pal?.chairSeat ?? chairColor;
        final benchBack = _pal == null
            ? _darken(chairColor, 0.35).withValues(alpha: 0.75)
            : _pal!.chairFrame;
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
            Paint()..color = benchBack,
          );
          canvas.drawRRect(
            bench,
            Paint()
              ..color = benchSeat.withValues(alpha: _pal == null ? 0.65 : 1.0),
          );
          if (_pal != null && detail != RestoflowFloorDetail.compact) {
            // Cushion highlight along the seat.
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  benchInset + 2 * scale,
                  benchTop + 1.2 * scale,
                  size.width - 2 * benchInset - 4 * scale,
                  benchH * 0.38,
                ),
                Radius.circular(2 * scale),
              ),
              Paint()..color = _lighten(benchSeat, 0.14),
            );
          }
          if (detail == RestoflowFloorDetail.rich) {
            // Upholstery tuft notches.
            final tuft = Paint()
              ..color = _darken(benchSeat, 0.25).withValues(alpha: 0.6)
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
        _paintMaterialOverlays(
          canvas,
          surface,
          (c, p) => c.drawRRect(rr, p),
          round: false,
        );
        _paintGrain(canvas, surface, round: false);
        canvas.drawRRect(rr, borderPaint);
    }
  }

  /// TABLE-119D: the material layered OVER the legacy state surface.
  ///
  /// The app's [fill] is painted exactly as before (so every state contract —
  /// including the kiosk's translucent "occupied" surface — keeps its
  /// pre-119D meaning), and the material arrives as two chroma-adaptive
  /// overlays:
  ///
  ///  * a VEIL of the material gradient whose alpha falls as the fill gets
  ///    more chromatic — a neutral "available" surface turns into rich wood,
  ///    while a status/selection tint keeps showing through;
  ///  * an ACCENT wash for chromatic fills — the fill re-saturated so even
  ///    the pale Material *container* tones the apps pass (POS/Dashboard)
  ///    stay unmistakably colored on top of the material.
  ///
  /// Material-only (legacy `null` paints nothing here).
  void _paintMaterialOverlays(
    Canvas canvas,
    Rect surface,
    void Function(Canvas, Paint) draw, {
    required bool round,
  }) {
    final pal = _pal;
    if (pal == null) return;
    final chroma =
        math.max(fill.r, math.max(fill.g, fill.b)) -
        math.min(fill.r, math.min(fill.g, fill.b));
    final veilAlpha = (0.85 - 3.5 * chroma).clamp(0.30, 0.85).toDouble();
    final veil = Paint();
    if (detail == RestoflowFloorDetail.compact) {
      veil.color = pal.top.withValues(alpha: veilAlpha);
    } else {
      veil.shader =
          (round
                  ? RadialGradient(
                      center: const Alignment(-0.3, -0.3),
                      radius: 1.1,
                      colors: [
                        pal.topLight.withValues(alpha: veilAlpha),
                        pal.top.withValues(alpha: veilAlpha),
                        pal.topDark.withValues(alpha: veilAlpha),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        pal.topLight.withValues(alpha: veilAlpha),
                        pal.top.withValues(alpha: veilAlpha),
                        pal.topDark.withValues(alpha: veilAlpha),
                      ],
                    ))
              .createShader(surface);
    }
    draw(canvas, veil);
    final accentAlpha = (fill.a * (2.2 * chroma)).clamp(0.0, 0.30).toDouble();
    if (accentAlpha > 0.02) {
      final hsl = HSLColor.fromColor(fill.withValues(alpha: 1));
      final accent = hsl
          .withSaturation((hsl.saturation * 2.5).clamp(0.40, 0.85).toDouble())
          .withLightness(hsl.lightness.clamp(0.35, 0.60).toDouble())
          .toColor();
      draw(canvas, Paint()..color = accent.withValues(alpha: accentAlpha));
    }
    if (material == RestoflowFloorMaterial.plastic &&
        detail != RestoflowFloorDetail.compact) {
      // 120B: one molded gloss sweep so plastic reads glossy, never wooden.
      canvas.drawArc(
        Rect.fromLTWH(
          surface.left + surface.width * 0.10,
          surface.top + surface.height * 0.08,
          surface.width * 0.55,
          surface.height * 0.5,
        ),
        math.pi * 1.05,
        math.pi * 0.45,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// TABLE-120B: the shared grain-strength rule, pinned by tests — RUSTIC
  /// wood reads visibly more weathered than every other family.
  static double grainAlpha(RestoflowFloorMaterial m) =>
      m == RestoflowFloorMaterial.rusticWood ? 0.62 : 0.42;

  /// TABLE-120B: plank strokes per rectangular top (pinned by tests): compact
  /// is always clean (0), rustic carries the plank character (5 at rich),
  /// everything else keeps the 119D 2/3.
  static int grainLineCount(
    RestoflowFloorMaterial m,
    RestoflowFloorDetail detail,
  ) {
    if (detail == RestoflowFloorDetail.compact) return 0;
    final rich = detail == RestoflowFloorDetail.rich;
    if (m == RestoflowFloorMaterial.rusticWood) return rich ? 5 : 3;
    return rich ? 3 : 2;
  }

  /// TABLE-119D/120B: material grain over the top — plank strokes on
  /// rectangular tops (rustic adds deterministic drift + knot dashes),
  /// growth rings on round ones. Skipped at compact and for grainless
  /// materials (plastic).
  void _paintGrain(Canvas canvas, Rect surface, {required bool round}) {
    final pal = _pal;
    if (pal == null ||
        detail == RestoflowFloorDetail.compact ||
        pal.grain.a == 0) {
      return;
    }
    final rustic = material == RestoflowFloorMaterial.rusticWood;
    final g = Paint()
      ..color = pal.grain.withValues(alpha: grainAlpha(material!))
      ..strokeWidth = rustic ? 1.2 : 1;
    if (round) {
      final c = surface.center;
      final r = surface.width / 2;
      final ring = Paint()
        ..color = pal.grain.withValues(alpha: grainAlpha(material!) - 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rustic ? 1.2 : 1;
      for (final k
          in detail == RestoflowFloorDetail.rich
              ? (rustic
                    ? const [0.26, 0.42, 0.56, 0.68]
                    : const [0.30, 0.50, 0.66])
              : const [0.36, 0.60]) {
        canvas.drawCircle(c, r * k, ring);
      }
      return;
    }
    final n = grainLineCount(material!, detail);
    for (var i = 1; i <= n; i++) {
      // Rustic planks drift a little (deterministic, index-driven — never
      // random at paint time).
      final drift = rustic ? ((i.isEven ? 1 : -1) * 0.9 * scale) : 0.0;
      final y = surface.top + surface.height * i / (n + 1) + drift;
      canvas.drawLine(
        Offset(surface.left + 3 * scale, y),
        Offset(surface.right - 3 * scale, y),
        g,
      );
    }
    if (rustic && detail == RestoflowFloorDetail.rich) {
      // Two short knot dashes for the weathered character (bounded).
      final knot = Paint()
        ..color = pal.grain.withValues(alpha: 0.55)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (final (tx, ty) in const [(0.24, 0.36), (0.68, 0.62)]) {
        final p = Offset(
          surface.left + surface.width * tx,
          surface.top + surface.height * ty,
        );
        canvas.drawLine(p, p + Offset(3.5 * scale, 0), knot);
      }
    }
  }

  /// TABLE-119D: one faint plate per seat around a round material top (rich
  /// only, bounded by the chair cap) — the strongest "this is a dining
  /// table" cue at large sizes.
  void _paintPlaceSettings(Canvas canvas, Rect surface) {
    if (detail != RestoflowFloorDetail.rich || chairs <= 0) return;
    final c = surface.center;
    final r = surface.width / 2;
    final rim = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final wellPaint = Paint()..color = Colors.white.withValues(alpha: 0.16);
    for (var i = 0; i < chairs; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / chairs;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.70;
      canvas.drawCircle(p, 3.6 * scale, wellPaint);
      canvas.drawCircle(p, 3.6 * scale, rim);
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
  /// 119D: the BASE stays the app's state fill exactly as pre-119D (every
  /// state contract preserved); the material arrives as the overlays in
  /// [_paintMaterialOverlays].
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
        ..color = (_pal == null ? _lighten(fill, 0.35) : _pal!.topLight)
            .withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// One REAL chair: seat pad + outward backrest, rotated so the backrest
  /// faces AWAY from the table ([outwardAngle] = direction the sitter's back
  /// points; 0 = up). Physical coordinates — never mirrored.
  void _paintChair(Canvas canvas, Offset center, double outwardAngle) {
    // 119D: themed seat/frame from the material palette; legacy keeps the
    // border-derived chair color exactly.
    final seatColor = _pal?.chairSeat ?? chairColor;
    final frameColor = _pal == null
        ? _darken(chairColor, 0.28)
        : _pal!.chairFrame;
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
    canvas.drawRRect(back, Paint()..color = frameColor);
    canvas.drawRRect(
      seat,
      Paint()..color = seatColor.withValues(alpha: _pal == null ? 0.85 : 1.0),
    );
    if (detail != RestoflowFloorDetail.compact) {
      canvas.drawRRect(
        seat,
        Paint()
          ..color = _darken(seatColor, 0.3).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      if (_pal != null) {
        // Cushion inset: the lighter pad on the seat.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(0, 0.8 * scale),
              width: seatW * 0.66,
              height: seatH * 0.58,
            ),
            Radius.circular(1.4 * scale),
          ),
          Paint()..color = _lighten(seatColor, 0.18),
        );
      }
    }
    if (detail == RestoflowFloorDetail.rich) {
      // Cushion crease.
      canvas.drawLine(
        Offset(-seatW * 0.28, 1.2 * scale),
        Offset(seatW * 0.28, 1.2 * scale),
        Paint()
          ..color = _darken(seatColor, 0.2).withValues(alpha: 0.5)
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
    // 119D: solid oak body (the tabletop tone, so barrels stay visible on a
    // dark floor) + iron-toned hoops from the material palette; legacy keeps
    // the translucent border-derived look exactly.
    final body = _pal == null
        ? _darken(chairColor, 0.12).withValues(alpha: 0.55)
        : _pal!.top;
    final hoopColor = _pal == null ? border : _pal!.chairFrame;
    _paintShadow(
      canvas,
      (cv, p) => cv.drawCircle(c + _shadowOffset * 0.7, r, p),
    );
    canvas.drawCircle(c, r, Paint()..color = body);
    final hoopPaint = Paint()
      ..color = hoopColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(c, r, hoopPaint);
    if (detail != RestoflowFloorDetail.compact) {
      // Vertical stave seams (chords).
      final stave = Paint()
        ..color = (_pal == null
            ? _darken(chairColor, 0.35).withValues(alpha: 0.55)
            : _pal!.chairFrame.withValues(alpha: 0.8))
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
          ..color = _lighten(
            _pal?.top ?? chairColor,
            0.25,
          ).withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  /// Round bar stools for a barrel table's extra seats.
  void _paintStools(Canvas canvas, Size size) {
    final seatColor = _pal?.chairSeat ?? chairColor;
    final r = 3.2 * scale;
    for (final a in chairAnchors(size)) {
      canvas.drawCircle(
        a,
        r,
        Paint()..color = seatColor.withValues(alpha: _pal == null ? 0.85 : 1.0),
      );
      if (detail != RestoflowFloorDetail.compact) {
        canvas.drawCircle(
          a,
          r,
          Paint()
            ..color = _darken(seatColor, 0.3).withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        if (_pal != null) {
          // Stool cushion highlight.
          canvas.drawCircle(
            a,
            r * 0.5,
            Paint()..color = _lighten(seatColor, 0.2),
          );
        }
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
      old.detail != detail ||
      old.material != material;
}

/// TABLE-119A/119D — paints one floor fixture's recognizable identity. Since
/// 119D the door/window/cashier/plant artwork OWNS its whole surface (base
/// slab included — the widget's box behind those kinds is transparent): a
/// door frame with leaf and swing arc, a glass window with frame/mullions/
/// sill, a walnut cashier counter with register/terminal, a top-down potted
/// plant. Walls (and unknown kinds, which degrade to the wall look) keep the
/// widget's slab fill and get stroke-only joints. Orientation comes from the
/// AUTHORITATIVE `orientation_quarter_turns` on the wire (never inferred
/// from aspect); painting rotates while the outer room rect stays untouched.
/// Vector-only, fixed scene palette, no blur / saveLayer / images.
class RestoflowFixturePainter extends CustomPainter {
  const RestoflowFixturePainter({
    required this.kind,
    required this.fill,
    required this.ink,
    required this.outline,
    this.quarterTurns = 0,
    this.detail = RestoflowFloorDetail.standard,
    this.style,
  });

  /// `wall` / `door` / `window` / `cashier` / `plant`; an unknown kind
  /// degrades to the wall look (forward-compatible, never a crash).
  final String kind;
  final Color fill;
  final Color ink;
  final Color outline;
  final int quarterTurns;
  final RestoflowFloorDetail detail;

  /// TABLE-VISUAL-CONFIGURATION-120: the persisted per-kind artwork variant
  /// (`null` / unknown = the kind's default artwork).
  final String? style;

  /// TABLE-120B: the ONE deterministic style resolution (pinned by tests):
  /// a style registered for [kind] resolves to itself; NULL, unknown and
  /// cross-kind values resolve to `'default'` — the renderer stays robust
  /// even against data the server-side registry would never persist.
  static String resolveStyle(String kind, String? style) =>
      style != null && floorElementStylesFor(kind).contains(style)
      ? style
      : 'default';

  String get _resolved => resolveStyle(kind, style);

  /// TABLE-119B: below this LOCAL thickness (the door strip's short side,
  /// after the quarter-turn frame swap) the door paints its dedicated THIN
  /// artwork — jambs + leaf + swing cue — instead of the full-height leaf.
  static const double kThinDoorThickness = 18.0;

  /// The LOCAL painting frame for [size] at [quarterTurns]: odd turns swap
  /// the axes. Shared by [paint] and [rendersThinDoor] so the public split
  /// can never diverge from what the painter actually does.
  static Size _localSize(Size size, int quarterTurns) =>
      quarterTurns.isOdd ? Size(size.height, size.width) : size;

  /// The thin-vs-full door split in the LOCAL frame — the exact predicate
  /// `_paintDoor` branches on.
  static bool _isThinLocal(Size local) => local.height < kThinDoorThickness;

  /// Deterministic thin-vs-full door split for [size] at [quarterTurns]
  /// (pinned by tests; pure geometry, no app identity). Delegates to the
  /// same helpers the paint path uses.
  static bool rendersThinDoor(Size size, int quarterTurns) =>
      _isThinLocal(_localSize(size, quarterTurns));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Rotate the ARTWORK by the authoritative quarter turns; the room rect
    // already carries the swapped footprint, so odd turns paint into a local
    // frame with swapped axes.
    final local = _localSize(size, quarterTurns);
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
    // 120B: three partition looks. `plain` (and default/unknown kinds) keeps
    // the muted 119D slab + joints; `brick` overlays a bounded staggered
    // brick pattern; `wood_partition` overlays warm timber planks.
    switch (_resolved) {
      case 'brick':
        _paintBrickWall(canvas, s);
        return;
      case 'wood_partition':
        _paintWoodPartitionWall(canvas, s);
        return;
    }
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

  /// 120B `wall/brick`: a warm masonry tint + bounded staggered joints (two
  /// courses when the strip is tall enough; compact simplifies to one).
  RRect _wallSlabRRect(Size s) {
    // Mirrors the widget's slab radius rule (side < 24 -> side/4, else 8) so
    // the tint overlays hug the rounded slab instead of squaring it off.
    final side = math.min(s.width, s.height);
    return RRect.fromRectAndRadius(
      Offset.zero & s,
      Radius.circular(side < 24 ? side / 4 : 8.0),
    );
  }

  void _paintBrickWall(Canvas canvas, Size s) {
    const mortar = Color(0xFF6B4438);
    canvas.drawRRect(
      _wallSlabRRect(s),
      Paint()..color = const Color(0xFFA96A52).withValues(alpha: 0.55),
    );
    final joint = Paint()
      ..color = mortar.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final twoCourses = s.height >= 6 && detail != RestoflowFloorDetail.compact;
    final rows = twoCourses ? 2 : 1;
    final n = (s.width / 14).clamp(2, 12).floor();
    if (twoCourses) {
      canvas.drawLine(
        Offset(0, s.height / 2),
        Offset(s.width, s.height / 2),
        joint,
      );
    }
    for (var row = 0; row < rows; row++) {
      final top = row * s.height / rows;
      final bottom = (row + 1) * s.height / rows;
      final offset = row.isOdd ? s.width / n / 2 : 0.0;
      for (var i = 0; i <= n; i++) {
        final x = offset + i * s.width / n;
        if (x <= 0 || x >= s.width) continue;
        canvas.drawLine(Offset(x, top + 0.5), Offset(x, bottom - 0.5), joint);
      }
    }
  }

  /// 120B `wall/wood_partition`: a warm timber tint + vertical plank strokes
  /// (bounded; low overdraw).
  void _paintWoodPartitionWall(Canvas canvas, Size s) {
    canvas.drawRRect(
      _wallSlabRRect(s),
      Paint()..color = const Color(0xFF8F6B44).withValues(alpha: 0.55),
    );
    final plank = Paint()
      ..color = const Color(0xFF4C3620).withValues(alpha: 0.65)
      ..strokeWidth = 1;
    final n = (s.width / 10).clamp(2, 14).floor();
    for (var i = 1; i < n; i++) {
      final x = i * s.width / n;
      canvas.drawLine(Offset(x, 0.5), Offset(x, s.height - 0.5), plank);
    }
    if (detail != RestoflowFloorDetail.compact) {
      canvas.drawLine(
        Offset(0, 0.8),
        Offset(s.width, 0.8),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30)
          ..strokeWidth = 1,
      );
    }
  }

  /// 120B: the three door schemes behind the shared composition — `wood`
  /// (timber slab + dark leaf), `glass` (pale glazing + glass leaf), `modern`
  /// (neutral slab + slate leaf). Default keeps the theme-derived 119D look.
  (Color, Color, Color) get _doorScheme => switch (_resolved) {
    'wood' => (
      const Color(0xFFB08356),
      const Color(0xFF5D3B22),
      const Color(0xFF8A6844),
    ),
    'glass' => (
      const Color(0xFFDCE9F3),
      const Color(0xFF9CC4DE),
      const Color(0xFF6E92AC),
    ),
    'modern' => (
      const Color(0xFFD8DCE1),
      const Color(0xFF4A5560),
      const Color(0xFF7C8894),
    ),
    _ => (fill, ink.withValues(alpha: 0.85), ink),
  };

  void _paintDoor(Canvas canvas, Size s) {
    final (base, leafColor, edge) = _doorScheme;
    final styled = _resolved != 'default';
    // 119D: the painter owns the frame slab (the widget's box is transparent).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & s,
        Radius.circular(math.min(2.5, s.shortestSide * 0.2)),
      ),
      Paint()..color = base,
    );
    if (_isThinLocal(s)) {
      _paintThinDoor(canvas, s);
      return;
    }
    final leafW = math.min(s.width * 0.42, s.height * 2.4);
    // Door LEAF along the frame from the hinge end.
    final leaf = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, s.height * 0.15, leafW, s.height * 0.7),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(leaf, Paint()..color = leafColor);
    if (_resolved == 'glass') {
      // Glazing highlight so the leaf reads as GLASS, not paint.
      canvas.drawRRect(
        leaf.deflate(1.2),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if (detail != RestoflowFloorDetail.compact) {
      // Panel inset on the leaf (styled doors take the scheme's edge tone;
      // the default keeps the exact 119D theme-derived stroke).
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            1 + leafW * 0.18,
            s.height * 0.24,
            leafW * 0.64,
            s.height * 0.52,
          ),
          const Radius.circular(1),
        ),
        Paint()
          ..color = styled
              ? edge.withValues(alpha: 0.8)
              : _lighten(ink, 0.25).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // Swing arc sweeping INTO the room from the hinge (bottom-left corner of
    // the frame); CustomPaint does not clip, so the arc reads on the floor.
    final sweep = math.min(s.width * 0.9, s.height * 6.0);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(1, s.height), radius: sweep),
      0,
      math.pi / 2,
      false,
      Paint()
        ..color = styled
            ? edge.withValues(alpha: 0.5)
            : ink.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (detail == RestoflowFloorDetail.rich) {
      canvas.drawCircle(
        Offset(1 + leafW - 2.5, s.height * 0.5),
        1.6,
        Paint()..color = styled ? _lighten(edge, 0.35) : _lighten(ink, 0.4),
      );
    }
  }

  /// TABLE-119B: the THIN door (a few px thick): two frame jambs at the
  /// strip's ends, the opening span between them, an open LEAF swinging into
  /// the room (+y in the local frame; quarter turns rotate it with the whole
  /// artwork) and its swing arc. CustomPaint does not clip, so the leaf/arc
  /// read on the floor beside the strip — the outer fixture rect and room
  /// geometry are untouched. Because the swing follows local +y, the
  /// AUTHORITATIVE quarter turns also choose the swing side (0=down, 1=left,
  /// 2=up, 3=right); a swing pointing off the room simply clips at the floor
  /// edge, leaving jambs + opening. Shape-only: no text/images, ~6 draw ops.
  void _paintThinDoor(Canvas canvas, Size s) {
    final t = s.height;
    // (The strip base slab is painted by [_paintDoor] before delegating.)
    // 120B: jamb/opening/leaf tones follow the door style so a thin glass
    // door still reads as GLASS — same shapes, same geometry, every style.
    final (jambC, openingC, leafC) = switch (_resolved) {
      'wood' => (
        const Color(0xFF4A2F17),
        const Color(0xFFE6CDAB),
        const Color(0xFF5D3B22),
      ),
      'glass' => (
        const Color(0xFF5F8CAD),
        const Color(0xFFD9EDF9),
        const Color(0xFF7FB3D4),
      ),
      'modern' => (
        const Color(0xFF3E4954),
        const Color(0xFFE7EBEF),
        const Color(0xFF4A5560),
      ),
      _ => (
        ink.withValues(alpha: 0.9),
        _lighten(fill, 0.35).withValues(alpha: 0.9),
        ink.withValues(alpha: 0.9),
      ),
    };
    final jambW = (t * 1.2).clamp(2.0, 6.0);
    final jamb = Paint()..color = jambC;
    canvas.drawRect(Rect.fromLTWH(0, 0, jambW, t), jamb);
    canvas.drawRect(Rect.fromLTWH(s.width - jambW, 0, jambW, t), jamb);
    // The opening span (kept light so it reads as a gap in the wall line).
    canvas.drawRect(
      Rect.fromLTWH(jambW, t * 0.3, s.width - 2 * jambW, t * 0.4),
      Paint()..color = openingC,
    );
    // Open leaf from the hinge jamb, swung ~55 degrees into the room.
    final hinge = Offset(jambW, t);
    final leafLen = (s.width - 2 * jambW).clamp(6.0, 30.0).toDouble();
    const angle = 55 * math.pi / 180;
    final tip = hinge + Offset(math.cos(angle), math.sin(angle)) * leafLen;
    canvas.drawLine(
      hinge,
      tip,
      Paint()
        ..color = leafC
        ..strokeWidth = math.max(1.6, t * 0.28)
        ..strokeCap = StrokeCap.round,
    );
    // Swing arc from the closed position round to the leaf tip.
    canvas.drawArc(
      Rect.fromCircle(center: hinge, radius: leafLen),
      0,
      angle,
      false,
      Paint()
        ..color = leafC.withValues(alpha: _resolved == 'default' ? 0.40 : 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// TABLE-119D: REAL glass owning the whole rect — a cool sky gradient pane
  /// inside an aluminium frame with mullions, diagonal glare and a sill. The
  /// widget's tinted box behind it is transparent now.
  void _paintWindow(Canvas canvas, Size s) {
    // 120B: three glazing schemes behind the shared composition —
    // modern_glass (minimal thin frame, no mullions), framed (warm thick
    // frame + denser mullions), dark_frame (near-black frame, clear glass).
    // Default keeps the exact 119D look.
    final resolved = _resolved;
    final (glassTop, glassBottom, frameTone) = switch (resolved) {
      'dark_frame' => (
        const Color(0xFFEAF4FA),
        const Color(0xFFC4DCEA),
        const Color(0xFF23282D),
      ),
      'framed' => (
        const Color(0xFFD8EAF4),
        const Color(0xFFA5C8DD),
        const Color(0xFF8A6844),
      ),
      'modern_glass' => (
        const Color(0xFFE2F0F8),
        const Color(0xFFB9D6E7),
        const Color(0xFF9AA6AF),
      ),
      _ => (
        const Color(0xFFD8EAF4),
        const Color(0xFFA5C8DD),
        const Color(0xFF5C6B75),
      ),
    };
    final frameScale = switch (resolved) {
      'modern_glass' => 0.06,
      'framed' => 0.14,
      'dark_frame' => 0.15,
      _ => 0.10,
    };
    final body = Offset.zero & s;
    final radius = Radius.circular(math.min(2.5, s.shortestSide * 0.2));
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, radius),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [glassTop, glassBottom],
        ).createShader(body),
    );
    final frame = Paint()
      ..color = frameTone
      ..style = PaintingStyle.stroke
      // The DEFAULT path keeps the exact 119D floor (1.2); only the minimal
      // modern_glass frame may go hairline.
      ..strokeWidth = math.max(
        resolved == 'modern_glass' ? 1.0 : 1.2,
        s.shortestSide * frameScale,
      );
    final r = Rect.fromLTWH(0.8, 0.8, s.width - 1.6, s.height - 1.6);
    canvas.drawRRect(RRect.fromRectAndRadius(r, radius), frame);
    // Mullions along the length (modern_glass keeps NONE; framed adds one).
    if (resolved != 'modern_glass') {
      final mullion = Paint()
        ..color = frameTone
        ..strokeWidth = math.max(1.0, s.shortestSide * 0.07);
      final n =
          ((s.width / 30).clamp(1, 6).floor() + (resolved == 'framed' ? 1 : 0))
              .clamp(1, 7);
      for (var i = 1; i <= n; i++) {
        final x = r.left + i * r.width / (n + 1);
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), mullion);
      }
    }
    if (detail != RestoflowFloorDetail.compact) {
      // Two diagonal glare strokes.
      final glare = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
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
          ..color = frameTone.withValues(alpha: 0.9)
          ..strokeWidth = 2,
      );
    }
  }

  /// TABLE-119D: the cashier is a REAL counter scene owning its whole rect —
  /// walnut counter top, service-edge front panel, register with a glowing
  /// screen and keypad, card terminal and cash tray. The widget's box behind
  /// it is transparent; the artwork IS the identity (a tiny caption may sit
  /// on the service edge).
  void _paintCashier(Canvas canvas, Size s) {
    // 120B: three counter schemes behind the ONE shared composition —
    // modern (light neutral), wood (the 119D walnut default), dark
    // (high-contrast espresso/steel).
    final (
      counterLight,
      counterTop,
      counterDark,
      counterFront,
    ) = switch (_resolved) {
      'modern' => (
        const Color(0xFFEFF2F5),
        const Color(0xFFDCE1E7),
        const Color(0xFFBFC7D0),
        const Color(0xFF87929E),
      ),
      'dark' => (
        const Color(0xFF4C545C),
        const Color(0xFF394046),
        const Color(0xFF282D33),
        const Color(0xFF15181C),
      ),
      _ => (
        const Color(0xFF9A7450),
        const Color(0xFF7E5B3B),
        const Color(0xFF63452A),
        const Color(0xFF4A3119),
      ),
    };
    final registerBody = switch (_resolved) {
      'modern' => const Color(0xFF47525E),
      'dark' => const Color(0xFF14171A),
      _ => const Color(0xFF2E3439),
    };
    final screenGlow = _resolved == 'dark'
        ? const Color(0xFFB2EEDC)
        : const Color(0xFF9FD8C8);
    final key = _resolved == 'dark'
        ? const Color(0xFFAAB4BC)
        : const Color(0xFF8B949B);
    final radius = Radius.circular(math.min(6.0, s.shortestSide * 0.16));
    final body = Offset.zero & s;
    // Counter slab with a wood-tone gradient.
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, radius),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [counterLight, counterTop, counterDark],
        ).createShader(body),
    );
    // Front service edge (where guests stand — and where the caption sits).
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, s.height * 0.72, s.width, s.height * 0.28),
        bottomLeft: radius,
        bottomRight: radius,
      ),
      Paint()..color = counterFront.withValues(alpha: 0.9),
    );
    // Counter edge highlight.
    canvas.drawLine(
      Offset(2, s.height * 0.72),
      Offset(s.width - 2, s.height * 0.72),
      Paint()
        ..color = counterLight.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
    // Register: dark body + glowing screen + keypad dots, left of centre.
    final regW = (s.width * 0.26).clamp(8.0, s.height * 0.9);
    final regH = s.height * 0.42;
    final reg = Rect.fromLTWH(
      s.width * 0.30 - regW / 2,
      s.height * 0.14,
      regW,
      regH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(reg, const Radius.circular(2)),
      Paint()..color = registerBody,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          reg.left + regW * 0.14,
          reg.top + regH * 0.12,
          regW * 0.72,
          regH * 0.36,
        ),
        const Radius.circular(1.5),
      ),
      Paint()..color = screenGlow,
    );
    if (detail != RestoflowFloorDetail.compact) {
      // Keypad dots.
      final dot = Paint()..color = key;
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(reg.left + regW * (0.25 + i * 0.25), reg.top + regH * 0.72),
          math.max(0.8, regW * 0.06),
          dot,
        );
      }
      // Card terminal to the right.
      final termW = regW * 0.5;
      final term = Rect.fromLTWH(
        s.width * 0.62,
        s.height * 0.2,
        termW,
        regH * 0.62,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(term, const Radius.circular(1.5)),
        Paint()..color = registerBody.withValues(alpha: 0.85),
      );
      canvas.drawRect(
        Rect.fromLTWH(
          term.left + termW * 0.18,
          term.top + term.height * 0.16,
          termW * 0.64,
          term.height * 0.3,
        ),
        Paint()..color = screenGlow.withValues(alpha: 0.8),
      );
    }
    if (detail == RestoflowFloorDetail.rich) {
      // Cash tray seams on the counter top.
      final seam = Paint()
        ..color = counterDark.withValues(alpha: 0.8)
        ..strokeWidth = 1;
      final tray = Rect.fromLTWH(
        s.width * 0.78,
        s.height * 0.2,
        s.width * 0.14,
        s.height * 0.34,
      );
      canvas.drawRect(
        tray,
        Paint()
          ..color = counterDark.withValues(alpha: 0.55)
          ..style = PaintingStyle.fill,
      );
      canvas.drawLine(
        Offset(tray.left, tray.center.dy),
        Offset(tray.right, tray.center.dy),
        seam,
      );
    }
  }

  /// TABLE-119D: a TOP-DOWN potted plant owning its whole rect — terracotta
  /// pot with rim and soil, a rosette of leaf blades in layered greens and a
  /// light catch. No box, no icon: the silhouette is the identity.
  void _paintPlant(Canvas canvas, Size s) {
    // 120B: three plant silhouettes — leafy (the 119D rosette default),
    // palm (long directional fronds) and compact_pot (dense small canopy on
    // a clearly visible pot).
    switch (_resolved) {
      case 'palm':
        _paintPalmPlant(canvas, s);
        return;
      case 'compact_pot':
        _paintCompactPotPlant(canvas, s);
        return;
    }
    const potClay = Color(0xFFB06A4A);
    const potRim = Color(0xFF8A4E33);
    const soil = Color(0xFF4A3226);
    const leafDark = Color(0xFF39724A);
    const leafMid = Color(0xFF4C8F5D);
    const leafLight = Color(0xFF6AAE79);
    final c = Offset(s.width / 2, s.height / 2);
    final side = math.min(s.width, s.height);
    final potR = side * 0.40;
    if (detail != RestoflowFloorDetail.compact) {
      canvas.drawCircle(
        c + Offset(1.2, 1.8),
        potR,
        Paint()..color = const Color(0xFF000000).withValues(alpha: 0.14),
      );
    }
    canvas.drawCircle(c, potR, Paint()..color = potClay);
    canvas.drawCircle(
      c,
      potR,
      Paint()
        ..color = potRim
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, potR * 0.14),
    );
    canvas.drawCircle(c, potR * 0.74, Paint()..color = soil);
    // Leaf rosette: rotated oval blades in two greens, then a light crown.
    final blades = switch (detail) {
      RestoflowFloorDetail.compact => 5,
      RestoflowFloorDetail.standard => 8,
      RestoflowFloorDetail.rich => 12,
    };
    for (var i = 0; i < blades; i++) {
      final a = i * 2 * math.pi / blades;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -potR * 0.46),
          width: potR * 0.46,
          height: potR * 1.0,
        ),
        Paint()..color = (i.isEven ? leafDark : leafMid),
      );
      canvas.restore();
    }
    canvas.drawCircle(c, potR * 0.30, Paint()..color = leafMid);
    canvas.drawCircle(c, potR * 0.16, Paint()..color = leafLight);
    if (detail == RestoflowFloorDetail.rich) {
      canvas.drawCircle(
        c + Offset(-potR * 0.16, -potR * 0.16),
        math.max(1.0, potR * 0.07),
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }
  }

  /// 120B `plant/palm`: a small clearly-visible pot with LONG directional
  /// fronds arcing outward — reads as a palm even at map sizes.
  void _paintPalmPlant(Canvas canvas, Size s) {
    const potClay = Color(0xFFB06A4A);
    const potRim = Color(0xFF8A4E33);
    const frondDark = Color(0xFF2F6B44);
    const frondLight = Color(0xFF56A06A);
    final c = Offset(s.width / 2, s.height / 2);
    final side = math.min(s.width, s.height);
    final potR = side * 0.24;
    if (detail != RestoflowFloorDetail.compact) {
      canvas.drawCircle(
        c + Offset(1.2, 1.8),
        potR,
        Paint()..color = const Color(0xFF000000).withValues(alpha: 0.14),
      );
    }
    // Fronds FIRST (they sweep over the floor), pot on top of their roots.
    final fronds = detail == RestoflowFloorDetail.compact ? 5 : 7;
    final reach = side * 0.46;
    for (var i = 0; i < fronds; i++) {
      final a = i * 2 * math.pi / fronds + 0.35;
      final dir = Offset(math.cos(a), math.sin(a));
      final normal = Offset(-dir.dy, dir.dx);
      final tip = c + dir * reach;
      final ctrl = c + dir * (reach * 0.45) + normal * (side * 0.10);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy),
        Paint()
          ..color = i.isEven ? frondDark : frondLight
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, side * 0.055)
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(c, potR, Paint()..color = potClay);
    canvas.drawCircle(
      c,
      potR,
      Paint()
        ..color = potRim
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, potR * 0.18),
    );
    canvas.drawCircle(c, potR * 0.45, Paint()..color = frondDark);
  }

  /// 120B `plant/compact_pot`: a LARGE pot with a small dense canopy — the
  /// pot itself is the identity.
  void _paintCompactPotPlant(Canvas canvas, Size s) {
    const potClay = Color(0xFFB06A4A);
    const potRim = Color(0xFF8A4E33);
    const soil = Color(0xFF4A3226);
    const leafDark = Color(0xFF39724A);
    const leafLight = Color(0xFF6AAE79);
    final c = Offset(s.width / 2, s.height / 2);
    final side = math.min(s.width, s.height);
    final potR = side * 0.44;
    if (detail != RestoflowFloorDetail.compact) {
      canvas.drawCircle(
        c + Offset(1.2, 1.8),
        potR,
        Paint()..color = const Color(0xFF000000).withValues(alpha: 0.14),
      );
    }
    canvas.drawCircle(c, potR, Paint()..color = potClay);
    canvas.drawCircle(
      c,
      potR,
      Paint()
        ..color = potRim
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, potR * 0.20),
    );
    canvas.drawCircle(c, potR * 0.68, Paint()..color = soil);
    // Dense small canopy: a tight ring of blades + a filled crown.
    final blades = detail == RestoflowFloorDetail.compact ? 6 : 10;
    for (var i = 0; i < blades; i++) {
      final a = i * 2 * math.pi / blades;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -potR * 0.28),
          width: potR * 0.26,
          height: potR * 0.52,
        ),
        Paint()..color = (i.isEven ? leafDark : leafLight),
      );
      canvas.restore();
    }
    canvas.drawCircle(c, potR * 0.22, Paint()..color = leafDark);
  }

  @override
  bool shouldRepaint(RestoflowFixturePainter old) =>
      old.kind != kind ||
      old.fill != fill ||
      old.ink != ink ||
      old.outline != outline ||
      old.quarterTurns != quarterTurns ||
      old.detail != detail ||
      old.style != style;
}
