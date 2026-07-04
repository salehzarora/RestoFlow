import 'dart:convert';
import 'dart:io';

import 'printer_target.dart';

/// The bridge's local configuration (RF-115).
///
/// With NO targets the bridge runs in DEMO SINK mode (accepts + counts jobs but
/// never touches hardware). With one or more `role -> host:port` targets it
/// forwards ESC/POS bytes over RAW 9100.
class BridgeConfig {
  BridgeConfig({
    Map<String, PrinterTarget>? targets,
    this.maxPayloadBytes = 1024 * 1024,
    this.host = '127.0.0.1',
    this.port = 8787,
  }) : targets = Map.unmodifiable(targets ?? const {});

  /// role/printer name -> target. Empty => sink mode.
  final Map<String, PrinterTarget> targets;

  /// Reject payloads larger than this (guards against pathological jobs).
  final int maxPayloadBytes;

  /// The LOOPBACK host to bind (default 127.0.0.1). Only loopback is permitted
  /// (validated in [fromArgs]); the server binds loopback regardless (never
  /// 0.0.0.0), so the bridge can never be reached off the machine.
  final String host;

  /// The loopback port to bind.
  final int port;

  bool get sinkMode => targets.isEmpty;

  List<String> get printerNames => targets.keys.toList(growable: false);

  /// The base URL a local caller (the POS/KDS) uses to reach the bridge.
  String urlForPort(int boundPort) => 'http://$host:$boundPort';

  /// A short, honest mode label for the startup banner + health.
  String get modeLabel => sinkMode ? 'DEMO SINK' : 'TCP (RAW 9100)';

  /// A one-line honest description of what jobs actually do in this mode.
  String get modeDescription => sinkMode
      ? 'jobs are accepted but NOT sent to any printer (nothing prints)'
      : 'forwards ESC/POS bytes to the configured printer(s)';

  /// `name -> host:port` lines for the banner (empty in sink mode).
  List<String> get printerLines => [
    for (final e in targets.entries) '${e.key} -> ${e.value}',
  ];

  static const Set<String> _loopbackHosts = {
    '127.0.0.1',
    'localhost',
    '::1',
    '0:0:0:0:0:0:0:1',
  };

  static bool _isLoopbackHost(String h) {
    final low = h.toLowerCase();
    return _loopbackHosts.contains(low) || low.startsWith('127.');
  }

  /// Parses CLI args (see `--help` / kPrintBridgeUsage). Unknown options throw
  /// [FormatException] so typos fail loudly instead of silently starting a
  /// mis-configured server. `--help` is handled by the caller BEFORE this.
  factory BridgeConfig.fromArgs(List<String> args) {
    final targets = <String, PrinterTarget>{};
    var port = 8787;
    var maxBytes = 1024 * 1024;
    var host = '127.0.0.1';
    var printerName = 'default';
    var demoRequested = false;
    String? configPath;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String next(String forFlag) {
        if (i + 1 >= args.length) {
          throw FormatException('$forFlag needs a value');
        }
        return args[++i];
      }

      switch (arg) {
        case '--help':
        case '-h':
          // Defensive: the entry point handles help first, but never treat it
          // as an unknown option here.
          break;
        case '--demo':
        case '--sink':
          demoRequested = true;
        case '--printer-name':
          printerName = next('--printer-name');
        case '--target':
          final value = next('--target');
          final eq = value.indexOf('=');
          if (eq > 0) {
            targets[value.substring(0, eq)] = PrinterTarget.parse(
              value.substring(eq + 1),
            );
          } else if (eq == 0) {
            throw FormatException('expected name=host:port', value);
          } else {
            // no name given -> use --printer-name (default "default").
            targets[printerName] = PrinterTarget.parse(value);
          }
        case '--host':
          host = next('--host');
          if (!_isLoopbackHost(host)) {
            throw FormatException(
              'print_bridge is LOCAL-ONLY; --host must be a loopback address '
              '(127.0.0.1 / localhost / ::1)',
              host,
            );
          }
        case '--config':
          configPath = next('--config');
        case '--port':
          port = _parseInt(next('--port'), '--port');
        case '--max-bytes':
          maxBytes = _parseInt(next('--max-bytes'), '--max-bytes');
        default:
          throw FormatException('unknown option', arg);
      }
    }

    if (demoRequested && targets.isNotEmpty) {
      throw const FormatException(
        '--demo/--sink cannot be combined with --target (a sink prints nothing)',
      );
    }

    if (configPath != null) {
      final fromFile = BridgeConfig.fromJson(
        jsonDecode(File(configPath).readAsStringSync()) as Map<String, Object?>,
      );
      // CLI --target entries override / merge onto the file config.
      return BridgeConfig(
        targets: {...fromFile.targets, ...targets},
        maxPayloadBytes: targets.isEmpty ? fromFile.maxPayloadBytes : maxBytes,
        host: host,
        port: port,
      );
    }

    return BridgeConfig(
      targets: targets,
      maxPayloadBytes: maxBytes,
      host: host,
      port: port,
    );
  }

  static int _parseInt(String value, String forFlag) {
    final n = int.tryParse(value);
    if (n == null) throw FormatException('$forFlag must be an integer', value);
    return n;
  }

  /// Parses a JSON config:
  ///   { "targets": { "grill": "192.0.2.50:9100" }, "maxPayloadBytes": 1048576,
  ///     "port": 8787 }
  factory BridgeConfig.fromJson(Map<String, Object?> json) {
    final targets = <String, PrinterTarget>{};
    final rawTargets = json['targets'];
    if (rawTargets is Map) {
      rawTargets.forEach((key, value) {
        targets['$key'] = PrinterTarget.parse('$value');
      });
    }
    return BridgeConfig(
      targets: targets,
      maxPayloadBytes:
          (json['maxPayloadBytes'] as num?)?.toInt() ?? 1024 * 1024,
      port: (json['port'] as num?)?.toInt() ?? 8787,
    );
  }
}
