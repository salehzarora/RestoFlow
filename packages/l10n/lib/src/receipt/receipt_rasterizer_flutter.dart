import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// body belonged. Defenses:
///  * every paragraph names an EXPLICIT font family plus a fallback list of
///    platform families that cover Arabic/Hebrew/Latin (the design-system
///    named-fallback pattern) instead of relying on the ambiguous platform
///    default lookup for isolated styled paragraphs;
///  * only CONCRETE, universally-shipped weights are used (w400/w700 — never
///    synthetic w600/w800 axes);
///  * EXACT band ownership: every line owns an integer, half-open, exactly
///    tiling row range `[startRow, endRow)` — adjacent bands share a boundary
///    (`next.startRow == previous.endRow`), painting is CLIPPED to the owned
///    band so glyph overflow can never leak into a neighbour's rows, and the
///    band is sized up front for BOTH the styled and the fallback render;
///  * ZERO-INK RECOVERY: a line with visible printable content that produced
///    no ink on the first pass gets ONE fallback render attempt at the base
///    spec, inside the SAME owned band (no reflow, no height change). This is
///    a best-effort recovery, NOT an absolute glyph guarantee — a device font
///    that cannot draw the text on either pass still yields a blank band, and
///    real hardware remains the final glyph-fidelity arbiter. The attempt is
///    observable via [ReceiptRasterRender.retriedLineIndexes].
class FlutterReceiptRasterizer implements ReceiptRasterizer {
  const FlutterReceiptRasterizer({
    this.fontSize = 22.0,
    this.lineHeight = 1.3,
    this.luminanceThreshold = 128,
    this.debugBlankFirstPassLineIndexes = const {},
    this.debugBlankEveryPassLineIndexes = const {},
  });

  /// The base (normal) glyph size in logical pixels (== dots at 1:1). Styled
  /// lines scale relative to this (a heading is larger, a sub-line smaller).
  final double fontSize;

  /// Multiplier applied to a line's font size for its block height.
  final double lineHeight;

  /// A pixel is treated as a black dot when opaque and below this luminance.
  final int luminanceThreshold;

  /// TEST-ONLY seam: line indexes whose FIRST paint pass is skipped, so tests
  /// can force a genuinely visible line to come out blank once (the Android
  /// font failure is not reproducible under the CI test font). Empty in
  /// production — when unused the output is untouched.
  @visibleForTesting
  final Set<int> debugBlankFirstPassLineIndexes;

  /// TEST-ONLY seam: line indexes never painted on ANY pass (models a device
  /// font that cannot draw the text at all). Empty in production.
  @visibleForTesting
  final Set<int> debugBlankEveryPassLineIndexes;

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

  /// [rasterize] plus per-line VISIBILITY: the exact, non-overlapping row
  /// range each logical line owns in the final bitmap ([ReceiptRasterBand]).
  /// The image is the production output — bands are the same integer ranges
  /// that position and clip the paint, so a per-band ink scan can never be
  /// satisfied by a neighbouring line's pixels.
  Future<ReceiptRasterRender> rasterizeDetailed(
    ReceiptRasterRequest request,
  ) async {
    final layouts = _layoutBands(request);
    final bands = [for (final l in layouts) l.band];
    final heightDots = layouts.isEmpty ? 1 : layouts.last.band.endRow;

    var image = await _render(layouts, request.widthDots, heightDots, pass: 0);
    var render = ReceiptRasterRender(image: image, bands: bands);

    // ZERO-INK RECOVERY (one fallback attempt, not a glyph guarantee): only
    // lines with actual VISIBLE printable content are eligible — separators
    // draw their own rule and invisible-only lines legitimately stay blank.
    final blank = <int>{
      for (final band in bands)
        if (!band.isSeparator &&
            hasVisibleReceiptText(band.text) &&
            render.inkInBand(band) == 0)
          band.index,
    };
    if (blank.isEmpty) return render;

    for (final l in layouts) {
      if (blank.contains(l.band.index)) l.useFallback = true;
    }
    image = await _render(layouts, request.widthDots, heightDots, pass: 1);
    render = ReceiptRasterRender(
      image: image,
      bands: bands,
      retriedLineIndexes: Set.unmodifiable(blank),
    );
    return render;
  }

  /// Lays out every line ONCE and assigns exact integer band ownership:
  /// a running row cursor gives each line `startRow = previous.endRow` and an
  /// integer height of `ceil(max(styled requirement, fallback requirement))`,
  /// so bands tile the bitmap exactly and the fallback pass fits the SAME
  /// band without moving later lines or changing the total height.
  List<_LineLayout> _layoutBands(ReceiptRasterRequest request) {
    final widthDots = request.widthDots;
    final textDirection = request.direction == ReceiptTextDirection.rtl
        ? ui.TextDirection.rtl
        : ui.TextDirection.ltr;
    final layouts = <_LineLayout>[];
    var cursor = 0;
    for (var i = 0; i < request.lines.length; i++) {
      final text = request.lines[i];
      final style = i < request.styles.length
          ? request.styles[i]
          : PrintLineStyle.normal;

      if (style == PrintLineStyle.separator) {
        final rows = math.max(1, _separatorHeight.ceil());
        layouts.add(
          _LineLayout.separator(
            band: ReceiptRasterBand(
              index: i,
              text: text,
              style: style,
              startRow: cursor,
              endRow: cursor + rows,
            ),
          ),
        );
        cursor += rows;
        continue;
      }

      final styleSpec = _specFor(style);
      final styled = _layoutLine(text, widthDots, textDirection, styleSpec);
      var required = math.max(styleSpec.size * lineHeight, styled.height);

      // FALLBACK HEIGHT SAFETY: a visible line may be re-rendered at the base
      // spec inside the same band, so reserve enough rows for EITHER render
      // before the band is finalized.
      ui.Paragraph? fallback;
      if (hasVisibleReceiptText(text)) {
        final fallbackSpec = _LineSpec(
          size: fontSize,
          weight: ui.FontWeight.w400,
          align: styleSpec.align,
        );
        fallback = _layoutLine(text, widthDots, textDirection, fallbackSpec);
        required = math.max(
          required,
          math.max(fontSize * lineHeight, fallback.height),
        );
      }

      final rows = math.max(1, required.ceil());
      layouts.add(
        _LineLayout.text(
          styled: styled,
          fallback: fallback,
          band: ReceiptRasterBand(
            index: i,
            text: text,
            style: style,
            startRow: cursor,
            endRow: cursor + rows,
          ),
        ),
      );
      cursor += rows;
    }
    return layouts;
  }

  Future<ReceiptRasterImage> _render(
    List<_LineLayout> layouts,
    int widthDots,
    int heightDots, {
    required int pass,
  }) async {
    final image = await _paint(layouts, widthDots, heightDots, pass: pass);
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
    List<_LineLayout> layouts,
    int widthDots,
    int heightDots, {
    required int pass,
  }) async {
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
    for (final layout in layouts) {
      final band = layout.band;
      final skip =
          debugBlankEveryPassLineIndexes.contains(band.index) ||
          (pass == 0 && debugBlankFirstPassLineIndexes.contains(band.index));
      if (skip) continue;
      // OWNERSHIP CLIP: nothing a line draws may escape its own rows, so a
      // neighbour's ink can never satisfy this band's zero-ink scan.
      canvas.save();
      canvas.clipRect(
        ui.Rect.fromLTRB(
          0,
          band.startRow.toDouble(),
          widthDots.toDouble(),
          band.endRow.toDouble(),
        ),
      );
      if (layout.isSeparator) {
        final lineY = (band.startRow + band.endRow) / 2;
        canvas.drawLine(
          ui.Offset(inset, lineY),
          ui.Offset(widthDots - inset, lineY),
          rulePaint,
        );
      } else {
        final paragraph = layout.useFallback && layout.fallback != null
            ? layout.fallback!
            : layout.styled!;
        canvas.drawParagraph(paragraph, ui.Offset(0, band.startRow.toDouble()));
      }
      canvas.restore();
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

/// Matches strings whose every character is invisible on paper: whitespace,
/// zero-width characters (ZWSP/ZWNJ/ZWJ), bidi marks and embedding controls,
/// word joiner and invisible operators, deprecated format characters, soft
/// hyphen, Arabic letter mark, and the BOM. Bounded local list — no Unicode
/// package.
final RegExp _invisibleOnlyPattern = RegExp(
  r'^[\s\u00AD\u061C\u180E\u200B-\u200F\u2028-\u202E\u2060-\u2064\u206A-\u206F\uFEFF]*$',
);

/// True when [text] contains at least one VISIBLE printable character (real
/// Arabic/Hebrew/Latin letters, digits, ×, ₪, punctuation…). Lines made only
/// of whitespace / zero-width / directional-control characters print nothing
/// legitimately and must not be treated as ink-expecting content. Combining
/// marks attached to real text are untouched — the pattern only ever matches
/// WHOLE strings of invisible characters.
bool hasVisibleReceiptText(String text) =>
    !_invisibleOnlyPattern.hasMatch(text);

/// One logical receipt line's EXACT vertical ownership inside the final
/// bitmap (PILOT-PRINT-FIDELITY-001). Rows are half-open `[startRow, endRow)`
/// and adjacent bands tile exactly: `next.startRow == previous.endRow`, the
/// first band starts at row 0, and the last band ends at the image height.
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

  /// First bitmap row (inclusive) owned by this line.
  final int startRow;

  /// One past the last bitmap row owned by this line.
  final int endRow;

  bool get isSeparator => style == PrintLineStyle.separator;

  /// Whether the printed receipt must show something in this band: separators
  /// draw their rule, and text lines only when they carry actually VISIBLE
  /// printable content (see [hasVisibleReceiptText] — zero-width/control-only
  /// strings legitimately print nothing).
  bool get expectsInk => isSeparator || hasVisibleReceiptText(text);
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

  /// Diagnostic metadata: line indexes that produced ZERO ink on the first
  /// pass despite visible content and received the one fallback render
  /// attempt (see the class doc — a recovery attempt, not a glyph
  /// guarantee). Empty in the normal single-pass case.
  final Set<int> retriedLineIndexes;

  /// Black-dot count within [band]'s OWNED rows (whole-width scan of the
  /// 1bpp data). Ownership is exact and painting is clipped to it, so a
  /// neighbouring line's ink can never contribute.
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

/// One laid-out line: its exact owned [band], the [styled] paragraph, and —
/// for visible text lines — the pre-measured base-spec [fallback] paragraph
/// the zero-ink recovery pass swaps in ([useFallback]) without reflowing.
class _LineLayout {
  _LineLayout.text({
    required this.styled,
    required this.fallback,
    required this.band,
  });
  _LineLayout.separator({required this.band}) : styled = null, fallback = null;

  final ui.Paragraph? styled;
  final ui.Paragraph? fallback;
  final ReceiptRasterBand band;
  bool useFallback = false;

  bool get isSeparator => styled == null;
}
