import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Process, SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/main.dart' as pos;
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

import 'online_order_inbox_fixtures.dart';

// Exercise the real boot-created outer guard and provider repository. Only
// anonymous-session establishment, secure storage and the final HTTP IO are
// synthetic. No hosted service, print endpoint or physical device is used.
const _credential = DeviceSessionCredential(
  deviceId: deviceId,
  sessionToken: 'synthetic-device-proof',
);
const _context = DeviceContext(
  organizationId: 'synthetic-org',
  restaurantId: 'synthetic-restaurant',
  branchId: 'synthetic-branch',
  deviceId: deviceId,
  deviceType: 'pos',
  deviceSessionId: 'synthetic-device-session',
);

class _Store extends InMemoryDeviceSessionSecretStore {
  Completer<DeviceSessionCredential?>? readGate;
  @override
  Future<DeviceSessionCredential?> read() => readGate?.future ?? super.read();
}

class _Logo implements DeviceReceiptLogoReader {
  @override
  Future<ReceiptLogoBytes?> load(String objectPath) async => null;
}

class _UnsupportedTransport implements SyncRpcTransport {
  var rpcCalls = 0;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    rpcCalls++;
    return {'ok': true};
  }
}

class _Wire {
  _Wire({this.realEdge = false, this.rpcError, this.replayed = false});

  final bool realEdge;
  final String? rpcError;
  final bool replayed;
  final rpcCalls = <Map<String, dynamic>>[];
  final requests = <http.Request>[];
  int status = 200;
  Completer<http.Response>? responseGate;
  late final client = SupabaseClient(
    'https://synthetic.invalid',
    'synthetic-public-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (realEdge) {
        final process = await Process.start('node', [
          [
            File('apps/pos/test/fixtures/guarded_decision_edge.mjs'),
            File('test/fixtures/guarded_decision_edge.mjs'),
          ].firstWhere((file) => file.existsSync()).absolute.path,
        ]);
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();
        process.stdin.write(
          jsonEncode({
            'url': request.url.toString(),
            'method': request.method,
            'headers': request.headers,
            'body': request.body,
            'rpcError': rpcError,
            'replayed': replayed,
          }),
        );
        await process.stdin.close();
        expect(await process.exitCode, 0);
        expect(await errors, isEmpty);
        final result = jsonDecode(await output) as Map<String, dynamic>;
        rpcCalls.addAll(
          (result['rpcCalls'] as List).cast<Map<String, dynamic>>(),
        );
        return http.Response(
          jsonEncode(result['body']),
          result['status'] as int,
          headers: {'content-type': 'application/json'},
        );
      }
      final gate = responseGate;
      if (gate != null) return gate.future;
      final body = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode(
          decisionJson(
            status: body['action'] == 'accept' ? 'accepted' : 'rejected',
          ),
        ),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  )..functions.setAuth('synthetic.device.jwt');
  late final transport = SupabaseSyncRpcTransport(
    client,
    timeout: realEdge
        ? const Duration(seconds: 5)
        : const Duration(milliseconds: 80),
  );
}

Future<
  ({
    OnlineOrderInboxRepository repository,
    DeviceSessionGuardedTransport guard,
    pos.PosBootCoordinator coordinator,
    ProviderContainer container,
    Future<void> Function() goOnline,
  })
>
_boot(SyncRpcTransport transport, _Store store, {bool offline = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
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
                const SyncSession(pinSessionId: pinId, deviceId: deviceId),
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
  expect(guarded, same(initial.seams!.transport));
  expect(guarded, isA<DeviceSessionGuardedTransport>());
  final repository = container.read(onlineOrderInboxRepositoryProvider);
  expect(repository, isA<RealOnlineOrderInboxRepository>());
  return (
    repository: repository,
    guard: guarded as DeviceSessionGuardedTransport,
    coordinator: coordinator,
    container: container,
    goOnline: () async {
      online = true;
      final upgraded = await coordinator.bootstrap();
      expect(upgraded.seams, same(initial.seams));
      expect(container.read(posAuthTransportProvider), same(guarded));
      expect(
        container.read(onlineOrderInboxRepositoryProvider),
        same(repository),
      );
    },
  );
}

Future<OnlineInboxDecisionResult> _decide(
  OnlineOrderInboxRepository repository,
  OnlineOrderDecision action,
) => repository.decide(
  requestId: requestId,
  decisionId: decisionId,
  decision: action,
  reason: action == OnlineOrderDecision.reject ? '  نفد المخزون  ' : null,
);

Matcher get _transportFailure => isA<OnlineInboxException>().having(
  (error) => error.failure,
  'retryable local transport refusal, not session rejection',
  OnlineInboxFailure.transport,
);

void _expectSingleEdgeCall(_Wire wire, OnlineOrderDecision action) {
  expect(wire.requests, hasLength(1));
  final request = wire.requests.single;
  expect(request.method, 'POST');
  expect(
    request.url.toString(),
    'https://synthetic.invalid/functions/v1/pos-web-order-decision',
  );
  expect(request.headers['Authorization'], 'Bearer synthetic.device.jwt');
  expect(jsonDecode(request.body), {
    'action': action.name,
    'request_id': requestId,
    'decision_id': decisionId,
    'device_id': deviceId,
    'pin_session_id': pinId,
    'device_session_token': _credential.sessionToken,
    if (action == OnlineOrderDecision.reject) 'reason': 'نفد المخزون',
  });
  expect(wire.requests.where((r) => r.url.path.contains('/rpc/')), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in OnlineOrderDecision.values) {
    test(
      'boot SDK to actual Edge handler forwards $action to exactly one RPC',
      () async {
        final wire = _Wire(realEdge: true);
        addTearDown(wire.client.dispose);
        final boot = await _boot(wire.transport, _Store());
        final result = await _decide(boot.repository, action);
        expect(result.replayed, false);
        _expectSingleEdgeCall(wire, action);
        expect(wire.rpcCalls, hasLength(1));
        final rpc = wire.rpcCalls.single;
        expect(
          rpc['url'],
          action == OnlineOrderDecision.accept
              ? 'https://synthetic.invalid/rest/v1/rpc/pos_accept_web_order'
              : 'https://synthetic.invalid/rest/v1/rpc/pos_reject_web_order_customer',
        );
        expect(
          (rpc['headers'] as Map)['Authorization'],
          'Bearer synthetic.device.jwt',
        );
        expect((rpc['headers'] as Map)['apikey'], 'synthetic-public-key');
        expect(rpc['body'], {
          'p_device_id': deviceId,
          'p_pin_session_id': pinId,
          'p_device_session_token': _credential.sessionToken,
          'p_request_id': requestId,
          'p_decision_id': decisionId,
          if (action == OnlineOrderDecision.reject) 'p_reason': 'نفد المخزون',
        });
      },
    );
    test(
      'real online boot forwards $action through the guarded Edge path once',
      () async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        final boot = await _boot(wire.transport, _Store());
        final result = await _decide(boot.repository, action);
        expect(
          result.status.name,
          action == OnlineOrderDecision.accept ? 'accepted' : 'rejected',
        );
        _expectSingleEdgeCall(wire, action);
      },
    );

    test('blocked boot refuses $action; allow does not replay it', () async {
      final wire = _Wire();
      addTearDown(wire.client.dispose);
      final boot = await _boot(wire.transport, _Store());
      boot.guard.block();
      await expectLater(
        _decide(boot.repository, action),
        throwsA(_transportFailure),
      );
      expect(wire.requests, isEmpty);
      boot.guard.allow();
      await Future<void>.delayed(Duration.zero);
      expect(wire.requests, isEmpty);
      await _decide(boot.repository, action);
      _expectSingleEdgeCall(wire, action);
    });

    test(
      'block during credential read prevents later $action handoff',
      () async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        final store = _Store();
        final boot = await _boot(wire.transport, store);
        final gate = store.readGate = Completer<DeviceSessionCredential?>();
        final result = _decide(boot.repository, action);
        final assertion = expectLater(result, throwsA(_transportFailure));
        boot.guard.block();
        gate.complete(_credential);
        await assertion;
        expect(wire.requests, isEmpty);
        expect(await store.read(), _credential);
      },
    );

    test(
      'real offline boot holds $action then upgrades same guarded repository',
      () async {
        final wire = _Wire();
        addTearDown(wire.client.dispose);
        final boot = await _boot(wire.transport, _Store(), offline: true);
        await expectLater(
          _decide(boot.repository, action),
          throwsA(_transportFailure),
        );
        expect(wire.requests, isEmpty);
        expect(boot.coordinator.upgradableTransport!.heldCallCount, 1);
        await boot.goOnline();
        expect(wire.requests, isEmpty); // Upgrade never replays a decision.
        boot.guard.block();
        await expectLater(
          _decide(boot.repository, action),
          throwsA(_transportFailure),
        );
        expect(wire.requests, isEmpty);
        boot.guard.allow();
        await _decide(boot.repository, action);
        _expectSingleEdgeCall(wire, action);
      },
    );
  }

  for (final error in [
    'invalid_session',
    'permission_denied',
    'decision_conflict',
  ]) {
    test(
      'actual Edge preserves authoritative $error without fallback',
      () async {
        final wire = _Wire(realEdge: true, rpcError: error);
        addTearDown(wire.client.dispose);
        final boot = await _boot(wire.transport, _Store());
        await expectLater(
          _decide(boot.repository, OnlineOrderDecision.reject),
          throwsA(
            isA<OnlineInboxException>().having(
              (e) => e.failure.name,
              'RPC denial',
              {
                'invalid_session': 'invalidSession',
                'permission_denied': 'permissionDenied',
                'decision_conflict': 'decisionConflict',
              }[error],
            ),
          ),
        );
        _expectSingleEdgeCall(wire, OnlineOrderDecision.reject);
        expect(wire.rpcCalls, hasLength(1));
      },
    );
  }

  test(
    'actual Edge replay response retains decision identity with one handoff',
    () async {
      final wire = _Wire(realEdge: true, replayed: true);
      addTearDown(wire.client.dispose);
      final boot = await _boot(wire.transport, _Store());
      final result = await _decide(boot.repository, OnlineOrderDecision.accept);
      expect(result.replayed, true);
      expect(result.decisionId, decisionId);
      _expectSingleEdgeCall(wire, OnlineOrderDecision.accept);
      expect(wire.rpcCalls, hasLength(1));
    },
  );

  test('unsupported inner capability has no ordinary RPC fallback', () async {
    final unsupported = _UnsupportedTransport();
    final boot = await _boot(unsupported, _Store());
    for (final action in OnlineOrderDecision.values) {
      await expectLater(
        _decide(boot.repository, action),
        throwsA(isA<OnlineInboxException>()),
      );
    }
    expect(unsupported.rpcCalls, 0);
    boot.guard.block();
    await boot.guard.invoke('heartbeat_device_session', {});
    expect(unsupported.rpcCalls, 1); // Legitimate recovery remains available.
    await expectLater(
      boot.guard.invoke('sync_push', {}),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.code,
          'blocked reason',
          'device_session_unverified',
        ),
      ),
    );
    expect(unsupported.rpcCalls, 1);
  });

  for (final status in [401, 403, 500]) {
    test(
      'HTTP $status through real composition never falls back or retries',
      () async {
        final wire = _Wire()..status = status;
        addTearDown(wire.client.dispose);
        final boot = await _boot(wire.transport, _Store());
        await expectLater(
          _decide(boot.repository, OnlineOrderDecision.accept),
          throwsA(isA<OnlineInboxException>()),
        );
        _expectSingleEdgeCall(wire, OnlineOrderDecision.accept);
      },
    );
  }

  test(
    'already handed-off timeout remains uncertain; block/allow never resends',
    () async {
      final wire = _Wire()..responseGate = Completer<http.Response>();
      addTearDown(wire.client.dispose);
      final boot = await _boot(wire.transport, _Store());
      await expectLater(
        _decide(boot.repository, OnlineOrderDecision.accept),
        throwsA(_transportFailure),
      );
      boot.guard.block();
      boot.guard.allow();
      wire.responseGate!.complete(
        http.Response(
          jsonEncode(decisionJson()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      _expectSingleEdgeCall(wire, OnlineOrderDecision.accept);
    },
  );
}
