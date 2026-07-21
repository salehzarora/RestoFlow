@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:restoflow_printing/src/transport/kitchen_network_sender_io.dart';
import 'package:test/test.dart';

/// KITCHEN-MODE-001C2C F1 — the REAL native connect path must surface a
/// connect timeout as `timeoutBeforeWrite` (retry-safe: zero bytes), not a
/// generic unreachable/retryable branch, and must never leak a late socket.
void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('an ACTUAL connect timeout through the native seam classifies as '
      'timeoutBeforeWrite', () async {
    final outcome = await sendKitchenBytesOverTcp(
      host: 'stalled.example',
      port: 9100,
      bytes: bytes,
      timeout: const Duration(milliseconds: 60),
      connect: (host, port, timeout) => boundedKitchenSocketConnect(
        host,
        port,
        timeout,
        // A raw connect that never completes = a genuinely stalled
        // network connect (deterministic stand-in for a blackholed host).
        rawConnect: (_, _) => Completer<Socket>().future,
      ),
    );
    expect(outcome.kind, KitchenTransportOutcomeKind.timeoutBeforeWrite);
    expect(outcome.reasonCode, 'connect_timeout');
    expect(outcome.isSafeToRetry, isTrue);
  });

  test('a REAL refused connection stays definitelyNotSent (loopback port '
      'with no listener)', () async {
    // Bind + close to obtain a port that is almost certainly unbound.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    final outcome = await sendKitchenBytesOverTcp(
      host: '127.0.0.1',
      port: port,
      bytes: bytes,
      timeout: const Duration(seconds: 3),
    );
    expect(outcome.kind, KitchenTransportOutcomeKind.definitelyNotSent);
    expect(outcome.reasonCode, 'connect_failed');
  });

  test('a REAL loopback send flushes and classifies accepted', () async {
    final received = <int>[];
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((client) {
      client.listen(received.addAll, onDone: client.destroy);
    });
    final outcome = await sendKitchenBytesOverTcp(
      host: '127.0.0.1',
      port: server.port,
      bytes: bytes,
      timeout: const Duration(seconds: 5),
    );
    expect(outcome.kind, KitchenTransportOutcomeKind.accepted);
    // Give the loopback delivery a moment, then verify EXACT bytes.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, bytes);
  });

  test('a LATE connect completion after the timeout is destroyed quietly '
      '(no unhandled async error, no double completion)', () async {
    final late = Completer<Socket>();
    final outcome = sendKitchenBytesOverTcp(
      host: 'late.example',
      port: 9100,
      bytes: bytes,
      timeout: const Duration(milliseconds: 40),
      connect: (host, port, timeout) => boundedKitchenSocketConnect(
        host,
        port,
        timeout,
        rawConnect: (_, _) => late.future,
      ),
    );
    expect(
      (await outcome).kind,
      KitchenTransportOutcomeKind.timeoutBeforeWrite,
    );
    // The raw connect now completes LATE with a real socket; the fix must
    // destroy it without surfacing an error into the test zone.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    late.complete(await Socket.connect('127.0.0.1', server.port));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
}
