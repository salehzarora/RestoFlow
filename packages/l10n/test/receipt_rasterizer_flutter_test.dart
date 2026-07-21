import 'dart:typed_data';

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
  // bitmap while header and totals printed. These tests pin, per logical
  // line, that under THIS test environment's font the content produces black
  // dots WITHIN THAT LINE'S OWN ROWS, that bands tile the bitmap exactly, and
  // that a first-pass zero-ink visible line is detected and given ONE
  // recorded fallback render attempt. They do NOT prove every device font
  // yields final ink — a device failing both passes may still print a blank
  // band; real hardware remains the final glyph-fidelity arbiter.
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
      // EXACT ownership: half-open bands tile the bitmap precisely — no
      // overlap, no unowned gap, full coverage.
      expect(r.bands.first.startRow, 0);
      expect(r.bands.last.endRow, r.image.heightDots);
      for (var i = 1; i < r.bands.length; i++) {
        expect(
          r.bands[i].startRow,
          r.bands[i - 1].endRow,
          reason:
              'band $i must begin exactly where band ${i - 1} ends '
              '(no overlap, no gap)',
        );
      }
      for (final band in r.bands) {
        expect(band.endRow, greaterThan(band.startRow));
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

    test('FRACTIONAL adjacent heights still produce exact integer '
        'ownership: every band starts where the previous ends', () async {
      // Mixed styles produce fractional logical heights (0.9×, 1.1×, 1.2×,
      // 1.55× of 22px × 1.3 line height, and the 18.7px separator).
      final r = await render(const [
        ('عنوان كبير', PrintLineStyle.headingLarge),
        ('1 × صنف', PrintLineStyle.item),
        ('  + إضافة', PrintLineStyle.sub),
        ('----', PrintLineStyle.separator),
        ('المجموع ₪10.00', PrintLineStyle.total),
        ('ملاحظة', PrintLineStyle.note),
        ('شكراً', PrintLineStyle.centered),
      ]);
      expectBandsTile(r); // asserts next.startRow == previous.endRow exactly
    });

    group('visible-content classification (no ink expected from '
        'invisible-only lines)', () {
      test('U+200B-only is NOT visible: expectsInk=false, no retry', () async {
        final r = await render(const [
          ('عنوان', PrintLineStyle.headingLarge),
          ('\u200B', PrintLineStyle.item),
          ('المجموع ₪10.00', PrintLineStyle.total),
        ]);
        expect(hasVisibleReceiptText('\u200B'), isFalse);
        expect(r.bands[1].expectsInk, isFalse);
        expect(r.retriedLineIndexes, isEmpty); // nothing to recover
        expect(r.inkInBand(r.bands[0]), greaterThan(0));
        expect(r.inkInBand(r.bands[2]), greaterThan(0));
      });

      test('default-ignorable-only combinations are NOT visible', () {
        for (final s in const [
          '',
          '   ',
          '\u200B\u200C\u200D',
          '\u2060\uFEFF',
          ' \u200E\u200F ',
          '\u202A\u202C\u00AD\u061C',
        ]) {
          expect(
            hasVisibleReceiptText(s),
            isFalse,
            reason: 'invisible-only "$s" must not expect ink',
          );
        }
      });

      test('real Arabic, Hebrew, English, digits, × and ₪ ARE visible and '
          'their owned bands carry ink', () async {
        expect(hasVisibleReceiptText('كباب حلبي'), isTrue);
        expect(hasVisibleReceiptText('שווארמה בפיתה'), isTrue);
        expect(hasVisibleReceiptText('2 × Burger ₪50.00'), isTrue);
        // Combining marks attached to real text stay visible.
        expect(hasVisibleReceiptText('مُشَكَّل'), isTrue);
        final r = await render(const [
          ('2 × كباب حلبي', PrintLineStyle.item),
          ('  + שווארמה', PrintLineStyle.sub),
          ('2 × Burger ₪50.00', PrintLineStyle.item),
        ]);
        for (final band in r.bands) {
          expect(band.expectsInk, isTrue);
          expect(r.inkInBand(band), greaterThan(0));
        }
      });
    });

    // HONEST CONTRACT under test here: a first-pass zero-ink VISIBLE line is
    // DETECTED, ONE fallback render is attempted, and the attempt is recorded
    // in retriedLineIndexes. This is NOT a guarantee that every valid line
    // ends with ink, and NOT proof a blank body is impossible on every device
    // font — a device failing both passes may legitimately remain blank, and
    // physical hardware stays the final glyph-fidelity arbiter. Because the
    // production rasterizer has NO forced-blank API (its constructor takes
    // only fontSize/lineHeight/luminanceThreshold), the blank first pass is
    // supplied as an explicit SYNTHETIC raster to the read-only
    // debugRecoverFromFirstPass diagnostic, which runs the SAME detection +
    // recovery step production uses.
    group('zero-ink recovery (one fallback attempt — not a glyph '
        'guarantee)', () {
      const receipt = [
        ('عنوان الإيصال', PrintLineStyle.headingLarge),
        ('1 × كباب حلبي', PrintLineStyle.item),
        ('2 × حمص بالطحينة', PrintLineStyle.item),
        ('  + إضافة ثوم', PrintLineStyle.sub),
        ('المجموع ₪68.00', PrintLineStyle.total),
      ];

      ReceiptRasterRequest req() => ReceiptRasterRequest(
        lines: [for (final (t, _) in receipt) t],
        styles: [for (final (_, s) in receipt) s],
        widthDots: 576,
        direction: ReceiptTextDirection.rtl,
        localeTag: 'ar',
      );

      /// A copy of [src] with [band]'s owned rows zeroed — the synthetic
      /// stand-in for a device font that painted nothing for that line.
      ReceiptRasterImage withBlankBand(
        ReceiptRasterImage src,
        ReceiptRasterBand band,
      ) {
        final data = Uint8List.fromList(src.data);
        data.fillRange(
          band.startRow * src.widthBytes,
          band.endRow * src.widthBytes,
          0,
        );
        return ReceiptRasterImage(
          data: data,
          widthBytes: src.widthBytes,
          heightDots: src.heightDots,
        );
      }

      test('NORMAL rasterize paints the visible middle line (no intentional '
          'skip path) and repeated calls are byte-identical', () async {
        final a = await rasterizer.rasterizeDetailed(req());
        expect(a.retriedLineIndexes, isEmpty);
        expect(a.inkInBand(a.bands[2]), greaterThan(0));
        final b = await rasterizer.rasterizeDetailed(req());
        expect(b.image.data, a.image.data);
      });

      test(
        'a SYNTHETIC first-pass blank on a visible middle line is '
        'detected despite fully inked neighbours, retried in ITS OWN band, '
        'and the real fallback paints without moving any other line',
        () async {
          final normal = await rasterizer.rasterizeDetailed(req());
          final synthetic = withBlankBand(normal.image, normal.bands[2]);
          // The synthetic input keeps both neighbours fully inked — their ink
          // must NOT mask the blank middle line (exact ownership, no overlap).
          final syntheticView = ReceiptRasterRender(
            image: synthetic,
            bands: normal.bands,
          );
          expect(syntheticView.inkInBand(normal.bands[1]), greaterThan(0));
          expect(syntheticView.inkInBand(normal.bands[2]), 0);
          expect(syntheticView.inkInBand(normal.bands[3]), greaterThan(0));

          final recovered = await rasterizer.debugRecoverFromFirstPass(
            req(),
            synthetic,
          );
          expect(recovered.retriedLineIndexes, {2});
          // The REAL fallback pass painted the line inside its own band.
          expect(recovered.inkInBand(recovered.bands[2]), greaterThan(0));
          expect(recovered.inkInBand(recovered.bands[1]), greaterThan(0));
          expect(recovered.inkInBand(recovered.bands[3]), greaterThan(0));
          // Band geometry is identical with and without the recovery: later
          // lines did not move and the total height is unchanged.
          expect(recovered.image.heightDots, normal.image.heightDots);
          for (var i = 0; i < normal.bands.length; i++) {
            expect(recovered.bands[i].startRow, normal.bands[i].startRow);
            expect(recovered.bands[i].endRow, normal.bands[i].endRow);
          }
        },
      );

      test('a line blank on BOTH passes (synthetic retry result): exactly '
          'one retry, no recursion or crash, neighbours intact, structure '
          'valid — the line honestly remains blank', () async {
        final normal = await rasterizer.rasterizeDetailed(req());
        final synthetic = withBlankBand(normal.image, normal.bands[2]);
        final r = await rasterizer.debugRecoverFromFirstPass(
          req(),
          synthetic,
          syntheticRetryResult: synthetic,
        );
        expect(r.retriedLineIndexes, {2});
        expect(r.inkInBand(r.bands[2]), 0); // honestly still blank
        expect(r.inkInBand(r.bands[1]), greaterThan(0));
        expect(r.inkInBand(r.bands[3]), greaterThan(0));
        expectBandsTile(r);
        expect(r.image.data.length, r.image.widthBytes * r.image.heightDots);
      });

      test('PRODUCTION ISOLATION: a diagnostic call leaves no residue — the '
          'same instance then renders normally, byte-identical to a fresh '
          'instance', () async {
        final before = await rasterizer.rasterizeDetailed(req());
        await rasterizer.debugRecoverFromFirstPass(
          req(),
          withBlankBand(before.image, before.bands[2]),
        );
        final after = await rasterizer.rasterizeDetailed(req());
        expect(after.retriedLineIndexes, isEmpty);
        expect(after.image.data, before.image.data);
        final fresh = await const FlutterReceiptRasterizer().rasterizeDetailed(
          req(),
        );
        expect(after.image.data, fresh.image.data);
      });
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
