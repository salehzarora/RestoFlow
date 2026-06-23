import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-070 AC2: the ESC/POS adapter renders a known, deterministic byte sequence
/// for a golden document at both 80mm and 58mm.
void main() {
  // A representative document: centered+bold header, a left line, a right line,
  // a 2-line feed, then a cut. Text is PRE-FORMATTED (no money math here).
  final goldenDoc = PrintDocument([
    const PrintTextLine(
      'RestoFlow',
      alignment: PrintAlignment.center,
      emphasis: TextEmphasis.bold,
    ),
    const PrintTextLine('Item A x2'),
    const PrintTextLine('Total 12.00', alignment: PrintAlignment.right),
    const PrintFeedLine(2),
    const PrintCutLine(),
  ]);

  // The exact expected byte stream, command-by-command.
  final golden = <int>[
    0x1B, 0x40, // init: ESC @
    0x1B, 0x74, 0x00, // select code page CP437 (ESC t 0)
    // Line 1: center, bold on, "RestoFlow", LF
    0x1B, 0x61, 0x01, // align center
    0x1B, 0x45, 0x01, // bold on
    0x52, 0x65, 0x73, 0x74, 0x6F, 0x46, 0x6C, 0x6F, 0x77, // RestoFlow
    0x0A,
    // Line 2: left, bold off, "Item A x2", LF
    0x1B, 0x61, 0x00, // align left
    0x1B, 0x45, 0x00, // bold off
    0x49, 0x74, 0x65, 0x6D, 0x20, 0x41, 0x20, 0x78, 0x32, // Item A x2
    0x0A,
    // Line 3: right, bold off, "Total 12.00", LF
    0x1B, 0x61, 0x02, // align right
    0x1B, 0x45, 0x00, // bold off
    0x54,
    0x6F,
    0x74,
    0x61,
    0x6C,
    0x20,
    0x31,
    0x32,
    0x2E,
    0x30,
    0x30, // Total 12.00
    0x0A,
    0x1B, 0x64, 0x02, // feed 2
    0x1D, 0x56, 0x01, // cut (partial)
  ];

  const adapter = EscPosPrintAdapter();

  test('golden bytes on the 80mm profile (AC2)', () {
    expect(adapter.encode(goldenDoc, PrinterProfile.escPos80mm), golden);
  });

  test('golden bytes on the 58mm profile (AC2)', () {
    // RF-070's adapter is width-agnostic for PRE-FORMATTED text (column wrapping
    // belongs to the receipt/kitchen templates, RF-072/RF-073); both default
    // profiles use CP437 + support cut, so the byte stream is identical here.
    expect(adapter.encode(goldenDoc, PrinterProfile.escPos58mm), golden);
  });
}
