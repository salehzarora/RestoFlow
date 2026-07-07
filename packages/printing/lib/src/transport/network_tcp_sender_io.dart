import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../print_result.dart';

/// Native (`dart:io`) sender: opens a raw TCP socket to `host:port`, writes the
/// already-encoded ESC/POS [bytes], and closes (ANDROID-002).
///
/// This is the RAW / JetDirect path most Wi-Fi/Ethernet thermal printers expose
/// on port 9100. Best-effort by contract (see [PrintResult]): success means the
/// bytes were flushed to the OS socket, NOT a hardware paper-print ack (ESC/POS
/// over a socket has none). Every failure mode (connect refused, host
/// unreachable, timeout) is mapped to a [PrintResult.failure] — it never throws
/// to the caller and never blocks indefinitely (connect + flush are bounded by
/// [timeout]).
Future<PrintResult> sendEscPosOverTcp({
  required String host,
  required int port,
  required Uint8List bytes,
  required Duration timeout,
}) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    // Don't wait on inbound status bytes; RAW printing is write-only.
    socket.add(bytes);
    // flush() completing = the bytes were handed to the OS -> best-effort
    // delivered. Bound it so a printer that accepts the TCP connection but
    // never drains can't hang the UI.
    await socket.flush().timeout(timeout);
    // Close politely, but delivery is already decided by the flush above, so a
    // slow/rude close must not turn a delivered print into a false failure.
    try {
      await socket.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // ignore: bytes were already flushed.
    }
    return const PrintResult.success();
  } on SocketException catch (e) {
    return PrintResult.failure(
      PrinterErrorCategory.unreachable,
      'socket: ${e.osError?.message ?? e.message}',
    );
  } on TimeoutException {
    return PrintResult.failure(
      PrinterErrorCategory.unreachable,
      'timed out after ${timeout.inMilliseconds}ms',
    );
  } catch (e) {
    return PrintResult.failure(PrinterErrorCategory.unknown, e.toString());
  } finally {
    socket?.destroy();
  }
}
