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
}
