import 'package:flutter/material.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset;

import 'floor_presets.dart';

import '../tokens.dart';

/// TABLE-FLOOR-LAYOUT-021 / TABLE-FLOOR-MAP-POLISH-027 — the shared FLOOR-MAP
/// building blocks.
///
/// Two presentation-only pieces used by every floor surface (Dashboard arrange
/// editor, POS table picker, POS Move Table):
///
///  * [RestoflowFloorTable] — a TOP-DOWN dining table: a compact table
///    surface with the label centred, the EXACT numeric seat count, and chair
///    glyphs distributed around the perimeter. Colours/flags are passed in by
///    the caller (the apps own their status→tone mapping); this widget knows
///    tokens only, never domain types.
///  * [RestoflowFloorSectionCanvas] — one section's white floor rectangle.
///
/// 027 GEOMETRY CONTRACT: the canvas places children by ROOM-UNIT RECTS
/// (0..10000 on each axis; x-units are 1/10000 of the canvas WIDTH, y-units
/// 1/10000 of the canvas HEIGHT). The caller computes room rects through the
/// shared domain contract (`floorTableRoomRect` etc.), so a table's size
/// RELATIVE TO THE ROOM is identical on every surface — the Dashboard↔POS
/// overlap-mismatch fix. Placement uses PHYSICAL left/top (never
/// Directional): the room does not mirror under RTL locales — only text does.
class RestoflowFloorSectionCanvas extends StatelessWidget {
  const RestoflowFloorSectionCanvas({
    super.key,
    required this.placed,
    this.background = const [],
    this.aspectRatio = kRestoflowFloorSectionAspect,
    this.overlay,
    this.floorPreset = FloorPreset.plainLight,
  });

  /// TABLE-VISUAL-LAYOUT-118: the section's floor style. The default paints
  /// the pre-118 white canvas exactly; any other preset paints ONE pattern
  /// painter (inside its own RepaintBoundary) UNDER [background] and [placed]
  /// — never a different geometry.
  final FloorPreset floorPreset;

  /// The placed tiles (tables): room-unit rects + the tile widget. Rendered
  /// ABOVE [background].
  final List<RestoflowFloorPlacedTile> placed;

  /// Non-interactive underlay content (fixtures, linked-group seams) rendered
  /// BELOW the tables in the same room-unit space.
  final List<RestoflowFloorPlacedTile> background;

  /// Canvas width : height. One tokenized ratio for every section.
  final double aspectRatio;

  /// Optional full-canvas overlay (the arrange editor injects its drag layer).
  final Widget Function(BoxConstraints constraints)? overlay;

  /// Maps a room-unit rect to PHYSICAL pixels for a canvas of [canvas] size.
  static Rect pixelsForRoomRect(
    ({double left, double top, double width, double height}) room,
    Size canvas,
  ) => Rect.fromLTWH(
    room.left * canvas.width / 10000,
    room.top * canvas.height / 10000,
    room.width * canvas.width / 10000,
    room.height * canvas.height / 10000,
  );

  Widget _canvasBody(BuildContext context) {
    final theme = Theme.of(context);
    final palette = RestoflowFloorPresetPalette.of(floorPreset);
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // 118: the preset base (plain light == the pre-118 Colors.white).
          color: palette.base,
          borderRadius: BorderRadius.circular(RestoflowRadii.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RestoflowRadii.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canvas = Size(constraints.maxWidth, constraints.maxHeight);
              Widget positioned(RestoflowFloorPlacedTile tile) {
                final rect = pixelsForRoomRect(tile.room, canvas);
                return Positioned(
                  // PHYSICAL coordinates by contract: left/top, never
                  // start/end — an RTL locale localizes the labels, not
                  // the room.
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: tile.child,
                );
              }

              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 118: the floor pattern, isolated so table-state repaints
                  // never re-run it (PERF-110 posture).
                  if (floorPreset != FloorPreset.plainLight)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: RestoflowFloorPresetPainter(floorPreset),
                        ),
                      ),
                    ),
                  for (final tile in background) positioned(tile),
                  for (final tile in placed) positioned(tile),
                  if (overlay != null) overlay!(constraints),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 027 readability floor: below the minimum width the canvas keeps its
    // geometry-true minimum size inside a horizontal scroller instead of
    // squashing tiles below legibility.
    return LayoutBuilder(
      builder: (context, outer) {
        if (outer.maxWidth.isFinite &&
            outer.maxWidth < kRestoflowFloorMinCanvasWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: kRestoflowFloorMinCanvasWidth,
              child: _canvasBody(context),
            ),
          );
        }
        return _canvasBody(context);
      },
    );
  }
}

/// The tokenized section canvas ratio (width : height).
/// 027: 1.6 → 1.9 (≈16% shorter maps at the same width; one shared token —
/// never a per-surface ratio).
const double kRestoflowFloorSectionAspect = 1.9;

/// 027: the minimum canvas width at which floor tiles stay readable; below
/// it the canvas scrolls horizontally instead of shrinking geometry.
const double kRestoflowFloorMinCanvasWidth = 480;

/// 027: the fixed size a floor tile takes OUTSIDE a canvas (the not-placed
/// and unassigned strips) — the design-reference footprint, since strips are
/// lists, not rooms.
const Size kRestoflowFloorStripTileSize = Size(120, 101);

/// One placed element on a [RestoflowFloorSectionCanvas]: a room-unit rect
/// (0..10000 per axis) plus the widget that fills it.
class RestoflowFloorPlacedTile {
  const RestoflowFloorPlacedTile({required this.room, required this.child});

  final ({double left, double top, double width, double height}) room;
  final Widget child;
}

/// 027: the subtle "these tables are one group" seam — a rounded translucent
/// outline drawn BEHIND a linked cluster's tiles (never a giant merged
/// table; per-member labels/statuses stay on the tiles above).
class RestoflowFloorClusterSeam extends StatelessWidget {
  const RestoflowFloorClusterSeam({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(RestoflowRadii.lg),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

/// The top-down dining-table visual. Purely presentational: the caller
/// resolves colours (status tones, selection) and passes plain values.
///
/// 027: the widget renders at whatever size its parent gives it (the canvas
/// sizes it from the SHARED room-unit footprint), scaling its typography and
/// chair geometry from the design reference width (120px). There is no
/// per-surface compact/non-compact variant any more.
class RestoflowFloorTable extends StatelessWidget {
  const RestoflowFloorTable({
    super.key,
    required this.label,
    required this.fill,
    required this.onFill,
    required this.border,
    this.seats,
    this.borderWidth = 1,
    this.statusIcon,
    this.footnote,
    this.chairCap = 12,
    this.preset = TableVisualPreset.classicRectTable,
  });

  /// TABLE-VISUAL-LAYOUT-118: how the table is DRAWN inside its (unchanged)
  /// footprint. The classic default keeps the pre-118 widget tree exactly;
  /// the other presets paint their shape through [RestoflowTableShapePainter]
  /// and layer the same label column above it.
  final TableVisualPreset preset;

  final String label;
  final int? seats;
  final Color fill;
  final Color onFill;
  final Color border;
  final double borderWidth;

  /// A small trailing glyph on the surface (check / occupied / blocked ...).
  /// Sized by the caller via [iconSizeFor] so it scales with the tile.
  final Widget? statusIcon;

  /// One tiny line under the label (status word, open orders, linked ...).
  final String? footnote;

  /// Maximum chair GLYPHS drawn; the numeric seat count is always exact.
  final int chairCap;

  /// The design-reference width every internal metric is authored against.
  static const double referenceWidth = 120;

  /// The scale factor a caller should use for icons meant to sit on a tile
  /// rendered [width] pixels wide.
  static double scaleFor(double width) =>
      (width / referenceWidth).clamp(0.55, 1.6);

  /// A status-glyph size matched to a tile of [width] pixels.
  static double iconSizeFor(double width) => 13 * scaleFor(width);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final s = scaleFor(size.width);
        final chairs = _chairSides(seats ?? 0, chairCap);
        final chairInset = 9.0 * s;
        final chairColor = border.a < 0.9
            ? border.withValues(alpha: 0.9)
            : border;

        final isRound = preset == TableVisualPreset.roundTable;
        final labelColumn = _labelColumn(theme, s, fitted: isRound);

        if (preset != TableVisualPreset.classicRectTable) {
          // 118: a painted shape inside the SAME footprint; the label column
          // sits on the painter's surface rect.
          final painter = RestoflowTableShapePainter(
            preset: preset,
            chairs: chairs.$1 + chairs.$2 + chairs.$3 + chairs.$4,
            fill: fill,
            border: border,
            borderWidth: borderWidth,
            chairColor: chairColor,
            inset: chairInset,
            scale: s,
            surfaceRadius: RestoflowRadii.md,
          );
          // 118F: the label column lives in the painter's CONTENT rect (the
          // surface for rectangular shapes; a rect inscribed in the circle
          // for a round table). A round table additionally scales its rows
          // DOWN — never truncates — when a word is wider than the chord,
          // so "RESERVED" / "OCCUPIED" / "2 open orders" stay whole and
          // inside the rim on every tile size.
          final content = painter.contentRect(size);
          return SizedBox(
            width: size.width,
            height: size.height,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.4,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: painter)),
                  Positioned(
                    left: content.left,
                    top: content.top,
                    width: content.width,
                    height: content.height,
                    child: isRound
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: content.width,
                              child: labelColumn,
                            ),
                          )
                        : Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4 * s),
                            child: labelColumn,
                          ),
                  ),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          width: size.width,
          height: size.height,
          // The tile has a FIXED footprint (it sits on a spatial canvas), so
          // the text inside clamps its scaling like other fixed-geometry
          // glyphs do — at 2× accessibility scale the label/seats stay
          // readable without overflowing the footprint. The status word is
          // also carried by the caller's Semantics label, which scales
          // normally.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.4,
            child: Stack(
              children: [
                // The table SURFACE, inset so the chairs sit around it.
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(chairInset),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(RestoflowRadii.md),
                        border: Border.all(color: border, width: borderWidth),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4 * s),
                        child: labelColumn,
                      ),
                    ),
                  ),
                ),
                // Chairs, deterministically spread per side. Physical
                // coordinates (left/top): the layout never mirrors for RTL.
                ..._chairRow(
                  count: chairs.$1,
                  horizontal: true,
                  leading: true,
                  size: size,
                  inset: chairInset,
                  scale: s,
                  color: chairColor,
                ),
                ..._chairRow(
                  count: chairs.$2,
                  horizontal: true,
                  leading: false,
                  size: size,
                  inset: chairInset,
                  scale: s,
                  color: chairColor,
                ),
                ..._chairRow(
                  count: chairs.$3,
                  horizontal: false,
                  leading: true,
                  size: size,
                  inset: chairInset,
                  scale: s,
                  color: chairColor,
                ),
                ..._chairRow(
                  count: chairs.$4,
                  horizontal: false,
                  leading: false,
                  size: size,
                  inset: chairInset,
                  scale: s,
                  color: chairColor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The label / seats / footnote column shared by every preset.
  ///
  /// TABLE-118F: with [fitted] (round tables) each row is wrapped in a
  /// scale-down [FittedBox] and the label loses its ellipsis, so a word that
  /// is wider than the inscribed content rect shrinks to fit instead of being
  /// cut — the whole status word always stays inside the round surface.
  Widget _labelColumn(
    ThemeData theme,
    double s, {
    bool fitted = false,
  }) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: fitted ? MainAxisSize.min : MainAxisSize.max,
    children: [
      _fit(
        fitted,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fitted)
              Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5 * s,
                  color: onFill,
                ),
              )
            else
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5 * s,
                    color: onFill,
                  ),
                ),
              ),
            if (statusIcon != null) ...[const SizedBox(width: 2), statusIcon!],
          ],
        ),
      ),
      if (seats != null)
        _fit(
          fitted,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_seat,
                size: 11 * s,
                color: onFill.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 2),
              Text(
                '$seats',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10.5 * s,
                  fontWeight: FontWeight.w700,
                  color: onFill.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      if (footnote != null)
        _fit(
          fitted,
          Text(
            footnote!,
            maxLines: 1,
            overflow: fitted ? TextOverflow.visible : TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9.5 * s,
              fontWeight: FontWeight.w700,
              color: onFill.withValues(alpha: 0.85),
            ),
          ),
        ),
    ],
  );

  /// TABLE-118F: scale-down wrapper for the round tile's rows (identity for
  /// every other preset, so their widget tree is untouched).
  static Widget _fit(bool fitted, Widget child) =>
      fitted ? FittedBox(fit: BoxFit.scaleDown, child: child) : child;

  /// Chairs per (top, bottom, start, end) — the [top, bottom, top, bottom,
  /// start, end] fill pattern (a 2-top reads 1+1 across, a 4-top 2+2).
  static (int, int, int, int) _chairSides(int seats, int cap) {
    final shown = seats < 0 ? 0 : (seats > cap ? cap : seats);
    const pattern = [0, 1, 0, 1, 2, 3];
    final out = [0, 0, 0, 0];
    for (var i = 0; i < shown; i++) {
      out[pattern[i % pattern.length]] += 1;
    }
    return (out[0], out[1], out[2], out[3]);
  }

  /// One side's chair glyphs, evenly spread along the edge. Physical
  /// coordinates (left/top): the chair layout never mirrors for RTL.
  List<Widget> _chairRow({
    required int count,
    required bool horizontal,
    required bool leading,
    required Size size,
    required double inset,
    required double scale,
    required Color color,
  }) {
    if (count <= 0) return const [];
    final chair = 6.0 * scale;
    final span = (horizontal ? size.width : size.height) - 2 * inset;
    return [
      for (var i = 0; i < count; i++)
        Positioned(
          left: horizontal
              ? inset + (i + 1) * span / (count + 1) - chair / 2
              : (leading ? 1.0 : size.width - inset + 2 * scale),
          top: horizontal
              ? (leading ? 1.0 : size.height - inset + 2 * scale)
              : inset + (i + 1) * span / (count + 1) - chair / 2,
          child: Container(
            width: horizontal ? chair : inset - 3 * scale,
            height: horizontal ? inset - 3 * scale : chair,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
    ];
  }
}
