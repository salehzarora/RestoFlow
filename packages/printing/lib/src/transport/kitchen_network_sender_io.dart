import 'dart:async';
import 'dart:io';

import 'kitchen_network_sender.dart';

/// Native (`dart:io`) connector for the phase-aware kitchen sender. Linked
/// ONLY behind `dart.library.io` — web builds get the stub.
KitchenSocketConnector? platformKitchenSocketConnector() =>
    (String host, int port, Duration timeout) =>
        boundedKitchenSocketConnect(host, port, timeout);

/// KITCHEN-MODE-001C2C F1 — the EXPLICIT bounded connect.
///
/// `Socket.connect(..., timeout:)` reports its internal timeout as a
/// [SocketException], which the phase classifier could not distinguish from
/// a refusal — making `timeoutBeforeWrite` unreachable on the real path.
/// This races the raw connect against Dart's own `.timeout` instead, so a
/// REAL connect timeout surfaces as [TimeoutException] (→
/// `timeoutBeforeWrite`, retry-safe: no byte was handed over) while a
/// refusal stays a [SocketException] (→ `definitelyNotSent`). A LATE
/// connect completion after the timeout is destroyed quietly — no leak, no
/// double-completion (the outer future has already completed with the
/// timeout), no unhandled async error.
Future<KitchenSendSocket> boundedKitchenSocketConnect(
  String host,
  int port,
  Duration timeout, {
  Future<Socket> Function(String host, int port)? rawConnect,
}) async {
  final pending = (rawConnect ?? Socket.connect)(host, port);
  try {
    final socket = await pending.timeout(timeout);
    return _IoKitchenSendSocket(socket);
  } on TimeoutException {
    unawaited(
      pending.then((socket) => socket.destroy()).catchError((Object _) {}),
    );
    rethrow;
  }
}

class _IoKitchenSendSocket implements KitchenSendSocket {
  _IoKitchenSendSocket(this._socket);

  final Socket _socket;

  @override
  void add(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();
}
