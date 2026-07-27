import 'dart:math' as math;

import '../media_profile.dart';
import '../print_document.dart';

/// PRINT-LAYOUT-001A: the localized strings the profile-aware diagnostic page
/// prints. Injected by the app (this package stays l10n-agnostic). The width /
/// height lines are pre-formatted by the app from the profile's dot geometry.
class MediaProfileDiagnosticLabels {
  const MediaProfileDiagnosticLabels({
    required this.heading,
    required this.profileName,
    required this.widthLine,
    required this.topSafe,
    required this.bottomSafe,
    this.heightLine,
  });

  final String heading;

  /// The selected profile's user-facing name (e.g. "50 × 50 mm label").
  final String profileName;

  /// Pre-formatted "Width: {n} dots".
  final String widthLine;

  /// Pre-formatted "Media height: {n} dots" — null for a continuous roll.
  final String? heightLine;

  final String topSafe;
  final String bottomSafe;
}

/// Three FIXED multilingual script samples printed on every diagnostic (whatever
/// the UI locale), so a physical page proves the printer shapes Arabic, Hebrew,
/// and Latin. Fixed print-check text — never shown in the app UI.
const String kDiagArabicSample = 'أبجد هوز عربي ١٢٣';
const String kDiagHebrewSample = 'אבגד הוז עברית 123';
const String kDiagEnglishSample = 'The quick brown fox ENGLISH 123';

/// Builds the profile-aware diagnostic [PrintDocument] (money-free): a heading,
/// the selected profile name + printable width (+ media height for a fixed
/// label), a full-width edge ruler + safe-area markers that bound the printable
/// width (the left/right edges), Arabic/Hebrew/English samples, and a final
/// BOTTOM safe-area line that proves the last line is not clipped.
///
/// Rendered through `rasterizeForMediaProfile` at the profile width, so a 50×50
/// diagnostic is 384 dots and paginates within 400; the ar/he samples force the
/// raster path even on a continuous roll.
PrintDocument buildMediaProfileDiagnosticDocument({
  required MediaProfile profile,
  required MediaProfileDiagnosticLabels labels,
}) {
  // A left|—right| ruler roughly filling the profile's column count, so the two
  // edges of the printable width are visible on paper (symbols, not UI copy).
  final rulerWidth = math.max(1, profile.columns - 2);
  final edgeRuler = '|${'-' * rulerWidth}|';

  return PrintDocument(<PrintLine>[
    PrintTextLine(
      labels.heading,
      style: PrintLineStyle.headingLarge,
      alignment: PrintAlignment.center,
    ),
    PrintTextLine(
      labels.profileName,
      style: PrintLineStyle.item,
      alignment: PrintAlignment.center,
    ),
    PrintTextLine(labels.widthLine, style: PrintLineStyle.normal),
    if (labels.heightLine case final h?)
      PrintTextLine(h, style: PrintLineStyle.normal),
    // TOP safe-area marker + the full-width edge ruler (left/right edges).
    PrintTextLine(labels.topSafe, style: PrintLineStyle.centered),
    PrintTextLine(edgeRuler, style: PrintLineStyle.normal),
    const PrintTextLine('', style: PrintLineStyle.separator),
    // Script proofs — the raster path shapes RTL runs correctly.
    PrintTextLine(kDiagArabicSample, style: PrintLineStyle.item),
    PrintTextLine(kDiagHebrewSample, style: PrintLineStyle.item),
    PrintTextLine(kDiagEnglishSample, style: PrintLineStyle.item),
    const PrintTextLine('', style: PrintLineStyle.separator),
    PrintTextLine(edgeRuler, style: PrintLineStyle.normal),
    // The final visible line — proves nothing past it was clipped.
    PrintTextLine(
      labels.bottomSafe,
      style: PrintLineStyle.note,
      alignment: PrintAlignment.center,
    ),
  ], localeTag: '');
}
