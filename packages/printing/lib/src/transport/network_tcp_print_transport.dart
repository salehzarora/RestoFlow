import 'dart:typed_data';

import '../print_result.dart';
import 'print_transport.dart';
// Web-safe transport selection: the stub is the default (browsers have no
// `dart:io`); the real socket sender is linked only where `dart.library.io`
// exists (Android/iOS/desktop). This file itself never imports `dart:io`, so
// the pure-Dart printing package stays importable from the web apps.
import 'network_tcp_sender_stub.dart'
    if (dart.library.io) 'network_tcp_sender_io.dart'
    as sender;

/// The default RAW/JetDirect ESC/POS TCP port for network thermal printers.
const int kEscPosNetworkDefaultPort = 9100;

/// A [PrintTransport] that delivers ESC/POS bytes over a raw TCP socket to a
/// network (Wi-Fi/Ethernet) thermal printer at [host]:[port] (ANDROID-002).
///
/// This is the first REAL, on-device physical transport (the RF-070 network
/// transport that `transportFor` had left `UnsupportedTransportException`). It
/// needs no print bridge and no service. On web the send fails clearly (see the
/// stub sender) so nothing silently claims to print. Owns no job identity /
/// retry / persistence — that stays with the RF-071 spool / callers.
class NetworkTcpPrintTransport implements PrintTransport {
  NetworkTcpPrintTransport({
    required this.host,
    this.port = kEscPosNetworkDefaultPort,
    this.timeout = const Duration(seconds: 6),
  });

  /// The printer's IP address (or resolvable host) on the local network.
  final String host;

  /// The TCP port; 9100 (RAW/JetDirect) by default.
  final int port;

  /// Bound for connect + flush so an unreachable/half-open printer can't hang.
  final Duration timeout;

  @override
  Future<PrintResult> send(Uint8List bytes) => sender.sendEscPosOverTcp(
    host: host,
    port: port,
    bytes: bytes,
    timeout: timeout,
  );

  @override
  Future<void> dispose() async {}
}
