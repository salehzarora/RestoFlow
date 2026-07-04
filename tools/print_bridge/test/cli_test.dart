import 'dart:async';
import 'dart:io';

import 'package:print_bridge/print_bridge.dart';
import 'package:test/test.dart';

/// RF-115 CLI fixes: --help, explicit demo/sink, --host (loopback-only),
/// --target host:port + --printer-name, unknown-option rejection, an honest
/// mode summary, and a clean (non-hanging) shutdown.
void main() {
  group('--help', () {
    test('isHelpRequested detects --help / -h anywhere, not otherwise', () {
      expect(isHelpRequested(['--help']), isTrue);
      expect(isHelpRequested(['-h']), isTrue);
      expect(isHelpRequested(['--port', '8787', '--help']), isTrue);
      expect(isHelpRequested(const []), isFalse);
      expect(isHelpRequested(['--demo']), isFalse);
    });

    test('the usage text documents the key options + the POS dart-define', () {
      for (final needle in [
        'Usage:',
        '--help',
        '--demo',
        '--target',
        '--host',
        '--port',
        'RESTOFLOW_PRINT_BRIDGE_URL',
        'LOCAL-ONLY',
      ]) {
        expect(kPrintBridgeUsage, contains(needle), reason: 'missing $needle');
      }
    });
  });

  group('config parsing (new flags)', () {
    test('--demo / --sink is explicit sink mode', () {
      expect(BridgeConfig.fromArgs(['--demo']).sinkMode, isTrue);
      expect(BridgeConfig.fromArgs(['--sink']).sinkMode, isTrue);
    });

    test('no args defaults to a loopback demo sink on 8787', () {
      final c = BridgeConfig.fromArgs(const []);
      expect(c.sinkMode, isTrue);
      expect(c.host, '127.0.0.1');
      expect(c.port, 8787);
    });

    test('--host accepts loopback and --port is applied', () {
      final c = BridgeConfig.fromArgs([
        '--host',
        'localhost',
        '--port',
        '9000',
      ]);
      expect(c.host, 'localhost');
      expect(c.port, 9000);
    });

    test('--host rejects a non-loopback address (LOCAL-ONLY)', () {
      expect(
        () => BridgeConfig.fromArgs(['--host', '0.0.0.0']),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BridgeConfig.fromArgs(['--host', '8.8.8.8']),
        throwsA(isA<FormatException>()),
      );
    });

    test('--target host:port uses --printer-name (default "default")', () {
      final c = BridgeConfig.fromArgs(['--target', '192.0.2.10:9100']);
      expect(c.sinkMode, isFalse);
      expect(c.targets['default']!.host, '192.0.2.10');
      expect(c.targets['default']!.port, 9100);

      final named = BridgeConfig.fromArgs([
        '--printer-name',
        'grill',
        '--target',
        '192.0.2.11:9100',
      ]);
      expect(named.targets['grill']!.port, 9100);
    });

    test('--demo cannot be combined with --target', () {
      expect(
        () => BridgeConfig.fromArgs(['--demo', '--target', '192.0.2.10:9100']),
        throwsA(isA<FormatException>()),
      );
    });

    test('an unknown option fails loudly (does not silently start)', () {
      expect(
        () => BridgeConfig.fromArgs(['--bogus']),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BridgeConfig.fromArgs(['--port']),
        throwsA(isA<FormatException>()),
      ); // missing value
    });

    test('honest mode summary: label + description + printer lines', () {
      final sink = BridgeConfig.fromArgs(['--demo']);
      expect(sink.modeLabel, 'DEMO SINK');
      expect(sink.modeDescription, contains('NOT sent'));
      expect(sink.printerLines, isEmpty);
      expect(sink.urlForPort(8787), 'http://127.0.0.1:8787');

      final tcp = BridgeConfig.fromArgs([
        '--target',
        'receipt=192.0.2.10:9100',
      ]);
      expect(tcp.modeLabel, 'TCP (RAW 9100)');
      expect(tcp.printerLines, ['receipt -> 192.0.2.10:9100']);
    });
  });

  group('shutdown (no hang)', () {
    test(
      'stop() closes the server, frees the port, and is idempotent',
      () async {
        final server = BridgeServer(BridgeHandler(config: BridgeConfig()));
        await server.start(port: 0); // ephemeral loopback port
        final boundPort = server.port;
        expect(boundPort, greaterThan(0));

        await server.stop();
        expect(server.port, 0);

        // The port is genuinely released — a fresh bind on it succeeds.
        final rebind = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          boundPort,
        );
        await rebind.close();

        // A second stop() after already stopped must not throw/hang.
        await server.stop();
      },
    );

    test(
      'runBridge returns when the interrupt fires + stops the server',
      () async {
        final server = BridgeServer(BridgeHandler(config: BridgeConfig()));
        await server.start(port: 0);
        final interrupts = StreamController<void>();
        final logs = <String>[];
        final ran = runBridge(
          server,
          interrupts: interrupts.stream,
          onLog: logs.add,
        );

        interrupts.add(null); // simulate Ctrl+C

        // Must COMPLETE (not hang) and leave the server closed.
        await ran.timeout(const Duration(seconds: 5));
        expect(server.port, 0);
        expect(logs, contains('print_bridge: shutting down...'));
        await interrupts.close();
      },
    );
  });
}
