import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-070 AC1: printing is behind the [Printer] interface — a fake can be
/// substituted with no driver changes (RISK R-001), and the real path
/// (adapter → in-memory transport) captures the encoded bytes.
void main() {
  final doc = PrintDocument([
    const PrintTextLine('Hi', alignment: PrintAlignment.center),
    const PrintCutLine(),
  ]);

  test(
    'FakePrinter records documents without encoding or hardware (AC1)',
    () async {
      final Printer printer = FakePrinter();
      final r = await printer.printDocument(doc);
      expect(r.ok, isTrue);
      expect((printer as FakePrinter).printed.single, same(doc));
    },
  );

  test(
    'AdapterPrinter + InMemoryPrintTransport encodes and captures bytes',
    () async {
      final transport = InMemoryPrintTransport();
      final Printer printer = AdapterPrinter(
        adapter: const EscPosPrintAdapter(),
        profile: PrinterProfile.escPos80mm,
        transport: transport,
      );

      final r = await printer.printDocument(doc);
      expect(r.ok, isTrue);

      final sent = transport.lastBytes!;
      // Begins with init (ESC @) + code-page select, and ends with a cut.
      expect(sent.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 0x00]);
      expect(sent.sublist(sent.length - 3), [0x1D, 0x56, 0x01]);
      // It matches the adapter's pure encode() of the same document/profile.
      expect(
        sent,
        const EscPosPrintAdapter().encode(doc, PrinterProfile.escPos80mm),
      );
    },
  );
}
