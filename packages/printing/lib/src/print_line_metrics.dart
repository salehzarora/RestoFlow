import 'dart:math' as math;

import 'print_document.dart';

/// PRINT-LAYOUT-001A — the SINGLE source of the per-line raster metrics, shared
/// by the real dart:ui renderer (which picks the font size) and the pure
/// pagination planner (which estimates each line's rendered height to decide
/// page breaks). Keeping them in one place means an estimate can never drift
/// from what the renderer actually produces.

/// The base (normal) glyph size in dots the renderer uses at 1:1.
const double kBaseReceiptFontSize = 22.0;

/// The renderer's built-in line-height multiplier when a profile does not
/// override it.
const double kBaseReceiptLineHeight = 1.3;

/// The per-style font-size multiplier (a heading is larger, a sub-line smaller;
/// a separator is a thin rule). The renderer multiplies the base size by this,
/// then by the profile font scale.
double printLineStyleSizeMultiplier(PrintLineStyle style) => switch (style) {
  PrintLineStyle.headingLarge => 1.55,
  PrintLineStyle.item => 1.1,
  PrintLineStyle.sub => 0.9,
  PrintLineStyle.total => 1.2,
  PrintLineStyle.note => 1.0,
  PrintLineStyle.centered => 1.0,
  PrintLineStyle.normal => 1.0,
  PrintLineStyle.separator => 0.85,
};

/// Estimates the rendered ROW height (dots) of each styled line for a media
/// profile's [fontScale] + [lineSpacing]. It matches the renderer's band-height
/// formula for single-line (pre-wrapped) receipt/ticket text — which is exactly
/// what pagination needs to plan page breaks. A separator is a thin rule (no
/// line-height multiplier), every other line is `size * lineSpacing`.
List<int> estimateReceiptLineRows(
  List<PrintLineStyle> styles, {
  double fontScale = 1.0,
  double lineSpacing = kBaseReceiptLineHeight,
  double baseFontSize = kBaseReceiptFontSize,
}) => <int>[
  for (final style in styles) _rows(style, baseFontSize, fontScale, lineSpacing),
];

int _rows(PrintLineStyle style, double base, double scale, double spacing) {
  final size = base * printLineStyleSizeMultiplier(style) * scale;
  final height = style == PrintLineStyle.separator ? size : size * spacing;
  return math.max(1, height.ceil());
}
