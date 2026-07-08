import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-RTL-001: the pure-Dart raster orchestration. Turns an already-laid-out
/// ESC/POS TEXT document into a single raster-image document so Arabic/Hebrew
/// (and non-ASCII ₪/×) print as glyphs, never "?????". The layout is reused
/// verbatim; money content is only moved into the bitmap, never recomputed.

PrintDocument _textDoc(List<String> texts) =>
    PrintDocument([for (final t in texts) PrintTextLine(t)]);

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

void main() {
  group('printDocumentNeedsRaster', () {
    test('false for pure ASCII (fast text path preserved)', () {
      expect(
        printDocumentNeedsRaster(_textDoc(['Receipt', 'Order: 1', 'Total 10'])),
        isFalse,
      );
    });
    test('true for Arabic / Hebrew / shekel sign / multiplier', () {
      expect(printDocumentNeedsRaster(_textDoc(['إيصال'])), isTrue);
      expect(printDocumentNeedsRaster(_textDoc(['קבלה'])), isTrue);
      expect(printDocumentNeedsRaster(_textDoc(['Total ₪10.00'])), isTrue);
      expect(printDocumentNeedsRaster(_textDoc(['Burger 2×'])), isTrue);
    });
    test('false for an already-raster document (never double-rastered)', () {
      final img = PrintRasterImageLine(
        data: Uint8List(8),
        widthBytes: 1,
        heightDots: 8,
      );
      expect(printDocumentNeedsRaster(PrintDocument([img])), isFalse);
    });
  });

  group('baseDirectionForLines', () {
    test('LTR for English', () {
      expect(
        baseDirectionForLines(['Receipt', 'Order 1']),
        ReceiptTextDirection.ltr,
      );
    });
    test('RTL for Arabic-dominant', () {
      expect(
        baseDirectionForLines(['إيصال', 'طلب رقم ١']),
        ReceiptTextDirection.rtl,
      );
    });
    test('LTR for an English receipt carrying a single Arabic name', () {
      expect(
        baseDirectionForLines(['Receipt', 'Order 1', 'Customer: محمد']),
        ReceiptTextDirection.ltr,
      );
    });
  });

  group('rasterizeTextDocument', () {
    test('produces ONE image + feed + cut; the original ar/he text reaches the '
        'rasterizer (rendered as glyphs, never ESC/POS text)', () async {
      final fake = FakeReceiptRasterizer();
      final doc = await rasterizeTextDocument(
        _textDoc(['إيصال', 'العميل: محمد', 'المجموع ₪10.00']),
        rasterizer: fake,
      );
      // The whole receipt is a single image — NO plain text lines survive that a
      // codepage-limited printer could turn into "?????".
      expect(doc.lines.whereType<PrintTextLine>(), isEmpty);
      expect(doc.lines.whereType<PrintRasterImageLine>().length, 1);
      expect(doc.lines.whereType<PrintFeedLine>().length, 1);
      expect(doc.lines.whereType<PrintCutLine>().length, 1);
      // The Arabic strings were handed to the rasterizer verbatim.
      expect(fake.requests.single.lines, [
        'إيصال',
        'العميل: محمد',
        'المجموع ₪10.00',
      ]);
      expect(fake.requests.single.widthDots, 576); // 80mm default
      expect(fake.requests.single.direction, ReceiptTextDirection.rtl);
    });
  });

  group('maybeRasterizeForRtl', () {
    test('null rasterizer -> the text doc is returned unchanged', () async {
      final text = _textDoc(['إيصال']);
      expect(
        identical(await maybeRasterizeForRtl(text, rasterizer: null), text),
        isTrue,
      );
    });
    test('ASCII-only -> unchanged (crisp fast text path)', () async {
      final text = _textDoc(['Receipt', 'Order 1']);
      final out = await maybeRasterizeForRtl(
        text,
        rasterizer: FakeReceiptRasterizer(),
      );
      expect(identical(out, text), isTrue);
    });
    test('Arabic content -> a raster document', () async {
      final out = await maybeRasterizeForRtl(
        _textDoc(['إيصال']),
        rasterizer: FakeReceiptRasterizer(),
      );
      expect(out.lines.whereType<PrintRasterImageLine>().length, 1);
      expect(out.lines.whereType<PrintTextLine>(), isEmpty);
    });
  });

  group('ESC/POS encoding of the raster document', () {
    test('encodes to GS v 0 raster bytes (0x1D 0x76 0x30)', () async {
      final doc = await rasterizeTextDocument(
        _textDoc(['إيصال']),
        rasterizer: FakeReceiptRasterizer(),
      );
      final bytes = const EscPosPrintAdapter().encode(
        doc,
        PrinterProfile.escPos80mm,
      );
      expect(_containsSeq(bytes, [0x1D, 0x76, 0x30]), isTrue);
    });
  });
}
