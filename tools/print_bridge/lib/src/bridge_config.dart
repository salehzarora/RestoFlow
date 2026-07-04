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
    this.port = 8787,
  }) : targets = Map.unmodifiable(targets ?? const {});

  /// role/printer name -> target. Empty => sink mode.
  final Map<String, PrinterTarget> targets;

  /// Reject payloads larger than this (guards against pathological jobs).
  final int maxPayloadBytes;

  /// The loopback port to bind.
  final int port;

  bool get sinkMode => targets.isEmpty;

  List<String> get printerNames => targets.keys.toList(growable: false);

  /// Parses CLI args:
  ///   --target name=host:port   (repeatable)
  ///   --config path.json
  ///   --port 8787
  ///   --max-bytes 1048576
  factory BridgeConfig.fromArgs(List<String> args) {
    final targets = <String, PrinterTarget>{};
    var port = 8787;
    var maxBytes = 1024 * 1024;
    String? configPath;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? next() => (i + 1 < args.length) ? args[++i] : null;
      switch (arg) {
        case '--target':
          final value = next();
          if (value == null)
            throw const FormatException('--target needs a value');
          final eq = value.indexOf('=');
          if (eq <= 0) {
            throw FormatException('expected name=host:port', value);
          }
          targets[value.substring(0, eq)] = PrinterTarget.parse(
            value.substring(eq + 1),
          );
        case '--config':
          configPath = next();
        case '--port':
          port = int.parse(next() ?? '8787');
        case '--max-bytes':
          maxBytes = int.parse(next() ?? '$maxBytes');
      }
    }

    if (configPath != null) {
      final fromFile = BridgeConfig.fromJson(
        jsonDecode(File(configPath).readAsStringSync()) as Map<String, Object?>,
      );
      // CLI --target entries override / merge onto the file config.
      return BridgeConfig(
        targets: {...fromFile.targets, ...targets},
        maxPayloadBytes: targets.isEmpty ? fromFile.maxPayloadBytes : maxBytes,
        port: port,
      );
    }

    return BridgeConfig(
        targets: targets, maxPayloadBytes: maxBytes, port: port);
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
