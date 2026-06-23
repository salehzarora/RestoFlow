import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-070: profile defaults + capability gating — an unsupported cut / drawer
/// kick / raster line is OMITTED from the byte stream (clear, deterministic).
void main() {
  const adapter = EscPosPrintAdapter();

  group('default profiles', () {
    test('80mm default', () {
      const p = PrinterProfile.escPos80mm;
      expect(p.paperWidth, PaperWidth.mm80);
      expect(p.columns, 48);
      expect(p.codePage, CodePage.cp437);
      expect(p.capabilities.supportsCut, isTrue);
    });

    test('58mm default (compact; must stay supported)', () {
      const p = PrinterProfile.escPos58mm;
      expect(p.paperWidth, PaperWidth.mm58);
      expect(p.columns, 32);
    });
  });

  group('capability gating omits unsupported commands', () {
    final doc = PrintDocument([
      const PrintTextLine('x'),
      const PrintCutLine(),
      const PrintDrawerKickLine(),
      PrintRasterImageLine(
        data: Uint8List.fromList([0xFF]),
        widthBytes: 1,
        heightDots: 1,
      ),
    ]);

    test('all capabilities on -> cut + kick + raster present', () {
      const profile = PrinterProfile(
        paperWidth: PaperWidth.mm80,
        columns: 48,
        capabilities: PrinterCapabilities(),
      );
      final bytes = adapter.encode(doc, profile);
      expect(_contains(bytes, [0x1D, 0x56, 0x01]), isTrue, reason: 'cut');
      expect(_contains(bytes, [0x1B, 0x70, 0, 25, 25]), isTrue, reason: 'kick');
      expect(_contains(bytes, [0x1D, 0x76, 0x30]), isTrue, reason: 'raster');
    });

    test('all capabilities off -> cut + kick + raster omitted', () {
      const profile = PrinterProfile(
        paperWidth: PaperWidth.mm80,
        columns: 48,
        capabilities: PrinterCapabilities(
          supportsCut: false,
          supportsDrawerKick: false,
          supportsRaster: false,
        ),
      );
      final bytes = adapter.encode(doc, profile);
      expect(_contains(bytes, [0x1D, 0x56, 0x01]), isFalse, reason: 'no cut');
      expect(_contains(bytes, [0x1B, 0x70]), isFalse, reason: 'no kick');
      expect(
        _contains(bytes, [0x1D, 0x76, 0x30]),
        isFalse,
        reason: 'no raster',
      );
      // The text line still printed.
      expect(_contains(bytes, [0x78]), isTrue, reason: 'text "x" present');
    });
  });
}

bool _contains(List<int> haystack, List<int> needle) {
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
