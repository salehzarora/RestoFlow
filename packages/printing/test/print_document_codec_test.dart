import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-071 A4: PrintDocument JSON round-trips and re-renders to identical bytes.
void main() {
  const codec = PrintDocumentCodec();
  const adapter = EscPosPrintAdapter();

  test('round-trips a mixed document and re-renders identical ESC/POS bytes', () {
    final doc = PrintDocument([
      const PrintTextLine(
        'RestoFlow',
        alignment: PrintAlignment.center,
        emphasis: TextEmphasis.bold,
      ),
      const PrintTextLine('شكرا', direction: PrintTextDirection.rtl),
      const PrintFeedLine(2),
      PrintRasterImageLine(
        data: Uint8List.fromList([0xFF, 0x00, 0xAA]),
        widthBytes: 1,
        heightDots: 3,
      ),
      const PrintDrawerKickLine(),
      const PrintCutLine(),
    ], localeTag: 'ar');

    final json = codec.encode(doc);
    final restored = codec.decode(json);

    expect(restored.localeTag, 'ar');
    expect(restored.lines.length, doc.lines.length);
    // The proof: re-rendered bytes are byte-identical before/after the round-trip.
    expect(
      adapter.encode(restored, PrinterProfile.escPos80mm),
      adapter.encode(doc, PrinterProfile.escPos80mm),
    );
  });

  test('decode rejects a raster line whose dimensions mismatch the payload', () {
    // 1 byte of data but claims 2x2 = 4 bytes.
    const bad =
        '{"localeTag":null,"lines":[{"type":"raster","data":"/w==","widthBytes":2,"heightDots":2}]}';
    expect(() => codec.decode(bad), throwsA(isA<FormatException>()));
  });

  test('decode rejects an unknown line type', () {
    expect(
      () => codec.decode('{"lines":[{"type":"bogus"}]}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('decode rejects a non-object root', () {
    expect(() => codec.decode('[]'), throwsA(isA<FormatException>()));
  });
}
