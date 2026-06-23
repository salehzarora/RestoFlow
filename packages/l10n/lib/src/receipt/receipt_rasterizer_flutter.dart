import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:restoflow_printing/restoflow_printing.dart';

/// The real Flutter/`dart:ui` [ReceiptRasterizer] for Arabic/Hebrew/English
/// receipts (RF-073, approved D3/D4).
///
/// Lives in `packages/l10n` (the localization owner) because Arabic/Hebrew
/// shaping + bidi + RTL layout are localization concerns and require Flutter's
/// text engine, which the pure-Dart `packages/printing` cannot import. It shapes
/// the localized receipt lines with `dart:ui` ([ui.ParagraphBuilder]), paints
/// black-on-white to an offscreen [ui.Picture], then thresholds the pixels into
/// a 1-bit-per-pixel, MSB-first, row-major bitmap that drops straight into a
/// [PrintRasterImageLine].
///
/// It uses the Flutter/platform DEFAULT fonts (no bundled font asset, approved
/// D3) and requires NO `BuildContext` and NO ARB dependency.
class FlutterReceiptRasterizer implements ReceiptRasterizer {
  const FlutterReceiptRasterizer({
    this.fontSize = 22.0,
    this.lineHeight = 1.3,
    this.luminanceThreshold = 128,
  });

  /// Glyph size in logical pixels (== dots at 1:1).
  final double fontSize;

  /// Multiplier applied to [fontSize] for inter-line spacing.
  final double lineHeight;

  /// A pixel is treated as a black dot when opaque and below this luminance.
  final int luminanceThreshold;

  static const ui.Color _black = ui.Color(0xFF000000);
  static const ui.Color _white = ui.Color(0xFFFFFFFF);

  @override
  Future<ReceiptRasterImage> rasterize(ReceiptRasterRequest request) async {
    final widthDots = request.widthDots;
    final textDirection = request.direction == ReceiptTextDirection.rtl
        ? ui.TextDirection.rtl
        : ui.TextDirection.ltr;

    final paragraph = _layoutParagraph(
      text: request.lines.join('\n'),
      widthDots: widthDots,
      textDirection: textDirection,
    );
    final heightDots = math.max(1, paragraph.height.ceil());

    final image = await _paint(paragraph, widthDots, heightDots);
    try {
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw StateError('failed to read rasterized receipt pixels');
      }
      return _threshold(byteData.buffer.asUint8List(), widthDots, heightDots);
    } finally {
      image.dispose();
    }
  }

  ui.Paragraph _layoutParagraph({
    required String text,
    required int widthDots,
    required ui.TextDirection textDirection,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textDirection: textDirection,
              textAlign: ui.TextAlign.start,
              fontSize: fontSize,
              height: lineHeight,
            ),
          )
          ..pushStyle(ui.TextStyle(color: _black, fontSize: fontSize))
          ..addText(text);
    return builder.build()
      ..layout(ui.ParagraphConstraints(width: widthDots.toDouble()));
  }

  Future<ui.Image> _paint(
    ui.Paragraph paragraph,
    int widthDots,
    int heightDots,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
      ui.Paint()..color = _white,
    );
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(widthDots, heightDots);
    } finally {
      picture.dispose();
    }
  }

  /// Pack RGBA pixels into a 1bpp, MSB-first, row-major bitmap (bit 1 == black).
  ReceiptRasterImage _threshold(Uint8List rgba, int widthDots, int heightDots) {
    final widthBytes = (widthDots + 7) ~/ 8;
    final out = Uint8List(widthBytes * heightDots);
    for (var y = 0; y < heightDots; y++) {
      final rowBase = y * widthBytes;
      for (var x = 0; x < widthDots; x++) {
        final i = (y * widthDots + x) * 4;
        final alpha = rgba[i + 3];
        // Luminance of the pixel composited over the white background.
        final lum = (rgba[i] * 30 + rgba[i + 1] * 59 + rgba[i + 2] * 11) ~/ 100;
        if (alpha > 127 && lum < luminanceThreshold) {
          out[rowBase + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    return ReceiptRasterImage(
      data: out,
      widthBytes: widthBytes,
      heightDots: heightDots,
    );
  }
}
