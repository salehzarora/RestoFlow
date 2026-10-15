@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/kitchen_contained_ack.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_containment.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_worker.dart';
import 'package:restoflow_pos/src/spool/pending_kitchen_ack_coordinator.dart';
import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:supabase/supabase.dart' as sdk;

// These tests execute the locked Supabase SDK, its authentication wrapper and
// the production HTTP boundary. Only the last HTTP transport and printers are
// synthetic. No hosted service or physical printer is contacted.
const _dispatchId = '50000000-0000-4000-8000-000000000001';
const _otherDispatchId = '50000000-0000-4000-8000-000000000002';
const _orderId = '70000000-0000-4000-8000-000000000001';
const _ackFunction = 'acknowledge_kitchen_print_dispatch';
const _ackPath = '/rest/v1/rpc/$_ackFunction';
const _context = DeviceContext(
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: 'device',
);
const _scope = KitchenImportScope(
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: 'device',
);
const _credential = DeviceSessionCredential(
  deviceId: 'device',
  sessionToken: 'synthetic-device-session',
);
final _at = DateTime.utc(2026, 10, 15);
final _url = Uri.parse('https://synthetic.invalid');
final _destination = ResolvedKitchenDestination(
  destination: const NetworkKitchenDestination(host: '192.0.2.1', port: 9100),
  fingerprint: kitchenDestinationFingerprint('network|192.0.2.1|9100'),
  displayLabel: 'Synthetic kitchen',
  transportKind: 'network',
  paperWidth: '80mm',
);

Map<String, Object?> _policy({String mode = 'ordinary', int revision = 1}) => {
  'ok': true,
  'organization_id': 'org',
  'restaurant_id': 'restaurant',
  'branch_id': 'branch',
  'device_id': 'device',
  'mode': mode,
  'revision': revision,
  'held_dispatch_ids': <String>[],
  'target_request_id': null,
  'expires_at': null,
};

Map<String, dynamic> _ackParams({String dispatchId = _dispatchId}) => {
  'p_device_id': _credential.deviceId,
  'p_session_token': _credential.sessionToken,
  'p_dispatch_id': dispatchId,
  'p_client_status': 'imported',
  'p_error_code': null,
};

String _jwt(int expiration) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'exp': expiration, 'sub': '10000000-0000-4000-8000-000000000001', 'role': 'authenticated'})}.'
      'synthetic-signature';
}

Map<String, dynamic> _session({required bool expired}) => {
  'access_token': _jwt(
    expired ? 1 : DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  ),
  'refresh_token': 'synthetic-refresh',
  'expires_in': 3600,
  'token_type': 'bearer',
  'user': {
    'id': '10000000-0000-4000-8000-000000000001',
    'aud': 'authenticated',
    'role': 'authenticated',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
    'is_anonymous': true,
  },
};

class _HttpWire extends http.BaseClient {
  final refreshEntered = Completer<void>();
  final releaseRefresh = Completer<void>();
  final ackEntered = Completer<void>();
  final acknowledgements = <Map<String, dynamic>>[];
  final ackRedirects = <bool>[];
  int refreshCalls = 0;
  int policyCalls = 0;
  int ackCalls = 0;
  int otherCalls = 0;
  Future<Object?> Function(int call)? policyResponse;
  Future<http.StreamedResponse> Function(http.BaseRequest)? ackResponse;

  http.StreamedResponse response(http.BaseRequest request, Object? body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/auth/v1/token') {
      refreshCalls++;
      if (!refreshEntered.isCompleted) refreshEntered.complete();
      await releaseRefresh.future;
      return response(request, _session(expired: false));
    }
    if (request.url.path == '/rest/v1/rpc/pos_kitchen_print_containment') {
      policyCalls++;
      return response(
        request,
        await policyResponse?.call(policyCalls) ?? _policy(),
      );
    }
    if (request.url.path == _ackPath) {
      // Count delegation before any fake-wire await, independently of auth and
      // policy traffic. A locally denied operation must never enter this arm.
      ackCalls++;
      ackRedirects.add(request.followRedirects);
      acknowledgements.add(
        Map<String, dynamic>.from(
          jsonDecode(await request.finalize().bytesToString()) as Map,
        ),
      );
      if (!ackEntered.isCompleted) ackEntered.complete();
      final hook = ackResponse;
      if (hook != null) return hook(request);
      return response(request, {
        'ok': true,
        'completed': false,
        'idempotency_replay': false,
      });
    }
    if (request.url.path == '/rest/v1/rpc/unrelated_probe') {
      otherCalls++;
      return response(request, {'ok': true});
    }
    throw StateError('Unexpected synthetic HTTP route');
  }
}

class _SdkHarness {
  _SdkHarness({
    Duration timeout = const Duration(seconds: 5),
    bool configureBoundary = true,
  }) {
    if (configureBoundary) {
      final pair = SupabaseSyncRpcTransport.createKitchenAckClient(
        _url.toString(),
        'synthetic-public-key',
        inner: wire,
        authOptions: const sdk.AuthClientOptions(autoRefreshToken: false),
        timeout: timeout,
      );
      boundary = pair.boundary;
      client = pair.client;
      rawTransport = pair.transport;
    } else {
      boundary = KitchenAckHttpBoundary(_url, inner: wire);
      client = sdk.SupabaseClient(
        _url.toString(),
        'synthetic-public-key',
        httpClient: boundary,
        authOptions: const sdk.AuthClientOptions(autoRefreshToken: false),
      );
      rawTransport = SupabaseSyncRpcTransport(client, timeout: timeout);
    }
    transport = DeviceSessionGuardedTransport(rawTransport);
  }

  final wire = _HttpWire();
  late final KitchenAckHttpBoundary boundary;
  late final sdk.SupabaseClient client;
  late final SupabaseSyncRpcTransport rawTransport;
  late final DeviceSessionGuardedTransport transport;

  Future<void> session({bool expired = false}) async {
    await client.auth.setInitialSession(jsonEncode(_session(expired: expired)));
    expect(client.auth.currentSession!.isExpired, expired);
  }

  Future<void> close() async {
    if (!wire.releaseRefresh.isCompleted) wire.releaseRefresh.complete();
    await client.dispose();
    boundary.close();
  }
}

class _PolicyTransport implements SyncRpcTransport {
  Object? policy = _policy();

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    expect(function, 'pos_kitchen_print_containment');
    return policy;
  }
}

class _HookedSecrets extends InMemoryDeviceSessionSecretStore {
  Future<void> Function()? beforeRead;

  @override
  Future<DeviceSessionCredential?> read() async {
    final hook = beforeRead;
    beforeRead = null;
    await hook?.call();
    return super.read();
  }
}

class _Renderer implements KitchenDispatchBytesRenderer {
  @override
  Future<Uint8List> renderToBytes(
    KitchenDispatchDocument dispatch, {
    String? customerPhoneOverride,
  }) async => Uint8List.fromList([1, 2, 3]);
}

class _SpoolHarness {
  final policyTransport = _PolicyTransport();
  final secrets = InMemoryDeviceSessionSecretStore();
  final ackSecrets = _HookedSecrets();
  final cipher = AesGcmKitchenSpoolCipher();
  final key = SecretValue(base64UrlEncode(List<int>.filled(32, 42)));
  late Directory directory;
  late KitchenSpoolDatabase database;
  late DriftKitchenSpoolStore store;
  late KitchenPrintContainment guard;
  late SupabaseKitchenDispatchAckRepository repository;
  bool current = true;
  int printerSends = 0;

  KitchenPrintContainment makeGuard(SyncRpcTransport transport) {
    final cache = <String, String>{};
    return KitchenPrintContainment(
      context: _context,
      secretStore: secrets,
      transport: transport,
      isCurrent: () => current,
      isOffline: () => false,
      readCache: (key) async => cache[key],
      writeCache: (key, value) async {
        cache[key] = value;
      },
      now: () => _at,
      domain: KitchenPrintContainmentDomain(),
    );
  }

  Future<void> open() async {
    directory = await Directory.systemTemp.createTemp('rf_r4_sdk_');
    database = await KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: () async => directory,
    ).open();
    store = DriftKitchenSpoolStore(database);
    await secrets.write(_credential);
    await ackSecrets.write(_credential);
    guard = makeGuard(policyTransport);
    repository = SupabaseKitchenDispatchAckRepository(
      transport: policyTransport,
      secretStore: ackSecrets,
    );
  }

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }

  KitchenContainedAck contained(_SdkHarness sdkHarness) => KitchenContainedAck(
    transport: sdkHarness.transport,
    secretStore: ackSecrets,
    authorize: guard.authorizeOperation,
  );

  Future<void> seedPending() async {
    final importer = KitchenDispatchImportCoordinator(
      store: store,
      cipher: cipher,
      key: key,
      scope: _scope,
      destination: _destination,
      ackRepository: repository,
      localJobIdGenerator: () => 'synthetic-sdk-job',
      now: () => _at,
      authorizeOperation: guard.authorizeOperation,
    );
    final result = await importer.importDispatches([
      PulledKitchenDispatch(
        dispatchId: _dispatchId,
        dispatchType: 'initial_order',
        orderId: _orderId,
        payloadVersion: 1,
        createdAt: _at.toIso8601String(),
        moneyFreePayload: const {
          'v': 1,
          'kind': 'initial_order',
          'order_code': 'Synthetic',
          'order_type': 'takeaway',
          'items': [
            {'qty': 1, 'name': 'Synthetic item'},
          ],
        },
      ),
    ]);
    expect(result.imported, 1);
    expect(result.acked, 0);
    expect(
      (await row()).pendingServerAckStatus,
      KitchenServerAckStatus.imported,
    );
  }

  Future<void> block() async {
    policyTransport.policy = _policy(mode: 'blocked', revision: 2);
    expect(await guard.synchronize(), isTrue);
  }

  Future<KitchenSpoolJobRow> row() async =>
      (await store.findByDispatchId(_dispatchId))!;

  Future<KitchenAckFlushOutcome> flush(KitchenContainedAck ack) async =>
      flushAck(
        store,
        repository,
        await row(),
        _at,
        backoffBase: const Duration(seconds: 1),
        backoffCap: const Duration(minutes: 1),
        acknowledge: ack.acknowledge,
      );

  PendingKitchenAckCoordinator pending(KitchenContainedAck ack) =>
      PendingKitchenAckCoordinator(
        store: store,
        ackRepository: repository,
        acknowledge: ack.acknowledge,
        now: () => _at,
      );

  KitchenPrintWorker worker(KitchenContainedAck ack) => KitchenPrintWorker(
    store: store,
    cipher: cipher,
    key: key,
    renderer: _Renderer(),
    networkSend: ({required host, required port, required bytes}) async {
      printerSends++;
      return const KitchenTransportOutcome(
        KitchenTransportOutcomeKind.accepted,
        'synthetic',
      );
    },
    bluetoothSend: ({required address, required bytes}) async {
      fail('Unexpected synthetic Bluetooth print');
    },
    sendGate: PrinterDestinationSendGate(),
    ackRepository: repository,
    acknowledge: ack.acknowledge,
    scope: _scope,
    permission: guard.permissionForJob,
    now: () => _at,
  );
}

void _unchanged(KitchenSpoolJobRow before, KitchenSpoolJobRow after) {
  expect(after.localJobId, before.localJobId);
  expect(after.status, before.status);
  expect(after.pendingServerAckStatus, before.pendingServerAckStatus);
  expect(after.serverAcknowledgedAt, before.serverAcknowledgedAt);
  expect(after.serverAckAttemptCount, before.serverAckAttemptCount);
  expect(after.serverAckNextAttemptAt, before.serverAckNextAttemptAt);
  expect(after.serverAckLastErrorCode, before.serverAckLastErrorCode);
  expect(after.encryptedPayloadBlob, before.encryptedPayloadBlob);
  expect(after.destinationFingerprint, before.destinationFingerprint);
}

void _evidence(String scenario, _SpoolHarness h, _SdkHarness s) {
  // Counts only: credentials, payloads and URLs never enter test evidence.
  // ignore: avoid_print
  print(
    jsonEncode({
      'case': scenario,
      'authHttpCalls': s.wire.refreshCalls,
      'policyHttpCalls': s.wire.policyCalls,
      'ackHttpCalls': s.wire.ackCalls,
      'printerSends': h.printerSends,
    }),
  );
}

void main() {
  late _SpoolHarness h;
  late _SdkHarness s;

  setUp(() async {
    h = _SpoolHarness();
    await h.open();
    await h.seedPending();
    s = _SdkHarness();
    await s.session();
  });
  tearDown(() async {
    await s.close();
    await h.close();
  });

  test(
    'ordinary authorized ACK uses the real SDK and protected HTTP path',
    () async {
      expect(await h.flush(h.contained(s)), KitchenAckFlushOutcome.acked);
      expect(s.wire.ackCalls, 1);
      expect(s.wire.refreshCalls, 0);
      expect(s.wire.acknowledgements.single['p_dispatch_id'], _dispatchId);
      expect(s.wire.ackRedirects, [false]);
      expect((await h.row()).pendingServerAckStatus, isNull);
      expect(h.printerSends, 0);
    },
  );

  // REVIEW-003's positive control and both SDK-authentication-wait reproducers.
  for (final change in ['none', 'blocked', 'scope', 'credential']) {
    test('real SDK refresh wait preserves safety for $change', () async {
      await s.session(expired: true);
      final before = await h.row();
      final flushing = h.flush(h.contained(s));
      await s.wire.refreshEntered.future.timeout(const Duration(seconds: 5));
      expect(s.wire.ackCalls, 0);
      if (change == 'blocked') await h.block();
      if (change == 'scope') h.current = false;
      if (change == 'credential') {
        await h.secrets.clear();
        expect(await h.guard.synchronize(), isFalse);
      }
      s.wire.releaseRefresh.complete();
      final outcome = await flushing;
      final after = await h.row();
      expect(s.wire.refreshCalls, 1);
      if (change == 'none') {
        expect(outcome, KitchenAckFlushOutcome.acked);
        expect(s.wire.ackCalls, 1);
        expect(after.pendingServerAckStatus, isNull);
      } else {
        expect(outcome, KitchenAckFlushOutcome.skipped);
        expect(s.wire.ackCalls, 0);
        _unchanged(before, after);
      }
      expect(h.printerSends, 0);
      _evidence('refresh-$change', h, s);
    });
  }

  test(
    'worker ACK deferral recovers the same evidence without printing again',
    () async {
      final ack = h.contained(s);
      expect(await h.flush(ack), KitchenAckFlushOutcome.acked);
      await s.session(expired: true);
      final work = h.worker(ack).run();
      await s.wire.refreshEntered.future.timeout(const Duration(seconds: 5));
      final before = await h.row();
      expect(h.printerSends, 1);
      expect(before.status, KitchenSpoolJobStatus.transportAccepted);
      expect(
        before.pendingServerAckStatus,
        KitchenServerAckStatus.transportAccepted,
      );
      await h.block();
      s.wire.releaseRefresh.complete();
      await work;
      _unchanged(before, await h.row());
      expect(s.wire.ackCalls, 1);

      h.policyTransport.policy = _policy(revision: 3);
      expect(
        await h.pending(ack).flush(deviceId: 'device', branchId: 'branch'),
        (1, 0, 0),
      );
      final recovered = await h.row();
      expect(recovered.localJobId, before.localJobId);
      expect(recovered.encryptedPayloadBlob, before.encryptedPayloadBlob);
      expect(recovered.status, KitchenSpoolJobStatus.transportAccepted);
      expect(recovered.pendingServerAckStatus, isNull);
      expect(s.wire.ackCalls, 2);
      expect(
        s.wire.acknowledgements.last['p_client_status'],
        'transport_accepted',
      );
      await h.worker(ack).run();
      expect(h.printerSends, 1);
      expect(s.wire.ackCalls, 2);
      _evidence('worker-pending-recovery', h, s);
    },
  );

  test('same SDK policy response revokes an ACK waiting for refresh', () async {
    final policyEntered = Completer<void>();
    final releasePolicy = Completer<void>();
    s.wire.policyResponse = (call) async {
      if (call == 1) return _policy();
      expect(call, 2);
      policyEntered.complete();
      await releasePolicy.future;
      return _policy(mode: 'blocked', revision: 2);
    };
    h.guard = h.makeGuard(s.transport);
    late Future<bool> restriction;
    h.ackSecrets.beforeRead = () async {
      restriction = h.guard.synchronize();
      await policyEntered.future.timeout(const Duration(seconds: 5));
      await s.session(expired: true);
    };
    final before = await h.row();
    final flushing = h.flush(h.contained(s));
    await s.wire.refreshEntered.future.timeout(const Duration(seconds: 5));
    expect(s.wire.ackCalls, 0);
    releasePolicy.complete();
    expect(await restriction.timeout(const Duration(seconds: 5)), isTrue);
    s.wire.releaseRefresh.complete();
    expect(await flushing, KitchenAckFlushOutcome.skipped);
    expect(s.wire.policyCalls, 2);
    expect(s.wire.refreshCalls, 1);
    expect(s.wire.ackCalls, 0);
    _unchanged(before, await h.row());
    _evidence('shared-sdk-policy-revocation', h, s);
  });

  test(
    'concurrent protected operations cannot inherit another permit',
    () async {
      await s.session(expired: true);
      var firstCurrent = true;
      final upgrade = UpgradableSyncTransport()..upgrade(s.rawTransport);
      final transport = DeviceSessionGuardedTransport(upgrade);
      final first = transport.invokeGuardedKitchenAck(
        _ackParams(),
        isCurrent: () => firstCurrent,
      );
      // Install the error listener before releasing either operation.
      final firstResult = expectLater(
        first,
        throwsA(isA<KitchenAckDispatchDeferred>()),
      );
      await s.wire.refreshEntered.future.timeout(const Duration(seconds: 5));
      final second = transport.invokeGuardedKitchenAck(
        _ackParams(dispatchId: _otherDispatchId),
        isCurrent: () => true,
      );
      firstCurrent = false;
      s.wire.releaseRefresh.complete();
      await firstResult;
      expect(await second, isA<Map>());
      expect(s.wire.refreshCalls, 1);
      expect(s.wire.ackCalls, 1);
      expect(s.wire.acknowledgements.single['p_dispatch_id'], _otherDispatchId);
      await expectLater(
        s.client
            .schema('public')
            .rpc(
              _ackFunction,
              params: _ackParams(dispatchId: _otherDispatchId),
            ),
        throwsA(isA<KitchenAckDispatchDeferred>()),
      );
      expect(s.wire.ackCalls, 1, reason: 'Completed context cannot be reused');
    },
  );

  test(
    'blocked redispatch preserves uncertainty after the first HTTP handoff',
    () async {
      var firstResponseReceived = false;
      final invocation = s.boundary.invokeAck(
        () async {
          final first = await s.client
              .schema('public')
              .rpc(_ackFunction, params: _ackParams());
          expect(first, isA<Map>());
          expect((first as Map)['ok'], isTrue);
          firstResponseReceived = true;
          return s.client
              .schema('public')
              .rpc(_ackFunction, params: _ackParams());
        },
        _ackParams(),
        schema: 'public',
        isCurrent: () => true,
      );
      await expectLater(
        invocation,
        throwsA(
          allOf(
            isNot(isA<KitchenAckDispatchDeferred>()),
            isA<SyncTransportException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  SyncTransportErrorKind.transient,
                )
                .having(
                  (error) => error.code,
                  'code',
                  'kitchen_ack_redispatch_blocked',
                ),
          ),
        ),
      );
      expect(firstResponseReceived, isTrue);
      expect(s.wire.ackCalls, 1);
      expect(s.wire.acknowledgements, hasLength(1));
      expect(s.wire.ackRedirects, [false]);
    },
  );

  test(
    'SDK ACK without operation context fails closed at the boundary',
    () async {
      await expectLater(
        s.client.schema('public').rpc(_ackFunction, params: _ackParams()),
        throwsA(isA<KitchenAckDispatchDeferred>()),
      );
      expect(s.wire.ackCalls, 0);
    },
  );

  test(
    'guarded transport without its configured HTTP boundary defers locally',
    () async {
      await s.close();
      s = _SdkHarness(configureBoundary: false);
      await s.session();
      final before = await h.row();
      expect(await h.flush(h.contained(s)), KitchenAckFlushOutcome.skipped);
      expect(s.wire.ackCalls, 0);
      _unchanged(before, await h.row());
    },
  );

  for (final endpoint in [false, true]) {
    test(
      'actual ${endpoint ? 'endpoint' : 'payload'} mismatch cannot use ACK permit',
      () async {
        final before = await h.row();
        final mismatchedClient = endpoint
            ? sdk.SupabaseClient(
                'https://different.invalid',
                'synthetic-public-key',
                httpClient: s.boundary,
                authOptions: const sdk.AuthClientOptions(
                  autoRefreshToken: false,
                ),
              )
            : s.client;
        if (endpoint) addTearDown(mismatchedClient.dispose);
        await expectLater(
          s.boundary.invokeAck(
            () async => mismatchedClient
                .schema('public')
                .rpc(
                  _ackFunction,
                  params: _ackParams(
                    dispatchId: endpoint ? _dispatchId : _otherDispatchId,
                  ),
                ),
            _ackParams(),
            schema: 'public',
            isCurrent: () => true,
          ),
          throwsA(isA<KitchenAckDispatchDeferred>()),
        );
        expect(s.wire.ackCalls, 0);
        _unchanged(before, await h.row());
      },
    );
  }

  test('timed out authentication cannot delegate a late ACK', () async {
    await s.close();
    s = _SdkHarness(timeout: const Duration(milliseconds: 50));
    await s.session(expired: true);
    final before = await h.row();
    final flushing = h.flush(h.contained(s));
    await s.wire.refreshEntered.future.timeout(const Duration(seconds: 5));
    expect(await flushing, KitchenAckFlushOutcome.retryScheduled);
    final afterTimeout = await h.row();
    expect(
      afterTimeout.serverAckAttemptCount,
      before.serverAckAttemptCount + 1,
    );
    // Register a later SDK continuation on the same refresh before releasing
    // it, so completion drains the earlier ACK continuation deterministically.
    final resumedSdk = s.transport.invoke('unrelated_probe', {});
    s.wire.releaseRefresh.complete();
    expect(await resumedSdk, {'ok': true});
    expect(s.wire.ackCalls, 0);
    _unchanged(afterTimeout, await h.row());
    expect(
      (await h.row()).pendingServerAckStatus,
      KitchenServerAckStatus.imported,
    );
  });

  test(
    'disposed boundary prevents ACK after SDK authentication finishes',
    () async {
      await s.session(expired: true);
      final before = await h.row();
      final flushing = h.flush(h.contained(s));
      await s.wire.refreshEntered.future.timeout(const Duration(seconds: 5));
      s.boundary.close();
      s.wire.releaseRefresh.complete();
      expect(await flushing, KitchenAckFlushOutcome.skipped);
      expect(s.wire.ackCalls, 0);
      _unchanged(before, await h.row());
    },
  );

  for (final uncertain in [false, true]) {
    test(
      'already delegated ${uncertain ? 'uncertainty' : 'success'} remains honest after revocation',
      () async {
        final releaseAck = Completer<void>();
        s.wire.ackResponse = (request) async {
          await releaseAck.future;
          if (uncertain)
            throw const SocketException('Synthetic interrupted response');
          return s.wire.response(request, {
            'ok': true,
            'completed': false,
            'idempotency_replay': false,
          });
        };
        final before = await h.row();
        final flushing = h.flush(h.contained(s));
        await s.wire.ackEntered.future.timeout(const Duration(seconds: 5));
        await h.block();
        releaseAck.complete();
        expect(
          await flushing,
          uncertain
              ? KitchenAckFlushOutcome.retryScheduled
              : KitchenAckFlushOutcome.acked,
        );
        expect(s.wire.ackCalls, 1);
        final after = await h.row();
        if (uncertain) {
          expect(after.pendingServerAckStatus, before.pendingServerAckStatus);
          expect(after.serverAckAttemptCount, before.serverAckAttemptCount + 1);
        } else {
          expect(after.pendingServerAckStatus, isNull);
          expect(after.serverAcknowledgedAt, isNotNull);
        }
        expect(h.printerSends, 0);
      },
    );
  }

  test(
    'shared authentication, policy, unrelated RPC and existing direct ACK work',
    () async {
      await s.session(expired: true);
      final policy = s.transport.invoke('pos_kitchen_print_containment', {
        'p_device_id': _credential.deviceId,
        'p_session_token': _credential.sessionToken,
      });
      await s.wire.refreshEntered.future.timeout(const Duration(seconds: 5));
      s.wire.releaseRefresh.complete();
      expect(await policy, isA<Map>());
      expect(await s.transport.invoke('unrelated_probe', {}), {'ok': true});
      expect(await s.transport.invoke(_ackFunction, _ackParams()), isA<Map>());
      expect(s.wire.refreshCalls, 1);
      expect(s.wire.policyCalls, 1);
      expect(s.wire.otherCalls, 1);
      expect(s.wire.ackCalls, 1);
    },
  );
}
