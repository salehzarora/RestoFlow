/// RestoFlow reference LOCAL print bridge (RF-115).
///
/// A tiny, self-contained, LOOPBACK-ONLY HTTP companion service that a
/// Flutter-web POS/KDS app POSTs ESC/POS print jobs to. It either forwards the
/// bytes to a configured RAW 9100 (host:port) printer target, or — with no
/// target — accepts them into a DEMO SINK and honestly reports that they did NOT
/// reach hardware.
///
/// SECURITY: the printer LAN target lives ONLY in THIS bridge's local flags /
/// config — never in the app or the server. The bridge binds 127.0.0.1 only,
/// never 0.0.0.0.
library;

export 'src/bridge_config.dart';
export 'src/cli.dart';
export 'src/bridge_handler.dart';
export 'src/bridge_server.dart';
export 'src/printer_socket.dart';
export 'src/printer_target.dart';
export 'src/runner.dart';
