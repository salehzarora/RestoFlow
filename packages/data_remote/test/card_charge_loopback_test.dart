// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: the card exchange over the REAL dart:io
// client (IOClient below the SDK and the POS HTTP boundary) and a loopback
// server on 127.0.0.1 - the only network the guard allows. It pins what a
// MockClient cannot: the bytes and headers on the wire, redirects and
// authentication challenges never re-sent, a reset connection, a late answer
// after the deadline, a connection still opening at the deadline, and a base
// URL whose card route the boundary refuses before any IO.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'support/captured_timers.dart';
import 'support/no_network.dart';

const _publicKey = 'synthetic-public-key';
const _jwt = 'synthetic.device.jwt';
const _cardPath = '/functions/v1/pos-card-charge';
const _attemptId = 'cccccccc-cccc-4ccc-accc-cccccccccccc';

Map<String, dynamic> _body() => <String, dynamic>{
  'action': 'status',
  'pin_session_id': 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
  'device_id': 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
  'device_session_token': 'synthetic-device-proof',
  'attempt_id': _attemptId,
};

const _envelope = <String, Object?>{
  'ok': true,
  'attempt_id': _attemptId,
  'state': 'unknown',
  'classification': 'in_progress',
  'recorded': false,
  'amount_minor': 4200,
  'currency_code': 'ILS',
  'server_ts': '2026-10-29T08:00:00Z',
};

/// One request as the loopback server saw it.
final class _Seen {
  _Seen(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, List<String>> headers;
  final List<int> body;
}

/// A loopback server that records every request and answers with [handle].
final class _Server {
  _Server._(this._server, this._handle);

  static Future<_Server> start(
    Future<void> Function(HttpRequest request) handle,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final wrapped = _Server._(server, handle);
    server.listen(wrapped._serve);
    return wrapped;
  }

  final HttpServer _server;
  final Future<void> Function(HttpRequest request) _handle;
  final seen = <_Seen>[];

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port';

  Future<void> _serve(HttpRequest request) async {
    final body = await request.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final headers = <String, List<String>>{};
    request.headers.forEach((name, values) => headers[name] = values);
    seen.add(_Seen(request.method, request.uri.toString(), headers, body));
    await _handle(request);
  }

  Future<void> close() => _server.close(force: true);
}

Future<void> _json(HttpRequest request, int status, Object body) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

/// Runs [body] against a POS client whose only allowed network is [server];
/// [baseSuffix] is appended to the server's URL as the configured base URL.
Future<void> _withClient(
  _Server server,
  Future<void> Function(SupabaseSyncRpcTransport transport) body, {
  Future<void> Function()? beforeConnect,
  String baseSuffix = '',
}) async {
  final denied = <String>[];
  await runWithoutNetwork(
    () async {
      final created = SupabaseSyncRpcTransport.createKitchenAckClient(
        '${server.url}$baseSuffix',
        _publicKey,
        inner: IOClient(HttpClient()),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      created.client.functions.setAuth(_jwt);
      try {
        await body(created.transport);
      } finally {
        await created.client.dispose();
        created.boundary.close();
      }
    },
    denied: denied,
    loopbackPort: server.port,
    beforeConnect: beforeConnect,
  );
  expect(denied, isEmpty, reason: 'unexpected network access');
}

Matcher _failure(
  CardChargeFailureKind kind,
  CardChargeFailureReason reason, {
  int? status,
}) => isA<CardChargeTransportFailure>()
    .having((f) => f.kind, 'kind', kind)
    .having((f) => f.reason, 'reason', reason)
    .having((f) => f.httpStatus, 'httpStatus', status);

void main() {
  test(
    'the wire: one POST, the exact bytes, the client Bearer and public '
    'apikey, application/json, no Origin; a 200 envelope is answered',
    () async {
      final server = await _Server.start((r) => _json(r, 200, _envelope));
      addTearDown(server.close);
      final body = _body();
      await _withClient(server, (transport) async {
        final result = await transport.sendCardCharge(body);
        expect(result, isA<CardChargeAnswered>());
        expect((result as CardChargeAnswered).body, _envelope);
      });
      expect(server.seen, hasLength(1));
      final seen = server.seen.single;
      expect(seen.method, 'POST');
      expect(seen.path, _cardPath);
      expect(seen.body, utf8.encode(jsonEncode(body)));
      expect(seen.headers['authorization'], ['Bearer $_jwt']);
      expect(seen.headers['apikey'], [_publicKey]);
      expect(seen.headers['content-type'], ['application/json']);
      expect(seen.headers.containsKey('origin'), isFalse);
    },
  );

  Future<void> redirectingServer(HttpRequest request, int status) async {
    if (request.uri.path != _cardPath) {
      return _json(request, 200, _envelope); // would be a second request
    }
    request.response
      ..statusCode = status
      ..headers.set(HttpHeaders.locationHeader, '/elsewhere');
    await request.response.close();
  }

  for (final status in [301, 302, 303, 307, 308]) {
    // dart:io re-sends a POST only on a 303 (as a GET): that row and its
    // control below prove the boundary's redirect rule; the others pin it.
    final role = status == 303
        ? 'the boundary proof, see the control'
        : 'a pin: dart:io would not re-send this POST either';
    test('a $status redirect is never followed: one request, uncertain '
        '($role)', () async {
      final server = await _Server.start((r) => redirectingServer(r, status));
      addTearDown(server.close);
      await _withClient(server, (transport) async {
        expect(
          await transport.sendCardCharge(_body()),
          _failure(
            CardChargeFailureKind.uncertain,
            CardChargeFailureReason.httpStatus,
            status: status,
          ),
        );
      });
      expect(server.seen.map((s) => '${s.method} ${s.path}'), [
        'POST $_cardPath',
      ]);
    });
  }

  test(
    'sensitivity control: WITHOUT the POS boundary, dart:io follows a 303 '
    'with a second (GET) request - what the redirect rows rule out',
    () async {
      final server = await _Server.start((r) => redirectingServer(r, 303));
      addTearDown(server.close);
      final denied = <String>[];
      await runWithoutNetwork(
        () async {
          final plain = SupabaseClient(
            server.url,
            _publicKey,
            httpClient: IOClient(HttpClient()),
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          );
          try {
            await plain.functions.invoke(
              posCardChargeFunction,
              body: jsonEncode(_body()),
              headers: const {'Content-Type': 'application/json'},
            );
          } finally {
            await plain.dispose();
          }
        },
        denied: denied,
        loopbackPort: server.port,
      );
      expect(denied, isEmpty);
      expect(server.seen.map((s) => '${s.method} ${s.path}'), [
        'POST $_cardPath',
        'GET /elsewhere',
      ]);
    },
  );

  for (final (status, header, kind) in [
    (
      401,
      HttpHeaders.wwwAuthenticateHeader,
      CardChargeFailureKind.unauthenticated,
    ),
    // A proxy's status, not the function's: uncertain.
    (407, HttpHeaders.proxyAuthenticateHeader, CardChargeFailureKind.uncertain),
  ]) {
    test('a $status challenge is ${kind.name} and never re-sent: one request '
        '(a pin: no credentials are configured, so dart:io would not re-send '
        'it either)', () async {
      final server = await _Server.start((request) async {
        request.response
          ..statusCode = status
          ..headers.set(header, 'Basic realm="synthetic"')
          ..headers.contentType = ContentType.json
          ..write('{"ok":false,"error":"synthetic"}');
        await request.response.close();
      });
      addTearDown(server.close);
      await _withClient(server, (transport) async {
        expect(
          await transport.sendCardCharge(_body()),
          _failure(kind, CardChargeFailureReason.httpStatus, status: status),
        );
      });
      expect(server.seen, hasLength(1));
    });
  }

  test('a connection reset before any answer is uncertain (transport), one '
      'request, never retried', () async {
    final server = await _Server.start((request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    });
    addTearDown(server.close);
    await _withClient(server, (transport) async {
      expect(
        await transport.sendCardCharge(_body()),
        _failure(
          CardChargeFailureKind.uncertain,
          CardChargeFailureReason.transport,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(server.seen, hasLength(1));
  });

  test('a 200 event stream is no answer: uncertain (malformed), and the open '
      'stream is closed rather than left holding the connection', () async {
    final closed = Completer<void>();
    final server = await _Server.start((request) async {
      request.response
        ..statusCode = 200
        ..persistentConnection = false
        ..headers.chunkedTransferEncoding = false
        ..headers.contentType = ContentType('text', 'event-stream');
      final socket = await request.response.detachSocket();
      socket.listen(
        (_) {},
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (_) {
          if (!closed.isCompleted) closed.complete();
        },
      );
      socket.add(utf8.encode('data: {"ok":true}\n\n')); // and never ends
    });
    addTearDown(server.close);
    await _withClient(server, (transport) async {
      expect(
        await transport.sendCardCharge(_body()),
        _failure(
          CardChargeFailureKind.uncertain,
          CardChargeFailureReason.malformedAnswer,
          status: 200,
        ),
      );
      await closed.future.timeout(const Duration(seconds: 10));
    });
    expect(server.seen, hasLength(1));
  });

  test('past the deadline after the request was written: uncertain '
      '(timeout); the late answer arrives and causes no second '
      'request', () async {
    final release = Completer<void>();
    final server = await _Server.start((request) async {
      await release.future;
      await _json(request, 200, _envelope);
    });
    addTearDown(server.close);
    await _withClient(server, (transport) async {
      final timers = <CapturedTimer>[];
      final pending = runCapturingTimers(
        timers,
        () => transport.sendCardCharge(_body()),
      );
      while (server.seen.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      timers.where((t) => t.duration == posCardChargeTimeout).single.fire();
      expect(
        await pending,
        _failure(
          CardChargeFailureKind.uncertain,
          CardChargeFailureReason.timeout,
        ),
      );
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.seen, hasLength(1));
    });
  });

  test('a connection still opening when the deadline passes is aborted: '
      'uncertain (timeout), and the server never receives the '
      'request', () async {
    final server = await _Server.start((r) => _json(r, 200, _envelope));
    addTearDown(server.close);
    final reached = Completer<void>();
    final open = Completer<void>();
    await _withClient(
      server,
      (transport) async {
        final timers = <CapturedTimer>[];
        final pending = runCapturingTimers(
          timers,
          () => transport.sendCardCharge(_body()),
        );
        await reached.future;
        timers.where((t) => t.duration == posCardChargeTimeout).single.fire();
        // Handed off before the deadline, so it may have executed as far as
        // the transport can tell.
        expect(
          await pending,
          _failure(
            CardChargeFailureKind.uncertain,
            CardChargeFailureReason.timeout,
          ),
        );
        open.complete();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      beforeConnect: () {
        if (!reached.isCompleted) reached.complete();
        return open.future;
      },
    );
    expect(server.seen, isEmpty);
  });

  for (final suffix in ['/.', '/a/..', '/?a', '#f', '/?%FF']) {
    test('a base URL ending in "$suffix" (dot segments, a query or a '
        'fragment): the card route is refused before any IO - not sent, and '
        'the server receives nothing', () async {
      final server = await _Server.start((r) => _json(r, 200, _envelope));
      addTearDown(server.close);
      await _withClient(server, baseSuffix: suffix, (transport) async {
        expect(
          await transport.sendCardCharge(_body()),
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.handoffRefused,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      expect(server.seen, isEmpty);
      // Control: the same server under its canonical base URL is reached.
      await _withClient(server, (transport) async {
        expect(
          await transport.sendCardCharge(_body()),
          isA<CardChargeAnswered>(),
        );
      });
      expect(server.seen.map((s) => '${s.method} ${s.path}'), [
        'POST $_cardPath',
      ]);
    });
  }

  group('the network guard itself', () {
    test('denies sockets and HTTP clients outside the allowed loopback '
        'port', () async {
      final denied = <String>[];
      await runWithoutNetwork(() async {
        await expectLater(
          Socket.connect('127.0.0.1', 9),
          throwsA(isA<NetworkDenied>()),
        );
        expect(HttpClient.new, throwsA(isA<NetworkDenied>()));
        // package:http's default client is refused when it is created.
        expect(http.Client.new, throwsA(isA<NetworkDenied>()));
      }, denied: denied);
      expect(denied, [
        'Socket.connect 127.0.0.1:9',
        'HttpClient',
        'HttpClient',
      ]);

      final server = await _Server.start((r) => _json(r, 200, _envelope));
      addTearDown(server.close);
      final allowedDenied = <String>[];
      await runWithoutNetwork(
        () async {
          await expectLater(
            Socket.connect('127.0.0.1', server.port + 1),
            throwsA(isA<NetworkDenied>()),
          );
          final client = HttpClient();
          for (final url in [
            'https://127.0.0.1:${server.port}/',
            'https://synthetic.invalid/',
            'http://synthetic.invalid:${server.port}/',
          ]) {
            await expectLater(
              client.getUrl(Uri.parse(url)),
              throwsA(isA<NetworkDenied>()),
            );
          }
          final request = await client.getUrl(Uri.parse('${server.url}/probe'));
          final response = await request.close();
          await response.drain<void>();
          client.close(force: true);
        },
        denied: allowedDenied,
        loopbackPort: server.port,
      );
      expect(allowedDenied, hasLength(4));
      expect(server.seen.map((s) => s.path), ['/probe']);
    });
  });
}
