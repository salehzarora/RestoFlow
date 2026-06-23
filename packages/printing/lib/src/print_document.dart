import 'dart:typed_data';

/// Horizontal alignment of a printed line (RF-070).
enum PrintAlignment { left, center, right }

/// Text emphasis (RF-070). Kept minimal — bold on/off only.
enum TextEmphasis { normal, bold }

/// Optional text-direction metadata carried on a line (RF-070).
///
/// RF-070 does NOT perform RTL layout or bidi — this is carried as a hint only;
/// real Arabic/Hebrew RTL receipts + rasterization are RF-073.
enum PrintTextDirection { ltr, rtl }

/// A render-neutral instruction in a [PrintDocument] (RF-070).
///
/// The document model contains NO ESC/POS bytes, NO money math, and NO device
/// codes. Text is PRE-FORMATTED by the caller (DECISION D-007/D-008: the print
/// layer never computes or formats money). An adapter turns these into bytes.
sealed class PrintLine {
  const PrintLine();
}

/// One line of pre-formatted text with alignment + emphasis (RF-070).
class PrintTextLine extends PrintLine {
  const PrintTextLine(
    this.text, {
    this.alignment = PrintAlignment.left,
    this.emphasis = TextEmphasis.normal,
    this.direction = PrintTextDirection.ltr,
  });

  /// Pre-formatted display text (the caller already formatted any money/qty).
  final String text;
  final PrintAlignment alignment;
  final TextEmphasis emphasis;

  /// Direction hint only (RF-070 does not lay out RTL — see RF-073).
  final PrintTextDirection direction;
}

/// Advance the paper by [lines] line-feeds (RF-070).
class PrintFeedLine extends PrintLine {
  const PrintFeedLine([this.lines = 1]) : assert(lines >= 0);
  final int lines;
}

/// Request a paper cut (honoured only if the profile supports it) (RF-070).
class PrintCutLine extends PrintLine {
  const PrintCutLine();
}

/// Request a cash-drawer kick COMMAND (RF-070, approved A1).
///
/// This is the raw ESC/POS command only — there is NO payment/cash trigger or
/// workflow here (that is RF-074). Honoured only if the profile supports it.
class PrintDrawerKickLine extends PrintLine {
  const PrintDrawerKickLine();
}

/// Print an ALREADY-PREPARED monochrome bitmap (RF-070, approved A2).
///
/// RF-070 does NOT rasterize text/Arabic/Hebrew/logos — it only encodes a
/// supplied 1-bit-per-pixel payload as ESC/POS raster bytes. Producing the
/// bitmap (shaping/bidi/fonts) is RF-073. Honoured only if the profile supports
/// raster. [data] is row-major, MSB-first, [widthBytes] bytes per row.
class PrintRasterImageLine extends PrintLine {
  PrintRasterImageLine({
    required this.data,
    required this.widthBytes,
    required this.heightDots,
  }) : assert(widthBytes > 0),
       assert(heightDots > 0),
       assert(
         data.length == widthBytes * heightDots,
         'raster data length must equal widthBytes * heightDots',
       );

  /// Monochrome bitmap payload (row-major, 1bpp, MSB first).
  final Uint8List data;

  /// Bytes per row (image width in dots / 8, rounded up by the caller).
  final int widthBytes;

  /// Image height in dots.
  final int heightDots;
}

/// A render-neutral print document: an ordered list of [PrintLine]s (RF-070).
class PrintDocument {
  const PrintDocument(this.lines, {this.localeTag});

  final List<PrintLine> lines;

  /// Optional locale tag (e.g. `ar`, `he`, `en`) carried as metadata; RF-070
  /// does not act on it (RF-073 owns localized receipts).
  final String? localeTag;
}
