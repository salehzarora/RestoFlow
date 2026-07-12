import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

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
/// brand-tinted area under a brand-green line, faint gridlines + baseline,
/// the peak point marked and value-labelled, and a subsampled row of x-axis
/// labels (so a 24-hour series never clips its labels on a phone).
///
/// The dominant "data-forward" visualization of the redesigned Overview — larger
/// and quieter than the compact [RestoflowBarChart], which it complements rather
/// than replaces.
///
/// Deliberately STATIC in its default form — no animation (the widget-test
/// corpus `pumpAndSettle`s). Pure presentation: it holds no business state,
/// formats no money, and has no external dependency, so it lives in the design
/// system with no l10n dependency. The caller supplies chronological data
/// (painted start→end in list order) plus a pre-built [semanticsLabel] textual
/// summary, so the chart is not conveyed by colour alone and is described to
/// screen readers. Zero values render honestly as a flat baseline; an empty
/// series renders nothing.
///
/// Dashboard V2 additions (all additive/opt-in):
///  * [smooth] draws the line as a MONOTONE cubic (Fritsch–Carlson): the curve
///    is shape-preserving and can never overshoot the real points, so it never
///    implies values outside the data.
///  * [tooltipBuilder] enables point selection via hover, tap/drag, and the
///    keyboard (focus the chart, then arrow keys; Escape clears). The selected
///    REAL point gets a crosshair + marker and a tooltip whose text the caller
///    builds from the datum (money formatted upstream). The tooltip is a real
///    text widget (accessible + testable), never canvas-only.
class RestoflowAreaChart extends StatefulWidget {
  const RestoflowAreaChart({
    required this.points,
    this.height = 220,
    this.peakValueLabel,
    this.semanticsLabel,
    this.lineColor,
    this.maxLabels = 7,
    this.yAxisTicks,
    this.yAxisLabelBuilder,
    this.smooth = false,
    this.tooltipBuilder,
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

  /// Optional ascending y-axis tick values, in the SAME units as
  /// [RestoflowAreaDatum.value] (money callers pass integer minor units — the
  /// chart still formats nothing). When set together with
  /// [yAxisLabelBuilder], a faint horizontal gridline is drawn at each tick
  /// with its label in a start-side gutter (RF-132), and the plot scales to at
  /// least the last tick. Null (the default) keeps the original single
  /// mid-gridline rendering, unchanged.
  final List<int>? yAxisTicks;

  /// Formats a [yAxisTicks] value into its axis label (the caller owns all
  /// formatting — money stays integer-minor upstream). Ignored when
  /// [yAxisTicks] is null.
  final String Function(int value)? yAxisLabelBuilder;

  /// Dashboard V2: draw the line as a monotone (non-overshooting) cubic curve
  /// instead of straight segments. Default false — existing consumers are
  /// pixel-unchanged.
  final bool smooth;

  /// Dashboard V2: when non-null the chart becomes interactive — hover, tap,
  /// drag, and keyboard (arrows / Escape) select one of the REAL [points], and
  /// this builder's text is shown in the selection tooltip (e.g.
  /// "14:00\n₪312.45" — the caller formats any money). Null (the default)
  /// keeps the chart display-only.
  final String Function(RestoflowAreaDatum datum)? tooltipBuilder;

  @override
  State<RestoflowAreaChart> createState() => _RestoflowAreaChartState();
}

class _RestoflowAreaChartState extends State<RestoflowAreaChart> {
  /// The interactively selected point index (hover/tap/keyboard); null = none.
  int? _selected;

  late final FocusNode _focusNode = FocusNode(debugLabel: 'RestoflowAreaChart');

  bool get _interactive => widget.tooltipBuilder != null;

  @override
  void didUpdateWidget(RestoflowAreaChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A REPLACED series invalidates any prior selection: keeping the old
    // index would either crash on a shorter list or silently tooltip a
    // DIFFERENT datum. Losing interactivity clears it too. (Mutating directly
    // is safe here — didUpdateWidget always precedes the rebuild.)
    if (!identical(oldWidget.points, widget.points) ||
        (oldWidget.tooltipBuilder != null && widget.tooltipBuilder == null)) {
      _selected = null;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _select(int? index) {
    if (_selected == index) return;
    setState(() => _selected = index);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final n = widget.points.length;
    if (n == 0) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _select(((_selected ?? _peakIndex()) + 1).clamp(0, n - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _select(((_selected ?? _peakIndex()) - 1).clamp(0, n - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _select(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int _peakIndex() {
    var peak = 0;
    for (var i = 1; i < widget.points.length; i++) {
      if (widget.points[i].value > widget.points[peak].value) peak = i;
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = widget.lineColor ?? scheme.primary;
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = theme.textTheme.bodySmall!.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final peakLabelStyle = theme.textTheme.labelSmall!.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

    final peakIndex = _peakIndex();

    final chart = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final metrics = _ChartMetrics.compute(
          width: width,
          height: widget.height,
          points: widget.points,
          peakValueLabel: widget.peakValueLabel,
          yAxisTicks: widget.yAxisTicks,
          yAxisLabelBuilder: widget.yAxisLabelBuilder,
          labelStyle: labelStyle,
          peakLabelStyle: peakLabelStyle,
          textScaler: textScaler,
        );

        // Never index the series with an unvalidated selection — the series
        // may have been swapped for a shorter one this frame (belt-and-braces
        // on top of the didUpdateWidget clearing).
        final rawSelected = _selected;
        final selected =
            (rawSelected != null &&
                rawSelected >= 0 &&
                rawSelected < widget.points.length)
            ? rawSelected
            : null;

        final paint = CustomPaint(
          painter: _AreaChartPainter(
            points: widget.points,
            peakIndex: peakIndex,
            peakValueLabel: widget.peakValueLabel,
            line: line,
            grid: scheme.outlineVariant,
            maxLabels: widget.maxLabels < 2 ? 2 : widget.maxLabels,
            labelStyle: labelStyle,
            peakLabelStyle: peakLabelStyle,
            markerRing: scheme.surface,
            textScaler: textScaler,
            yAxisTicks: widget.yAxisTicks,
            yAxisLabelBuilder: widget.yAxisLabelBuilder,
            smooth: widget.smooth,
            selectedIndex: _interactive ? selected : null,
            showPointDots: _interactive,
          ),
        );

        if (!_interactive) {
          return SizedBox(width: width, height: widget.height, child: paint);
        }

        Widget? tooltip;
        if (selected != null && metrics != null) {
          tooltip = _SelectionTooltip(
            text: widget.tooltipBuilder!(widget.points[selected]),
            anchor: Offset(
              metrics.xAt(selected),
              metrics.yAt(widget.points[selected].value),
            ),
            bounds: Size(width, widget.height),
          );
        }

        void selectAtDx(double dx) {
          final m = metrics;
          if (m == null) return;
          _select(m.nearestIndex(dx));
        }

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKeyEvent,
          child: MouseRegion(
            onHover: (e) => selectAtDx(e.localPosition.dx),
            onExit: (_) {
              // Keep a keyboard-owned selection; clear hover-only selection.
              if (!_focusNode.hasFocus) _select(null);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                // Taking focus lets the keyboard (arrows/Escape) continue from
                // the tapped point — selection is never hover- or mouse-only.
                _focusNode.requestFocus();
                selectAtDx(d.localPosition.dx);
              },
              onHorizontalDragUpdate: (d) => selectAtDx(d.localPosition.dx),
              child: SizedBox(
                width: width,
                height: widget.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: paint),
                    if (tooltip != null) tooltip,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    final summary = widget.semanticsLabel;
    if (summary == null) return chart;
    // A single labelled node so the series is described to screen readers (not
    // conveyed by colour/shape alone).
    return Semantics(label: summary, container: true, child: chart);
  }
}

/// The selection tooltip: a real text bubble (accessible + testable) anchored
/// above the selected point and clamped inside the chart bounds.
class _SelectionTooltip extends StatelessWidget {
  const _SelectionTooltip({
    required this.text,
    required this.anchor,
    required this.bounds,
  });

  final String text;
  final Offset anchor;
  final Size bounds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    // Measure so the bubble can be clamped precisely inside the chart.
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 3,
    )..layout(maxWidth: bounds.width - 2 * RestoflowSpacing.sm);
    final w = tp.width.ceilToDouble() + 2 * RestoflowSpacing.md + 2;
    final h = tp.height + 2 * RestoflowSpacing.sm;
    final left = (anchor.dx - w / 2).clamp(
      0.0,
      (bounds.width - w).clamp(0.0, bounds.width),
    );
    final top = (anchor.dy - h - 12).clamp(
      0.0,
      (bounds.height - h).clamp(0.0, bounds.height),
    );

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: w,
          padding: const EdgeInsets.symmetric(
            horizontal: RestoflowSpacing.md,
            vertical: RestoflowSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            border: Border.all(color: kRestoflowHairline),
            boxShadow: RestoflowShadows.md,
          ),
          // The tooltip carries an hour + a formatted amount: a numeric run
          // that must lay out LTR (matching the LTR measurement above) even
          // inside RTL locales, exactly like axis labels.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              text,
              style: style,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// The shared plot geometry, computed identically by the widget (hit-testing +
/// tooltip anchoring) and the painter (drawing) from the same inputs.
class _ChartMetrics {
  const _ChartMetrics({
    required this.gutterW,
    required this.topPad,
    required this.plotH,
    required this.baseY,
    required this.plotLeft,
    required this.plotW,
    required this.maxValue,
    required this.count,
  });

  final double gutterW;
  final double topPad;
  final double plotH;
  final double baseY;
  final double plotLeft;
  final double plotW;
  final int maxValue;
  final int count;

  double xAt(int i) =>
      count == 1 ? plotLeft + plotW / 2 : plotLeft + i * (plotW / (count - 1));

  double yAt(int v) => maxValue == 0 ? baseY : baseY - (v / maxValue) * plotH;

  /// The point index nearest to a local x offset (for hover/tap selection).
  int nearestIndex(double dx) {
    if (count <= 1) return 0;
    final step = plotW / (count - 1);
    final raw = ((dx - plotLeft) / step).round();
    return raw.clamp(0, count - 1);
  }

  /// Computes the geometry for a chart of [width]×[height]; null when there is
  /// no room to plot (extreme text scale on a tiny canvas).
  static _ChartMetrics? compute({
    required double width,
    required double height,
    required List<RestoflowAreaDatum> points,
    required String? peakValueLabel,
    required List<int>? yAxisTicks,
    required String Function(int value)? yAxisLabelBuilder,
    required TextStyle labelStyle,
    required TextStyle peakLabelStyle,
    required TextScaler textScaler,
  }) {
    if (width <= 0 || points.isEmpty) return null;
    final dataMax = points.fold<int>(0, (m, p) => p.value > m ? p.value : m);

    TextPainter layout(String text, TextStyle style, double maxWidth) =>
        TextPainter(
          text: TextSpan(text: text, style: style),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth);

    var gutterW = 0.0;
    var tickMax = 0;
    if (yAxisTicks != null &&
        yAxisTicks.isNotEmpty &&
        yAxisLabelBuilder != null) {
      var widest = 0.0;
      for (final t in yAxisTicks) {
        final tp = layout(yAxisLabelBuilder(t), labelStyle, width);
        if (tp.width > widest) widest = tp.width;
      }
      final candidate = widest + 8;
      if (candidate < width * 0.5) {
        gutterW = candidate;
        tickMax = yAxisTicks.last;
      }
    }
    final maxValue = tickMax > dataMax ? tickMax : dataMax;

    const xLabelGap = 4.0;
    const peakLabelGap = 8.0;
    final sampleXLabel = layout(
      points.first.label.isEmpty ? '0' : points.first.label,
      labelStyle,
      double.infinity,
    );
    final axisH = sampleXLabel.height + xLabelGap + 2;

    var topPad = 6.0;
    if (peakValueLabel != null) {
      final peakTp = layout(peakValueLabel, peakLabelStyle, width);
      topPad = peakTp.height + peakLabelGap + 2;
    }

    final plotH = height - axisH - topPad;
    if (plotH <= 0) return null;
    return _ChartMetrics(
      gutterW: gutterW,
      topPad: topPad,
      plotH: plotH,
      baseY: topPad + plotH,
      plotLeft: gutterW,
      plotW: width - gutterW,
      maxValue: maxValue,
      count: points.length,
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  _AreaChartPainter({
    required this.points,
    required this.peakIndex,
    required this.peakValueLabel,
    required this.line,
    required this.grid,
    required this.maxLabels,
    required this.labelStyle,
    required this.peakLabelStyle,
    required this.markerRing,
    required this.textScaler,
    this.yAxisTicks,
    this.yAxisLabelBuilder,
    this.smooth = false,
    this.selectedIndex,
    this.showPointDots = false,
  });

  final List<RestoflowAreaDatum> points;
  final int peakIndex;
  final String? peakValueLabel;
  final Color line;
  final Color grid;
  final int maxLabels;
  final TextStyle labelStyle;
  final TextStyle peakLabelStyle;
  final Color markerRing;
  final TextScaler textScaler;
  final List<int>? yAxisTicks;
  final String Function(int value)? yAxisLabelBuilder;
  final bool smooth;
  final int? selectedIndex;
  final bool showPointDots;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    final metrics = _ChartMetrics.compute(
      width: size.width,
      height: size.height,
      points: points,
      peakValueLabel: peakValueLabel,
      yAxisTicks: yAxisTicks,
      yAxisLabelBuilder: yAxisLabelBuilder,
      labelStyle: labelStyle,
      peakLabelStyle: peakLabelStyle,
      textScaler: textScaler,
    );
    // Not enough room (extreme text scale): draw nothing rather than overflow.
    if (metrics == null) return;
    final baseY = metrics.baseY;
    final hasYAxis = metrics.gutterW > 0;
    final maxValue = metrics.maxValue;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    if (hasYAxis) {
      // One faint gridline + start-side label per tick (RF-132); the labels sit
      // in the reserved gutter, right-aligned toward the axis, clamped so they
      // never escape the canvas at any text scale.
      final ticks = yAxisTicks!;
      final builder = yAxisLabelBuilder!;
      for (final value in ticks) {
        final y = metrics.yAt(value);
        canvas.drawLine(
          Offset(metrics.plotLeft, y),
          Offset(size.width, y),
          gridPaint,
        );
        final tp = _layout(builder(value), labelStyle, size.width);
        final labelY = (y - tp.height / 2).clamp(
          0.0,
          (size.height - tp.height).clamp(0.0, size.height),
        );
        tp.paint(
          canvas,
          Offset(
            (metrics.gutterW - 8 - tp.width).clamp(0.0, metrics.gutterW),
            labelY,
          ),
        );
      }
    } else {
      // Original rendering: a single faint mid gridline (recessive).
      canvas.drawLine(
        Offset(0, metrics.topPad + metrics.plotH / 2),
        Offset(size.width, metrics.topPad + metrics.plotH / 2),
        gridPaint,
      );
    }
    canvas.drawLine(
      Offset(metrics.plotLeft, baseY),
      Offset(size.width, baseY),
      gridPaint,
    );

    final pts = [
      for (var i = 0; i < n; i++)
        Offset(metrics.xAt(i), metrics.yAt(points[i].value)),
    ];

    // The line path: straight segments, or the monotone (never-overshooting)
    // cubic when [smooth].
    Path? linePath;
    if (n >= 2) {
      linePath = smooth
          ? _monotonePath(pts)
          : (Path()..moveTo(pts.first.dx, pts.first.dy));
      if (!smooth) {
        for (var i = 1; i < n; i++) {
          linePath.lineTo(pts[i].dx, pts[i].dy);
        }
      }
    }

    // Filled area under the curve (only meaningful with a magnitude and ≥2
    // points; a zero series stays a flat baseline — honest, no phantom fill).
    // The fill fades toward the baseline (Dashboard V2), staying subtle.
    if (linePath != null && maxValue > 0) {
      final area = Path.from(linePath)
        ..lineTo(pts.last.dx, baseY)
        ..lineTo(pts.first.dx, baseY)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, metrics.topPad),
            Offset(0, baseY),
            [line.withValues(alpha: 0.22), line.withValues(alpha: 0.02)],
          )
          ..style = PaintingStyle.fill,
      );
    }

    // The selection crosshair sits under the line stroke.
    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < n) {
      final sx = pts[selected].dx;
      canvas.drawLine(
        Offset(sx, metrics.topPad),
        Offset(sx, baseY),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
    }

    // The line stroke.
    if (linePath != null) {
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

    // Small dots on every REAL point (interactive charts only) — the V2 look
    // that also communicates where selection can land.
    if (showPointDots && maxValue > 0) {
      final dotPaint = Paint()..color = line;
      for (final p in pts) {
        canvas.drawCircle(p, 2.5, dotPaint);
      }
    }

    // The peak marker (a filled dot with a surface ring) + its value label,
    // placed within the reserved top padding above the marker so it never
    // collides with the line or escapes the top of the chart, at any scale.
    if (maxValue > 0) {
      final pk = pts[peakIndex];
      canvas.drawCircle(pk, 5, Paint()..color = markerRing);
      canvas.drawCircle(pk, 3.5, Paint()..color = line);
      final peak = peakValueLabel;
      if (peak != null) {
        final peakTp = _layout(peak, peakLabelStyle, size.width);
        final labelW = peakTp.width;
        final labelX = (pk.dx - labelW / 2).clamp(
          0.0,
          (size.width - labelW).clamp(0.0, size.width),
        );
        final labelY = (pk.dy - 8.0 - peakTp.height).clamp(
          0.0,
          (baseY - peakTp.height).clamp(0.0, baseY),
        );
        peakTp.paint(canvas, Offset(labelX, labelY));
      }
    }

    // The selected point marker (over the line, under the tooltip widget).
    if (selected != null && selected >= 0 && selected < n && maxValue > 0) {
      final sp = pts[selected];
      canvas.drawCircle(sp, 6, Paint()..color = markerRing);
      canvas.drawCircle(sp, 4, Paint()..color = line);
    }

    // X-axis labels, evenly subsampled so a dense series never clips. The last
    // point always gets a label so the series' end is anchored. Each label is
    // measured (so it never ellipsizes at large scale) and clamped inside the
    // canvas; the reserved axis strip keeps them clear of following content.
    final xLabelY = baseY + 4.0;
    final step = (n / maxLabels).ceil().clamp(1, n);
    for (var i = 0; i < n; i += step) {
      _paintLabelAt(canvas, i, metrics.xAt(i), size.width, xLabelY);
    }
    if ((n - 1) % step != 0) {
      _paintLabelAt(canvas, n - 1, metrics.xAt(n - 1), size.width, xLabelY);
    }
  }

  /// Builds the monotone cubic path (Fritsch–Carlson tangents): shape- and
  /// monotonicity-preserving, so the smoothed curve NEVER overshoots the real
  /// points or implies values outside them.
  Path _monotonePath(List<Offset> pts) {
    final n = pts.length;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (n == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }
    // Secant slopes.
    final d = List<double>.filled(n - 1, 0);
    for (var i = 0; i < n - 1; i++) {
      final dx = pts[i + 1].dx - pts[i].dx;
      d[i] = dx == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / dx;
    }
    // Tangents.
    final m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    // Clamp tangents so no segment overshoots (Fritsch–Carlson).
    for (var i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final a = m[i] / d[i];
      final b = m[i + 1] / d[i];
      final s = a * a + b * b;
      if (s > 9) {
        final t = 3 / math.sqrt(s);
        m[i] = t * a * d[i];
        m[i + 1] = t * b * d[i];
      }
    }
    for (var i = 0; i < n - 1; i++) {
      final dx = pts[i + 1].dx - pts[i].dx;
      path.cubicTo(
        pts[i].dx + dx / 3,
        pts[i].dy + (m[i] * dx) / 3,
        pts[i + 1].dx - dx / 3,
        pts[i + 1].dy - (m[i + 1] * dx) / 3,
        pts[i + 1].dx,
        pts[i + 1].dy,
      );
    }
    return path;
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
      old.grid != grid ||
      old.maxLabels != maxLabels ||
      old.labelStyle != labelStyle ||
      old.peakLabelStyle != peakLabelStyle ||
      old.markerRing != markerRing ||
      old.textScaler != textScaler ||
      old.yAxisTicks != yAxisTicks ||
      old.yAxisLabelBuilder != yAxisLabelBuilder ||
      old.smooth != smooth ||
      old.selectedIndex != selectedIndex ||
      old.showPointDots != showPointDots;
}
