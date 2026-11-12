// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: network denial for the card-transport
// tests. Inside [runWithoutNetwork] every new HttpClient (the SDK's HTTP and
// WebSocket paths each create one) and every Socket.connect / startConnect is
// refused with [NetworkDenied] and recorded - except, when [loopbackPort] is
// given, a direct plain-HTTP connection to 127.0.0.1 on that port (the test's
// own loopback server). RawSocket and SecureSocket connects do not consult
// these overrides; no code under test opens one directly, and an HTTPS
// HttpClient is refused before it can.
import 'dart:async';
import 'dart:io';

/// An unexpected network access in a test.
final class NetworkDenied implements Exception {
  const NetworkDenied(this.what);

  final String what;

  @override
  String toString() => 'NetworkDenied($what)';
}

/// Runs [body] with the network denied; every refused attempt is added to
/// [denied]. [beforeConnect], when given, is awaited before each allowed
/// loopback connection opens (a test's way to hold a connection mid-setup).
R runWithoutNetwork<R>(
  R Function() body, {
  required List<String> denied,
  int? loopbackPort,
  Future<void> Function()? beforeConnect,
}) => IOOverrides.runWithIOOverrides(
  () => HttpOverrides.runWithHttpOverrides(
    body,
    _DenyHttp(loopbackPort, denied, beforeConnect),
  ),
  _DenySockets(loopbackPort, denied),
);

bool _loopback(Object? host) =>
    host == '127.0.0.1' ||
    (host is InternetAddress && host.address == '127.0.0.1');

final class _DenySockets extends IOOverrides {
  _DenySockets(this._port, this._denied);

  final int? _port;
  final List<String> _denied;

  bool _allowed(Object? host, int port) =>
      _port != null && port == _port && _loopback(host);

  @override
  Future<Socket> socketConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    if (!_allowed(host, port)) {
      _denied.add('Socket.connect $host:$port');
      return Future.error(NetworkDenied('Socket.connect $host:$port'));
    }
    return super.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) {
    if (!_allowed(host, port)) {
      _denied.add('Socket.startConnect $host:$port');
      return Future.error(NetworkDenied('Socket.startConnect $host:$port'));
    }
    return super.socketStartConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
  }
}

final class _DenyHttp extends HttpOverrides {
  _DenyHttp(this._port, this._denied, this._beforeConnect);

  final int? _port;
  final List<String> _denied;
  final Future<void> Function()? _beforeConnect;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final port = _port;
    if (port == null) {
      _denied.add('HttpClient');
      throw const NetworkDenied('HttpClient');
    }
    final client = super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.scheme != 'http' || !_loopback(uri.host) || uri.port != port) {
        _denied.add('HttpClient ${uri.scheme}://${uri.host}:${uri.port}');
        return Future.error(
          NetworkDenied('HttpClient ${uri.scheme}://${uri.host}:${uri.port}'),
        );
      }
      final hold = _beforeConnect;
      if (hold == null) return Socket.startConnect(uri.host, uri.port);
      return hold().then((_) => Socket.startConnect(uri.host, uri.port));
    };
    return client;
  }
}
