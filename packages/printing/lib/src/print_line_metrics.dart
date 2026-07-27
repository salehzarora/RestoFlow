import 'dart:math' as math;

import 'print_document.dart';
import 'print_typography.dart';

/// PRINT-LAYOUT-001A/001B — the per-line raster metrics used by the pure
/// pagination planner (which estimates each line's rendered height to decide
/// page breaks). Since 001B the per-role SIZE hierarchy lives in
/// [PrintTypography]; this file re-exposes the base multiplier for callers that
/// predate the typography object and turns styles into estimated row heights.
/// Keeping the size source in one place ([PrintTypography.sizeMultiplier]) means
/// an estimate can never drift from what the renderer actually produces.

/// The per-style font-size multiplier for the STANDARD hierarchy. Thin delegate
/// to [PrintTypography.standard] — the single source — kept for backward
/// compatibility. Profile-aware callers should read [PrintTypography] directly.
double printLineStyleSizeMultiplier(PrintLineStyle style) =>
    PrintTypography.standard.sizeMultiplier(style);

/// Estimates the rendered ROW height (dots) of each styled line for a
/// [typography] hierarchy at a media profile's [fontScale] + [lineSpacing]. It
/// matches the renderer's band-height formula for single-line (pre-wrapped)
/// receipt/ticket text — which is exactly what pagination needs to plan page
/// breaks. A separator is a thin rule (no line-height multiplier), every other
/// line is `size * lineSpacing`.
List<int> estimateReceiptLineRows(
  List<PrintLineStyle> styles, {
  double fontScale = 1.0,
  double? lineSpacing,
  double? baseFontSize,
  PrintTypography typography = PrintTypography.standard,
}) {
  final base = baseFontSize ?? typography.baseFontSize;
  final spacing = lineSpacing ?? typography.lineHeight;
  return <int>[
    for (final style in styles)
      _rows(style, base, fontScale, spacing, typography),
  ];
}

int _rows(
  PrintLineStyle style,
  double base,
  double scale,
  double spacing,
  PrintTypography typography,
) {
  final size = base * typography.sizeMultiplier(style) * scale;
  final height = style == PrintLineStyle.separator ? size : size * spacing;
  return math.max(1, height.ceil());
}
