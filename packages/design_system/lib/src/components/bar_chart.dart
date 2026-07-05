import 'package:flutter/material.dart';

import '../tokens.dart';

/// One bar of a [RestoflowBarChart] (DESIGN-002): an x-axis [label] and an
/// integer [value]. Money callers pass integer minor units directly — the
/// chart never formats money; only the caller-supplied [RestoflowBarChart.peakValueLabel]
/// carries a formatted string.
class RestoflowBarDatum {
  const RestoflowBarDatum({required this.label, required this.value});

  /// Short x-axis label (e.g. "12"). Rendered verbatim, not localized here.
  final String label;

  /// Bar magnitude (any unit; the chart scales to the max). Never negative.
  final int value;
}

/// A compact, single-hue bar chart for a time/category series (DESIGN-002):
/// brand-green bars with rounded tops anchored to a baseline, one faint
/// mid gridline, x-axis labels, and the peak bar emphasised + value-labelled.
///
/// Deliberately STATIC — no animation (the widget-test corpus `pumpAndSettle`s;
/// an implicit/looping animation would hang it). Pure presentation: it holds no
/// state, formats no money, and takes pre-built strings, so it lives in the
/// design system with no l10n dependency. The time axis is painted start→end in
/// list order (the caller supplies chronological data); labels remain readable
/// under RTL because they are short numerics.
class RestoflowBarChart extends StatelessWidget {
  const RestoflowBarChart({
    required this.bars,
    this.height = 160,
    this.peakValueLabel,
    this.barColor,
    super.key,
  });

  /// The series, in display (chronological) order. Empty renders nothing.
  final List<RestoflowBarDatum> bars;

  /// The plot height (labels/padding add to this).
  final double height;

  /// Optional pre-formatted label for the tallest bar (e.g. "₪338.00") drawn
  /// above it. The caller formats it (money stays integer-minor upstream).
  final String? peakValueLabel;

  /// Bar fill; defaults to the theme's brand primary.
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = barColor ?? scheme.primary;

    // The index of the tallest bar (first on ties) gets the emphasis + label.
    var peakIndex = 0;
    for (var i = 1; i < bars.length; i++) {
      if (bars[i].value > bars[peakIndex].value) peakIndex = i;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: CustomPaint(
            painter: _BarChartPainter(
              bars: bars,
              peakIndex: peakIndex,
              peakValueLabel: peakValueLabel,
              fill: fill,
              grid: scheme.outlineVariant,
              labelStyle: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              peakLabelStyle: theme.textTheme.labelSmall!.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ),
        );
      },
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.bars,
    required this.peakIndex,
    required this.peakValueLabel,
    required this.fill,
    required this.grid,
    required this.labelStyle,
    required this.peakLabelStyle,
    required this.textScaler,
  });

  final List<RestoflowBarDatum> bars;
  final int peakIndex;
  final String? peakValueLabel;
  final Color fill;
  final Color grid;
  final TextStyle labelStyle;
  final TextStyle peakLabelStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = RestoflowSpacing.sm;
    const axisH = 18.0; // room for x-axis labels
    const topPad = 16.0; // room for the peak value label
    final plotH = size.height - axisH - topPad;
    if (plotH <= 0) return;

    final maxValue = bars.fold<int>(0, (m, b) => b.value > m ? b.value : m);
    final n = bars.length;
    final barW = (size.width - gap * (n - 1)) / n;
    if (barW <= 0) return;

    // A single faint mid gridline (recessive).
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final midY = topPad + plotH / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), gridPaint);
    // Baseline.
    final baseY = topPad + plotH;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), gridPaint);

    for (var i = 0; i < n; i++) {
      final bar = bars[i];
      final frac = maxValue == 0 ? 0.0 : bar.value / maxValue;
      final barH = frac * plotH;
      final left = i * (barW + gap);
      final isPeak = i == peakIndex && maxValue > 0;
      final paint = Paint()
        ..color = isPeak ? fill : fill.withValues(alpha: 0.55);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, baseY - barH, barW, barH),
        topLeft: const Radius.circular(RestoflowRadii.sm),
        topRight: const Radius.circular(RestoflowRadii.sm),
      );
      canvas.drawRRect(rect, paint);

      // X-axis label under each bar.
      _paintText(
        canvas,
        bar.label,
        labelStyle,
        Offset(left, baseY + 4),
        barW,
        TextAlign.center,
      );

      // The peak value label above the tallest bar. Its box is widened well
      // beyond one bar (many thin bars on a narrow phone would otherwise
      // ellipsize the one callout number to "…") and clamped inside the canvas,
      // so the emphasised value stays readable at every width.
      if (isPeak && peakValueLabel != null) {
        final barCenter = left + barW / 2;
        final labelW = (barW * 2).clamp(84.0, size.width);
        final labelX = (barCenter - labelW / 2).clamp(0.0, size.width - labelW);
        _paintText(
          canvas,
          peakValueLabel!,
          peakLabelStyle,
          Offset(labelX, baseY - barH - topPad),
          labelW,
          TextAlign.center,
        );
      }
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset topLeft,
    double maxWidth,
    TextAlign align,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(
      canvas,
      Offset(topLeft.dx + (maxWidth - tp.width) / 2, topLeft.dy),
    );
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.bars != bars ||
      old.peakValueLabel != peakValueLabel ||
      old.fill != fill;
}
