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
  });

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

  double _barrelDiameter(Size size) =>
      math.min(size.height - inset * 0.8, size.width * 0.27);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final fillPaint = Paint()..color = fill;
    final borderPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    final chairPaint = Paint()..color = chairColor.withValues(alpha: 0.55);
    final surface = surfaceRect(size);
    switch (preset) {
      case TableVisualPreset.classicRectTable:
        final rr = RRect.fromRectAndRadius(
          surface,
          Radius.circular(surfaceRadius),
        );
        canvas.drawRRect(rr, fillPaint);
        canvas.drawRRect(rr, borderPaint);
      case TableVisualPreset.roundTable:
        final center = surface.center;
        final r = surface.width / 2;
        // Chairs: small rounded pads spread evenly around the top.
        final pad = 3.2 * scale;
        final ring = r + inset * 0.5;
        for (var i = 0; i < chairs; i++) {
          final a = -math.pi / 2 + i * 2 * math.pi / chairs;
          final c = center + Offset(math.cos(a), math.sin(a)) * ring;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: c, width: pad * 2, height: pad * 2),
              Radius.circular(pad * 0.6),
            ),
            chairPaint,
          );
        }
        canvas.drawCircle(center, r, fillPaint);
        canvas.drawCircle(center, r, borderPaint);
        // A faint inner ring reads as a round top even at small scales.
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
        final barrelPaint = Paint()..color = chairColor.withValues(alpha: 0.35);
        final hoopPaint = Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (final cx in [d / 2 + 1, size.width - d / 2 - 1]) {
          final c = Offset(cx, size.height / 2);
          canvas.drawCircle(c, d / 2, barrelPaint);
          canvas.drawCircle(c, d / 2, hoopPaint);
          // Two hoops.
          for (final k in [-0.42, 0.42]) {
            final y = c.dy + d * k / 2;
            final half = math.sqrt(
              math.max(0, (d / 2) * (d / 2) - (y - c.dy) * (y - c.dy)),
            );
            canvas.drawLine(
              Offset(c.dx - half, y),
              Offset(c.dx + half, y),
              hoopPaint,
            );
          }
        }
        final rr = RRect.fromRectAndRadius(
          surface,
          Radius.circular(surfaceRadius),
        );
        canvas.drawRRect(rr, fillPaint);
        canvas.drawRRect(rr, borderPaint);
      case TableVisualPreset.boothTable:
        final benchH = inset * 0.85;
        final benchInset = inset * 0.5;
        for (final top in [1.0, size.height - benchH - 1.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                benchInset,
                top,
                size.width - 2 * benchInset,
                benchH,
              ),
              Radius.circular(3 * scale),
            ),
            chairPaint,
          );
        }
        final rr = RRect.fromRectAndRadius(
          surface,
          Radius.circular(surfaceRadius),
        );
        canvas.drawRRect(rr, fillPaint);
        canvas.drawRRect(rr, borderPaint);
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
      old.surfaceRadius != surfaceRadius;
}
