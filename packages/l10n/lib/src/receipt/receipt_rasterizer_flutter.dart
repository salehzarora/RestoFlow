import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:restoflow_printing/restoflow_printing.dart';

/// The real Flutter/`dart:ui` [ReceiptRasterizer] for Arabic/Hebrew/English
/// receipts (RF-073, approved D3/D4; PRINT-RASTER-STYLE-001 adds styled lines).
///
/// Lives in `packages/l10n` (the localization owner) because Arabic/Hebrew
/// shaping + bidi + RTL layout are localization concerns and require Flutter's
/// text engine, which the pure-Dart `packages/printing` cannot import. It shapes
/// each receipt line with `dart:ui` ([ui.ParagraphBuilder]) — PRINT-RASTER-STYLE-001:
/// one paragraph PER line, styled by its [PrintLineStyle] (font size / weight /
/// alignment; a `separator` draws a rule) — paints black-on-white to an offscreen
/// [ui.Picture], then thresholds the pixels into a 1-bit-per-pixel, MSB-first,
/// row-major bitmap that drops straight into a [PrintRasterImageLine].
///
/// It uses the Flutter/platform DEFAULT fonts (no bundled font asset, approved
/// D3) and requires NO `BuildContext` and NO ARB dependency. A request with no
/// per-line styles renders every line as [PrintLineStyle.normal] (prior behavior).
class FlutterReceiptRasterizer implements ReceiptRasterizer {
  const FlutterReceiptRasterizer({
    this.fontSize = 22.0,
    this.lineHeight = 1.3,
    this.luminanceThreshold = 128,
  });

  /// The base (normal) glyph size in logical pixels (== dots at 1:1). Styled
  /// lines scale relative to this (a heading is larger, a sub-line smaller).
  final double fontSize;

  /// Multiplier applied to a line's font size for its block height.
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

    // One laid-out block per line, styled by its PrintLineStyle. A `separator`
    // is a horizontal rule (no text). Heights accumulate top-to-bottom.
    final blocks = <_Block>[];
    var totalHeight = 0.0;
    for (var i = 0; i < request.lines.length; i++) {
      final style = i < request.styles.length
          ? request.styles[i]
          : PrintLineStyle.normal;
      if (style == PrintLineStyle.separator) {
        blocks.add(_Block.separator(_separatorHeight));
        totalHeight += _separatorHeight;
        continue;
      }
      final spec = _specFor(style);
      final paragraph = _layoutLine(
        request.lines[i],
        widthDots,
        textDirection,
        spec,
      );
      final height = math.max(spec.size * lineHeight, paragraph.height);
      blocks.add(_Block.text(paragraph, height));
      totalHeight += height;
    }
    final heightDots = math.max(1, totalHeight.ceil());

    final image = await _paint(blocks, widthDots, heightDots);
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

  double get _separatorHeight => fontSize * 0.85;

  _LineSpec _specFor(PrintLineStyle style) {
    switch (style) {
      case PrintLineStyle.headingLarge:
        return _LineSpec(
          size: fontSize * 1.55,
          weight: ui.FontWeight.w800,
          align: ui.TextAlign.center,
        );
      case PrintLineStyle.centered:
        return _LineSpec(
          size: fontSize,
          weight: ui.FontWeight.w400,
          align: ui.TextAlign.center,
        );
      case PrintLineStyle.item:
        return _LineSpec(
          size: fontSize * 1.1,
          weight: ui.FontWeight.w600,
          align: ui.TextAlign.start,
        );
      case PrintLineStyle.sub:
        return _LineSpec(
          size: fontSize * 0.9,
          weight: ui.FontWeight.w400,
          align: ui.TextAlign.start,
        );
      case PrintLineStyle.note:
        return _LineSpec(
          size: fontSize,
          weight: ui.FontWeight.w700,
          align: ui.TextAlign.start,
        );
      case PrintLineStyle.total:
        return _LineSpec(
          size: fontSize * 1.2,
          weight: ui.FontWeight.w800,
          align: ui.TextAlign.start,
        );
      case PrintLineStyle.normal:
      case PrintLineStyle.separator:
        return _LineSpec(
          size: fontSize,
          weight: ui.FontWeight.w400,
          align: ui.TextAlign.start,
        );
    }
  }

  ui.Paragraph _layoutLine(
    String text,
    int widthDots,
    ui.TextDirection textDirection,
    _LineSpec spec,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textDirection: textDirection,
              textAlign: spec.align,
              fontSize: spec.size,
              height: lineHeight,
              fontWeight: spec.weight,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: _black,
              fontSize: spec.size,
              fontWeight: spec.weight,
            ),
          )
          ..addText(text);
    return builder.build()
      ..layout(ui.ParagraphConstraints(width: widthDots.toDouble()));
  }

  Future<ui.Image> _paint(
    List<_Block> blocks,
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
    final rulePaint = ui.Paint()
      ..color = _black
      ..strokeWidth = 2.0;
    final inset = widthDots * 0.03;
    var y = 0.0;
    for (final block in blocks) {
      final paragraph = block.paragraph;
      if (paragraph != null) {
        canvas.drawParagraph(paragraph, ui.Offset(0, y));
      } else {
        final lineY = y + block.height / 2;
        canvas.drawLine(
          ui.Offset(inset, lineY),
          ui.Offset(widthDots - inset, lineY),
          rulePaint,
        );
      }
      y += block.height;
    }
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

/// The render attributes derived from a [PrintLineStyle].
class _LineSpec {
  const _LineSpec({
    required this.size,
    required this.weight,
    required this.align,
  });

  final double size;
  final ui.FontWeight weight;
  final ui.TextAlign align;
}

/// One vertical block: a laid-out text [paragraph] (a styled line) or, when
/// [paragraph] is null, a horizontal separator rule. [height] is its vertical span.
class _Block {
  _Block.text(this.paragraph, this.height);
  _Block.separator(this.height) : paragraph = null;

  final ui.Paragraph? paragraph;
  final double height;
}
