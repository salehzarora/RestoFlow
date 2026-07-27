import 'dart:math' as math;
import 'dart:typed_data';

import '../media_profile.dart';
import '../print_document.dart';
import '../print_line_metrics.dart';
import '../print_pagination.dart';
import '../print_typography.dart';
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

/// A money row on a receipt — a plain key/value line ([PrintLineStyle.normal])
/// or the emphasised [PrintLineStyle.total]. Used only to keep an unbroken run
/// of money rows (the totals block) together across a fixed-label page break.
bool _isMoneyRow(PrintLineStyle style) =>
    style == PrintLineStyle.normal || style == PrintLineStyle.total;

/// PRINT-LAYOUT-001C: one blank, ink-free text line appended BELOW the last
/// visible content so the final footer/item never sits against the physical
/// cutter. It is rendered into the SAME raster image (before the feed + cut), so
/// the printed page carries ~one line of blank paper as a bottom-safe tail. It
/// is [PrintLineStyle.normal] height (a full text line, not the smaller spacer)
/// and carries no text, so it expects no ink and never triggers zero-ink recovery.
const PrintTextLine _bottomSafeTailLine = PrintTextLine(
  '',
  style: PrintLineStyle.normal,
);

/// The rendered ROW height (dots) of the bottom-safe tail for [profile] — one
/// normal text line at the profile's font scale + line spacing. Fixed-label
/// pagination reserves this so a page (content + tail) never exceeds the media
/// height; content that would encroach moves to the next page instead of clipping.
int bottomSafeTailRows(MediaProfile profile) {
  final typography = PrintTypography.forProfile(profile);
  final size =
      typography.baseFontSize *
      typography.sizeMultiplier(PrintLineStyle.normal) *
      profile.fontScale;
  return math.max(1, (size * profile.lineSpacing).ceil());
}

/// True when [doc] carries any non-ASCII text (Arabic/Hebrew letters, ₪, ×, …)
/// that ESC/POS TEXT mode cannot reliably print — the signal to switch to
/// raster. A document that is already a raster image (no text lines) returns
/// false, so it is never double-rastered.
bool printDocumentNeedsRaster(PrintDocument doc) => doc.lines
    .whereType<PrintTextLine>()
    .any((l) => l.text.codeUnits.any((c) => c > 0x7f));

/// PRINT-BRANDING-LOGO-001: the leading lines a caller placed BEFORE the first
/// text line — a customer-receipt logo raster + its feed. Text rasterization
/// keeps only [PrintTextLine]s, so without preserving this preamble the logo
/// would vanish whenever a receipt rasterizes (ar/he — Arabic is the default
/// locale — and every fixed-media label). Returns the leading non-text run only
/// (the trailing feed/cut are re-emitted by the raster paths).
List<PrintLine> leadingPreambleLines(PrintDocument doc) {
  final preamble = <PrintLine>[];
  for (final line in doc.lines) {
    if (line is PrintTextLine) break;
    preamble.add(line);
  }
  return preamble;
}

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
  // PRINT-RASTER-STYLE-001: carry each line's semantic style so the rasterizer
  // can render large/centered headings, an emphasised total, indented sub-lines,
  // etc. Lines with no style stay [PrintLineStyle.normal] (prior behavior).
  // PRINT-LAYOUT-001C: append the bottom-safe tail (one blank line) BELOW the
  // content so the last visible line clears the physical cutter — it becomes
  // blank raster rows in this single image, before the feed + cut.
  final lines = <String>[
    for (final l in textLines) l.text,
    _bottomSafeTailLine.text,
  ];
  final styles = <PrintLineStyle>[
    for (final l in textLines) l.style,
    _bottomSafeTailLine.style,
  ];
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
    // PRINT-BRANDING-LOGO-001: keep the leading logo raster (+ its feed) above
    // the rasterized text so it still prints on ar/he receipts.
    ...leadingPreambleLines(textDoc),
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

  // PRINT-LAYOUT-001B: the profile-aware type hierarchy (compact on the small
  // 50×50 label, standard elsewhere). Threaded into BOTH the height measurement
  // and every page render so the planned page heights match what is painted.
  final typography = PrintTypography.forProfile(profile);
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
        typography: typography,
      ),
    );
  } else {
    rows = estimateReceiptLineRows(
      styles,
      fontScale: profile.fontScale,
      lineSpacing: profile.lineSpacing,
      typography: typography,
    );
  }
  // A block (kept whole when it fits a page) starts at every line that is not a
  // sub/note continuation of the item above it — AND not a money row that
  // continues an unbroken run of money rows, so the totals block (subtotal …
  // total … change) stays together on one page instead of splitting at a page
  // boundary (PRINT-LAYOUT-001B).
  final blockStarts = <int>{
    for (var i = 0; i < styles.length; i++)
      if (styles[i] != PrintLineStyle.sub &&
          styles[i] != PrintLineStyle.note &&
          !(_isMoneyRow(styles[i]) && i > 0 && _isMoneyRow(styles[i - 1])))
        i,
  };
  // Reserve room for the per-page continuation header + page number: at most two
  // added lines, each no taller than the tallest content line — so a rendered
  // page (content + those two) never exceeds printableHeightDots.
  final maxRow = rows.isEmpty ? 1 : rows.reduce(math.max);
  final reserved = (pageLabel == null && continuationHeader == null)
      ? 0
      : 2 * maxRow;

  // PRINT-LAYOUT-001C: reserve one blank text line at the BOTTOM of every page
  // (the bottom-safe tail) so the last visible line clears the cutter. Because
  // the tail is subtracted from the page budget, content that would reach the
  // bottom moves to the next page instead of being clipped.
  final tailRows = bottomSafeTailRows(profile);
  final pageBudget = math.max(1, profile.printableHeightDots - tailRows);

  // PRINT-BRANDING-LOGO-001: the logo is COMPOSED into the SAME first physical
  // page as the receipt title/text — never a dedicated logo label. Its height
  // (image + a bounded gap) is reserved on page one via a synthetic leading
  // block, so pagination flows the title + as much content as fits after it; the
  // logo raster is then stacked ON TOP of page one's text raster into one image.
  final logoLine = _firstRasterImage(leadingPreambleLines(textDoc));
  final gapDots = logoLine != null ? _fixedLogoGapDots(profile) : 0;

  // Tentatively compose the logo (a synthetic leading block, index 0) ahead of
  // the title block (index 1). The logo may only STAY if the planner actually
  // places the logo AND the title together on page one. Testing this against the
  // planner's OWN effective budget — not a looser guard — is essential: on a
  // multi-page ticket the planner packs each page against `pageBudget - reserved`
  // (it holds back rows for the per-page number/continuation line), so a tall
  // logo that fits `pageBudget` alone can still shove the title onto page two,
  // leaving the logo on a near-dedicated page. When that happens we OMIT the logo
  // (text-only) and re-plan without it — never crop it, never give it its own
  // label or page. A no-logo document skips all of this and plans identically to
  // the pre-branding output (byte-for-byte).
  var composeLogo = logoLine != null && rows.isNotEmpty;
  var offset = composeLogo ? 1 : 0;

  List<PrintPagePlan> planTextOnly() => planPrintPages(
    lineHeights: rows,
    maxPageRows: pageBudget,
    blockStartAt: blockStarts,
    reservedRowsPerPage: reserved,
  );

  List<PrintPagePlan> pages;
  if (composeLogo) {
    pages = planPrintPages(
      lineHeights: <int>[logoLine.heightDots + gapDots, ...rows],
      maxPageRows: pageBudget,
      blockStartAt: <int>{0, for (final b in blockStarts) b + 1},
      reservedRowsPerPage: reserved,
    );
    final firstPage = pages.first.lineIndexes;
    if (!(firstPage.contains(0) && firstPage.contains(1))) {
      // The logo landed alone (or the title got bumped) — omit and re-plan.
      composeLogo = false;
      offset = 0;
      pages = planTextOnly();
    }
  } else {
    pages = planTextOnly();
  }
  final total = pages.length;

  final out = <PrintLine>[];
  for (var p = 0; p < total; p++) {
    final pageLines = <String>[];
    final pageStyles = <PrintLineStyle>[];
    var pageCarriesLogo = false;
    // Compact continuation header on pages 2+ so the order stays identifiable.
    if (p > 0 && continuationHeader != null) {
      pageLines.add(continuationHeader(p + 1, total));
      pageStyles.add(PrintLineStyle.centered);
    }
    for (final planIndex in pages[p].lineIndexes) {
      if (composeLogo && planIndex == 0) {
        // The synthetic logo block reserves page-one height; the real logo
        // raster is stacked in AFTER the text is rasterized (below).
        pageCarriesLogo = true;
        continue;
      }
      final i = planIndex - offset;
      pageLines.add(lines[i]);
      pageStyles.add(styles[i]);
    }
    // Page number on every page of a multi-page run.
    if (total > 1 && pageLabel != null) {
      pageLines.add(pageLabel(p + 1, total));
      pageStyles.add(PrintLineStyle.centered);
    }
    // PRINT-LAYOUT-001C: the bottom-safe tail closes every page BELOW its
    // content + page number (its height was reserved from the page budget), so
    // the final line never touches the cut.
    pageLines.add(_bottomSafeTailLine.text);
    pageStyles.add(_bottomSafeTailLine.style);

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
        typography: typography,
      ),
    );
    // ONE image, ONE feed, ONE cut per physical page — the logo (page one only)
    // is stacked into that single page image, never emitted as its own label.
    final pageImage = pageCarriesLogo
        ? _stackLogoOnPage(logoLine!, gapDots, image)
        : image.toPrintLine();
    out
      ..add(pageImage)
      ..add(PrintFeedLine(profile.feedLines))
      ..add(const PrintCutLine());
  }
  return PrintDocument(out, localeTag: textDoc.localeTag);
}

/// The first raster-image line in [lines] (a composed logo preamble), or null.
PrintRasterImageLine? _firstRasterImage(List<PrintLine> lines) {
  for (final line in lines) {
    if (line is PrintRasterImageLine) return line;
  }
  return null;
}

/// A bounded blank gap (dots) between the logo and the title on a fixed label —
/// about half a normal text line, so the logo reads as a header without a large
/// void or an extra page.
int _fixedLogoGapDots(MediaProfile profile) =>
    math.max(6, bottomSafeTailRows(profile) ~/ 2);

/// Stack the [logo] raster ON TOP of [page]'s text raster (with a [gapDots]
/// blank white band between) into ONE 1bpp image, so the logo shares the first
/// physical page with the receipt. Both are 1bpp at the same width; a width
/// mismatch (defensive) drops the logo rather than emitting a corrupt image.
PrintLine _stackLogoOnPage(
  PrintRasterImageLine logo,
  int gapDots,
  ReceiptRasterImage page,
) {
  if (logo.widthBytes != page.widthBytes) return page.toPrintLine();
  final gapLen = page.widthBytes * gapDots;
  final data = Uint8List(logo.data.length + gapLen + page.data.length);
  data.setRange(0, logo.data.length, logo.data);
  // the gap band stays zero (white).
  data.setRange(logo.data.length + gapLen, data.length, page.data);
  return PrintRasterImageLine(
    data: data,
    widthBytes: page.widthBytes,
    heightDots: logo.heightDots + gapDots + page.heightDots,
  );
}
