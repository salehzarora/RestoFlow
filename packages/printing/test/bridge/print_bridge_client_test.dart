import 'dart:convert';
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-115: the LOCAL print-bridge client is HONEST — it only reports
/// `sentToPrinter` when the bridge CONFIRMS the transport write, reports
/// `accepted` (received, not sent) for a demo sink, `failed` with a category
/// otherwise, and NEVER points at a non-loopback URL.

/// A scripted [BridgeHttpClient] with no sockets.
class _FakeHttp implements BridgeHttpClient {
  _FakeHttp({this.health, this.print, this.throwOnPost = false});

  final BridgeHttpResponse? health;
  final BridgeHttpResponse? print;
  final bool throwOnPost;

  Uri? lastPostUrl;
  String? lastPostBody;
  Uri? lastGetUrl;

  @override
  Future<BridgeHttpResponse> getUrl(Uri url) async {
    lastGetUrl = url;
    if (health == null) throw Exception('connection refused');
    return health!;
  }

  @override
  Future<BridgeHttpResponse> postJson(Uri url, String body) async {
    lastPostUrl = url;
    lastPostBody = body;
    if (throwOnPost) throw Exception('connection refused');
    return print!;
  }
}

BridgeHttpResponse _ok(Map<String, Object?> json) =>
    BridgeHttpResponse(statusCode: 200, body: jsonEncode(json));

void main() {
  final bytes = Uint8List.fromList([0x1b, 0x40, 0x41, 0x42]);

  group('local-only URL guard', () {
    for (final url in [
      'http://127.0.0.1:8787',
      'http://localhost:8787',
      'http://[::1]:8787',
      'http://kds.localhost:9100',
      'http://127.0.0.5:8787',
    ]) {
      test('accepts loopback $url', () {
        expect(() => assertLoopbackBridgeUrl(url), returnsNormally);
        expect(
          () => PrintBridgeClient(baseUrl: url, httpClient: _FakeHttp()),
          returnsNormally,
        );
      });
    }

    for (final url in [
      'https://app.restoflow.example',
      'http://203.0.113.9:8787',
      'http://0.0.0.0:8787',
      'http://192.0.2.50:9100',
    ]) {
      test('rejects non-loopback $url', () {
        expect(
          () => assertLoopbackBridgeUrl(url),
          throwsA(isA<NonLoopbackBridgeUrlException>()),
        );
        expect(
          () => PrintBridgeClient(baseUrl: url, httpClient: _FakeHttp()),
          throwsA(isA<NonLoopbackBridgeUrlException>()),
        );
      });
    }

    test('rejects a malformed URL', () {
      expect(
        () => assertLoopbackBridgeUrl('not a url'),
        throwsA(isA<NonLoopbackBridgeUrlException>()),
      );
    });
  });

  group('health()', () {
    test('connected when the bridge answers ok:true', () async {
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: _FakeHttp(health: _ok({'ok': true, 'mode': 'sink'})),
      );
      expect(await client.health(), BridgeHealth.connected);
    });

    test('unreachable when the GET throws (nothing listening)', () async {
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: _FakeHttp(health: null),
      );
      expect(await client.health(), BridgeHealth.unreachable);
    });

    test('misconfigured on a non-200 / non-bridge answer', () async {
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: _FakeHttp(
          health: const BridgeHttpResponse(statusCode: 404, body: 'nope'),
        ),
      );
      expect(await client.health(), BridgeHealth.misconfigured);
    });

    test('misconfigured when ok is not true', () async {
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: _FakeHttp(health: _ok({'ok': false})),
      );
      expect(await client.health(), BridgeHealth.misconfigured);
    });
  });

  group('submit()', () {
    test(
      'sent -> sentToPrinter (bridge confirmed the transport write)',
      () async {
        final http = _FakeHttp(
          print: _ok({'ok': true, 'status': 'sent', 'mode': 'tcp'}),
        );
        final client = PrintBridgeClient(
          baseUrl: 'http://127.0.0.1:8787',
          httpClient: http,
          role: 'receipt',
        );
        final result = await client.submit(bytes: bytes);
        expect(result.outcome, BridgeSubmitOutcome.sentToPrinter);
        expect(result.ok, isTrue);
        expect(result.mode, 'tcp');
        // The role + base64 payload are forwarded.
        final sent = jsonDecode(http.lastPostBody!) as Map<String, Object?>;
        expect(sent['role'], 'receipt');
        expect(sent['format'], 'escpos');
        expect(base64Decode(sent['payloadBase64']! as String), bytes);
        expect(http.lastPostUrl.toString(), 'http://127.0.0.1:8787/print');
      },
    );

    test(
      'accepted_sink -> accepted (received, NOT sent to hardware)',
      () async {
        final client = PrintBridgeClient(
          baseUrl: 'http://127.0.0.1:8787',
          httpClient: _FakeHttp(
            print: _ok({'ok': true, 'status': 'accepted_sink', 'mode': 'sink'}),
          ),
        );
        final result = await client.submit(bytes: bytes);
        expect(result.outcome, BridgeSubmitOutcome.accepted);
        // Honesty: the sink is NOT a confirmed print.
        expect(result.outcome, isNot(BridgeSubmitOutcome.sentToPrinter));
        expect(result.mode, 'sink');
      },
    );

    test('a transport error maps to failed(unreachable)', () async {
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: _FakeHttp(throwOnPost: true),
      );
      final result = await client.submit(bytes: bytes);
      expect(result.outcome, BridgeSubmitOutcome.failed);
      expect(result.category, PrinterErrorCategory.unreachable);
    });

    test('ok:false with a category maps to a categorized failure', () async {
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: _FakeHttp(
          print: BridgeHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'ok': false,
              'error': 'connection refused',
              'category': 'unreachable',
            }),
          ),
        ),
      );
      final result = await client.submit(bytes: bytes);
      expect(result.outcome, BridgeSubmitOutcome.failed);
      expect(result.category, PrinterErrorCategory.unreachable);
      expect(result.message, 'connection refused');
    });

    test('an empty payload is rejected without a call', () async {
      final http = _FakeHttp(print: _ok({'ok': true, 'status': 'sent'}));
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: http,
      );
      final result = await client.submit(bytes: Uint8List(0));
      expect(result.outcome, BridgeSubmitOutcome.failed);
      expect(http.lastPostBody, isNull);
    });

    test('an oversized payload is rejected as unsupported', () async {
      final http = _FakeHttp(print: _ok({'ok': true, 'status': 'sent'}));
      final client = PrintBridgeClient(
        baseUrl: 'http://127.0.0.1:8787',
        httpClient: http,
        maxPayloadBytes: 4,
      );
      final result = await client.submit(
        bytes: Uint8List.fromList(List.filled(16, 0x41)),
      );
      expect(result.outcome, BridgeSubmitOutcome.failed);
      expect(result.category, PrinterErrorCategory.unsupported);
      expect(http.lastPostBody, isNull);
    });
  });

  group('PrintBridgeTransport', () {
    test('sentToPrinter -> PrintResult.success', () async {
      final transport = PrintBridgeTransport(
        PrintBridgeClient(
          baseUrl: 'http://127.0.0.1:8787',
          httpClient: _FakeHttp(print: _ok({'ok': true, 'status': 'sent'})),
        ),
      );
      expect((await transport.send(bytes)).ok, isTrue);
    });

    test('failed -> PrintResult.failure with the category', () async {
      final transport = PrintBridgeTransport(
        PrintBridgeClient(
          baseUrl: 'http://127.0.0.1:8787',
          httpClient: _FakeHttp(throwOnPost: true),
        ),
      );
      final result = await transport.send(bytes);
      expect(result.ok, isFalse);
      expect(result.category, PrinterErrorCategory.unreachable);
    });
  });

  group('PrintBridgeDispatcher', () {
    test('encodes a document to ESC/POS bytes and submits them', () async {
      final http = _FakeHttp(print: _ok({'ok': true, 'status': 'sent'}));
      final dispatcher = PrintBridgeDispatcher(
        client: PrintBridgeClient(
          baseUrl: 'http://127.0.0.1:8787',
          httpClient: http,
        ),
      );
      final doc = const PrintDocument([
        PrintTextLine('RestoFlow', alignment: PrintAlignment.center),
        PrintCutLine(),
      ]);
      final result = await dispatcher.dispatch(doc);
      expect(result.outcome, BridgeSubmitOutcome.sentToPrinter);
      // Non-empty ESC/POS bytes were sent (init + text + cut).
      final sent = jsonDecode(http.lastPostBody!) as Map<String, Object?>;
      expect(base64Decode(sent['payloadBase64']! as String).isNotEmpty, isTrue);
    });
  });
}
