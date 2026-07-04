import 'dart:convert';

import 'bridge_config.dart';
import 'printer_socket.dart';
import 'printer_target.dart';

/// A bridge HTTP response: a status code + a JSON body.
class BridgeResponse {
  const BridgeResponse(this.status, this.json);
  final int status;
  final Map<String, Object?> json;
}

/// The bridge request logic, separated from the HTTP transport so it is fully
/// unit-testable (inject a fake [PrinterSocket]; no real server needed).
class BridgeHandler {
  BridgeHandler({
    required this.config,
    PrinterSocket? socket,
    this.timeout = const Duration(seconds: 5),
  }) : socket = socket ?? const RawTcpPrinterSocket();

  final BridgeConfig config;
  final PrinterSocket socket;
  final Duration timeout;

  int _sinkCount = 0;

  /// Number of jobs accepted by the demo sink (for diagnostics/tests).
  int get sinkCount => _sinkCount;

  /// `GET /health`.
  BridgeResponse health() => BridgeResponse(200, {
    'ok': true,
    'mode': config.sinkMode ? 'sink' : 'tcp',
    'printers': config.printerNames,
  });

  /// `POST /print` with `{format:'escpos', payloadBase64, role?/printer?}`.
  ///
  /// Sink mode => `accepted_sink` (HONESTLY not sent to hardware). TCP mode =>
  /// `sent` on a confirmed write, or a `{ok:false, category:'unreachable'}` on a
  /// transport failure. NEVER claims a physical print it cannot confirm.
  Future<BridgeResponse> print(Map<String, Object?> body) async {
    if (body['format'] != 'escpos') {
      return _error(400, 'unsupported format', 'unsupported');
    }
    final payloadBase64 = body['payloadBase64'];
    if (payloadBase64 is! String || payloadBase64.isEmpty) {
      return _error(400, 'missing payloadBase64', 'unknown');
    }
    final List<int> bytes;
    try {
      bytes = base64Decode(payloadBase64);
    } catch (_) {
      return _error(400, 'invalid base64 payload', 'unknown');
    }
    if (bytes.isEmpty) return _error(400, 'empty payload', 'unknown');
    if (bytes.length > config.maxPayloadBytes) {
      return _error(413, 'payload exceeds max bytes', 'unsupported');
    }

    if (config.sinkMode) {
      _sinkCount++;
      return const BridgeResponse(200, {
        'ok': true,
        'status': 'accepted_sink',
        'mode': 'sink',
        'note': 'accepted (demo sink — not sent to hardware)',
      });
    }

    final role = (body['role'] ?? body['printer'])?.toString();
    final target = _resolveTarget(role);
    if (target == null) {
      return _error(404, 'no target for role "$role"', 'unsupported');
    }
    try {
      await socket.send(target.host, target.port, bytes, timeout: timeout);
      return const BridgeResponse(200, {
        'ok': true,
        'status': 'sent',
        'mode': 'tcp',
      });
    } on PrinterSocketException catch (e) {
      return _error(502, 'transport failure: ${e.message}', 'unreachable');
    } catch (e) {
      return _error(502, 'transport failure: $e', 'unreachable');
    }
  }

  PrinterTarget? _resolveTarget(String? role) {
    if (role != null && config.targets.containsKey(role)) {
      return config.targets[role];
    }
    if (config.targets.isNotEmpty) return config.targets.values.first;
    return null;
  }

  BridgeResponse _error(int status, String error, String category) =>
      BridgeResponse(status, {
        'ok': false,
        'error': error,
        'category': category,
      });
}
