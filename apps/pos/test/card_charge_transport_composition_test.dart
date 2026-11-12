// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: both real POS boot compositions expose
// the card Edge capability (execution packet §5 and §6). The real boot
// coordinator, the boot-created guard, the provider graph and the production
// POS client shape (createKitchenAckClient) are used; only the anonymous
// sign-in, secure storage and the final HTTP IO are synthetic. One group runs
// the REAL, unchanged pos-card-charge handler offline through node. No hosted
// service, provider, terminal or card is used; creating an HttpClient is
// refused and recorded, and any recorded attempt fails the test.
import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show
        File,
        HttpClient,
        HttpOverrides,
        Process,
        SecurityContext,
        SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/main.dart' as pos;
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

const _url = 'https://synthetic.invalid';
const _publicKey = 'synthetic-public-key';
const _cardPath = '/functions/v1/pos-card-charge';
const _tokenPath = '/auth/v1/token';
const _deviceId = 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
const _pinId = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
const _attemptId = 'cccccccc-cccc-4ccc-accc-cccccccccccc';
const _json = {'content-type': 'application/json'};

const _credential = DeviceSessionCredential(
  deviceId: _deviceId,
  sessionToken: 'synthetic-device-proof',
);
const _context = DeviceContext(
  organizationId: 'synthetic-org',
  restaurantId: 'synthetic-restaurant',
  branchId: 'synthetic-branch',
  deviceId: _deviceId,
  deviceType: 'pos',
  deviceSessionId: 'synthetic-device-session',
);

Map<String, dynamic> _common(String action) => <String, dynamic>{
  'action': action,
  'pin_session_id': _pinId,
  'device_id': _deviceId,
  'device_session_token': 'synthetic-device-proof',
  'attempt_id': _attemptId,
};

Map<String, dynamic> _startBody({Object amount = 1200}) => {
  ..._common('start'),
  'mode': 'test',
  'amount_minor': amount,
  'currency_code': 'ILS',
};

const _envelope = <String, Object?>{
  'ok': true,
  'attempt_id': _attemptId,
  'state': 'sent',
  'classification': 'test_sent',
  'recorded': false,
  'amount_minor': 1200,
  'currency_code': 'ILS',
  'server_ts': '2026-10-29T08:00:00Z',
};

/// Refuses every new HttpClient and records the attempt, so a refusal some
/// layer swallows still fails the test (see tearDown).
class _NoNetwork extends HttpOverrides {
  final attempts = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts.add('HttpClient');
    throw StateError('NETWORK_DENIED_IN_CARD_TEST');
  }
}

class _Logo implements DeviceReceiptLogoReader {
  @override
  Future<ReceiptLogoBytes?> load(String objectPath) async => null;
}

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A synthetic, unsigned JWT whose `exp` is [expiresAt].
String _jwt(String subject, int expiresAt) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': subject, 'role': 'authenticated', 'exp': expiresAt})}.'
      'synthetic-signature';
}

String _session(String accessToken, int expiresAt) => jsonEncode({
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

/// The production POS client shape over a scripted MockClient.
final class _Wire {
  _Wire({this.realEdge = false});

  final bool realEdge;
  final requests = <http.Request>[];
  final edgeRuns = <Map<String, dynamic>>[];
  Completer<http.Response>? cardGate;
  Completer<http.Response>? refreshGate;
  Object? Function(String rpc)? rpcAnswer;

  late final created = SupabaseSyncRpcTransport.createKitchenAckClient(
    _url,
    _publicKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    inner: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path == _tokenPath) {
        final gate = refreshGate;
        if (gate != null) return gate.future;
        return http.Response('{}', 400, headers: _json, request: request);
      }
      if (path.startsWith('/rest/v1/rpc/')) {
        final answer = rpcAnswer?.call(path.substring('/rest/v1/rpc/'.length));
        return http.Response(
          jsonEncode(answer ?? const {'ok': true}),
          200,
          headers: _json,
          request: request,
        );
      }
      if (path == _cardPath) {
        if (realEdge) return _realEdge(request);
        final gate = cardGate;
        if (gate != null) return gate.future;
        return http.Response(
          jsonEncode(_envelope),
          200,
          headers: _json,
          request: request,
        );
      }
      return http.Response('{}', 404, headers: _json, request: request);
    }),
  );

  SupabaseSyncRpcTransport get transport => created.transport;
  SupabaseClient get client => created.client;
  List<http.Request> get cards =>
      requests.where((r) => r.url.path == _cardPath).toList();

  /// The request, its exact bytes included, through the real handler (node).
  Future<http.Response> _realEdge(http.Request request) async {
    final process = await Process.start('node', [
      [
        File('apps/pos/test/fixtures/card_charge_edge.mjs'),
        File('test/fixtures/card_charge_edge.mjs'),
      ].firstWhere((file) => file.existsSync()).absolute.path,
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(
      jsonEncode({
        'url': request.url.toString(),
        'method': request.method,
        'headers': request.headers,
        'body': base64.encode(request.bodyBytes),
      }),
    );
    await process.stdin.close();
    expect(await process.exitCode, 0);
    expect(await errors, isEmpty);
    final result = jsonDecode(await output) as Map<String, dynamic>;
    edgeRuns.add(result);
    return http.Response(
      jsonEncode(result['body']),
      result['status'] as int,
      headers: _json,
      request: request,
    );
  }
}

Future<
  ({
    DeviceSessionGuardedTransport guard,
    pos.PosBootCoordinator coordinator,
    pos.PosDeviceSeams seams,
    Future<void> Function() goOnline,
  })
>
_boot(SyncRpcTransport transport, {bool offline = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = InMemoryDeviceSessionSecretStore();
  await store.write(_credential);
  await store.writeCachedContext(_context);
  var online = !offline;
  final coordinator = pos.PosBootCoordinator(
    prefs: prefs,
    demoMode: false,
    secretStore: store,
    createSession: () async {
      if (!online) throw const SocketException('synthetic offline');
      return (
        transport: transport,
        imageUrlResolver: FakeDeviceImageUrlResolver(),
        receiptLogoReader: _Logo(),
        invalidationSourceFactory: (_) => const DisabledInvalidationSource(),
      );
    },
  );
  final root =
      pos.buildPosBootRoot(
            prefs: prefs,
            locale: const Locale('en'),
            coordinator: coordinator,
            includePeriodicWork: false,
            extraOverrides: [
              runtimeConfigProvider.overrideWithValue(
                RuntimeConfig.test(isDemoMode: false),
              ),
              posSyncSessionProvider.overrideWithValue(
                const SyncSession(pinSessionId: _pinId, deviceId: _deviceId),
              ),
            ],
          )
          as DeviceBootGate<pos.PosBootResult>;
  final initial = await coordinator.bootstrap();
  final scope = root.builder(initial) as ProviderScope;
  final container = ProviderContainer(overrides: scope.overrides);
  addTearDown(container.dispose);
  container.read(posDeviceContextProvider.notifier).set(_context);
  final guarded = container.read(posAuthTransportProvider);
  // The provider graph hands every consumer the boot-created guard.
  expect(guarded, same(initial.seams!.transport));
  expect(guarded, isA<DeviceSessionGuardedTransport>());
  expect(guarded, isA<AuthenticatedCardChargeTransport>());
  return (
    guard: guarded as DeviceSessionGuardedTransport,
    coordinator: coordinator,
    seams: initial.seams!,
    goOnline: () async {
      online = true;
      final upgraded = await coordinator.bootstrap();
      expect(upgraded.seams, same(initial.seams));
      expect(container.read(posAuthTransportProvider), same(guarded));
    },
  );
}

Future<_Wire> _wire({bool realEdge = false}) async {
  final wire = _Wire(realEdge: realEdge);
  addTearDown(wire.client.dispose);
  await wire.client.auth.setInitialSession(
    _session(_jwt('synthetic-device', _now() + 3600), _now() + 3600),
  );
  return wire;
}

/// A real barrier before asserting that nothing MORE happened: lets SDK
/// continuations and isolate decoding finish.
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

/// One captured timer: its duration, a way to fire it, and the real stand-in
/// timer that tells whether it is still pending.
typedef _Captured = ({Duration duration, void Function() fire, Timer timer});

/// Captures the timers a call creates (non-zero one-shots), so the test reads
/// the deadline the composition armed and fires it on demand, and records any
/// periodic timer in [periodic]. A captured timer stays pending (a day) until
/// fired; firing cancels it first, so it is inactive afterwards, exactly as a
/// timer that ran.
Future<T> _capturingTimers<T>(
  List<_Captured> timers,
  Future<T> Function() body, {
  List<Duration>? periodic,
}) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration <= Duration.zero) {
        return parent.createTimer(zone, duration, callback);
      }
      final timer = parent.createTimer(zone, const Duration(days: 1), () {});
      timers.add((
        duration: duration,
        fire: () {
          timer.cancel();
          callback();
        },
        timer: timer,
      ));
      return timer;
    },
    createPeriodicTimer: (self, parent, zone, period, callback) {
      periodic?.add(period);
      return parent.createPeriodicTimer(zone, period, (_) {})..cancel();
    },
  ),
);

/// After a card call returned and a settle: no timer it armed is still
/// pending (no delayed re-send can follow), nothing periodic was armed, and it
/// armed [deadlines] deadline(s) - none for a call the guard or the hold mode
/// refused before the SDK call.
void _expectNoPendingWork(
  List<_Captured> timers,
  List<Duration> periodic, {
  int deadlines = 1,
}) {
  expect(
    timers.where((t) => t.timer.isActive).map((t) => t.duration),
    isEmpty,
    reason: 'a timer is still pending',
  );
  expect(periodic, isEmpty);
  expect(
    timers.where((t) => t.duration == posCardChargeTimeout),
    hasLength(deadlines),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NoNetwork network;
  setUp(() => HttpOverrides.global = network = _NoNetwork());
  tearDown(() {
    HttpOverrides.global = null;
    expect(network.attempts, isEmpty, reason: 'unexpected network access');
  });

  test('online boot: the boot guard is the card capability and sends one '
      'exact request with the current session token', () async {
    final wire = await _wire();
    final boot = await _boot(wire.transport);
    final body = _startBody();
    final result = await boot.guard.sendCardCharge(body);
    expect(result, isA<CardChargeAnswered>());
    expect(wire.cards, hasLength(1));
    final request = wire.cards.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), '$_url$_cardPath');
    expect(request.bodyBytes, utf8.encode(jsonEncode(body)));
    expect(
      request.headers['authorization'],
      'Bearer ${wire.client.auth.currentSession!.accessToken}',
    );
    expect(request.headers['apikey'], _publicKey);
    expect(
      request.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('origin')),
    );
  });

  test('degraded boot: a held card exchange is refused with zero IO, the '
      'in-place upgrade never replays it, then one request', () async {
    final wire = await _wire();
    final boot = await _boot(wire.transport, offline: true);
    final timers = <_Captured>[];
    final periodic = <Duration>[];
    expect(
      await _capturingTimers(
        timers,
        () => boot.guard.sendCardCharge(_startBody()),
        periodic: periodic,
      ),
      _failure(
        CardChargeFailureKind.notSent,
        CardChargeFailureReason.devicePrincipalPending,
      ),
    );
    expect(boot.coordinator.upgradableTransport!.heldCallCount, 1);
    expect(wire.requests, isEmpty);
    await boot.goOnline();
    await _settle();
    expect(wire.cards, isEmpty);
    _expectNoPendingWork(timers, periodic, deadlines: 0);
    expect(
      await boot.guard.sendCardCharge(_startBody()),
      isA<CardChargeAnswered>(),
    );
    expect(wire.cards, hasLength(1));
  });

  for (final offline in [false, true]) {
    final name = offline ? 'degraded-then-upgraded' : 'online';
    test('$name boot: the card call arms the dedicated deadline; past it the '
        'exchange is uncertain and the late answer causes no second '
        'send', () async {
      final wire = await _wire();
      final boot = await _boot(wire.transport, offline: offline);
      if (offline) await boot.goOnline();
      wire.cardGate = Completer<http.Response>();
      final timers = <_Captured>[];
      final periodic = <Duration>[];
      final pending = _capturingTimers(
        timers,
        () => boot.guard.sendCardCharge(_startBody()),
        periodic: periodic,
      );
      await _until(() => wire.cards.isNotEmpty);
      expect(wire.cards, hasLength(1));
      expect(timers.map((t) => t.duration), [posCardChargeTimeout]);
      timers.single.fire();
      expect(
        await pending,
        _failure(
          CardChargeFailureKind.uncertain,
          CardChargeFailureReason.timeout,
        ),
      );
      wire.cardGate!.complete(
        http.Response(jsonEncode(_envelope), 200, headers: _json),
      );
      await _settle();
      expect(wire.cards, hasLength(1));
      _expectNoPendingWork(timers, periodic);
    });
  }

  test('a block that lands during the SDK token refresh refuses at the '
      'handoff through the boot guard: nothing is sent', () async {
    final wire = _Wire();
    addTearDown(wire.client.dispose);
    final expired = _now() - 3600;
    await wire.client.auth.setInitialSession(
      _session(_jwt('synthetic-device', expired), expired),
    );
    wire.refreshGate = Completer<http.Response>();
    final boot = await _boot(wire.transport);
    final timers = <_Captured>[];
    final periodic = <Duration>[];
    final pending = _capturingTimers(
      timers,
      () => boot.guard.sendCardCharge(_startBody()),
      periodic: periodic,
    );
    await _until(() => wire.requests.isNotEmpty);
    expect(wire.requests.map((r) => r.url.path), [_tokenPath]);
    boot.guard.block();
    wire.refreshGate!.complete(
      http.Response(
        _session(_jwt('synthetic-device', _now() + 3600), _now() + 3600),
        200,
        headers: _json,
      ),
    );
    expect(
      await pending,
      _failure(
        CardChargeFailureKind.notSent,
        CardChargeFailureReason.deviceSessionUnverified,
      ),
    );
    await _settle();
    expect(wire.cards, isEmpty);
    boot.guard.allow();
    await _settle();
    expect(wire.cards, isEmpty); // allow never replays it
    _expectNoPendingWork(timers, periodic);
  });

  test('a block that lands right after the call started (before the SDK '
      'reaches the HTTP handoff) refuses: nothing is sent', () async {
    final wire = await _wire();
    final boot = await _boot(wire.transport);
    final timers = <_Captured>[];
    final periodic = <Duration>[];
    final pending = _capturingTimers(
      timers,
      () => boot.guard.sendCardCharge(_startBody()),
      periodic: periodic,
    );
    boot.guard.block(); // synchronously, before any SDK continuation runs
    expect(
      await pending,
      _failure(
        CardChargeFailureKind.notSent,
        CardChargeFailureReason.deviceSessionUnverified,
      ),
    );
    await _settle();
    expect(wire.cards, isEmpty);
    _expectNoPendingWork(timers, periodic);
  });

  test('a revoked device-session verdict blocks the boot guard: the card '
      'exchange is refused before the Edge invocation', () async {
    final wire = await _wire();
    final boot = await _boot(wire.transport);
    wire.rpcAnswer = (rpc) => rpc == 'restore_device_session'
        ? const {'ok': false, 'error': 'invalid_session', 'reason': 'revoked'}
        : null;
    final pairing = boot.seams.pairing as SupabaseDevicePairingRepository;
    final outcome = await pairing.restoreOutcome(expectedDeviceType: 'pos');
    expect(outcome, isA<DeviceSessionRestoreRejected>());
    expect(boot.guard.isBlocked, isTrue);
    final timers = <_Captured>[];
    final periodic = <Duration>[];
    expect(
      await _capturingTimers(
        timers,
        () => boot.guard.sendCardCharge(_startBody()),
        periodic: periodic,
      ),
      _failure(
        CardChargeFailureKind.notSent,
        CardChargeFailureReason.deviceSessionUnverified,
      ),
    );
    await _settle();
    expect(wire.cards, isEmpty);
    _expectNoPendingWork(timers, periodic, deadlines: 0);
  });

  test('a revoked heartbeat verdict blocks the boot guard: the card '
      'exchange is refused before the Edge invocation', () async {
    final wire = await _wire();
    final boot = await _boot(wire.transport);
    wire.rpcAnswer = (rpc) => switch (rpc) {
      'restore_device_session' => const {
        'ok': true,
        'device_id': _deviceId,
        'organization_id': 'synthetic-org',
        'restaurant_id': 'synthetic-restaurant',
        'branch_id': 'synthetic-branch',
        'device_session_id': 'synthetic-device-session',
        'device_type': 'pos',
      },
      'heartbeat_device_session' => const {
        'ok': false,
        'error': 'invalid_session',
        'reason': 'revoked',
      },
      _ => null,
    };
    final pairing = boot.seams.pairing as SupabaseDevicePairingRepository;
    expect(
      await pairing.restoreOutcome(expectedDeviceType: 'pos'),
      isA<DeviceSessionRestored>(),
    );
    expect(boot.guard.isBlocked, isFalse);
    expect(await pairing.heartbeat(), DeviceHeartbeatResult.invalidSession);
    expect(boot.guard.isBlocked, isTrue);
    final timers = <_Captured>[];
    final periodic = <Duration>[];
    expect(
      await _capturingTimers(
        timers,
        () => boot.guard.sendCardCharge(_startBody()),
        periodic: periodic,
      ),
      _failure(
        CardChargeFailureKind.notSent,
        CardChargeFailureReason.deviceSessionUnverified,
      ),
    );
    await _settle();
    expect(wire.cards, isEmpty);
    _expectNoPendingWork(timers, periodic, deadlines: 0);
  });

  group('the real pos-card-charge handler (unchanged, offline, flag off)', () {
    test(
      'accepts the exact request: no Origin, path, Bearer, media type and '
      'key set pass its boundary; the flag-off refusal is answered',
      () async {
        final wire = await _wire(realEdge: true);
        final boot = await _boot(wire.transport);
        final result = await boot.guard.sendCardCharge(_startBody());
        expect(result, isA<CardChargeAnswered>());
        expect((result as CardChargeAnswered).body, {
          'ok': false,
          'error': 'card_payments_disabled',
        });
        expect(wire.cards, hasLength(1));
        expect(wire.edgeRuns.single['status'], 200);
        expect(wire.edgeRuns.single['fetches'], isEmpty);
        expect(wire.edgeRuns.single['globalFetches'], isEmpty);
      },
    );

    test('a schema refusal (a non-integer amount) is notApplied, never '
        'uncertain', () async {
      final wire = await _wire(realEdge: true);
      final boot = await _boot(wire.transport);
      final timers = <_Captured>[];
      final periodic = <Duration>[];
      expect(
        await _capturingTimers(
          timers,
          () => boot.guard.sendCardCharge(_startBody(amount: 12.5)),
          periodic: periodic,
        ),
        _failure(
          CardChargeFailureKind.notApplied,
          CardChargeFailureReason.httpStatus,
          status: 400,
        ),
      );
      await _settle();
      expect(wire.cards, hasLength(1));
      _expectNoPendingWork(timers, periodic);
      expect(wire.edgeRuns.single['body'], {
        'ok': false,
        'error': 'invalid_request',
      });
      expect(wire.edgeRuns.single['fetches'], isEmpty);
      expect(wire.edgeRuns.single['globalFetches'], isEmpty);
    });

    test('an unproven status (no database reachable) is the 503 unavailable: '
        'uncertain', () async {
      final wire = await _wire(realEdge: true);
      final boot = await _boot(wire.transport);
      final timers = <_Captured>[];
      final periodic = <Duration>[];
      expect(
        await _capturingTimers(
          timers,
          () => boot.guard.sendCardCharge(_common('status')),
          periodic: periodic,
        ),
        _failure(
          CardChargeFailureKind.uncertain,
          CardChargeFailureReason.httpStatus,
          status: 503,
        ),
      );
      await _settle();
      expect(wire.cards, hasLength(1));
      _expectNoPendingWork(timers, periodic);
      final run = wire.edgeRuns.single;
      expect(run['body'], {'ok': false, 'error': 'unavailable'});
      // The proof's one refused fetch, to the synthetic origin; nothing else.
      expect(run['fetches'], ['$_url/rest/v1/rpc/card_attempt_context']);
      expect(run['globalFetches'], isEmpty);
    });
  });
}
