import 'print_adapter.dart';
import 'print_document.dart';
import 'print_result.dart';
import 'printer_profile.dart';
import 'transport/print_transport.dart';

/// The high-level printing port the app calls (RF-070).
///
/// Substitutable: [AdapterPrinter] is the real path (adapter → transport);
/// [FakePrinter] records documents with no encoding/hardware. This is the
/// RISK R-001 mitigation — printing is always behind this interface.
abstract class Printer {
  Future<PrintResult> printDocument(PrintDocument document);
}

/// The real [Printer]: encodes via a [PrintAdapter] for a [PrinterProfile] and
/// sends the bytes over a [PrintTransport] (RF-070, §13.1). Holds no job
/// identity — the RF-071 spool drives idempotency/retry around this.
class AdapterPrinter implements Printer {
  const AdapterPrinter({
    required this.adapter,
    required this.profile,
    required this.transport,
  });

  final PrintAdapter adapter;
  final PrinterProfile profile;
  final PrintTransport transport;

  @override
  Future<PrintResult> printDocument(PrintDocument document) {
    final bytes = adapter.encode(document, profile);
    return transport.send(bytes);
  }
}

/// A test/double [Printer] that records documents without encoding or hardware
/// (RF-070). Proves the printing pipeline is substitutable (AC1 / RISK R-001).
class FakePrinter implements Printer {
  final List<PrintDocument> printed = [];

  @override
  Future<PrintResult> printDocument(PrintDocument document) async {
    printed.add(document);
    return const PrintResult.success();
  }
}
