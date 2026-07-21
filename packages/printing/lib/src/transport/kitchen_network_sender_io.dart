import 'dart:io';

import 'kitchen_network_sender.dart';

/// Native (`dart:io`) connector for the phase-aware kitchen sender. Linked
/// ONLY behind `dart.library.io` — web builds get the stub.
KitchenSocketConnector? platformKitchenSocketConnector() =>
    (String host, int port, Duration timeout) async => _IoKitchenSendSocket(
      await Socket.connect(host, port, timeout: timeout),
    );

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
