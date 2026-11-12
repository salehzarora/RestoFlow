// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: the card Edge transport over the SDK
// (execution packet §5 and §6). Fake HTTP only - a MockClient below the SDK's
// AuthHttpClient, inside a network-denying zone - and synthetic values.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'support/captured_timers.dart';
import 'support/no_network.dart';

const _url = 'https://synthetic.invalid';
const _publicKey = 'synthetic-public-key';
const _jwt = 'synthetic.device.jwt';
const _endpoint = '$_url/functions/v1/pos-card-charge';
const _cardPath = '/functions/v1/pos-card-charge';
const _tokenPath = '/auth/v1/token';
const _attemptId = 'cccccccc-cccc-4ccc-accc-cccccccccccc';
const _json = {'content-type': 'application/json'};

/// The function's refusal tokens that only ever come with a non-200 status,
/// written out (the static test derives the same set from its sources).
const _non200Tokens = [
  'invalid_request',
  'invalid_session',
  'provider_unavailable',
  'unavailable',
  'origin_not_allowed',
  'not_found',
  'method_not_allowed',
];

/// A `start` body as 001F will build it (synthetic identifiers).
Map<String, dynamic> _startBody() => <String, dynamic>{
  'action': 'start',
  'pin_session_id': 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
  'device_id': 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
  'device_session_token': 'synthetic-device-proof',
  'attempt_id': _attemptId,
  'mode': 'live',
  'amount_minor': 4200,
  'currency_code': 'ILS',
  'order_id': 'dddddddd-dddd-4ddd-addd-dddddddddddd',
  'expected_revision': 3,
};

/// A `free_order` body with non-ASCII text, to pin the UTF-8 bytes.
Map<String, dynamic> _freeOrderBody() => <String, dynamic>{
  'action': 'free_order',
  'pin_session_id': 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
  'device_id': 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
  'device_session_token': 'synthetic-device-proof',
  'attempt_id': _attemptId,
  'reason': 'הלקוח שילם במזומן — العميل دفع نقدا',
  'confirmation_source': 'provider_report',
  'confirmation_reference': 'synthetic-ref',
};

const _envelope = <String, Object?>{
  'ok': true,
  'attempt_id': _attemptId,
  'state': 'sent',
  'classification': 'in_progress',
  'recorded': false,
  'amount_minor': 4200,
  'currency_code': 'ILS',
  'server_ts': '2026-10-29T08:00:00Z',
};

http.Response _ok(http.Request request) =>
    http.Response(jsonEncode(_envelope), 200, headers: _json, request: request);

/// A plain JSON answer carrying its request (PostgREST reads it).
http.Response _okRpc(http.Request request) =>
    http.Response('{"ok":true}', 200, headers: _json, request: request);

/// A synthetic, unsigned JWT whose `exp` is [expiresAt] (seconds).
String _syntheticJwt(String subject, int expiresAt) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': subject, 'role': 'authenticated', 'exp': expiresAt})}.'
      'synthetic-signature';
}

/// A gotrue session JSON for [accessToken] expiring at [expiresAt].
String _sessionJson(String accessToken, int expiresAt) => jsonEncode({
  'access_token': accessToken,
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': expiresAt,
  'refresh_token': 'synthetic-refresh-token',
  'user': {
    'id': 'eeeeeeee-eeee-4eee-aeee-eeeeeeeeeeee',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'aud': 'authenticated',
    'created_at': '2026-10-29T08:00:00Z',
    'is_anonymous': true,
  },
});

int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// The POS client ([SupabaseSyncRpcTransport.createKitchenAckClient], no
/// background token refresh) over a scripted MockClient that records every
/// request. [refreshGate], when set, holds the SDK's token refresh.
final class _Wire {
  _Wire({this.answer, this.url = _url});

  http.Response Function(http.Request request)? answer;
  final String url;
  Object Function()? fail;
  Completer<http.Response>? gate;
  Completer<http.Response>? refreshGate;
  final requests = <http.Request>[];

  late final created = SupabaseSyncRpcTransport.createKitchenAckClient(
    url,
    _publicKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    inner: MockClient((request) async {
      requests.add(request);
      final refresh = refreshGate;
      if (refresh != null && request.url.path == _tokenPath) {
        return refresh.future;
      }
      final failure = fail;
      if (failure != null) throw failure();
      final held = gate;
      if (held != null) return held.future;
      return (answer ?? _ok)(request);
    }),
  );

  SupabaseSyncRpcTransport get transport => created.transport;
  SupabaseClient get client => created.client;
  List<http.Request> get cardRequests =>
      requests.where((r) => r.url.path == _cardPath).toList();

  /// An expired session: the next call refreshes it inline first.
  Future<void> expireSession() async {
    final expired = _nowSeconds() - 3600;
    await client.auth.setInitialSession(
      _sessionJson(_syntheticJwt('device-one', expired), expired),
    );
  }

  /// The successful refresh answer, carrying [token].
  http.Response refreshed(String token) => http.Response(
    _sessionJson(token, _nowSeconds() + 3600),
    200,
    headers: _json,
  );
}

/// Runs [body] with the network denied and fails if anything tried to reach it.
Future<void> _offline(Future<void> Function() body) async {
  final denied = <String>[];
  await runWithoutNetwork(body, denied: denied);
  expect(denied, isEmpty, reason: 'unexpected network access');
}

_Wire _wire({http.Response Function(http.Request)? answer, String url = _url}) {
  final wire = _Wire(answer: answer, url: url);
  wire.client.functions.setAuth(_jwt);
  addTearDown(wire.client.dispose);
  return wire;
}

/// One card exchange inside a timer-capturing Zone, proven to be the only
/// one: the call armed exactly its deadline and nothing else (so no delayed,
/// periodic or timer-driven re-send can be pending), its end cancelled that
/// deadline, and after a real settle - which runs any zero-delay or microtask
/// work - the wire had seen exactly one request.
Future<CardChargeTransportResult> _onceWithoutRetry(_Wire wire) async {
  final timers = <CapturedTimer>[];
  final periodic = <Duration>[];
  final result = await runCapturingTimers(
    timers,
    () => wire.transport.sendCardCharge(_startBody()),
    periodic: periodic,
  );
  await _settle();
  expect(timers.map((t) => t.duration), [posCardChargeTimeout]);
  expect(timers.single.isActive, isFalse);
  expect(periodic, isEmpty);
  expect(wire.requests, hasLength(1));
  return result;
}

/// The timers a call armed while it ran in a timer-capturing Zone.
typedef _Armed = ({List<CapturedTimer> timers, List<Duration> periodic});

/// Starts [call] in a timer-capturing Zone: every non-zero timer it arms, or
/// anything it schedules arms, is captured and runs only when the test fires
/// it (zero-duration timers stay real and run during a settle).
({Future<T> result, _Armed armed}) _capture<T>(Future<T> Function() call) {
  final timers = <CapturedTimer>[];
  final periodic = <Duration>[];
  final result = runCapturingTimers(timers, call, periodic: periodic);
  return (result: result, armed: (timers: timers, periodic: periodic));
}

/// After a card call returned and a real settle ran any zero-delay or
/// microtask work: no timer it armed is still pending, so no delayed re-send
/// can follow; nothing periodic was armed; and it armed exactly [deadlines]
/// deadline(s) — one for its exchange, none for a call refused before the SDK
/// call (a re-send through `sendCardCharge` would arm another).
void _expectNoPendingWork(_Armed armed, {int deadlines = 1}) {
  expect(
    armed.timers.where((t) => t.isActive).map((t) => t.duration),
    isEmpty,
    reason: 'a timer is still pending',
  );
  expect(armed.periodic, isEmpty);
  expect(
    armed.timers.where((t) => t.duration == posCardChargeTimeout),
    hasLength(deadlines),
  );
}

/// A real barrier before asserting that nothing MORE happened: lets isolate
/// decoding and SDK continuations finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

/// Waits (real time, at most 10 s) until [condition] holds - for what MUST
/// happen, so a slow host cannot turn a pass into a failure.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
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
  group('one exact, authenticated request', () {
    test('POST to the exact function path; the exact bytes of the caller '
        'map; Bearer of the client, its public apikey; application/json; no '
        'Origin; the caller map unchanged', () async {
      await _offline(() async {
        final wire = _wire();
        final body = _startBody();
        final before = jsonEncode(body);
        final result = await wire.transport.sendCardCharge(body);
        expect(result, isA<CardChargeAnswered>());
        expect(wire.requests, hasLength(1));
        final request = wire.cardRequests.single;
        expect(request.method, 'POST');
        expect(request.url.toString(), _endpoint);
        expect(request.url.hasQuery, isFalse);
        expect(request.bodyBytes, utf8.encode(before));
        expect(jsonDecode(request.body), body);
        expect(jsonEncode(body), before);
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['authorization'], 'Bearer $_jwt');
        expect(request.headers['apikey'], _publicKey);
        // Only the SDK's own headers plus the content type: no Origin, and no
        // credential or key of the transport's own.
        expect(request.headers.keys.map((k) => k.toLowerCase()).toSet(), {
          'content-type',
          'authorization',
          'apikey',
          'x-client-info',
        });
        expect(request.followRedirects, isFalse);
      });
    });

    test('non-ASCII text travels as its exact UTF-8 bytes', () async {
      await _offline(() async {
        final wire = _wire();
        final body = _freeOrderBody();
        await wire.transport.sendCardCharge(body);
        final request = wire.cardRequests.single;
        expect(request.bodyBytes, utf8.encode(jsonEncode(body)));
        expect(jsonDecode(utf8.decode(request.bodyBytes)), body);
      });
    });

    test('the CURRENT session access token is forwarded at call time (not '
        'pinned): a later session is used by the next call', () async {
      await _offline(() async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        final first = _syntheticJwt('device-one', _nowSeconds() + 3600);
        await wire.client.auth.setInitialSession(
          _sessionJson(first, _nowSeconds() + 3600),
        );
        await wire.transport.sendCardCharge(_startBody());
        final second = _syntheticJwt('device-two', _nowSeconds() + 3600);
        await wire.client.auth.setInitialSession(
          _sessionJson(second, _nowSeconds() + 3600),
        );
        await wire.transport.sendCardCharge(_startBody());
        final cards = wire.cardRequests;
        expect(cards, hasLength(2));
        expect(cards[0].headers['authorization'], 'Bearer $first');
        expect(cards[1].headers['authorization'], 'Bearer $second');
        expect(cards.map((r) => r.headers['apikey']), [_publicKey, _publicKey]);
      });
    });

    test('a 200 answer is returned unread and deeply unmodifiable', () async {
      await _offline(() async {
        final nested = {
          ..._envelope,
          'extra': {
            'list': [1, 2],
          },
        };
        final wire = _wire(
          answer: (_) => http.Response(jsonEncode(nested), 200, headers: _json),
        );
        final result = await wire.transport.sendCardCharge(_startBody());
        expect(result, isA<CardChargeAnswered>());
        final body = (result as CardChargeAnswered).body;
        expect(body, nested);
        expect(() => body['ok'] = false, throwsUnsupportedError);
        expect(() => (body['extra'] as Map)['x'] = 1, throwsUnsupportedError);
        expect(
          () => ((body['extra'] as Map)['list'] as List).add(3),
          throwsUnsupportedError,
        );
        expect(result.toString(), isNot(contains('cccccccc')));
      });
    });

    test('a plain SDK client is not a fallback: refused before any '
        'request', () async {
      await _offline(() async {
        var calls = 0;
        final client = SupabaseClient(
          _url,
          _publicKey,
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('{}', 200, headers: _json);
          }),
        );
        addTearDown(client.dispose);
        final run = _capture(
          () => SupabaseSyncRpcTransport(client).sendCardCharge(_startBody()),
        );
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.capabilityUnavailable,
          ),
        );
        await _settle();
        _expectNoPendingWork(run.armed, deadlines: 0);
        expect(calls, 0);
      });
    });

    test('a body that is not JSON-encodable is refused before any '
        'request', () async {
      await _offline(() async {
        final wire = _wire();
        final run = _capture(
          () => wire.transport.sendCardCharge({
            ..._startBody(),
            'amount_minor': DateTime.utc(2026),
          }),
        );
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.unencodableBody,
          ),
        );
        await _settle();
        _expectNoPendingWork(run.armed, deadlines: 0);
        expect(wire.requests, isEmpty);
      });
    });
  });

  group('the one-handoff gate', () {
    test('a direct functions.invoke of the card route, outside the '
        'transport, is refused by the boundary in every spelling: nothing is '
        'sent', () async {
      await _offline(() async {
        final wire = _wire();
        final run = _capture(() async {
          for (final name in [
            posCardChargeFunction,
            '$posCardChargeFunction/',
            '$posCardChargeFunction/sub',
            'POS-CARD-CHARGE',
            'prefix/$posCardChargeFunction',
            '$posCardChargeFunction%2Fsub',
            'x?/$posCardChargeFunction',
            'x#/$posCardChargeFunction',
          ]) {
            await expectLater(
              wire.client.functions.invoke(
                name,
                body: jsonEncode(_startBody()),
                headers: const {'Content-Type': 'application/json'},
              ),
              throwsA(isA<CardChargeHandoffRefused>()),
              reason: name,
            );
          }
        });
        await run.result;
        await _settle();
        expect(wire.requests, isEmpty);
        _expectNoPendingWork(run.armed, deadlines: 0);
      });
    });

    test('inside an exchange the boundary refuses other bytes, a query, '
        'another method, origin or path, and a second handoff', () async {
      await _offline(() async {
        final sent = <http.Request>[];
        final boundary = KitchenAckHttpBoundary(
          Uri.parse(_url),
          inner: MockClient((request) async {
            sent.add(request);
            return _ok(request);
          }),
        );
        addTearDown(boundary.close);
        final bytes = utf8.encode(jsonEncode(_startBody()));
        http.Request request({
          String method = 'POST',
          String url = _endpoint,
          List<int>? body,
        }) => http.Request(method, Uri.parse(url))..bodyBytes = body ?? bytes;
        final exchange = CardChargeExchange(bytes, () => true);
        final run = _capture(
          () => boundary.runCardCharge(exchange, () async {
            for (final wrong in [
              request(body: utf8.encode('{}')),
              request(url: '$_endpoint?region=any'),
              request(method: 'PUT'),
              request(url: 'https://other.invalid$_cardPath'),
              request(url: '$_url/prefix$_cardPath'),
              request(url: '$_endpoint/'),
              request(url: '$_url/functions/v1/POS-CARD-CHARGE'),
            ]) {
              await expectLater(
                boundary.send(wrong),
                throwsA(isA<CardChargeHandoffRefused>()),
              );
            }
            expect(exchange.handedOff, isFalse);
            await boundary.send(request());
            expect(exchange.handedOff, isTrue);
            await expectLater(
              boundary.send(request()),
              throwsA(isA<CardChargeHandoffRefused>()),
            );
          }),
        );
        await run.result;
        await _settle();
        expect(sent, hasLength(1));
        expect(sent.single.followRedirects, isFalse);
        expect(sent.single.bodyBytes, bytes);
        _expectNoPendingWork(run.armed, deadlines: 0);
      });
    });

    test('a deadline during a held token refresh ends the exchange: '
        'uncertain (timeout) like every timeout, though nothing was handed '
        'off, and the late refresh never sends the request', () async {
      await _offline(() async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        await wire.expireSession();
        wire.refreshGate = Completer<http.Response>();
        final timers = <CapturedTimer>[];
        final periodic = <Duration>[];
        final pending = runCapturingTimers(
          timers,
          () => wire.transport.sendCardCharge(_startBody()),
          periodic: periodic,
        );
        await _until(() => wire.requests.isNotEmpty);
        expect(wire.requests.map((r) => r.url.path), [_tokenPath]);
        final deadline = timers.single;
        expect(deadline.duration, posCardChargeTimeout);
        deadline.fire();
        expect(
          await pending,
          _failure(
            CardChargeFailureKind.uncertain,
            CardChargeFailureReason.timeout,
          ),
        );
        final late = _syntheticJwt('device-late', _nowSeconds() + 3600);
        wire.refreshGate!.complete(wire.refreshed(late));
        // The refresh is applied, the SDK continues to the boundary, and the
        // ended exchange refuses the handoff.
        await _until(
          () => wire.client.auth.currentSession?.accessToken == late,
        );
        await _settle();
        expect(wire.cardRequests, isEmpty);
        _expectNoPendingWork((timers: timers, periodic: periodic));
      });
    });

    test('control: the same held refresh released before the deadline sends '
        'exactly one request with the refreshed token', () async {
      await _offline(() async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        await wire.expireSession();
        wire.refreshGate = Completer<http.Response>();
        final timers = <CapturedTimer>[];
        final pending = runCapturingTimers(
          timers,
          () => wire.transport.sendCardCharge(_startBody()),
        );
        await _until(() => wire.requests.isNotEmpty);
        final fresh = _syntheticJwt('device-fresh', _nowSeconds() + 3600);
        wire.refreshGate!.complete(wire.refreshed(fresh));
        expect(await pending, isA<CardChargeAnswered>());
        expect(wire.cardRequests, hasLength(1));
        expect(
          wire.cardRequests.single.headers['authorization'],
          'Bearer $fresh',
        );
        expect(timers.single.isActive, isFalse);
      });
    });

    test('isCurrent turning false during a held token refresh refuses at the '
        'handoff: notSent (device session), nothing sent', () async {
      await _offline(() async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        await wire.expireSession();
        wire.refreshGate = Completer<http.Response>();
        var current = true;
        final run = _capture(
          () => wire.transport.sendCardCharge(
            _startBody(),
            isCurrent: () => current,
          ),
        );
        await _until(() => wire.requests.isNotEmpty);
        current = false;
        wire.refreshGate!.complete(
          wire.refreshed(_syntheticJwt('device-two', _nowSeconds() + 3600)),
        );
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.deviceSessionUnverified,
          ),
        );
        await _settle();
        expect(wire.cardRequests, isEmpty);
        _expectNoPendingWork(run.armed);
      });
    });

    test('a boundary closed during a held token refresh refuses: notSent '
        '(handoff refused), nothing sent', () async {
      await _offline(() async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        await wire.expireSession();
        wire.refreshGate = Completer<http.Response>();
        final run = _capture(() => wire.transport.sendCardCharge(_startBody()));
        await _until(() => wire.requests.isNotEmpty);
        wire.created.boundary.close();
        wire.refreshGate!.complete(
          wire.refreshed(_syntheticJwt('device-two', _nowSeconds() + 3600)),
        );
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.handoffRefused,
          ),
        );
        await _settle();
        expect(wire.cardRequests, isEmpty);
        _expectNoPendingWork(run.armed);
      });
    });

    test('a composed handoff check that throws refuses the handoff: notSent '
        '(handoff refused), nothing sent, nothing pending', () async {
      await _offline(() async {
        final wire = _wire();
        final run = _capture(
          () => wire.transport.sendCardCharge(
            _startBody(),
            isCurrent: () => throw StateError('synthetic check failure'),
          ),
        );
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.handoffRefused,
          ),
        );
        await _settle();
        expect(wire.requests, isEmpty);
        _expectNoPendingWork(run.armed);
      });
    });
  });

  group('the dedicated timeout', () {
    test('the card call arms exactly one deadline of posCardChargeTimeout '
        'and no periodic work; an answer in time cancels it', () async {
      await _offline(() async {
        final wire = _wire();
        final timers = <CapturedTimer>[];
        final periodic = <Duration>[];
        final result = await runCapturingTimers(
          timers,
          () => wire.transport.sendCardCharge(_startBody()),
          periodic: periodic,
        );
        expect(result, isA<CardChargeAnswered>());
        expect(timers.map((t) => t.duration), [posCardChargeTimeout]);
        expect(timers.single.isActive, isFalse);
        expect(periodic, isEmpty);
        expect(wire.cardRequests, hasLength(1));
      });
    });

    test('ordinary calls keep their current timeout: RPC and the web-order '
        'decision arm the general 15 s deadline', () async {
      await _offline(() async {
        final wire = _wire(answer: _okRpc);
        final rpcTimers = <CapturedTimer>[];
        await runCapturingTimers(
          rpcTimers,
          () => wire.transport.invoke('sync_pull', <String, dynamic>{}),
        );
        expect(rpcTimers.map((t) => t.duration), [const Duration(seconds: 15)]);
        final decisionTimers = <CapturedTimer>[];
        await runCapturingTimers(
          decisionTimers,
          () => wire.transport.decideWebOrder(<String, dynamic>{}),
        );
        expect(decisionTimers.map((t) => t.duration), [
          const Duration(seconds: 15),
        ]);
      });
    });

    test(
      'a configured general timeout never changes the card deadline',
      () async {
        await _offline(() async {
          final created = SupabaseSyncRpcTransport.createKitchenAckClient(
            _url,
            _publicKey,
            inner: MockClient((request) async => _okRpc(request)),
            timeout: const Duration(seconds: 7),
          );
          addTearDown(created.client.dispose);
          final rpc = <CapturedTimer>[];
          await runCapturingTimers(
            rpc,
            () => created.transport.invoke('sync_pull', <String, dynamic>{}),
          );
          expect(rpc.map((t) => t.duration), [const Duration(seconds: 7)]);
          final card = <CapturedTimer>[];
          await runCapturingTimers(
            card,
            () => created.transport.sendCardCharge(_startBody()),
          );
          expect(card.map((t) => t.duration), [posCardChargeTimeout]);
        });
      },
    );

    test('past the deadline after the handoff the exchange is uncertain '
        '(timeout); the late answer is never read and never causes a second '
        'send', () async {
      await _offline(() async {
        final wire = _wire()..gate = Completer<http.Response>();
        final timers = <CapturedTimer>[];
        final periodic = <Duration>[];
        final pending = runCapturingTimers(
          timers,
          () => wire.transport.sendCardCharge(_startBody()),
          periodic: periodic,
        );
        await _until(() => wire.cardRequests.isNotEmpty);
        expect(wire.cardRequests, hasLength(1));
        expect(timers.single.duration, posCardChargeTimeout);
        timers.single.fire();
        expect(
          await pending,
          _failure(
            CardChargeFailureKind.uncertain,
            CardChargeFailureReason.timeout,
          ),
        );
        wire.gate!.complete(_ok(wire.cardRequests.single));
        await _settle();
        expect(wire.requests, hasLength(1));
        expect(timers, hasLength(1));
        _expectNoPendingWork((timers: timers, periodic: periodic));
      });
    });
  });

  group('failure classification (one card request each, never retried)', () {
    final statusRows = <(int, CardChargeFailureKind)>[
      (201, CardChargeFailureKind.uncertain),
      (204, CardChargeFailureKind.uncertain),
      (301, CardChargeFailureKind.uncertain),
      (302, CardChargeFailureKind.uncertain),
      (303, CardChargeFailureKind.uncertain),
      (307, CardChargeFailureKind.uncertain),
      (308, CardChargeFailureKind.uncertain),
      (400, CardChargeFailureKind.notApplied),
      (401, CardChargeFailureKind.unauthenticated),
      (402, CardChargeFailureKind.uncertain),
      (403, CardChargeFailureKind.notApplied),
      (404, CardChargeFailureKind.notApplied),
      (405, CardChargeFailureKind.notApplied),
      (406, CardChargeFailureKind.uncertain),
      (407, CardChargeFailureKind.uncertain),
      (408, CardChargeFailureKind.uncertain),
      (409, CardChargeFailureKind.uncertain),
      (410, CardChargeFailureKind.uncertain),
      (412, CardChargeFailureKind.uncertain),
      (413, CardChargeFailureKind.uncertain),
      (415, CardChargeFailureKind.uncertain),
      (422, CardChargeFailureKind.uncertain),
      (425, CardChargeFailureKind.uncertain),
      (429, CardChargeFailureKind.uncertain),
      (451, CardChargeFailureKind.uncertain),
      (499, CardChargeFailureKind.uncertain),
      (500, CardChargeFailureKind.uncertain),
      (502, CardChargeFailureKind.uncertain),
      (503, CardChargeFailureKind.uncertain),
      (504, CardChargeFailureKind.uncertain),
      (546, CardChargeFailureKind.uncertain),
      (600, CardChargeFailureKind.uncertain),
    ];
    for (final (status, kind) in statusRows) {
      test('HTTP $status is ${kind.name}', () async {
        await _offline(() async {
          final wire = _wire(
            answer: (_) => http.Response(
              jsonEncode({'ok': false, 'error': 'synthetic_$status'}),
              status,
              headers: _json,
            ),
          );
          expect(
            await _onceWithoutRetry(wire),
            _failure(kind, CardChargeFailureReason.httpStatus, status: status),
          );
        });
      });
    }

    test('the status policy is closed: 401 is unauthenticated, exactly 400, '
        '403, 404 and 405 are notApplied, and every other non-200 status is '
        'uncertain', () {
      const unauthenticated = {401};
      const notApplied = {400, 403, 404, 405};
      final statuses = [0, 99, for (var s = 100; s <= 599; s++) s, 600, 999]
        ..remove(200);
      expect(statuses, hasLength(503));
      for (final status in statuses) {
        expect(
          classifyCardChargeAnswer(status, {'ok': false, 'error': 'synthetic'}),
          _failure(
            unauthenticated.contains(status)
                ? CardChargeFailureKind.unauthenticated
                : notApplied.contains(status)
                ? CardChargeFailureKind.notApplied
                : CardChargeFailureKind.uncertain,
            CardChargeFailureReason.httpStatus,
            status: status,
          ),
          reason: 'HTTP $status',
        );
      }
    });

    test('the body never changes a non-200 kind: the same closed map for '
        'every status with each answer shape, with and without the attempt '
        'id', () {
      const unauthenticated = {401};
      const notApplied = {400, 403, 404, 405};
      final bodies = <String, Object?>{
        for (final token in _non200Tokens) token: {'ok': false, 'error': token},
        'a typed refusal of this attempt': {
          'ok': false,
          'error': 'poll_limit',
          'attempt_id': _attemptId,
          'attempt_state': 'sent',
        },
        'this attempt\'s approved envelope': {
          ..._envelope,
          'state': 'approved',
        },
        'an HTML page':
            '<html><body>Proxy Authentication Required</body></html>',
        'an empty body': '',
        'no body': null,
      };
      final statuses = [0, 99, for (var s = 100; s <= 599; s++) s, 600, 999]
        ..remove(200);
      for (final MapEntry(key: shape, value: body) in bodies.entries) {
        for (final attemptId in [null, _attemptId]) {
          for (final status in statuses) {
            expect(
              classifyCardChargeAnswer(status, body, attemptId: attemptId),
              _failure(
                unauthenticated.contains(status)
                    ? CardChargeFailureKind.unauthenticated
                    : notApplied.contains(status)
                    ? CardChargeFailureKind.notApplied
                    : CardChargeFailureKind.uncertain,
                CardChargeFailureReason.httpStatus,
                status: status,
              ),
              reason: 'HTTP $status with $shape (attempt id: $attemptId)',
            );
          }
        }
      }
    });

    for (final (status, body, headers) in [
      (409, jsonEncode({'ok': false, 'error': 'invalid_request'}), _json),
      (422, jsonEncode({'ok': false, 'error': 'invalid_request'}), _json),
      (
        407,
        '<html><body>Proxy Authentication Required</body></html>',
        const {'content-type': 'text/html'},
      ),
    ]) {
      test('HTTP $status is uncertain whatever its body says (one card '
          'request, never retried)', () async {
        await _offline(() async {
          final wire = _wire(
            answer: (_) => http.Response(body, status, headers: headers),
          );
          expect(
            await _onceWithoutRetry(wire),
            _failure(
              CardChargeFailureKind.uncertain,
              CardChargeFailureReason.httpStatus,
              status: status,
            ),
          );
        });
      });
    }

    test('a 503 that claims an approved attempt is still uncertain, never an '
        'answer', () async {
      await _offline(() async {
        final wire = _wire(
          answer: (_) => http.Response(
            jsonEncode({..._envelope, 'state': 'approved'}),
            503,
            headers: _json,
          ),
        );
        expect(
          await _onceWithoutRetry(wire),
          _failure(
            CardChargeFailureKind.uncertain,
            CardChargeFailureReason.httpStatus,
            status: 503,
          ),
        );
      });
    });

    final malformed = <String, Object?>{
      'a JSON array': [1, 2],
      'JSON null': null,
      'a JSON string': 'ok',
      'an object without ok': {'state': 'approved', 'attempt_id': _attemptId},
      'a non-boolean ok': {'ok': 'true', 'attempt_id': _attemptId},
      'an envelope of another attempt': {
        ..._envelope,
        'attempt_id': 'ffffffff-ffff-4fff-afff-ffffffffffff',
      },
      'an envelope without attempt_id': {..._envelope}..remove('attempt_id'),
      'a refusal of another attempt': {
        'ok': false,
        'error': 'poll_limit',
        'attempt_id': 'ffffffff-ffff-4fff-afff-ffffffffffff',
        'attempt_state': 'sent',
      },
      for (final token in _non200Tokens)
        'a 200 $token refusal': {'ok': false, 'error': token},
    };
    for (final entry in malformed.entries) {
      test('a 200 with ${entry.key} fails closed: uncertain '
          '(malformed)', () async {
        await _offline(() async {
          final wire = _wire(
            answer: (_) =>
                http.Response(jsonEncode(entry.value), 200, headers: _json),
          );
          expect(
            await _onceWithoutRetry(wire),
            _failure(
              CardChargeFailureKind.uncertain,
              CardChargeFailureReason.malformedAnswer,
              status: 200,
            ),
          );
        });
      });
    }

    for (final entry in <String, Map<String, Object?>>{
      'a typed refusal without an attempt': {
        'ok': false,
        'error': 'permission_denied',
      },
      'a typed refusal of this attempt': {
        'ok': false,
        'error': 'poll_limit',
        'attempt_id': _attemptId,
        'attempt_state': 'sent',
      },
      'this attempt\'s envelope': _envelope,
    }.entries) {
      test('a 200 with ${entry.key} is answered, unread', () async {
        await _offline(() async {
          final wire = _wire(
            answer: (_) =>
                http.Response(jsonEncode(entry.value), 200, headers: _json),
          );
          final result = await _onceWithoutRetry(wire);
          expect(result, isA<CardChargeAnswered>());
          expect((result as CardChargeAnswered).body, entry.value);
        });
      });
    }

    for (final entry in <String, http.Response Function()>{
      'an empty body': () => http.Response('', 200, headers: _json),
      'text/plain JSON': () => http.Response(
        jsonEncode(_envelope),
        200,
        headers: {'content-type': 'text/plain'},
      ),
      'no content type': () => http.Response(jsonEncode(_envelope), 200),
      'octet-stream': () => http.Response.bytes(
        utf8.encode(jsonEncode(_envelope)),
        200,
        headers: {'content-type': 'application/octet-stream'},
      ),
      'an event stream': () => http.Response(
        'data: {"ok":true}\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    }.entries) {
      test('a 200 with ${entry.key} fails closed: uncertain '
          '(malformed)', () async {
        await _offline(() async {
          final wire = _wire(answer: (_) => entry.value());
          expect(
            await _onceWithoutRetry(wire),
            _failure(
              CardChargeFailureKind.uncertain,
              CardChargeFailureReason.malformedAnswer,
              status: 200,
            ),
          );
        });
      });
    }

    for (final entry in <String, http.Response Function()>{
      'truncated JSON': () => http.Response('{"ok":tru', 200, headers: _json),
      'invalid UTF-8': () =>
          http.Response.bytes([0x7b, 0xff, 0xfe, 0x7d], 200, headers: _json),
      'a truncated error body': () =>
          http.Response('{"ok":fal', 400, headers: _json),
    }.entries) {
      test('${entry.key} fails closed: uncertain (malformed), no status '
          'claimed', () async {
        await _offline(() async {
          final wire = _wire(answer: (_) => entry.value());
          expect(
            await _onceWithoutRetry(wire),
            _failure(
              CardChargeFailureKind.uncertain,
              CardChargeFailureReason.malformedAnswer,
            ),
          );
        });
      });
    }

    for (final entry in <String, Object Function()>{
      'a reset connection': () =>
          http.ClientException('Connection reset by peer'),
      'a socket failure': () => const SocketException('synthetic failure'),
      'a TLS failure': () => const HandshakeException('synthetic handshake'),
      'any other error': () => StateError('synthetic'),
    }.entries) {
      test('${entry.key} after the handoff is uncertain (transport), never '
          'retried', () async {
        await _offline(() async {
          final wire = _wire()..fail = entry.value;
          expect(
            await _onceWithoutRetry(wire),
            _failure(
              CardChargeFailureKind.uncertain,
              CardChargeFailureReason.transport,
            ),
          );
        });
      });
    }

    test('an access token the SDK cannot prepare (expired session, refresh '
        'unreachable) is a lost connection: uncertain (access token '
        'unavailable), though the function was never called; nothing is '
        'retried, then or once the connection returns', () async {
      await _offline(() async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        await wire.expireSession();
        wire.fail = () => http.ClientException('synthetic offline');
        final run = _capture(() => wire.transport.sendCardCharge(_startBody()));
        var done = false;
        unawaited(run.result.whenComplete(() => done = true));
        // gotrue retries a retryable refresh with back-off waits (captured):
        // run each wait at once while the call is pending, never the card
        // deadline, and nothing once the call has returned.
        await _until(() {
          if (done) return true;
          for (final timer in run.armed.timers.toList()) {
            if (timer.isActive && timer.duration != posCardChargeTimeout) {
              timer.fire();
            }
          }
          return false;
        });
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.uncertain,
            CardChargeFailureReason.accessTokenUnavailable,
          ),
        );
        await _settle();
        _expectNoPendingWork(run.armed);
        // Only the SDK's own refresh attempts reached the wire.
        expect(wire.requests.map((r) => r.url.path).toSet(), {_tokenPath});
        // The connection returns and an ordinary call makes the SDK use it:
        // the session is refreshed, and nothing waiting for that is sent.
        final fresh = _syntheticJwt('device-back', _nowSeconds() + 3600);
        wire
          ..fail = null
          ..answer = (request) => request.url.path == _tokenPath
              ? wire.refreshed(fresh)
              : _ok(request);
        await wire.transport.invoke('sync_pull', <String, dynamic>{});
        expect(wire.client.auth.currentSession?.accessToken, fresh);
        await _settle();
        expect(wire.cardRequests, isEmpty);
        expect(run.armed.timers.where((t) => t.isActive), isEmpty);
      });
    });

    test('a refused refresh signs the SDK out: it then sends the public key '
        'as the Bearer, and the 401 that follows is unauthenticated', () async {
      await _offline(() async {
        final wire = _Wire(
          answer: (request) => request.url.path == _tokenPath
              ? http.Response(
                  '{"code":400,"error_code":"refresh_token_not_found",'
                  '"msg":"synthetic"}',
                  400,
                  headers: _json,
                  request: request,
                )
              : http.Response(
                  '{"ok":false,"error":"invalid_session"}',
                  401,
                  headers: _json,
                  request: request,
                ),
        );
        addTearDown(wire.client.dispose);
        await wire.expireSession();
        final run = _capture(() => wire.transport.sendCardCharge(_startBody()));
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.unauthenticated,
            CardChargeFailureReason.httpStatus,
            status: 401,
          ),
        );
        await _settle();
        _expectNoPendingWork(run.armed);
        expect(
          wire.cardRequests.single.headers['authorization'],
          'Bearer $_publicKey',
        );
      });
    });

    test('the failure kinds and reasons are transport facts only (no '
        'decline, approval or attempt state)', () {
      expect(CardChargeFailureKind.values.map((k) => k.name), [
        'notSent',
        'unauthenticated',
        'notApplied',
        'uncertain',
      ]);
      expect(CardChargeFailureReason.values.map((r) => r.name), [
        'deviceSessionUnverified',
        'devicePrincipalPending',
        'capabilityUnavailable',
        'unsupportedPlatform',
        'unencodableBody',
        'accessTokenUnavailable',
        'handoffRefused',
        'timeout',
        'transport',
        'httpStatus',
        'malformedAnswer',
      ]);
    });

    test('the 200-refusal tokens are exactly the seven the function only '
        'answers with another status', () {
      expect(cardChargeNon200Errors, _non200Tokens.toSet());
      expect(cardChargeNon200Errors, hasLength(7));
    });
  });

  group('the card route is recognized fail-closed, whatever the base '
      'URL', () {
    for (final (base, gated) in [
      (_url, true),
      ('$_url/', true),
      ('$_url/prefix', true),
      ('https://SYNTHETIC.invalid:443', true),
      ('$_url/.', false),
      ('$_url/a/..', false),
      ('$_url/?a', false),
      ('$_url#f', false),
      ('$_url/?%FF', false),
    ]) {
      final outcome = gated
          ? 'one gated exchange'
          : 'refused before any IO with zero requests, never passed through';
      test('$base: $outcome', () async {
        await _offline(() async {
          final wire = _wire(url: base);
          final body = _startBody();
          final run = _capture(() => wire.transport.sendCardCharge(body));
          final result = await run.result;
          await _settle();
          _expectNoPendingWork(run.armed);
          if (gated) {
            expect(result, isA<CardChargeAnswered>());
            expect(wire.requests, hasLength(1));
            final sent = wire.requests.single;
            expect(sent.url.pathSegments.last, posCardChargeFunction);
            expect(sent.followRedirects, isFalse);
            expect(sent.bodyBytes, utf8.encode(jsonEncode(body)));
          } else {
            expect(
              result,
              _failure(
                CardChargeFailureKind.notSent,
                CardChargeFailureReason.handoffRefused,
              ),
            );
            expect(wire.requests, isEmpty);
          }
        });
      });
    }
  });

  group('upgradable forwarding', () {
    test('hold mode refuses with zero IO and counts it; the upgrade never '
        'replays it; then exactly one exchange', () async {
      await _offline(() async {
        final held = UpgradableSyncTransport();
        final run = _capture(() => held.sendCardCharge(_startBody()));
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.devicePrincipalPending,
          ),
        );
        expect(held.heldCallCount, 1);
        final wire = _wire();
        held.upgrade(wire.transport);
        await _settle();
        expect(wire.requests, isEmpty);
        _expectNoPendingWork(run.armed, deadlines: 0);
        final body = _startBody();
        expect(await held.sendCardCharge(body), isA<CardChargeAnswered>());
        expect(wire.cardRequests, hasLength(1));
        expect(
          wire.cardRequests.single.bodyBytes,
          utf8.encode(jsonEncode(body)),
        );
        expect(held.heldCallCount, 1);
      });
    });

    test('the caller isCurrent reaches the handoff through the upgraded '
        'transport', () async {
      await _offline(() async {
        final held = UpgradableSyncTransport();
        final wire = _wire();
        held.upgrade(wire.transport);
        final run = _capture(
          () => held.sendCardCharge(_startBody(), isCurrent: () => false),
        );
        expect(
          await run.result,
          _failure(
            CardChargeFailureKind.notSent,
            CardChargeFailureReason.deviceSessionUnverified,
          ),
        );
        await _settle();
        expect(wire.requests, isEmpty);
        _expectNoPendingWork(run.armed);
      });
    });

    test('an upgrade to a transport without the capability refuses: not '
        'sent', () async {
      final held = UpgradableSyncTransport()..upgrade(_PlainTransport());
      final run = _capture(() => held.sendCardCharge(_startBody()));
      expect(
        await run.result,
        _failure(
          CardChargeFailureKind.notSent,
          CardChargeFailureReason.capabilityUnavailable,
        ),
      );
      await _settle();
      _expectNoPendingWork(run.armed, deadlines: 0);
    });
  });

  group('the HTTP boundary keeps every other route as it was', () {
    test('RPC and other function routes keep the client default redirects; '
        'the ACK route keeps its own gate', () async {
      await _offline(() async {
        final seen = <(String, bool)>[];
        final boundary = KitchenAckHttpBoundary(
          Uri.parse(_url),
          inner: MockClient((request) async {
            seen.add((request.url.path, request.followRedirects));
            return _okRpc(request);
          }),
        );
        addTearDown(boundary.close);
        Future<void> post(String path) =>
            boundary.send(http.Request('POST', Uri.parse('$_url$path')));
        await post('/functions/v1/pos-web-order-decision');
        await post('/functions/v1/pos-card-charges');
        await post('/rest/v1/rpc/sync_pull');
        await expectLater(
          post('/rest/v1/rpc/acknowledge_kitchen_print_dispatch'),
          throwsA(isA<KitchenAckDispatchDeferred>()),
        );
        expect(seen, [
          ('/functions/v1/pos-web-order-decision', true),
          ('/functions/v1/pos-card-charges', true),
          ('/rest/v1/rpc/sync_pull', true),
        ]);
      });
    });
  });

  group('no body is logged or printed', () {
    test('during card exchanges neither the SDK log nor print carries the '
        'request or answer body or a token; results print no body', () async {
      final previous = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previous);
      final records = <LogRecord>[];
      StreamSubscription<LogRecord>? subscription;
      addTearDown(() => subscription?.cancel());
      final printed = <String>[];
      final token = _syntheticJwt('logging-device', _nowSeconds() + 3600);
      await runZoned(
        () => _offline(() async {
          final wire = _Wire(
            answer: (_) => http.Response(
              jsonEncode({..._envelope, 'marker': 'answer-body-marker'}),
              200,
              headers: _json,
            ),
          );
          addTearDown(wire.client.dispose);
          // gotrue logs the session itself (tokens included) on an auth state
          // change - an SDK record outside the exchange; capture only the
          // exchanges.
          await wire.client.auth.setInitialSession(
            _sessionJson(token, _nowSeconds() + 3600),
          );
          await _settle();
          subscription = Logger.root.onRecord.listen(records.add);
          final body = {
            ..._startBody(),
            'device_session_token': 'request-body-marker',
          };
          final ok = await wire.transport.sendCardCharge(body);
          expect(ok, isA<CardChargeAnswered>());
          expect(ok.toString(), isNot(contains('marker')));
          wire.answer = (_) => http.Response(
            jsonEncode({'ok': false, 'error': 'answer-body-marker'}),
            503,
            headers: _json,
          );
          final failed = await wire.transport.sendCardCharge(body);
          expect(failed.toString(), isNot(contains('marker')));
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      final logged = [
        for (final r in records)
          '${r.loggerName} ${r.message} ${r.error} ${r.object} ${r.stackTrace}',
      ];
      expect(logged, isNotEmpty, reason: 'the SDK logs at FINEST');
      for (final secret in [
        'marker',
        token,
        'aaaaaaaa-aaaa-4aaa',
        _attemptId,
        '4200',
      ]) {
        expect(
          logged.where((l) => l.contains(secret)),
          isEmpty,
          reason: secret,
        );
        expect(
          printed.where((l) => l.contains(secret)),
          isEmpty,
          reason: secret,
        );
      }
    });
  });
}

final class _PlainTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      throw StateError('never called');
}
