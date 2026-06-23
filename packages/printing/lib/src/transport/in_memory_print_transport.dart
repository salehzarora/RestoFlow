import 'dart:typed_data';

import '../print_result.dart';
import 'print_transport.dart';

/// An in-memory [PrintTransport] (RF-070): captures every sent byte batch
/// instead of touching hardware. The only transport RF-070 ships — it makes the
/// pipeline fully testable with no sockets/USB/Bluetooth (approved A3).
class InMemoryPrintTransport implements PrintTransport {
  final List<Uint8List> _batches = [];

  /// Each `send` call's bytes, in order.
  List<Uint8List> get batches => List.unmodifiable(_batches);

  /// The most recently sent bytes, or null if nothing has been sent.
  Uint8List? get lastBytes => _batches.isEmpty ? null : _batches.last;

  /// All sent bytes concatenated (handy for golden assertions across a job).
  Uint8List get allBytes {
    final out = BytesBuilder(copy: false);
    for (final b in _batches) {
      out.add(b);
    }
    return out.toBytes();
  }

  @override
  Future<PrintResult> send(Uint8List bytes) async {
    _batches.add(Uint8List.fromList(bytes));
    return const PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

/// Returns the transport for [connectivity] (RF-070).
///
/// Only [PrintConnectivity.inMemory] is implemented; network/USB/Bluetooth throw
/// [UnsupportedTransportException] so an unsupported config fails clearly
/// (approved A3). No sockets are opened and no USB/BT libraries are referenced.
PrintTransport transportFor(PrintConnectivity connectivity) {
  switch (connectivity) {
    case PrintConnectivity.inMemory:
      return InMemoryPrintTransport();
    case PrintConnectivity.network:
    case PrintConnectivity.usb:
    case PrintConnectivity.bluetooth:
      throw UnsupportedTransportException(connectivity);
  }
}
