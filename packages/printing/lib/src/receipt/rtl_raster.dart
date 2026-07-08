import '../print_document.dart';
import 'receipt_rasterizer.dart';

/// PRINT-RTL-001: turn an already-laid-out ESC/POS TEXT [PrintDocument] into a
/// single monochrome RASTER-image document so Arabic/Hebrew (and non-ASCII
/// symbols like the shekel sign or the "×N" multiplier) print correctly on
/// thermal printers that have no reliable Unicode/RTL codepage.
///
/// The receipt/ticket layout logic is UNCHANGED: this reuses the exact
/// pre-formatted [PrintTextLine.text] lines the existing text converters already
/// produce (two-column spacing, dashes, indentation), so money/tax content is
/// only MOVED into the bitmap — never recomputed or reformatted. The heavy
/// dart:ui shaping lives behind the [ReceiptRasterizer] port (real impl in
/// restoflow_l10n); this file stays pure Dart.

/// The default 80mm printable raster width in dots (multiple of 8). 58mm = 384.
const int kNativeRasterWidthDots = 576;

/// True when [doc] carries any non-ASCII text (Arabic/Hebrew letters, ₪, ×, …)
/// that ESC/POS TEXT mode cannot reliably print — the signal to switch to
/// raster. A document that is already a raster image (no text lines) returns
/// false, so it is never double-rastered.
bool printDocumentNeedsRaster(PrintDocument doc) => doc.lines
    .whereType<PrintTextLine>()
    .any((l) => l.text.codeUnits.any((c) => c > 0x7f));

/// Whether [r] is an Arabic or Hebrew letter (used to pick the base direction).
bool _isRtlLetter(int r) =>
    (r >= 0x0590 && r <= 0x05ff) || // Hebrew
    (r >= 0x0600 && r <= 0x06ff) || // Arabic
    (r >= 0x0750 && r <= 0x077f) || // Arabic Supplement
    (r >= 0x08a0 && r <= 0x08ff) || // Arabic Extended-A
    (r >= 0xfb1d && r <= 0xfb4f) || // Hebrew presentation forms
    (r >= 0xfb50 && r <= 0xfdff) || // Arabic presentation forms-A
    (r >= 0xfe70 && r <= 0xfeff); // Arabic presentation forms-B

/// The base paragraph direction for [lines], by DOMINANT strong-directional
/// script: RTL when Arabic/Hebrew letters outnumber Latin letters (an ar/he
/// receipt), else LTR (an English receipt, even one carrying a single Arabic
/// customer name — dart:ui still shapes that run RTL within the LTR paragraph).
ReceiptTextDirection baseDirectionForLines(Iterable<String> lines) {
  var rtl = 0;
  var ltr = 0;
  for (final line in lines) {
    for (final r in line.runes) {
      if (_isRtlLetter(r)) {
        rtl++;
      } else if ((r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a)) {
        ltr++;
      }
    }
  }
  return rtl > ltr ? ReceiptTextDirection.rtl : ReceiptTextDirection.ltr;
}

/// Renders [textDoc]'s pre-formatted text lines into ONE [PrintRasterImageLine]
/// via [rasterizer], returning a raster [PrintDocument] (image + feed + cut).
/// [widthDots] must be a multiple of 8 (576 for 80mm, 384 for 58mm). When
/// [direction] is omitted it is derived from the content.
Future<PrintDocument> rasterizeTextDocument(
  PrintDocument textDoc, {
  required ReceiptRasterizer rasterizer,
  int widthDots = kNativeRasterWidthDots,
  ReceiptTextDirection? direction,
  int feedLines = 3,
}) async {
  final lines = textDoc.lines
      .whereType<PrintTextLine>()
      .map((l) => l.text)
      .toList(growable: false);
  final image = await rasterizer.rasterize(
    ReceiptRasterRequest(
      lines: lines,
      widthDots: widthDots,
      direction: direction ?? baseDirectionForLines(lines),
      localeTag: textDoc.localeTag ?? '',
    ),
  );
  return PrintDocument([
    image.toPrintLine(),
    PrintFeedLine(feedLines),
    const PrintCutLine(),
  ], localeTag: textDoc.localeTag);
}

/// If [rasterizer] is provided AND [textDoc] contains content ESC/POS text mode
/// cannot reliably print, returns the raster version of [textDoc]; otherwise
/// returns [textDoc] unchanged (English-only ASCII keeps the fast, crisp text
/// path). This is the single decision point the native print bridges call.
Future<PrintDocument> maybeRasterizeForRtl(
  PrintDocument textDoc, {
  required ReceiptRasterizer? rasterizer,
  int widthDots = kNativeRasterWidthDots,
  int feedLines = 3,
}) async {
  if (rasterizer == null || !printDocumentNeedsRaster(textDoc)) return textDoc;
  return rasterizeTextDocument(
    textDoc,
    rasterizer: rasterizer,
    widthDots: widthDots,
    feedLines: feedLines,
  );
}
