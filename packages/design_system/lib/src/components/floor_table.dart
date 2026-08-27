import 'package:flutter/material.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPreset,
        TableSectionRoomFramePreset,
        TableVisualPreset,
        floorRoomAspect,
        kFloorStandardAspect;

import 'floor_presets.dart';
import 'floor_scene_theme.dart';

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
    this.roomFrame,
  });

  /// TABLE-ROOM-FRAME-121: the section's optional ROOM FRAME preset. When
  /// set, the canvas resolves its width:height from the frame (the SHARED
  /// projection — callers compute room rects through the same frame, so the
  /// furniture's on-screen physical aspect never changes); NULL keeps
  /// [aspectRatio] (default: the legacy tokenized ratio) byte-for-byte.
  final TableSectionRoomFramePreset? roomFrame;

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
      // 121: a room frame overrides the caller ratio; NULL = legacy exactly.
      aspectRatio: roomFrame == null ? aspectRatio : floorRoomAspect(roomFrame),
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

              return RestoflowFloorSceneScope(
                floorPreset: floorPreset,
                child: Stack(
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
                ),
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
/// never a per-surface ratio). 121: this IS the domain's Standard room-frame
/// aspect — the two constants must never diverge.
const double kRestoflowFloorSectionAspect = kFloorStandardAspect;

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
    this.material,
  });

  /// TABLE-119D: the table-surface material. `null` (the default) resolves
  /// the deterministic shared mapping from [preset] and the enclosing
  /// canvas's floor preset (via [RestoflowFloorSceneScope]) — identical on
  /// every surface with zero app plumbing. Set it to override per tile (the
  /// seam a future persisted per-table style would use).
  final RestoflowFloorMaterial? material;

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
        final chairInset = 9.0 * s;
        final chairColor = border.a < 0.9
            ? border.withValues(alpha: 0.9)
            : border;

        final isRound = preset == TableVisualPreset.roundTable;
        final labelColumn = _labelColumn(theme, s, fitted: isRound);
        // 119D: the material resolves from the enclosing canvas's floor
        // preset unless the caller overrides it.
        final resolvedMaterial =
            material ??
            restoflowDefaultFloorMaterial(
              preset,
              RestoflowFloorSceneScope.of(context),
            );

        // TABLE-119A: EVERY preset paints through the one shared painter
        // (classic included — real chairs, shaded tops). The painter is
        // isolated in its own RepaintBoundary so one tile's state change
        // never repaints its siblings, and the deterministic size-driven
        // detail tier keeps small tiles crisp and cheap. Geometry is
        // untouched: same footprint, same surface/content rects, same
        // label column, same hit target.
        final painter = RestoflowTableShapePainter(
          preset: preset,
          chairs: (seats ?? 0) < 0
              ? 0
              : ((seats ?? 0) > chairCap ? chairCap : (seats ?? 0)),
          fill: fill,
          border: border,
          borderWidth: borderWidth,
          chairColor: chairColor,
          inset: chairInset,
          scale: s,
          surfaceRadius: RestoflowRadii.md,
          detail: restoflowFloorDetailFor(size.width),
          material: resolvedMaterial,
        );
        final content = painter.contentRect(size);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.4,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(child: CustomPaint(painter: painter)),
                ),
                // TABLE-119D: the label column sits on a translucent PLATE so
                // it stays readable on real material tops. The plate hugs the
                // text (Center + min column), lives inside the same content
                // rect, and adapts its tone to the caller's onFill so status
                // icons keep their contrast (dark plate under light ink,
                // light plate under dark ink). Round tiles keep their 118F
                // scale-down behaviour via the outer FittedBox.
                Positioned(
                  left: content.left,
                  top: content.top,
                  width: content.width,
                  height: content.height,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: content.width.clamp(1.0, double.infinity),
                        ),
                        child: DecoratedBox(
                          key: const ValueKey('restoflow-floor-label-plate'),
                          decoration: BoxDecoration(
                            // A dark onFill sits on the material's own light
                            // plate; a light onFill (selected) flips to the
                            // shared dark plate so icons keep contrast.
                            color: onFill.computeLuminance() > 0.5
                                ? Colors.black.withValues(alpha: 0.38)
                                : RestoflowMaterialPalette.of(
                                    resolvedMaterial,
                                  ).labelPlate,
                            borderRadius: BorderRadius.circular(6 * s),
                          ),
                          child: Padding(
                            // 118F interaction: the ROUND content rect is
                            // already inscribed, so its plate keeps padding
                            // minimal — the text keeps (almost) the full
                            // pre-119D width budget.
                            padding: EdgeInsets.symmetric(
                              horizontal: (isRound ? 2 : 5) * s,
                              vertical: 2.5 * s,
                            ),
                            child: labelColumn,
                          ),
                        ),
                      ),
                    ),
                  ),
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
    // 119D: always min — the plate hugs the text on every preset.
    mainAxisSize: MainAxisSize.min,
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
}
