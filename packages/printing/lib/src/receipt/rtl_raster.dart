import 'dart:math' as math;

import '../media_profile.dart';
import '../print_document.dart';
import '../print_line_metrics.dart';
import '../print_pagination.dart';
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
  final textLines = textDoc.lines.whereType<PrintTextLine>().toList(
    growable: false,
  );
  final lines = textLines.map((l) => l.text).toList(growable: false);
  // PRINT-RASTER-STYLE-001: carry each line's semantic style so the rasterizer
  // can render large/centered headings, an emphasised total, indented sub-lines,
  // etc. Lines with no style stay [PrintLineStyle.normal] (prior behavior).
  final styles = textLines.map((l) => l.style).toList(growable: false);
  final image = await rasterizer.rasterize(
    ReceiptRasterRequest(
      lines: lines,
      styles: styles,
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

/// A localized string for a fixed-media page (PRINT-LAYOUT-001A). [page] is
/// 1-based; [total] is the page count. Supplied by the app layer (which owns
/// l10n) so this pure package prints "Page 2 of 3" / "#A17 (cont.)" without an
/// ARB dependency.
typedef PageLineLabel = String Function(int page, int total);

/// PRINT-LAYOUT-001A: render [textDoc] for a specific [profile], honoring its
/// exact printable width, safe margins, font scale, line spacing, feed, and —
/// for a FIXED medium — fixed-height PAGINATION so nothing runs off the label.
///
///  * `continuous80` (the default roll): behaves exactly like [maybeRasterizeForRtl]
///    — ASCII-only English stays the crisp text path; non-ASCII rasterizes to ONE
///    image at 576 dots, feed 3. Byte-identical to the pre-profile output.
///  * `label50x50` / `label80x80` (fixed labels): ALWAYS rasterize (so the label
///    width + pagination apply uniformly, never a narrow bitmap on a wide canvas
///    or an unpaginated overflow), split into pages that each fit
///    `profile.printableHeightDots`, and emit one image + feed + cut PER PAGE at
///    the profile's exact width. A multi-page run adds a localized page number
///    ([pageLabel]) to every page and a compact [continuationHeader] to pages
///    2+, so a kitchen ticket stays identifiable across labels.
///
/// With no [rasterizer] the fixed-media path cannot render at the right width, so
/// it returns [textDoc] unchanged (a degraded fallback that never crashes; the
/// native bridges always inject a rasterizer).
Future<PrintDocument> rasterizeForMediaProfile(
  PrintDocument textDoc, {
  required ReceiptRasterizer? rasterizer,
  required MediaProfile profile,
  PageLineLabel? pageLabel,
  PageLineLabel? continuationHeader,
}) async {
  if (!profile.paginates) {
    // Continuous roll: identical to the existing content-triggered raster path.
    return maybeRasterizeForRtl(
      textDoc,
      rasterizer: rasterizer,
      widthDots: profile.widthDots,
      feedLines: profile.feedLines,
    );
  }
  // Fixed label: without a rasterizer we cannot honor the width — degrade safely.
  if (rasterizer == null) return textDoc;

  final textLines = textDoc.lines.whereType<PrintTextLine>().toList(
    growable: false,
  );
  final lines = textLines.map((l) => l.text).toList(growable: false);
  final styles = textLines.map((l) => l.style).toList(growable: false);
  final direction = baseDirectionForLines(lines);

  // Plan on the REAL rendered heights when the rasterizer can measure them
  // (dart:ui metrics) — an estimate could under-count and overflow the label.
  // Fall back to the conservative estimate only for a non-measuring rasterizer.
  final List<int> rows;
  if (rasterizer is RasterLineMeasurer) {
    rows = await (rasterizer as RasterLineMeasurer).measureLineRows(
      ReceiptRasterRequest(
        lines: lines,
        styles: styles,
        widthDots: profile.widthDots,
        direction: direction,
        localeTag: textDoc.localeTag ?? '',
        fontScale: profile.fontScale,
        lineSpacing: profile.lineSpacing,
        safeLeftDots: profile.safeLeftDots,
        safeRightDots: profile.safeRightDots,
      ),
    );
  } else {
    rows = estimateReceiptLineRows(
      styles,
      fontScale: profile.fontScale,
      lineSpacing: profile.lineSpacing,
    );
  }
  // A block (kept whole when it fits a page) starts at every line that is not a
  // sub/note continuation of the item above it.
  final blockStarts = <int>{
    for (var i = 0; i < styles.length; i++)
      if (styles[i] != PrintLineStyle.sub && styles[i] != PrintLineStyle.note) i,
  };
  // Reserve room for the per-page continuation header + page number: at most two
  // added lines, each no taller than the tallest content line — so a rendered
  // page (content + those two) never exceeds printableHeightDots.
  final maxRow = rows.isEmpty ? 1 : rows.reduce(math.max);
  final reserved = (pageLabel == null && continuationHeader == null)
      ? 0
      : 2 * maxRow;

  final pages = planPrintPages(
    lineHeights: rows,
    maxPageRows: profile.printableHeightDots,
    blockStartAt: blockStarts,
    reservedRowsPerPage: reserved,
  );
  final total = pages.length;

  final out = <PrintLine>[];
  for (var p = 0; p < total; p++) {
    final pageLines = <String>[];
    final pageStyles = <PrintLineStyle>[];
    // Compact continuation header on pages 2+ so the order stays identifiable.
    if (p > 0 && continuationHeader != null) {
      pageLines.add(continuationHeader(p + 1, total));
      pageStyles.add(PrintLineStyle.centered);
    }
    for (final i in pages[p].lineIndexes) {
      pageLines.add(lines[i]);
      pageStyles.add(styles[i]);
    }
    // Page number on every page of a multi-page run.
    if (total > 1 && pageLabel != null) {
      pageLines.add(pageLabel(p + 1, total));
      pageStyles.add(PrintLineStyle.centered);
    }

    final image = await rasterizer.rasterize(
      ReceiptRasterRequest(
        lines: pageLines,
        styles: pageStyles,
        widthDots: profile.widthDots,
        direction: direction,
        localeTag: textDoc.localeTag ?? '',
        fontScale: profile.fontScale,
        lineSpacing: profile.lineSpacing,
        safeLeftDots: profile.safeLeftDots,
        safeRightDots: profile.safeRightDots,
      ),
    );
    out
      ..add(image.toPrintLine())
      ..add(PrintFeedLine(profile.feedLines))
      ..add(const PrintCutLine());
  }
  return PrintDocument(out, localeTag: textDoc.localeTag);
}
