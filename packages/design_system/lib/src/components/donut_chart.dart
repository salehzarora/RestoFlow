import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// One slice of a [RestoflowDonutChart]: an integer [value] (any unit; the chart
/// scales to the total), a [color], and a short [label] for the caller's legend.
class RestoflowDonutSegment {
  const RestoflowDonutSegment({
    required this.value,
    required this.color,
    required this.label,
  });

  /// Slice magnitude. Never negative; zero-value slices are skipped.
  final int value;

  /// Slice colour (brand/semantic; the caller picks it).
  final Color color;

  /// Short slice label for a caller-built legend (not drawn on the ring).
  final String label;
}

/// A compact donut/ring chart (Dashboard "1c" payment mix), mirroring
/// [RestoflowBarChart]'s philosophy: a `CustomPainter`, deliberately STATIC (no
/// animation — `pumpAndSettle`-safe), and money-free (it takes integer values;
/// the caller formats any money in [centerLabel]/[centerSub] and in the legend
/// rendered beside it). An all-zero series draws a single faint track ring
/// (honest empty), never a fabricated slice. RTL-safe: the ring is symmetric and
/// the centred text mirrors with the layout.
class RestoflowDonutChart extends StatelessWidget {
  const RestoflowDonutChart({
    required this.segments,
    this.centerLabel,
    this.centerSub,
    this.size = 180,
    this.ringWidth = 17,
    super.key,
  });

  /// The slices, in draw order (start at the top, clockwise).
  final List<RestoflowDonutSegment> segments;

  /// Optional prominent centre label (e.g. "82%" or a formatted total).
  final String? centerLabel;

  /// Optional muted centre sub-label under [centerLabel].
  final String? centerSub;

  /// The chart's square side length.
  final double size;

  /// The ring thickness.
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(
              segments: segments,
              ringWidth: ringWidth,
              trackColor: scheme.surfaceContainerHighest,
            ),
          ),
          if (centerLabel != null || centerSub != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (centerLabel case final c?)
                  Text(
                    c,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: kRestoflowInk,
                    ),
                  ),
                if (centerSub case final s?)
                  Text(
                    s,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.ringWidth,
    required this.trackColor,
  });

  final List<RestoflowDonutSegment> segments;
  final double ringWidth;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final drawn = segments.where((s) => s.value > 0).toList();
    final total = drawn.fold<int>(0, (s, seg) => s + seg.value);
    final rect = Rect.fromLTWH(
      ringWidth / 2,
      ringWidth / 2,
      size.width - ringWidth,
      size.height - ringWidth,
    );

    // Empty / all-zero: a single faint full track ring (never a fake slice).
    if (total == 0) {
      canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..color = trackColor,
      );
      return;
    }

    const gap = 0.06; // radians between slices
    final multi = drawn.length > 1;
    final totalGap = multi ? gap * drawn.length : 0.0;
    final usable = 2 * math.pi - totalGap;
    var angle = -math.pi / 2; // start at the top

    for (final seg in drawn) {
      final sweep = usable * (seg.value / total);
      canvas.drawArc(
        rect,
        angle,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..strokeCap = multi ? StrokeCap.round : StrokeCap.butt
          ..color = seg.color,
      );
      angle += sweep + (multi ? gap : 0);
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.segments != segments ||
      old.ringWidth != ringWidth ||
      old.trackColor != trackColor;
}
