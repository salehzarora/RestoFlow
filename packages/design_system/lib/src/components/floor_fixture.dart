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
  });

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
        final paintArt = kind == 'wall' ? side >= 6 : side >= 18;
        final showIcon = icon != null && side >= 18 && !paintArt;
        final showLabel = text != null && text.isNotEmpty && h >= 30 && w >= 40;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: kind == 'wall' ? 0 : 0.35),
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
                          detail: restoflowFloorDetailFor(side),
                        )
                      : null,
                  child: showIcon || showLabel
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showIcon)
                                Icon(
                                  icon,
                                  size: (side * 0.42).clamp(10.0, 26.0),
                                  color: on,
                                ),
                              if (showLabel)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Text(
                                    text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: on,
                                      fontSize: (side * 0.16).clamp(8.0, 11.0),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : null,
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
