import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PILOT-PRINT-FIDELITY-001 — the TCP receipt route is ONE full-height
/// bitmap, not slices. These tests pin the transmitted structure so no row
/// range of the generated raster (header, item body, totals) can be lost or
/// reordered between the rasterizer and the wire:
///  * exactly one GS v 0 command;
///  * its width/height fields equal the generated raster;
///  * the payload length equals widthBytes × height (every row, in order);
///  * feed runs only AFTER the complete payload, then the cut.
void main() {
  const gsV0 = [0x1D, 0x76, 0x30, 0x00];
  const escD = [0x1B, 0x64]; // feed n lines
  const gsV = [0x1D, 0x56]; // cut

  List<int> indexesOf(List<int> haystack, List<int> needle) {
    final hits = <int>[];
    for (var i = 0; i + needle.length <= haystack.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) hits.add(i);
    }
    return hits;
  }

  Future<(List<int>, ReceiptRasterImage)> encodeRasterDoc({
    int lines = 40,
  }) async {
    final rasterizer = FakeReceiptRasterizer();
    final doc = await rasterizeTextDocument(
      PrintDocument([
        for (var i = 0; i < lines; i++) PrintTextLine('سطر إيصال رقم $i'),
      ]),
      rasterizer: rasterizer,
    );
    final image = await rasterizer.rasterize(rasterizer.requests.single);
    final bytes = const EscPosPrintAdapter().encode(
      doc,
      PrinterProfile.escPos80mm,
    );
    return (bytes, image);
  }

  test('exactly ONE GS v 0 raster command carries the whole receipt', () async {
    final (bytes, _) = await encodeRasterDoc();
    expect(indexesOf(bytes, gsV0), hasLength(1));
  });

  test(
    'the GS v 0 header fields equal the generated raster: 576-dot width '
    '(72 bytes/row) and the FULL height — no 255 clamp, no banding',
    () async {
      final (bytes, image) = await encodeRasterDoc();
      final at = indexesOf(bytes, gsV0).single;
      final xL = bytes[at + 4];
      final xH = bytes[at + 5];
      final yL = bytes[at + 6];
      final yH = bytes[at + 7];
      expect(xL + (xH << 8), 576 ~/ 8); // 72 bytes per row
      expect(xL + (xH << 8), image.widthBytes);
      expect(yL + (yH << 8), image.heightDots);
    },
  );

  test('the payload is EVERY raster row in order: length == widthBytes × '
      'height and byte-identical to the generated image data', () async {
    final (bytes, image) = await encodeRasterDoc();
    final at = indexesOf(bytes, gsV0).single;
    final payloadStart = at + 8;
    final payload = bytes.sublist(
      payloadStart,
      payloadStart + image.widthBytes * image.heightDots,
    );
    expect(payload.length, image.widthBytes * image.heightDots);
    expect(payload, image.data);
  });

  test('feed comes only AFTER the complete payload; the cut after the feed — '
      'no command interrupts pending image bytes', () async {
    final (bytes, image) = await encodeRasterDoc();
    final at = indexesOf(bytes, gsV0).single;
    final payloadEnd = at + 8 + image.widthBytes * image.heightDots;
    final feedAt = indexesOf(
      bytes,
      escD,
    ).where((i) => i >= payloadEnd).toList();
    final cutAt = indexesOf(bytes, gsV).where((i) => i >= payloadEnd).toList();
    expect(feedAt, isNotEmpty, reason: 'feed must follow the raster payload');
    expect(cutAt, isNotEmpty, reason: 'cut must follow the raster payload');
    expect(feedAt.first, lessThan(cutAt.first));
    // Nothing but the feed/cut trailer follows the payload.
    expect(
      indexesOf(bytes, escD).where((i) => i < payloadEnd && i >= at),
      isEmpty,
      reason: 'no feed may run between the header and the payload end',
    );
  });

  test(
    'a TALL receipt (many rows) still travels as one contiguous payload',
    () async {
      final (bytes, image) = await encodeRasterDoc(lines: 200);
      expect(image.heightDots, greaterThan(255)); // beyond a one-byte height
      final at = indexesOf(bytes, gsV0).single;
      final yL = bytes[at + 6];
      final yH = bytes[at + 7];
      expect(yL + (yH << 8), image.heightDots);
    },
  );
}
