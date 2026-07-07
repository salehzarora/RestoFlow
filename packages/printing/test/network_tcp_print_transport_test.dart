import 'dart:io';
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// ANDROID-002: the native network (TCP/RAW 9100) ESC/POS transport actually
/// delivers bytes to a listening socket, and fails clearly — never throws,
/// never hangs — when the printer is unreachable.
void main() {
  group('NetworkTcpPrintTransport (dart:io)', () {
    test('delivers the exact bytes to a listening printer and reports '
        'success', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      final gotAll = server.first.then((socket) async {
        await for (final chunk in socket) {
          received.addAll(chunk);
        }
        await socket.close();
      });

      final transport = NetworkTcpPrintTransport(
        host: '127.0.0.1',
        port: server.port,
        timeout: const Duration(seconds: 2),
      );
      final payload = Uint8List.fromList([0x1B, 0x40, 0x41, 0x42, 0x43, 0x0A]);
      final result = await transport.send(payload);

      expect(result.ok, isTrue, reason: result.toString());
      await gotAll;
      expect(received, payload);
      await transport.dispose();
      await server.close();
    });

    test('default port is the RAW/JetDirect 9100', () {
      expect(kEscPosNetworkDefaultPort, 9100);
      expect(NetworkTcpPrintTransport(host: '10.0.0.1').port, 9100);
    });

    test('an unreachable printer fails clearly (unreachable), never throws '
        'or hangs', () async {
      // Bind then immediately release a port so connecting to it is refused.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();

      final transport = NetworkTcpPrintTransport(
        host: '127.0.0.1',
        port: deadPort,
        timeout: const Duration(seconds: 2),
      );
      final result = await transport.send(Uint8List.fromList([1, 2, 3]));

      expect(result.ok, isFalse);
      expect(result.category, PrinterErrorCategory.unreachable);
      await transport.dispose();
    });
  });
}
