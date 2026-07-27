import 'dart:typed_data';

import '../print_document.dart';
import '../print_typography.dart';

/// Text direction for a rasterized receipt block (RF-073).
enum ReceiptTextDirection { ltr, rtl }

/// A request to rasterize a localized receipt into a monochrome bitmap (RF-073).
///
/// The [lines] are already localized + laid out logically by the builder; the
/// rasterizer only shapes/bidis/paints them. [widthDots] is the printable raster
/// width for the target paper (e.g. 384 for 58mm, 576 for 80mm).
class ReceiptRasterRequest {
  ReceiptRasterRequest({
    required List<String> lines,
    required this.widthDots,
    required this.direction,
    required this.localeTag,
    List<PrintLineStyle>? styles,
    this.fontScale = 1.0,
    this.lineSpacing,
    this.safeLeftDots = 0,
    this.safeRightDots = 0,
    this.typography = PrintTypography.standard,
  }) : assert(
         styles == null || styles.length == lines.length,
         'styles must be parallel to lines',
       ),
       assert(fontScale > 0),
       assert(lineSpacing == null || lineSpacing > 0),
       assert(safeLeftDots >= 0 && safeRightDots >= 0),
       assert(safeLeftDots + safeRightDots < widthDots),
       lines = List.unmodifiable(lines),
       styles = List.unmodifiable(
         styles ??
             List<PrintLineStyle>.filled(lines.length, PrintLineStyle.normal),
       );

  /// Logical, already-localized receipt lines (top to bottom).
  final List<String> lines;

  /// PRINT-RASTER-STYLE-001: per-line semantic style, PARALLEL to [lines]
  /// (styles[i] applies to lines[i]). Defaults to [PrintLineStyle.normal] for
  /// every line when omitted, so existing callers are unchanged and the renderer
  /// keeps its prior uniform behavior.
  final List<PrintLineStyle> styles;

  /// Printable width in dots for the target paper (must be a multiple of 8).
  final int widthDots;

  /// Base text direction (RTL for Arabic/Hebrew, LTR for English).
  final ReceiptTextDirection direction;

  /// BCP-47-ish locale tag (`ar` / `he` / `en`) — metadata for the rasterizer.
  final String localeTag;

  /// PRINT-LAYOUT-001A: multiplier applied to every line's font size (a media
  /// profile scales type up on an 80×80 label). Default `1.0` == prior output.
  final double fontScale;

  /// PRINT-LAYOUT-001A: line-height multiplier override (from the media profile);
  /// null keeps the rasterizer's built-in line height (prior behavior).
  final double? lineSpacing;

  /// PRINT-LAYOUT-001A: safe left/right print margins in dots. Content is laid
  /// out + painted inside `[safeLeftDots, widthDots - safeRightDots]`; the
  /// emitted bitmap stays [widthDots] wide. Default `0` == full-width (prior).
  final int safeLeftDots;
  final int safeRightDots;

  /// PRINT-LAYOUT-001B: the per-role typography tokens (size multiplier + weight
  /// + alignment) the renderer applies to each line's [PrintLineStyle]. Defaults
  /// to [PrintTypography.standard]; the fixed-media path passes the profile-aware
  /// config so the small 50×50 label uses the gentler compact hierarchy.
  final PrintTypography typography;
}

/// A rasterized monochrome bitmap ready to become a [PrintRasterImageLine].
///
/// [data] is row-major, 1-bit-per-pixel, MSB-first (the exact layout
/// [PrintRasterImageLine] requires). [widthBytes] is bytes per row
/// (`widthDots / 8`); [heightDots] is the rendered height.
class ReceiptRasterImage {
  ReceiptRasterImage({
    required this.data,
    required this.widthBytes,
    required this.heightDots,
  }) : assert(widthBytes > 0),
       assert(heightDots > 0),
       assert(
         data.length == widthBytes * heightDots,
         'raster data length must equal widthBytes * heightDots',
       );

  final Uint8List data;
  final int widthBytes;
  final int heightDots;

  /// Convert to the RF-070 print line (same 1bpp row-major contract).
  PrintRasterImageLine toPrintLine() => PrintRasterImageLine(
    data: data,
    widthBytes: widthBytes,
    heightDots: heightDots,
  );
}

/// PORT: turns a localized receipt ([ReceiptRasterRequest]) into a 1bpp bitmap
/// (RF-073). The real Flutter/`dart:ui` shaping+bidi implementation lives in
/// `packages/l10n`; `packages/printing` stays pure-Dart and ships only this
/// port + a deterministic fake. This is the seam that lets Arabic/Hebrew print
/// correctly without routing them through the ASCII-only ESC/POS text path.
abstract interface class ReceiptRasterizer {
  Future<ReceiptRasterImage> rasterize(ReceiptRasterRequest request);
}

/// PRINT-LAYOUT-001A: an OPTIONAL capability a [ReceiptRasterizer] may also
/// implement — the EXACT rendered ROW height (in dots) each line will occupy,
/// without painting. Fixed-media pagination uses this so a page is planned on
/// the real dart:ui heights (never a font-independent estimate that could
/// under-count and overflow the label). A rasterizer that does not implement it
/// falls back to a conservative estimate.
abstract interface class RasterLineMeasurer {
  /// The per-line rendered row height for [request] (parallel to `request.lines`).
  Future<List<int>> measureLineRows(ReceiptRasterRequest request);
}

/// A deterministic, dependency-free [ReceiptRasterizer] for tests (RF-073).
///
/// It performs NO real shaping — it records every request (so tests can assert
/// the localized text reached the rasterizer) and returns a correctly-sized,
/// non-blank bitmap. Height is derived deterministically from the line count.
class FakeReceiptRasterizer implements ReceiptRasterizer, RasterLineMeasurer {
  FakeReceiptRasterizer({this.dotsPerLine = 24, this.fillByte = 0x55});

  @override
  Future<List<int>> measureLineRows(ReceiptRasterRequest request) async => [
    for (var i = 0; i < request.lines.length; i++) dotsPerLine,
  ];

  /// Recorded requests, in call order (for test assertions).
  final List<ReceiptRasterRequest> requests = <ReceiptRasterRequest>[];

  /// Synthetic line height in dots.
  final int dotsPerLine;

  /// Non-zero fill so the bitmap is never "all white" (bit 1 == black dot).
  final int fillByte;

  @override
  Future<ReceiptRasterImage> rasterize(ReceiptRasterRequest request) async {
    requests.add(request);
    final widthBytes = (request.widthDots + 7) ~/ 8;
    final lineCount = request.lines.isEmpty ? 1 : request.lines.length;
    final heightDots = lineCount * dotsPerLine;
    final data = Uint8List(widthBytes * heightDots)
      ..fillRange(0, widthBytes * heightDots, fillByte);
    return ReceiptRasterImage(
      data: data,
      widthBytes: widthBytes,
      heightDots: heightDots,
    );
  }
}
