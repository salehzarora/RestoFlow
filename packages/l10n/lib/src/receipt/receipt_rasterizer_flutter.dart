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
/// It bundles NO font asset (approved D3) and requires NO `BuildContext` and
/// NO ARB dependency. A request with no per-line styles renders every line as
/// [PrintLineStyle.normal] (prior behavior).
///
/// PILOT-PRINT-FIDELITY-001 hardening — a physical receipt printed its
/// header/totals but a HEIGHT-RESERVING BLANK band where the item/modifier
/// body belonged (each line is an isolated paragraph whose block height is
/// reserved whether or not any glyph painted). Three defenses:
///  * every paragraph names an EXPLICIT font family plus a fallback list of
///    platform families that cover Arabic/Hebrew/Latin (the design-system
///    named-fallback pattern) instead of relying on the ambiguous platform
///    default lookup for isolated styled paragraphs;
///  * only CONCRETE, universally-shipped weights are used (w400/w700 — never
///    synthetic w600/w800 axes);
///  * after thresholding, any line whose text is renderable yet produced ZERO
///    ink triggers ONE safe re-render pass where those lines drop to the base
///    spec that body-adjacent lines demonstrably print with — a valid line is
///    never silently reserved as blank height.
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

  /// Explicit primary family: the Android system default, resolved by NAME so
  /// isolated paragraphs never depend on the engine's anonymous default
  /// lookup. Harmless where absent — the fallbacks below take over.
  static const String _fontFamily = 'Roboto';

  /// Named, repository-safe fallback families (no bundled asset): Android's
  /// Noto Arabic/Hebrew system fonts first, then the desktop/web families the
  /// design system already relies on for ar/he.
  static const List<String> _fontFallbacks = <String>[
    'Noto Naskh Arabic UI',
    'Noto Naskh Arabic',
    'Noto Sans Arabic',
    'Noto Sans Hebrew',
    'Segoe UI',
    'Tahoma',
    'Arial',
    'sans-serif',
  ];

  @override
  Future<ReceiptRasterImage> rasterize(ReceiptRasterRequest request) async =>
      (await rasterizeDetailed(request)).image;

  /// [rasterize] plus per-line VISIBILITY: which vertical rows of the final
  /// bitmap each logical line occupies ([ReceiptRasterBand]). The image is the
  /// production output — bands are derived from the same block heights that
  /// position the paint, so tests/diagnostics can assert ink per line without
  /// changing what a printer receives.
  Future<ReceiptRasterRender> rasterizeDetailed(
    ReceiptRasterRequest request,
  ) async {
    final first = await _renderPass(request, const {});
    // INK GUARANTEE: a line whose text is renderable must not come out as
    // reserved-but-blank height. If any did, re-render ONCE with those lines
    // dropped to the base spec (the size/weight the plain body demonstrably
    // prints with); the retry is observable via [ReceiptRasterRender
    // .retriedLineIndexes] so tests and diagnostics can see it happened.
    final blank = <int>{
      for (final band in first.bands)
        if (!band.isSeparator &&
            band.text.trim().isNotEmpty &&
            first.inkInBand(band) == 0)
          band.index,
    };
    if (blank.isEmpty) return first;
    return _renderPass(request, blank);
  }

  Future<ReceiptRasterRender> _renderPass(
    ReceiptRasterRequest request,
    Set<int> safeRespecLines,
  ) async {
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
      final styleSpec = _specFor(style);
      // A retried line keeps its alignment but takes the BASE size/weight —
      // the exact configuration the plain body lines print with.
      final spec = safeRespecLines.contains(i)
          ? _LineSpec(
              size: fontSize,
              weight: ui.FontWeight.w400,
              align: styleSpec.align,
            )
          : styleSpec;
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

    final image = await _render(blocks, widthDots, heightDots);
    return ReceiptRasterRender(
      image: image,
      bands: _bandsFor(request, blocks, heightDots),
      retriedLineIndexes: Set.unmodifiable(safeRespecLines),
    );
  }

  Future<ReceiptRasterImage> _render(
    List<_Block> blocks,
    int widthDots,
    int heightDots,
  ) async {
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

  List<ReceiptRasterBand> _bandsFor(
    ReceiptRasterRequest request,
    List<_Block> blocks,
    int heightDots,
  ) {
    final bands = <ReceiptRasterBand>[];
    var y = 0.0;
    for (var i = 0; i < blocks.length; i++) {
      final style = i < request.styles.length
          ? request.styles[i]
          : PrintLineStyle.normal;
      final startRow = y.floor().clamp(0, heightDots);
      y += blocks[i].height;
      final endRow = y.ceil().clamp(0, heightDots);
      bands.add(
        ReceiptRasterBand(
          index: i,
          text: request.lines[i],
          style: style,
          startRow: startRow,
          endRow: endRow,
        ),
      );
    }
    return bands;
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

  /// Semantic weights collapse to the two CONCRETE axes every platform ships
  /// (w400/w700) — synthetic w600/w800 lookups are never requested.
  static ui.FontWeight _concreteWeight(ui.FontWeight weight) =>
      weight.value >= ui.FontWeight.w600.value
      ? ui.FontWeight.w700
      : ui.FontWeight.w400;

  ui.Paragraph _layoutLine(
    String text,
    int widthDots,
    ui.TextDirection textDirection,
    _LineSpec spec,
  ) {
    final weight = _concreteWeight(spec.weight);
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textDirection: textDirection,
              textAlign: spec.align,
              fontFamily: _fontFamily,
              fontSize: spec.size,
              height: lineHeight,
              fontWeight: weight,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: _black,
              fontFamily: _fontFamily,
              fontFamilyFallback: _fontFallbacks,
              fontSize: spec.size,
              fontWeight: weight,
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

/// One logical receipt line's vertical placement inside the final bitmap
/// (PILOT-PRINT-FIDELITY-001). Pure metadata for tests/diagnostics — the
/// printed bytes are unchanged. Rows are half-open: `[startRow, endRow)`.
class ReceiptRasterBand {
  const ReceiptRasterBand({
    required this.index,
    required this.text,
    required this.style,
    required this.startRow,
    required this.endRow,
  });

  /// Position of the line in the request (parallel to `request.lines`).
  final int index;

  /// The logical line text this band renders.
  final String text;

  /// The semantic style the band was rendered with.
  final PrintLineStyle style;

  /// First bitmap row (inclusive) of this line's block.
  final int startRow;

  /// One past the last bitmap row of this line's block.
  final int endRow;

  bool get isSeparator => style == PrintLineStyle.separator;

  /// Whether the line carries visible content a printed receipt must show
  /// (non-empty after trimming; separators draw their own rule).
  bool get expectsInk => isSeparator || text.trim().isNotEmpty;
}

/// The detailed result of [FlutterReceiptRasterizer.rasterizeDetailed]: the
/// production bitmap plus the per-line bands that compose it.
class ReceiptRasterRender {
  const ReceiptRasterRender({
    required this.image,
    required this.bands,
    this.retriedLineIndexes = const {},
  });

  final ReceiptRasterImage image;
  final List<ReceiptRasterBand> bands;

  /// Line indexes that came out BLANK on the first pass (despite renderable
  /// text) and were re-rendered with the base spec — empty in the normal
  /// single-pass case.
  final Set<int> retriedLineIndexes;

  /// Black-dot count within [band]'s rows (whole-width scan of the 1bpp data).
  int inkInBand(ReceiptRasterBand band) {
    var count = 0;
    for (var row = band.startRow; row < band.endRow; row++) {
      final base = row * image.widthBytes;
      for (var b = 0; b < image.widthBytes; b++) {
        var byte = image.data[base + b];
        while (byte != 0) {
          count += byte & 1;
          byte >>= 1;
        }
      }
    }
    return count;
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
