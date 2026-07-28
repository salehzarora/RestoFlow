@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-BRANDING-LOGO-001 (§6) — the RAW TCP transport stays CONSERVATIVE with a
/// REAL loopback socket: a successful send delivers the payload EXACTLY once (one
/// socket, no second send); a connect failure is a pre-dispatch failure that sent
/// nothing. Proven on real bytes over 127.0.0.1, not a fake.
void main() {
  test(
    'success delivers the payload EXACTLY once and marks completed',
    () async {
      var connections = 0;
      final buffer = <int>[];
      final gotAll = Completer<void>();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        connections++;
        socket.listen(
          buffer.addAll,
          onDone: () {
            if (!gotAll.isCompleted) gotAll.complete();
          },
        );
      });

      final transport = NetworkTcpPrintTransport(
        host: server.address.address,
        port: server.port,
        timeout: const Duration(seconds: 2),
      );
      final payload = Uint8List.fromList(List.generate(1000, (i) => i % 251));

      final result = await transport.send(payload);
      await gotAll.future.timeout(const Duration(seconds: 2));
      await transport.dispose();
      await server.close();

      expect(result.ok, isTrue);
      expect(result.sendStarted, isTrue);
      expect(result.physicalOutcome, PrintPhysicalOutcome.completed);
      expect(connections, 1, reason: 'exactly one socket payload attempt');
      expect(buffer, orderedEquals(payload), reason: 'exact bytes, no framing');
    },
  );

  test('a connect failure is a PRE-dispatch failure (nothing sent)', () async {
    // Bind then immediately close to obtain a port that refuses connections.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close();

    final transport = NetworkTcpPrintTransport(
      host: '127.0.0.1',
      port: deadPort,
      timeout: const Duration(milliseconds: 500),
    );
    final result = await transport.send(Uint8List.fromList([1, 2, 3, 4]));
    await transport.dispose();

    expect(result.ok, isFalse);
    expect(result.category, PrinterErrorCategory.unreachable);
    expect(
      result.sendStarted,
      isFalse,
      reason: 'connect failed before any byte left',
    );
    expect(result.physicalOutcome, PrintPhysicalOutcome.failedBeforeDispatch);
    expect(result.bytesSent, isNull);
  });
}
