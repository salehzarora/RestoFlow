import 'dart:typed_data';

import '../print_result.dart';

/// The transports a printer can (eventually) be reached over (RF-070, §3).
enum PrintConnectivity { inMemory, network, usb, bluetooth }

/// Thrown when a transport that RF-070 does not implement is requested.
///
/// RF-070 ships ONLY the in-memory transport; real network/USB/Bluetooth are
/// deferred (RF-071 or a dedicated transport ticket, approved A3). This fails
/// clearly rather than silently doing nothing.
class UnsupportedTransportException implements Exception {
  const UnsupportedTransportException(this.connectivity, [this.message]);

  final PrintConnectivity connectivity;
  final String? message;

  @override
  String toString() =>
      'UnsupportedTransportException(${connectivity.name}: '
      '${message ?? 'transport not implemented in RF-070; deferred (RF-071+)'})';
}

/// A byte sink that delivers encoded bytes to a printer (RF-070, §13.1 layer 3).
///
/// Reports best-effort success/failure as a [PrintResult]; it owns no job
/// identity, retry, or persistence (that is the RF-071 spool).
abstract class PrintTransport {
  Future<PrintResult> send(Uint8List bytes);

  /// Release any resources. No-op for the in-memory transport.
  Future<void> dispose();
}
