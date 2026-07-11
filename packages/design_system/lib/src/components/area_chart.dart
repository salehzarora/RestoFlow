import 'package:flutter/material.dart';

/// One point of a [RestoflowAreaChart] (RF-127): a short x-axis [label] and an
/// integer [value]. Money callers pass integer minor units directly — the chart
/// never formats money; only the caller-supplied [RestoflowAreaChart.peakValueLabel]
/// and [RestoflowAreaChart.semanticsLabel] carry formatted / localized strings.
class RestoflowAreaDatum {
  const RestoflowAreaDatum({required this.label, required this.value});

  /// Short x-axis label (e.g. "14"). Rendered verbatim, not localized here.
  final String label;

  /// Point magnitude (any unit; the chart scales to the max). Never negative.
  final int value;
}

/// A calm, single-hue filled area/line chart for a time series (RF-127): a soft
/// brand-tinted area under a brand-green line, a faint mid gridline + baseline,
/// the peak point marked and value-labelled, and a subsampled row of x-axis
/// labels (so a 24-hour series never clips its labels on a phone).
///
/// The dominant "data-forward" visualization of the redesigned Overview — larger
/// and quieter than the compact [RestoflowBarChart], which it complements rather
/// than replaces.
///
/// Deliberately STATIC — no animation (the widget-test corpus `pumpAndSettle`s).
/// Pure presentation: it holds no state, formats no money, has no business logic
/// and no external dependency, so it lives in the design system with no l10n
/// dependency. The caller supplies chronological data (painted start→end in list
/// order) plus a pre-built [semanticsLabel] textual summary, so the chart is not
/// conveyed by colour alone and is described to screen readers. Zero values
/// render honestly as a flat baseline; an empty series renders nothing.
class RestoflowAreaChart extends StatelessWidget {
  const RestoflowAreaChart({
    required this.points,
    this.height = 220,
    this.peakValueLabel,
    this.semanticsLabel,
    this.lineColor,
    this.maxLabels = 7,
    super.key,
  });

  /// The series, in display (chronological) order. Empty renders nothing.
  final List<RestoflowAreaDatum> points;

  /// The plot height (labels/padding add to this).
  final double height;

  /// Optional pre-formatted label for the peak point (e.g. "₪132.40"), drawn
  /// above it. The caller formats it (money stays integer-minor upstream).
  final String? peakValueLabel;

  /// Optional accessible textual summary describing the series (e.g. "Sales by
  /// hour: peak ₪132.40"). When set, the chart is exposed to screen readers with
  /// this label so the data is not conveyed by colour/shape alone.
  final String? semanticsLabel;

  /// Line/area hue; defaults to the theme's brand primary.
  final Color? lineColor;

  /// The maximum number of x-axis labels to draw (evenly subsampled) so dense
  /// series (e.g. 24 hours) stay readable and unclipped.
  final int maxLabels;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = lineColor ?? scheme.primary;

    var peakIndex = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].value > points[peakIndex].value) peakIndex = i;
    }

    final chart = LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: CustomPaint(
            painter: _AreaChartPainter(
              points: points,
              peakIndex: peakIndex,
              peakValueLabel: peakValueLabel,
              line: line,
              fill: line.withValues(alpha: 0.14),
              grid: scheme.outlineVariant,
              maxLabels: maxLabels < 2 ? 2 : maxLabels,
              labelStyle: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              peakLabelStyle: theme.textTheme.labelSmall!.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              markerRing: scheme.surface,
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ),
        );
      },
    );

    final summary = semanticsLabel;
    if (summary == null) return chart;
    // A single labelled node so the series is described to screen readers (not
    // conveyed by colour/shape alone).
    return Semantics(label: summary, container: true, child: chart);
  }
}

class _AreaChartPainter extends CustomPainter {
  _AreaChartPainter({
    required this.points,
    required this.peakIndex,
    required this.peakValueLabel,
    required this.line,
    required this.fill,
    required this.grid,
    required this.maxLabels,
    required this.labelStyle,
    required this.peakLabelStyle,
    required this.markerRing,
    required this.textScaler,
  });

  final List<RestoflowAreaDatum> points;
  final int peakIndex;
  final String? peakValueLabel;
  final Color line;
  final Color fill;
  final Color grid;
  final int maxLabels;
  final TextStyle labelStyle;
  final TextStyle peakLabelStyle;
  final Color markerRing;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final n = points.length;
    if (n == 0) return;
    final maxValue = points.fold<int>(0, (m, p) => p.value > m ? p.value : m);

    // Scale-aware vertical reservations: measure the ACTUAL label heights at the
    // current text scale so labels never collide with the plot or escape the
    // chart when the OS text size is increased (fixed reservations would clip).
    const xLabelGap = 4.0;
    const peakLabelGap = 8.0;
    final sampleXLabel = _layout(
      points.first.label.isEmpty ? '0' : points.first.label,
      labelStyle,
      double.infinity,
    );
    final axisH = sampleXLabel.height + xLabelGap + 2;

    final peak = peakValueLabel;
    TextPainter? peakTp;
    var topPad = 6.0;
    if (peak != null) {
      peakTp = _layout(peak, peakLabelStyle, size.width);
      topPad = peakTp.height + peakLabelGap + 2;
    }

    final plotH = size.height - axisH - topPad;
    // Not enough room (extreme text scale): draw nothing rather than overflow.
    if (plotH <= 0) return;
    final baseY = topPad + plotH;

    // A single faint mid gridline (recessive) + the baseline.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, topPad + plotH / 2),
      Offset(size.width, topPad + plotH / 2),
      gridPaint,
    );
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), gridPaint);

    double xAt(int i) => n == 1 ? size.width / 2 : i * (size.width / (n - 1));
    double yAt(int v) => maxValue == 0 ? baseY : baseY - (v / maxValue) * plotH;

    final pts = [
      for (var i = 0; i < n; i++) Offset(xAt(i), yAt(points[i].value)),
    ];

    // Filled area under the curve (only meaningful with a magnitude and ≥2
    // points; a zero series stays a flat baseline — honest, no phantom fill).
    if (n >= 2 && maxValue > 0) {
      final area = Path()..moveTo(pts.first.dx, baseY);
      for (final p in pts) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(pts.last.dx, baseY)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill,
      );
    }

    // The line stroke.
    if (n >= 2) {
      final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < n; i++) {
        linePath.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(
        linePath,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // The peak marker (a filled dot with a surface ring) + its value label,
    // placed within the reserved [topPad] above the marker so it never collides
    // with the line or escapes the top of the chart, at any text scale.
    if (maxValue > 0) {
      final pk = pts[peakIndex];
      canvas.drawCircle(pk, 5, Paint()..color = markerRing);
      canvas.drawCircle(pk, 3.5, Paint()..color = line);
      if (peakTp != null) {
        final labelW = peakTp.width;
        final labelX = (pk.dx - labelW / 2).clamp(
          0.0,
          (size.width - labelW).clamp(0.0, size.width),
        );
        final labelY = (pk.dy - peakLabelGap - peakTp.height).clamp(
          0.0,
          (baseY - peakTp.height).clamp(0.0, baseY),
        );
        peakTp.paint(canvas, Offset(labelX, labelY));
      }
    }

    // X-axis labels, evenly subsampled so a dense series never clips. The last
    // point always gets a label so the series' end is anchored. Each label is
    // measured (so it never ellipsizes at large scale) and clamped inside the
    // canvas; the reserved [axisH] keeps them clear of the following content.
    final xLabelY = baseY + xLabelGap;
    final step = (n / maxLabels).ceil().clamp(1, n);
    for (var i = 0; i < n; i += step) {
      _paintLabelAt(canvas, i, xAt(i), size.width, xLabelY);
    }
    if ((n - 1) % step != 0) {
      _paintLabelAt(canvas, n - 1, xAt(n - 1), size.width, xLabelY);
    }
  }

  void _paintLabelAt(
    Canvas canvas,
    int index,
    double centerX,
    double width,
    double y,
  ) {
    final tp = _layout(points[index].label, labelStyle, width);
    final x = (centerX - tp.width / 2).clamp(
      0.0,
      (width - tp.width).clamp(0.0, width),
    );
    tp.paint(canvas, Offset(x, y));
  }

  /// Lays out [text] at the current [textScaler] (single line, ellipsized) so
  /// callers can both measure (height/width) and paint at the OS text size.
  TextPainter _layout(String text, TextStyle style, double maxWidth) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  @override
  bool shouldRepaint(_AreaChartPainter old) =>
      old.points != points ||
      old.peakIndex != peakIndex ||
      old.peakValueLabel != peakValueLabel ||
      old.line != line ||
      old.fill != fill ||
      old.grid != grid ||
      old.maxLabels != maxLabels ||
      old.labelStyle != labelStyle ||
      old.peakLabelStyle != peakLabelStyle ||
      old.markerRing != markerRing ||
      old.textScaler != textScaler;
}
