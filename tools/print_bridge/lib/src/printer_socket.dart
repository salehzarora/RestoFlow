import 'dart:io';

/// Writes ESC/POS bytes to a printer over a RAW TCP (9100) socket.
///
/// Injected so the bridge handler is unit-testable with no real sockets.
/// A [PrinterSocketException] means the bytes were NOT delivered.
abstract class PrinterSocket {
  Future<void> send(
    String host,
    int port,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 5),
  });
}

/// Thrown when the bytes could not be written to the printer transport.
class PrinterSocketException implements Exception {
  const PrinterSocketException(this.message);
  final String message;
  @override
  String toString() => 'PrinterSocketException: $message';
}

/// The real RAW 9100 socket writer (`dart:io`).
class RawTcpPrinterSocket implements PrinterSocket {
  const RawTcpPrinterSocket();

  @override
  Future<void> send(
    String host,
    int port,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
    } on SocketException catch (e) {
      throw PrinterSocketException(e.message);
    } finally {
      socket?.destroy();
    }
  }
}
