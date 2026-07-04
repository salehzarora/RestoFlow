import 'dart:typed_data';

import '../print_result.dart';
import '../transport/print_transport.dart';
import 'print_bridge_client.dart';

/// A [PrintTransport] that delivers bytes through a local [PrintBridgeClient]
/// (RF-115), so the existing packages/printing pipeline
/// (`EscPosPrintAdapter.encode(document, profile) -> bytes -> transport`) can
/// drive a real printer through the bridge.
///
/// HONESTY NOTE: [PrintResult] has only success/failure — it cannot carry the
/// three-way bridge distinction. Both `sentToPrinter` AND `accepted` (a demo
/// sink) map to [PrintResult.success] here because both delivered the bytes to
/// the bridge. Callers that must distinguish "actually sent to a printer" from
/// "accepted by a demo sink" use [PrintBridgeClient.submit] directly (the POS/
/// KDS print controllers do exactly that, and label the difference honestly).
class PrintBridgeTransport implements PrintTransport {
  const PrintBridgeTransport(this.client, {this.role});

  final PrintBridgeClient client;

  /// The optional printer role (`'receipt'`/`'kitchen'`) forwarded per send.
  final String? role;

  @override
  Future<PrintResult> send(Uint8List bytes) async {
    final result = await client.submit(bytes: bytes, role: role);
    switch (result.outcome) {
      case BridgeSubmitOutcome.sentToPrinter:
      case BridgeSubmitOutcome.accepted:
        return const PrintResult.success();
      case BridgeSubmitOutcome.failed:
        return PrintResult.failure(
          result.category ?? PrinterErrorCategory.unknown,
          result.message,
        );
    }
  }

  @override
  Future<void> dispose() async {}
}
