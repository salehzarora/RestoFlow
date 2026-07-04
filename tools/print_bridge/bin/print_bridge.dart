import 'dart:async';
import 'dart:io';

import 'package:print_bridge/print_bridge.dart';

/// RestoFlow reference LOCAL print bridge (RF-115).
///
///   dart run print_bridge --help                 # usage, then exit
///   dart run print_bridge --demo                 # demo SINK (prints nothing)
///   dart run print_bridge --target 192.0.2.10:9100
///   dart run print_bridge --target grill=192.0.2.11:9100 --port 8787
///
/// Binds a loopback address ONLY. The printer LAN target lives here, never in
/// the app. Ctrl+C shuts the server down and exits.
Future<void> main(List<String> args) async {
  // --help is handled FIRST: it prints usage and exits WITHOUT starting a server.
  if (isHelpRequested(args)) {
    stdout.write(kPrintBridgeUsage);
    return;
  }

  final BridgeConfig config;
  try {
    config = BridgeConfig.fromArgs(args);
  } on FormatException catch (e) {
    final detail = e.source == null ? e.message : '${e.message}: ${e.source}';
    stderr.writeln('print_bridge: $detail');
    stderr.writeln('Try: dart run print_bridge --help');
    exitCode = 64; // EX_USAGE
    return;
  }

  final server = BridgeServer(BridgeHandler(config: config));
  await server.start(host: config.host, port: config.port);
  final url = config.urlForPort(server.port);

  stdout.writeln('RestoFlow print bridge (RF-115)');
  stdout.writeln('  URL:      $url   (LOCAL-ONLY — bound to loopback)');
  stdout.writeln('  mode:     ${config.modeLabel} — ${config.modeDescription}');
  if (config.sinkMode) {
    stdout.writeln(
      '            WARNING: nothing prints. Pass --target <host:port> '
      'for a real ESC/POS printer.',
    );
    stdout.writeln('  printers: (none — demo sink)');
  } else {
    stdout.writeln('  printers:');
    for (final line in config.printerLines) {
      stdout.writeln('            $line');
    }
  }
  stdout.writeln('  Point the POS/KDS at it (loopback only):');
  stdout.writeln(
    '    flutter run -d chrome --dart-define=RESTOFLOW_PRINT_BRIDGE_URL=$url',
  );
  stdout.writeln('  Press Ctrl+C to stop.');

  // Clean shutdown on Ctrl+C: runBridge cancels its signal subscription (the
  // un-cancelled subscription was what kept the isolate alive and hung the
  // process) and closes the server. exit(0) then guarantees termination even if
  // a platform keeps an event source alive after a clean shutdown.
  await runBridge(
    server,
    interrupts: ProcessSignal.sigint.watch().map<void>((_) {}),
    onLog: stdout.writeln,
  );
  exit(0);
}
