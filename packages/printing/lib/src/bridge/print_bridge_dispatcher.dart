import '../escpos/escpos_print_adapter.dart';
import '../print_adapter.dart';
import '../print_document.dart';
import '../printer_profile.dart';
import 'print_bridge_client.dart';

/// Encodes a render-neutral [PrintDocument] to ESC/POS bytes and submits them
/// to a local print bridge (RF-115).
///
/// This is the single seam an app wires to turn a prepared document into a real
/// (or sink) print: `dispatch(document)` runs `adapter.encode(document, profile)`
/// then `client.submit(bytes)`, returning the HONEST [BridgeSubmitResult]. It
/// performs NO money math (the caller supplies a fully pre-formatted document —
/// DECISION D-007/D-008).
class PrintBridgeDispatcher {
  const PrintBridgeDispatcher({
    required this.client,
    this.profile = PrinterProfile.escPos80mm,
    this.adapter = const EscPosPrintAdapter(),
  });

  final PrintBridgeClient client;
  final PrinterProfile profile;
  final PrintAdapter adapter;

  /// Probes the bridge's reachability.
  Future<BridgeHealth> health() => client.health();

  /// Encodes [document] for [profile] and submits the bytes to the bridge.
  Future<BridgeSubmitResult> dispatch(PrintDocument document) {
    final bytes = adapter.encode(document, profile);
    return client.submit(bytes: bytes);
  }
}
