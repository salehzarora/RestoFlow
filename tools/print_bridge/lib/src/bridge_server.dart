import 'dart:convert';
import 'dart:io';

import 'bridge_handler.dart';

/// The LOOPBACK-ONLY HTTP transport around a [BridgeHandler] (RF-115).
///
/// Binds `127.0.0.1` only (never `0.0.0.0`), sends permissive CORS headers so a
/// local Flutter-web app can call it, and answers OPTIONS preflight. It owns no
/// printer logic — that is the injected [BridgeHandler].
class BridgeServer {
  BridgeServer(this.handler);

  final BridgeHandler handler;
  HttpServer? _server;

  /// The bound port (0 before [start]).
  int get port => _server?.port ?? 0;

  /// Binds loopback IPv4 on [port] and starts serving.
  Future<void> start({int port = 8787}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_onRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _onRequest(HttpRequest req) async {
    final res = req.response;
    _applyCors(req, res);
    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }
      if (req.method == 'GET' && req.uri.path == '/health') {
        await _writeJson(res, handler.health());
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/print') {
        final raw = await utf8.decoder.bind(req).join();
        Map<String, Object?> body;
        try {
          body = (jsonDecode(raw) as Map).cast<String, Object?>();
        } catch (_) {
          await _writeJson(
            res,
            const BridgeResponse(400, {
              'ok': false,
              'error': 'invalid json body',
              'category': 'unknown',
            }),
          );
          return;
        }
        await _writeJson(res, await handler.print(body));
        return;
      }
      await _writeJson(
        res,
        const BridgeResponse(404, {
          'ok': false,
          'error': 'not found',
          'category': 'unknown',
        }),
      );
    } catch (e) {
      await _writeJson(
        res,
        BridgeResponse(
            500, {'ok': false, 'error': '$e', 'category': 'unknown'}),
      );
    }
  }

  /// Permissive CORS for LOCAL callers only: the server binds loopback, so only
  /// local origins can reach it. A localhost `Origin` is reflected; anything
  /// else falls back to `*` (non-credentialed).
  void _applyCors(HttpRequest req, HttpResponse res) {
    final origin = req.headers.value('origin');
    final allow = (origin != null && _isLocalOrigin(origin)) ? origin : '*';
    res.headers.set('Access-Control-Allow-Origin', allow);
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'content-type');
    res.headers.set('Vary', 'Origin');
  }

  static bool _isLocalOrigin(String origin) {
    try {
      final host = Uri.parse(origin).host.toLowerCase();
      return host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '::1' ||
          host.endsWith('.localhost');
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeJson(HttpResponse res, BridgeResponse r) async {
    res.statusCode = r.status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(r.json));
    await res.close();
  }
}
