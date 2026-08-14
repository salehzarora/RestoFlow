import 'package:flutter/material.dart';

import '../tokens.dart';

/// TABLE-FLOOR-LAYOUT-021 — the shared FLOOR-MAP building blocks.
///
/// Two presentation-only pieces used by every floor surface (Dashboard arrange
/// editor, POS table picker, POS Move Table):
///
///  * [RestoflowFloorTable] — a TOP-DOWN dining table: a compact table
///    surface with the label centred, the EXACT numeric seat count, and chair
///    glyphs distributed around the perimeter. Colours/flags are passed in by
///    the caller (the apps own their status→tone mapping); this widget knows
///    tokens only, never domain types.
///  * [RestoflowFloorSectionCanvas] — one section's white floor rectangle: a
///    fixed-aspect canvas that places tiles at NORMALIZED fractions of the
///    usable area. Placement uses PHYSICAL left/top (never Directional):
///    the room does not mirror under RTL locales — only text does.
///
/// Geometry contract: a placed child's anchor is its TOP-LEFT corner at
/// `fraction * (canvas - tile)`, so a 0..1 fraction can never overflow the
/// canvas. The inverse mapping lives here too so the arrange editor and the
/// read-only surfaces can never disagree about where a fraction lands.
class RestoflowFloorSectionCanvas extends StatelessWidget {
  const RestoflowFloorSectionCanvas({
    super.key,
    required this.tileSize,
    required this.placed,
    this.aspectRatio = kRestoflowFloorSectionAspect,
    this.overlay,
  });

  /// The uniform tile footprint every placed child occupies (the caller sizes
  /// its [RestoflowFloorTable]s to exactly this).
  final Size tileSize;

  /// The placed tiles: normalized unit fractions (0..1) + the tile widget.
  final List<RestoflowFloorPlacedTile> placed;

  /// Canvas width : height. One tokenized v1 ratio for every section.
  final double aspectRatio;

  /// Optional full-canvas overlay (the arrange editor injects its drag layer).
  final Widget Function(BoxConstraints constraints)? overlay;

  /// The PHYSICAL top-left for a normalized fraction pair (never mirrored).
  static Offset topLeftFor(
    double fractionX,
    double fractionY,
    Size canvas,
    Size tile,
  ) => Offset(
    fractionX.clamp(0.0, 1.0) * (canvas.width - tile.width),
    fractionY.clamp(0.0, 1.0) * (canvas.height - tile.height),
  );

  /// The inverse of [topLeftFor]: fraction pair for a tile top-left, clamped.
  static (double, double) fractionsFor(Offset topLeft, Size canvas, Size tile) {
    final usableWidth = canvas.width - tile.width;
    final usableHeight = canvas.height - tile.height;
    return (
      usableWidth <= 0 ? 0.0 : (topLeft.dx / usableWidth).clamp(0.0, 1.0),
      usableHeight <= 0 ? 0.0 : (topLeft.dy / usableHeight).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(RestoflowRadii.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RestoflowRadii.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canvas = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final tile in placed)
                    Positioned(
                      // PHYSICAL coordinates by contract: left/top, never
                      // start/end — an RTL locale localizes the labels, not
                      // the room.
                      left: topLeftFor(
                        tile.fractionX,
                        tile.fractionY,
                        canvas,
                        tileSize,
                      ).dx,
                      top: topLeftFor(
                        tile.fractionX,
                        tile.fractionY,
                        canvas,
                        tileSize,
                      ).dy,
                      width: tileSize.width,
                      height: tileSize.height,
                      child: tile.child,
                    ),
                  if (overlay != null) overlay!(constraints),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The tokenized v1 section canvas ratio (width : height).
const double kRestoflowFloorSectionAspect = 1.6;

/// One placed tile on a [RestoflowFloorSectionCanvas].
class RestoflowFloorPlacedTile {
  const RestoflowFloorPlacedTile({
    required this.fractionX,
    required this.fractionY,
    required this.child,
  });

  final double fractionX;
  final double fractionY;
  final Widget child;
}

/// The top-down dining-table visual. Purely presentational: the caller
/// resolves colours (status tones, selection) and passes plain values.
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
    this.compact = false,
    this.chairCap = 12,
  });

  final String label;
  final int? seats;
  final Color fill;
  final Color onFill;
  final Color border;
  final double borderWidth;

  /// A small trailing glyph on the surface (check / occupied / blocked ...).
  final Widget? statusIcon;

  /// One tiny line under the label (status word, open orders, linked ...).
  final String? footnote;

  final bool compact;

  /// Maximum chair GLYPHS drawn; the numeric seat count is always exact.
  final int chairCap;

  /// The uniform tile footprint for a floor surface (chairs included).
  static Size sizeFor({required bool compact}) =>
      compact ? const Size(96, 84) : const Size(120, 102);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = sizeFor(compact: compact);
    final chairs = _chairSides(seats ?? 0, chairCap);
    const chairInset = 9.0;
    final chairColor = border.a < 0.9 ? border.withValues(alpha: 0.9) : border;

    return SizedBox(
      width: size.width,
      height: size.height,
      // The tile has a FIXED footprint (it sits on a spatial canvas), so the
      // text inside clamps its scaling like other fixed-geometry glyphs do —
      // at 2× accessibility scale the label/seats stay readable without
      // overflowing the 84/102px tile. The status word is also carried by the
      // caller's Semantics label, which scales normally.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        child: Stack(
          children: [
            // The table SURFACE, inset so the chairs sit around it.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(chairInset),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(RestoflowRadii.md),
                    border: Border.all(color: border, width: borderWidth),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 12 : 13.5,
                                  color: onFill,
                                ),
                              ),
                            ),
                            if (statusIcon != null) ...[
                              const SizedBox(width: 2),
                              statusIcon!,
                            ],
                          ],
                        ),
                        if (seats != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_seat,
                                size: compact ? 10 : 11,
                                color: onFill.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '$seats',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: compact ? 9.5 : 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: onFill.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        if (footnote != null)
                          Text(
                            footnote!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: compact ? 8.5 : 9.5,
                              fontWeight: FontWeight.w700,
                              color: onFill.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Chairs, deterministically spread per side (top/bottom/start/end).
            ..._chairRow(
              count: chairs.$1,
              horizontal: true,
              leading: true,
              size: size,
              inset: chairInset,
              color: chairColor,
            ),
            ..._chairRow(
              count: chairs.$2,
              horizontal: true,
              leading: false,
              size: size,
              inset: chairInset,
              color: chairColor,
            ),
            ..._chairRow(
              count: chairs.$3,
              horizontal: false,
              leading: true,
              size: size,
              inset: chairInset,
              color: chairColor,
            ),
            ..._chairRow(
              count: chairs.$4,
              horizontal: false,
              leading: false,
              size: size,
              inset: chairInset,
              color: chairColor,
            ),
          ],
        ),
      ),
    );
  }

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
    required Color color,
  }) {
    if (count <= 0) return const [];
    const chair = 6.0;
    final span = (horizontal ? size.width : size.height) - 2 * inset;
    return [
      for (var i = 0; i < count; i++)
        Positioned(
          left: horizontal
              ? inset + (i + 1) * span / (count + 1) - chair / 2
              : (leading ? 1.0 : size.width - inset + 2),
          top: horizontal
              ? (leading ? 1.0 : size.height - inset + 2)
              : inset + (i + 1) * span / (count + 1) - chair / 2,
          child: Container(
            width: horizontal ? chair : inset - 3,
            height: horizontal ? inset - 3 : chair,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
    ];
  }
}
