import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// RF-073 — the real Flutter/dart:ui receipt rasterizer. Structural assertions
/// only (D3): exact width, positive height, non-empty + not-all-white pixels.
/// No exact Skia byte goldens (platform-dependent), no BuildContext.
void main() {
  // dart:ui Picture.toImage needs an initialized binding (but NOT a widget tree
  // / BuildContext) — proves the rasterizer is context-free.
  TestWidgetsFlutterBinding.ensureInitialized();

  const rasterizer = FlutterReceiptRasterizer();

  ReceiptRasterRequest request(
    List<String> lines, {
    required int widthDots,
    required ReceiptTextDirection direction,
    required String localeTag,
  }) => ReceiptRasterRequest(
    lines: lines,
    widthDots: widthDots,
    direction: direction,
    localeTag: localeTag,
  );

  void expectValidBitmap(ReceiptRasterImage image, int expectedWidthDots) {
    expect(image.widthBytes, expectedWidthDots ~/ 8);
    expect(image.heightDots, greaterThan(0));
    expect(image.data, isNotEmpty);
    expect(image.data.length, image.widthBytes * image.heightDots);
    // Not all white: at least one black dot was rendered (test font draws boxes).
    expect(image.data.any((b) => b != 0), isTrue);
    // Convertible straight into a print line.
    expect(image.toPrintLine(), isA<PrintRasterImageLine>());
  }

  test('Arabic (RTL) renders an 80mm (576-dot) bitmap', () async {
    final image = await rasterizer.rasterize(
      request(
        const ['إيصال: R-1001', 'الإجمالي 58.50 ILS', 'شكراً'],
        widthDots: 576,
        direction: ReceiptTextDirection.rtl,
        localeTag: 'ar',
      ),
    );
    expectValidBitmap(image, 576);
  });

  test('Hebrew (RTL) renders a 58mm (384-dot) bitmap', () async {
    final image = await rasterizer.rasterize(
      request(
        const ['קבלה: R-1001', 'סה"כ 58.50 ILS', 'תודה'],
        widthDots: 384,
        direction: ReceiptTextDirection.rtl,
        localeTag: 'he',
      ),
    );
    expectValidBitmap(image, 384);
  });

  test('English (LTR) renders a 58mm (384-dot) bitmap', () async {
    final image = await rasterizer.rasterize(
      request(
        const ['Receipt: R-1001', 'TOTAL 58.50 ILS', 'Thank you'],
        widthDots: 384,
        direction: ReceiptTextDirection.ltr,
        localeTag: 'en',
      ),
    );
    expectValidBitmap(image, 384);
  });

  // PRINT-RASTER-STYLE-001: styled lines change size/shape, not just count.
  // Structural (D3) assertions only — height / non-blank, never exact bytes.
  Future<ReceiptRasterImage> rasterStyled(
    List<String> lines,
    List<PrintLineStyle> styles, {
    ReceiptTextDirection direction = ReceiptTextDirection.ltr,
    String localeTag = 'en',
  }) => rasterizer.rasterize(
    ReceiptRasterRequest(
      lines: lines,
      styles: styles,
      widthDots: 576,
      direction: direction,
      localeTag: localeTag,
    ),
  );

  test(
    'a headingLarge line renders taller than the same normal line',
    () async {
      final normal = await rasterStyled(
        const ['Order #A1'],
        const [PrintLineStyle.normal],
      );
      final heading = await rasterStyled(
        const ['Order #A1'],
        const [PrintLineStyle.headingLarge],
      );
      expect(heading.heightDots, greaterThan(normal.heightDots));
      expectValidBitmap(heading, 576);
    },
  );

  test('a separator style draws a rule (non-blank, no text needed)', () async {
    final image = await rasterStyled(
      const ['---'],
      const [PrintLineStyle.separator],
    );
    // The rule painted black dots even though the "text" is ignored.
    expect(image.data.any((b) => b != 0), isTrue);
    expectValidBitmap(image, 576);
  });

  test(
    'Arabic heading + total styles still rasterize (RTL preserved)',
    () async {
      final image = await rasterStyled(
        const ['إيصال', 'المجموع ₪58.50'],
        const [PrintLineStyle.headingLarge, PrintLineStyle.total],
        direction: ReceiptTextDirection.rtl,
        localeTag: 'ar',
      );
      expectValidBitmap(image, 576);
    },
  );

  test('more lines yield a taller bitmap (deterministic ordering)', () async {
    final short = await rasterizer.rasterize(
      request(
        const ['one'],
        widthDots: 384,
        direction: ReceiptTextDirection.ltr,
        localeTag: 'en',
      ),
    );
    final tall = await rasterizer.rasterize(
      request(
        const ['one', 'two', 'three', 'four', 'five', 'six'],
        widthDots: 384,
        direction: ReceiptTextDirection.ltr,
        localeTag: 'en',
      ),
    );
    expect(tall.heightDots, greaterThan(short.heightDots));
  });

  // PILOT-PRINT-FIDELITY-001: per-BAND ink. The physical defect was a receipt
  // whose item/modifier body occupied blank vertical space inside the single
  // bitmap while header and totals printed. These tests pin, per logical line,
  // that valid non-empty content produces actual black dots WITHIN THAT LINE'S
  // OWN ROWS — a blank-but-height-reserving body can never pass again.
  // HONESTY: the CI text engine substitutes a test font that draws solid boxes
  // for most glyphs, so a DEVICE-ONLY font-fallback miss may not reproduce
  // here; real hardware remains the final arbiter for glyph fidelity. What
  // these tests DO guarantee structurally: bands tile the bitmap exactly, and
  // the renderer never silently accepts an ink-less band for renderable text.
  group('per-band body ink (PILOT-PRINT-FIDELITY-001)', () {
    Future<ReceiptRasterRender> render(
      List<(String, PrintLineStyle)> styledLines, {
      ReceiptTextDirection direction = ReceiptTextDirection.rtl,
      String localeTag = 'ar',
    }) => rasterizer.rasterizeDetailed(
      ReceiptRasterRequest(
        lines: [for (final (t, _) in styledLines) t],
        styles: [for (final (_, s) in styledLines) s],
        widthDots: 576,
        direction: direction,
        localeTag: localeTag,
      ),
    );

    void expectEveryBandInked(ReceiptRasterRender r) {
      for (final band in r.bands) {
        if (!band.expectsInk) continue;
        expect(
          r.inkInBand(band),
          greaterThan(0),
          reason:
              'line ${band.index} (${band.style.name}) '
              '"${band.text.trim()}" rendered NO ink in rows '
              '${band.startRow}..${band.endRow}',
        );
      }
    }

    void expectBandsTile(ReceiptRasterRender r) {
      expect(r.bands.first.startRow, 0);
      expect(r.bands.last.endRow, r.image.heightDots);
      for (var i = 1; i < r.bands.length; i++) {
        // floor/ceil rounding may overlap adjacent bands by one row but can
        // never leave an unowned gap.
        expect(r.bands[i].startRow, lessThanOrEqualTo(r.bands[i - 1].endRow));
        expect(r.bands[i].endRow, greaterThanOrEqualTo(r.bands[i - 1].endRow));
      }
    }

    // The exact physical shape: Arabic header, meta, item + modifiers with
    // two-column padding and the × multiplier, totals below.
    List<(String, PrintLineStyle)> arabicReceipt() => const [
      ('مطعم الأصالة', PrintLineStyle.headingLarge),
      ('مدفوع', PrintLineStyle.centered),
      ('#A1B2C3', PrintLineStyle.headingLarge),
      ('صالة · طاولة T3 · 14:30', PrintLineStyle.centered),
      ('--------', PrintLineStyle.separator),
      ('2 × كباب حلبي                          ₪50.00', PrintLineStyle.item),
      ('  + إضافة ثوم ×2', PrintLineStyle.sub),
      ('  + بدون بصل', PrintLineStyle.sub),
      ('1 × حمص بالطحينة                       ₪18.00', PrintLineStyle.item),
      ('--------', PrintLineStyle.separator),
      ('المجموع                                ₪68.00', PrintLineStyle.total),
      ('المدفوع                                ₪70.00', PrintLineStyle.normal),
      ('الباقي                                  ₪2.00', PrintLineStyle.normal),
      ('شكراً لزيارتكم', PrintLineStyle.centered),
    ];

    test('Arabic receipt: header, EVERY item, EVERY modifier, and totals '
        'bands all carry ink; bands tile the bitmap', () async {
      final r = await render(arabicReceipt());
      expectBandsTile(r);
      expectEveryBandInked(r);
      // Explicit body pins (the photographed blank region).
      final items = r.bands.where((b) => b.style == PrintLineStyle.item);
      final subs = r.bands.where((b) => b.style == PrintLineStyle.sub);
      expect(items, hasLength(2));
      expect(subs, hasLength(2));
      for (final b in [...items, ...subs]) {
        expect(r.inkInBand(b), greaterThan(0));
      }
    });

    test('Hebrew item + modifiers carry ink', () async {
      final r = await render(const [
        ('קבלה', PrintLineStyle.headingLarge),
        ('2 × שווארמה בפיתה                      ₪45.00', PrintLineStyle.item),
        ('  + תוספת חריף', PrintLineStyle.sub),
        ('סה"כ                                   ₪45.00', PrintLineStyle.total),
      ], localeTag: 'he');
      expectBandsTile(r);
      expectEveryBandInked(r);
    });

    test('English item with the × multiplier carries ink', () async {
      final r = await render(
        const [
          ('Receipt', PrintLineStyle.headingLarge),
          (
            '2 × Burger                             ₪50.00',
            PrintLineStyle.item,
          ),
          ('  + Extra cheese', PrintLineStyle.sub),
          (
            'TOTAL                                  ₪50.00',
            PrintLineStyle.total,
          ),
        ],
        direction: ReceiptTextDirection.ltr,
        localeTag: 'en',
      );
      expectBandsTile(r);
      expectEveryBandInked(r);
    });

    test('mixed RTL text, digits, currency, and two-column spacing stay '
        'non-blank', () async {
      final r = await render(const [
        ('3 × Pizza مرغريتا 12" ₪36.50           ₪109.50', PrintLineStyle.item),
      ]);
      expect(r.inkInBand(r.bands.single), greaterThan(0));
    });

    test('a MANY-item receipt grows vertically, keeps every item band inked, '
        'and keeps totals present (no clipping)', () async {
      final few = await render(arabicReceipt());
      final many = await render([
        ...arabicReceipt().take(5),
        for (var i = 1; i <= 12; i++) ...[
          (
            '$i × صنف رقم $i                        ₪10.00',
            PrintLineStyle.item,
          ),
          ('  + إضافة $i', PrintLineStyle.sub),
        ],
        ...arabicReceipt().skip(9),
      ]);
      expect(many.image.heightDots, greaterThan(few.image.heightDots));
      expectBandsTile(many);
      expectEveryBandInked(many);
      expect(
        many.bands.where((b) => b.style == PrintLineStyle.total).length,
        1,
      );
    });

    test('a LONG receipt keeps every section: no missing middle', () async {
      final r = await render([
        ('رأس الإيصال', PrintLineStyle.headingLarge),
        for (var i = 1; i <= 40; i++)
          (
            '$i × صنف طويل جداً رقم $i              ₪10.00',
            PrintLineStyle.item,
          ),
        ('المجموع                               ₪400.00', PrintLineStyle.total),
      ]);
      expectBandsTile(r);
      expectEveryBandInked(r);
    });

    test('a healthy receipt renders in ONE pass (no retry)', () async {
      final r = await render(arabicReceipt());
      expect(r.retriedLineIndexes, isEmpty);
    });

    test('INK GUARANTEE: a renderable-but-blank line triggers exactly one '
        'safe re-render pass and is observable', () async {
      // U+200B (zero-width space) is NOT trimmed whitespace, so the line
      // counts as renderable — yet no font produces ink for it. The renderer
      // must detect the blank band and retry it with the base spec rather
      // than silently reserving blank height.
      final r = await render(const [
        ('عنوان', PrintLineStyle.headingLarge),
        ('​', PrintLineStyle.item),
        ('المجموع ₪10.00', PrintLineStyle.total),
      ]);
      expect(r.retriedLineIndexes, {1});
      // The neighbours still carry ink; the receipt still renders.
      expect(r.inkInBand(r.bands[0]), greaterThan(0));
      expect(r.inkInBand(r.bands[2]), greaterThan(0));
    });

    test('production rasterize() bytes are IDENTICAL to the detailed render '
        '(the seam changes nothing a printer receives)', () async {
      final request = ReceiptRasterRequest(
        lines: [for (final (t, _) in arabicReceipt()) t],
        styles: [for (final (_, s) in arabicReceipt()) s],
        widthDots: 576,
        direction: ReceiptTextDirection.rtl,
        localeTag: 'ar',
      );
      final plain = await rasterizer.rasterize(request);
      final detailed = await rasterizer.rasterizeDetailed(request);
      expect(plain.heightDots, detailed.image.heightDots);
      expect(plain.widthBytes, detailed.image.widthBytes);
      expect(plain.data, detailed.image.data);
    });
  });

  // PRINT-RTL-001: the full live path — an already-laid-out ESC/POS TEXT document
  // rasterized by the REAL dart:ui renderer, then encoded to ESC/POS raster
  // bytes. Proves ar/he go out as a GS v 0 image, never codepage text.
  group('text document -> real raster -> ESC/POS GS v 0 bytes', () {
    PrintDocument textDoc(List<String> lines) =>
        PrintDocument([for (final l in lines) PrintTextLine(l)]);

    test(
      'Arabic (80mm) encodes to a raster image, no text lines survive',
      () async {
        final doc = await rasterizeTextDocument(
          textDoc(const ['إيصال: R-1001', 'العميل: محمد', 'الإجمالي ₪58.50']),
          rasterizer: rasterizer,
        );
        expect(doc.lines.whereType<PrintTextLine>(), isEmpty);
        final bytes = const EscPosPrintAdapter().encode(
          doc,
          PrinterProfile.escPos80mm,
        );
        expect(_containsSeq(bytes, const [0x1D, 0x76, 0x30]), isTrue);
      },
    );

    test('Hebrew (58mm) encodes to a raster image', () async {
      final doc = await rasterizeTextDocument(
        textDoc(const ['קבלה: R-1001', 'לקוח: דוד', 'סה"כ ₪58.50']),
        rasterizer: rasterizer,
        widthDots: 384,
      );
      final bytes = const EscPosPrintAdapter().encode(
        doc,
        PrinterProfile.escPos58mm,
      );
      expect(_containsSeq(bytes, const [0x1D, 0x76, 0x30]), isTrue);
    });
  });
}

bool _containsSeq(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}
