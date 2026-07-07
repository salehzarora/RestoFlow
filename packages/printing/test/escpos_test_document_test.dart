import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// ANDROID-002: the "Test print" diagnostic document is a real, encodable,
/// money-free ESC/POS document (ASCII-only) — safe to send to a network printer.
void main() {
  const adapter = EscPosPrintAdapter();
  const profile = PrinterProfile.escPos80mm;

  test('encodes to ESC/POS bytes with the ASCII banner and a cut', () {
    final doc = escPosNetworkTestDocument();
    final bytes = adapter.encode(doc, profile);

    // Contains the ASCII "RestoFlow" banner (as raw data bytes).
    final banner = 'RestoFlow'.codeUnits;
    expect(_indexOf(bytes, banner), isNonNegative);
    // Ends with a partial cut (GS V 1) since the 80mm profile supports it.
    expect(_indexOf(bytes, [0x1D, 0x56, 0x01]), isNonNegative);
  });

  test('context lines appear when supplied; non-ASCII degrades to "?" '
      '(never a crash)', () {
    final doc = escPosNetworkTestDocument(
      printerName: 'Counter',
      deviceLabel: 'مطبخ', // Arabic -> each glyph maps to '?'
    );
    final bytes = adapter.encode(doc, profile);
    expect(_indexOf(bytes, 'Printer: Counter'.codeUnits), isNonNegative);
    // The Arabic device label rendered as replacement chars, not raw bytes.
    expect(_indexOf(bytes, 'Device: ????'.codeUnits), isNonNegative);
  });

  test('is money-free: no currency symbols or decimal amounts', () {
    final doc = escPosNetworkTestDocument(printerName: 'X', deviceLabel: 'Y');
    for (final line in doc.lines) {
      if (line is PrintTextLine) {
        expect(line.text, isNot(contains('₪')));
        expect(line.text, isNot(matches(RegExp(r'\d+\.\d{2}'))));
      }
    }
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return 0;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
