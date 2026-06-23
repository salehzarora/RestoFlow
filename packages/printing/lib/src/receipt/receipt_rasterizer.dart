import 'dart:typed_data';

import '../print_document.dart';

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
  }) : lines = List.unmodifiable(lines);

  /// Logical, already-localized receipt lines (top to bottom).
  final List<String> lines;

  /// Printable width in dots for the target paper (must be a multiple of 8).
  final int widthDots;

  /// Base text direction (RTL for Arabic/Hebrew, LTR for English).
  final ReceiptTextDirection direction;

  /// BCP-47-ish locale tag (`ar` / `he` / `en`) — metadata for the rasterizer.
  final String localeTag;
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

/// A deterministic, dependency-free [ReceiptRasterizer] for tests (RF-073).
///
/// It performs NO real shaping — it records every request (so tests can assert
/// the localized text reached the rasterizer) and returns a correctly-sized,
/// non-blank bitmap. Height is derived deterministically from the line count.
class FakeReceiptRasterizer implements ReceiptRasterizer {
  FakeReceiptRasterizer({this.dotsPerLine = 24, this.fillByte = 0x55});

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
