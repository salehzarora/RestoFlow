import 'dart:async';
import 'dart:io';

import 'package:print_bridge/print_bridge.dart';

/// RestoFlow reference LOCAL print bridge (RF-115).
///
/// Usage:
///   dart run print_bridge                              # demo SINK mode
///   dart run print_bridge --target grill=192.0.2.50:9100
///   dart run print_bridge --config bridge.config.json --port 8787
///
/// Binds 127.0.0.1 ONLY. The printer LAN target lives here, never in the app.
Future<void> main(List<String> args) async {
  final BridgeConfig config;
  try {
    config = BridgeConfig.fromArgs(args);
  } on FormatException catch (e) {
    stderr.writeln('print_bridge: bad arguments: ${e.message}');
    exitCode = 64; // EX_USAGE
    return;
  }

  final server = BridgeServer(BridgeHandler(config: config));
  await server.start(port: config.port);

  stdout.writeln(
    'RestoFlow print bridge (RF-115) listening on '
    'http://127.0.0.1:${server.port}',
  );
  stdout.writeln(
    '  mode:     ${config.sinkMode ? 'SINK (demo — jobs are NOT sent to hardware)' : 'TCP (RAW 9100)'}',
  );
  stdout.writeln(
    '  printers: ${config.printerNames.isEmpty ? '(none)' : config.printerNames.join(', ')}',
  );
  stdout.writeln('  LOCAL-ONLY: bound to loopback (127.0.0.1), never 0.0.0.0.');
  stdout.writeln('  Press Ctrl+C to stop.');

  final done = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nprint_bridge: shutting down…');
    await server.stop();
    if (!done.isCompleted) done.complete();
  });
  await done.future;
}
