import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';
import 'floor_presets.dart';

/// TABLE-FLOOR-MAP-POLISH-027 — the shared VISUAL-ONLY floor fixture tile
/// (wall / door / window / cashier / plant).
///
/// Purely decorative: no status, no occupancy, no tap semantics of its own —
/// interactivity (Dashboard element-arrange mode) is the caller's wrapper, and
/// read-only surfaces (POS picker, Move Table) wrap it in an [IgnorePointer].
/// The five kinds stay visually distinguishable in MUTED chrome so fixtures
/// never compete with the status-tinted tables above them. Sizing is fully
/// canvas-driven (the placed-tile rect); internals scale with the box.
class RestoflowFloorFixture extends StatelessWidget {
  const RestoflowFloorFixture({
    super.key,
    required this.kind,
    this.label,
    this.selected = false,
    this.quarterTurns = 0,
    this.style,
  });

  /// TABLE-VISUAL-CONFIGURATION-120: the persisted artwork variant
  /// (`table_floor_elements.visual_style`, validated per kind by the server).
  /// `null` = the kind's default artwork. 120A plumbs the seam; the variant
  /// ARTWORK lands in 120B — until then every style paints the default look.
  final String? style;

  /// One of `wall` / `door` / `window` / `cashier` / `plant` (an unknown kind
  /// degrades to the wall look — never a crash on a newer server).
  final String kind;

  /// Optional caption (cashier/door only by contract; the widget simply drops
  /// a label it has no room to draw).
  final String? label;

  /// Element-arrange highlight (Dashboard only).
  final bool selected;

  /// TABLE-119A: the AUTHORITATIVE `orientation_quarter_turns` from the wire
  /// - rotates directional artwork (door leaf/swing, window sill). The room
  /// rect already carries the swapped footprint; this never changes geometry.
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final side = w < h ? w : h;
        final (Color fill, Color on, IconData? icon) = switch (kind) {
          'window' => (
            scheme.primary.withValues(alpha: 0.14),
            scheme.primary.withValues(alpha: 0.8),
            null,
          ),
          'door' => (
            scheme.tertiaryContainer,
            scheme.onTertiaryContainer,
            Icons.meeting_room_outlined,
          ),
          'cashier' => (
            scheme.secondaryContainer,
            scheme.onSecondaryContainer,
            Icons.point_of_sale_outlined,
          ),
          'plant' => (
            RestoflowTone.success.styleOf(theme).container,
            RestoflowTone.success.styleOf(theme).accent,
            Icons.local_florist_outlined,
          ),
          // wall + forward-compatible fallback
          _ => (scheme.outlineVariant, scheme.onSurfaceVariant, null),
        };
        final radius = BorderRadius.circular(
          side < 24 ? side / 4 : RestoflowRadii.sm,
        );
        final text = label;
        // TABLE-119A: recognizable vector artwork replaces the flat icon box
        // whenever there is room (walls need only a sliver for their joints);
        // tiny fixtures keep the lightweight flat fallback.
        // 119B: a door's artwork gates on its LONG side — the standard
        // 900x150-unit door strip is only ~5-8px thick on POS/kiosk, yet must
        // still read as a door (thin leaf + swing cue), never a flat strip.
        // The threshold must clear BOTH orientations on the pinned minimum
        // canvas (480px wide, y-scale is 1/1.9 of x): a ROTATED door there is
        // only ~22.7px long, so the gate sits at 18, never 24.
        // 119D: windows are thin wall strips exactly like doors (a 300-unit
        // window is ~16px tall on kiosk, ~9px on POS), so they gate on the
        // LONG side too — otherwise the glass never paints and the strip
        // falls back to a wall-look box.
        final long = w > h ? w : h;
        // 120B: a STYLED wall must reach its artwork even as a thin strip
        // (the standard 3000x150 wall is only ~4.6px thick on the POS), so
        // it gates on the LONG side like doors/windows. The default wall
        // keeps the exact 119D gate — its look is unchanged everywhere.
        final styledWall =
            kind == 'wall' &&
            RestoflowFixturePainter.resolveStyle(kind, style) != 'default';
        final paintArt = switch (kind) {
          'wall' => side >= 6 || (styledWall && long >= 18),
          'door' || 'window' => long >= 18,
          _ => side >= 18,
        };
        // TABLE-119D: with artwork active the PAINTER owns the fixture's whole
        // identity — plant/cashier/window/door paint their full surface, so
        // the box behind them goes transparent (no more "colored rectangle
        // with an icon"). Walls keep their slab fill (a wall IS a slab), and
        // tiny fixtures keep the flat colored fallback.
        // Only the kinds whose painter paints its OWN full base slab may drop
        // the box fill; an unknown/forward-compat kind falls to the wall look
        // (stroke-only joints) and must keep its slab.
        const artKinds = {'door', 'window', 'cashier', 'plant'};
        final artOwnsSurface = paintArt && artKinds.contains(kind);
        final boxFill = artOwnsSurface ? Colors.transparent : fill;
        final showIcon = icon != null && side >= 18 && !paintArt;
        final showLabel = text != null && text.isNotEmpty && h >= 30 && w >= 40;
        final labelText = showLabel
            ? Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: paintArt ? Colors.white : on,
                  fontSize: (side * 0.16).clamp(8.0, 11.0),
                  fontWeight: FontWeight.w600,
                ),
              )
            : null;
        return Container(
          decoration: BoxDecoration(color: boxFill, borderRadius: radius),
          // 119D: the border lives in the FOREGROUND so the Dashboard's
          // arrange-mode selection ring stays visible above full-surface
          // fixture artwork (the painter fills the whole box now).
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(
                      alpha: kind == 'wall' || artOwnsSurface ? 0 : 0.35,
                    ),
              width: selected ? 2 : 1,
            ),
          ),
          child: paintArt || showIcon || showLabel
              ? _FixtureBody(
                  painter: paintArt
                      ? RestoflowFixturePainter(
                          kind: kind,
                          fill: fill,
                          ink: on,
                          outline: scheme.outline,
                          quarterTurns: quarterTurns,
                          style: style,
                          // 119D: fixture richness scales with the LONG side
                          // — a wide counter earns its keypad/terminal even
                          // though it is short.
                          detail: restoflowFloorDetailFor(long),
                        )
                      : null,
                  // With artwork, the caption anchors to the bottom service
                  // edge on a small dark plate (clear of the scene); the flat
                  // fallback keeps the centred icon+label chrome.
                  child: paintArt
                      ? (labelText == null
                            ? null
                            : Align(
                                // The caption follows the artwork's rotation
                                // to the side its service edge lands on
                                // (cashier front at local +y): 0=bottom,
                                // 1=left, 2=top, 3=right.
                                alignment: switch (quarterTurns % 4) {
                                  1 => Alignment.centerLeft,
                                  2 => Alignment.topCenter,
                                  3 => Alignment.centerRight,
                                  _ => Alignment.bottomCenter,
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(1.5),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 0.5,
                                      ),
                                      child: labelText,
                                    ),
                                  ),
                                ),
                              ))
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showIcon)
                                Icon(
                                  icon,
                                  size: (side * 0.42).clamp(10.0, 26.0),
                                  color: on,
                                ),
                              if (labelText != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: labelText,
                                ),
                            ],
                          ),
                        ),
                )
              : const SizedBox.expand(),
        );
      },
    );
  }
}

/// TABLE-119A: layers the fixture painter under the (rare) icon/label chrome
/// without changing the fixture's box or geometry.
class _FixtureBody extends StatelessWidget {
  const _FixtureBody({required this.painter, required this.child});

  final RestoflowFixturePainter? painter;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (painter != null)
        RepaintBoundary(child: CustomPaint(painter: painter)),
      if (child != null) child!,
    ],
  );
}
