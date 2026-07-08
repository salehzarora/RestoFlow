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
