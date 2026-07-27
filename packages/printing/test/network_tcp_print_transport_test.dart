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

    // PILOT-PRINT-FIDELITY-001: a full rasterized receipt buffer — init,
    // ONE GS v 0 with every image row, then feed, then cut — arrives
    // complete and IN ORDER; flush drains before close, so the body rows
    // can never be dropped while a later trailer still prints.
    test('a full raster receipt buffer arrives complete and ordered '
        '(image rows, then feed, then cut)', () async {
      final rasterizer = FakeReceiptRasterizer();
      final doc = await rasterizeTextDocument(
        PrintDocument([for (var i = 0; i < 60; i++) PrintTextLine('سطر $i')]),
        rasterizer: rasterizer,
      );
      final image = await rasterizer.rasterize(rasterizer.requests.first);
      final bytes = const EscPosPrintAdapter().encode(
        doc,
        PrinterProfile.escPos80mm,
      );

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
        timeout: const Duration(seconds: 5),
      );
      final result = await transport.send(Uint8List.fromList(bytes));
      expect(result.ok, isTrue, reason: result.toString());
      await gotAll;

      // Complete: every byte, byte-identical.
      expect(received, bytes);
      // Ordered: header → payload (all rows) → feed → cut.
      final at = _indexOfSeq(received, const [0x1D, 0x76, 0x30, 0x00]);
      expect(at, isNonNegative);
      final payloadEnd = at + 8 + image.widthBytes * image.heightDots;
      expect(
        received.sublist(at + 8, payloadEnd),
        image.data,
        reason: 'every raster row must arrive, in order',
      );
      final feedAt = _indexOfSeq(received.sublist(payloadEnd), const [
        0x1B,
        0x64,
      ]);
      final cutAt = _indexOfSeq(received.sublist(payloadEnd), const [
        0x1D,
        0x56,
      ]);
      expect(feedAt, isNonNegative);
      expect(cutAt, isNonNegative);
      expect(feedAt, lessThan(cutAt));
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

int _indexOfSeq(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
