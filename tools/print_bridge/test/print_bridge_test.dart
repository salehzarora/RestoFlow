import 'dart:convert';
import 'dart:io';

import 'package:print_bridge/print_bridge.dart';
import 'package:test/test.dart';

/// A fake [PrinterSocket] that records writes or fails on demand — no real
/// sockets, so the transport branches are deterministic (RFC-5737 IPs only).
class _FakeSocket implements PrinterSocket {
  _FakeSocket({this.fail = false});

  final bool fail;
  final List<({String host, int port, List<int> bytes})> writes = [];

  @override
  Future<void> send(
    String host,
    int port,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (fail) {
      throw const PrinterSocketException('connection refused');
    }
    writes.add((host: host, port: port, bytes: bytes));
  }
}

String _escposB64() => base64Encode([0x1b, 0x40, 0x48, 0x69]); // init + "Hi"

void main() {
  group('health()', () {
    test('sink mode reports mode:sink and no printers', () {
      final handler = BridgeHandler(config: BridgeConfig());
      final res = handler.health();
      expect(res.status, 200);
      expect(res.json['ok'], true);
      expect(res.json['mode'], 'sink');
      expect(res.json['printers'], isEmpty);
    });

    test('tcp mode reports mode:tcp and the configured printer names', () {
      final handler = BridgeHandler(
        config: BridgeConfig(
          targets: {'receipt': PrinterTarget.parse('192.0.2.10:9100')},
        ),
      );
      final res = handler.health();
      expect(res.json['mode'], 'tcp');
      expect(res.json['printers'], ['receipt']);
    });
  });

  group('print() — sink', () {
    test('accepts into the sink and HONESTLY reports it did not reach hardware',
        () async {
      final handler = BridgeHandler(config: BridgeConfig());
      final res = await handler.print({
        'format': 'escpos',
        'payloadBase64': _escposB64(),
      });
      expect(res.status, 200);
      expect(res.json['ok'], true);
      expect(res.json['status'], 'accepted_sink');
      expect(res.json['status'], isNot('sent'));
      expect(handler.sinkCount, 1);
    });
  });

  group('print() — tcp forward', () {
    test('forwards to the target and reports sent', () async {
      final socket = _FakeSocket();
      final handler = BridgeHandler(
        config: BridgeConfig(
          targets: {'receipt': PrinterTarget.parse('192.0.2.10:9100')},
        ),
        socket: socket,
      );
      final res = await handler.print({
        'format': 'escpos',
        'role': 'receipt',
        'payloadBase64': _escposB64(),
      });
      expect(res.json['status'], 'sent');
      expect(socket.writes.single.host, '192.0.2.10');
      expect(socket.writes.single.port, 9100);
    });

    test('an unreachable target returns ok:false, category unreachable',
        () async {
      final handler = BridgeHandler(
        config: BridgeConfig(
          targets: {'receipt': PrinterTarget.parse('192.0.2.10:9100')},
        ),
        socket: _FakeSocket(fail: true),
      );
      final res = await handler.print({
        'format': 'escpos',
        'role': 'receipt',
        'payloadBase64': _escposB64(),
      });
      expect(res.json['ok'], false);
      expect(res.json['category'], 'unreachable');
    });

    test('an unknown role with no matching target is rejected', () async {
      final handler = BridgeHandler(
        config: BridgeConfig(
          targets: {'receipt': PrinterTarget.parse('192.0.2.10:9100')},
        ),
        socket: _FakeSocket(),
      );
      // A role that does not exist falls back to the first target (best effort).
      final res = await handler.print({
        'format': 'escpos',
        'role': 'nonexistent',
        'payloadBase64': _escposB64(),
      });
      expect(res.json['status'], 'sent');
    });
  });

  group('print() — rejects bad input', () {
    final handler = BridgeHandler(config: BridgeConfig(maxPayloadBytes: 8));

    test('a non-escpos format is rejected', () async {
      final res = await handler.print({
        'format': 'pdf',
        'payloadBase64': _escposB64(),
      });
      expect(res.json['ok'], false);
      expect(res.json['category'], 'unsupported');
    });

    test('a missing/empty payload is rejected', () async {
      final res =
          await handler.print({'format': 'escpos', 'payloadBase64': ''});
      expect(res.json['ok'], false);
    });

    test('an invalid base64 payload is rejected', () async {
      final res = await handler.print({
        'format': 'escpos',
        'payloadBase64': 'not-base64-!!!',
      });
      expect(res.json['ok'], false);
    });

    test('an oversized payload is rejected (413, unsupported)', () async {
      final big = base64Encode(List.filled(64, 0x41));
      final res = await handler.print({
        'format': 'escpos',
        'payloadBase64': big,
      });
      expect(res.status, 413);
      expect(res.json['category'], 'unsupported');
    });
  });

  group('config parsing', () {
    test('--target name=host:port', () {
      final config = BridgeConfig.fromArgs([
        '--target',
        'grill=192.0.2.21:9100',
        '--port',
        '9191',
      ]);
      expect(config.sinkMode, isFalse);
      expect(config.targets['grill']!.host, '192.0.2.21');
      expect(config.targets['grill']!.port, 9100);
      expect(config.port, 9191);
    });

    test('no targets => sink mode', () {
      expect(BridgeConfig.fromArgs(const []).sinkMode, isTrue);
    });

    test('a malformed target is rejected', () {
      expect(
        () => BridgeConfig.fromArgs(['--target', 'grill=nope']),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('BridgeServer (real loopback bind)', () {
    late BridgeServer server;

    setUp(() async {
      server = BridgeServer(BridgeHandler(config: BridgeConfig()));
      await server.start(port: 0); // ephemeral loopback port
    });
    tearDown(() => server.stop());

    test('binds loopback and answers GET /health with CORS', () async {
      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );
      req.headers.set('origin', 'http://localhost:5555');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();

      expect(res.statusCode, 200);
      final json = jsonDecode(body) as Map<String, Object?>;
      expect(json['ok'], true);
      expect(json['mode'], 'sink');
      // CORS reflects the localhost origin so a Flutter-web app can call it.
      expect(
        res.headers.value('access-control-allow-origin'),
        'http://localhost:5555',
      );
    });

    test('answers OPTIONS preflight with 204 + CORS', () async {
      final client = HttpClient();
      final req = await client.openUrl(
        'OPTIONS',
        Uri.parse('http://127.0.0.1:${server.port}/print'),
      );
      final res = await req.close();
      await res.drain<void>();
      client.close();
      expect(res.statusCode, 204);
      expect(
        res.headers.value('access-control-allow-methods'),
        contains('POST'),
      );
    });

    test('POST /print to the sink returns accepted_sink over HTTP', () async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/print'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
          jsonEncode({'format': 'escpos', 'payloadBase64': _escposB64()}));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, Object?>;
      expect(json['status'], 'accepted_sink');
    });
  });
}
