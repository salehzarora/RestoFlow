import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// Scripted transport: records every invocation, returns queued responses or
/// throws queued errors. No network, no token logging.
class _FakeTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];
  final List<Object? Function()> _script = [];

  void enqueue(Object? response) => _script.add(() => response);
  void enqueueThrow(Object error) => _script.add(() => throw error);

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, Map.of(params)));
    return _script.removeAt(0)();
  }
}

Future<InMemoryDeviceSessionSecretStore> _storeWithCred() async {
  final store = InMemoryDeviceSessionSecretStore();
  await store.write(
    const DeviceSessionCredential(
      deviceId: 'dev-1',
      sessionToken: 'tok-secret-1',
    ),
  );
  return store;
}

void main() {
  group('SupabaseDeviceKitchenModeRepository (D1 contract)', () {
    late _FakeTransport transport;

    Future<SupabaseDeviceKitchenModeRepository> repo() async =>
        SupabaseDeviceKitchenModeRepository(
          transport: transport,
          secretStore: await _storeWithCred(),
          now: () => DateTime.utc(2026, 7, 20, 12),
        );

    setUp(() => transport = _FakeTransport());

    test('kds envelope -> verifiedKds with the verification time', () async {
      transport.enqueue({
        'ok': true,
        'entity': 'kitchen_workflow_mode',
        'kitchen_workflow_mode': 'kds',
        'server_ts': '2026-07-20T12:00:00Z',
      });
      final result = await (await repo()).fetchMode();
      expect(result, isA<KitchenModeVerifiedKds>());
      expect(
        (result as KitchenModeVerifiedKds).verifiedAt,
        DateTime.utc(2026, 7, 20, 12),
      );
      final (fn, params) = transport.calls.single;
      expect(fn, 'get_device_kitchen_workflow_mode');
      expect(params['p_device_id'], 'dev-1');
      expect(params['p_session_token'], 'tok-secret-1');
    });

    test(
      'printer_only WITHOUT a revision -> revisionUnavailable (never a '
      'trusted printer-only state, no fake revision, no default 1)',
      () async {
        transport.enqueue({
          'ok': true,
          'kitchen_workflow_mode': 'printer_only',
          'server_ts': 'x',
        });
        expect(
          await (await repo()).fetchMode(),
          isA<KitchenModeRevisionUnavailable>(),
        );
      },
    );

    test('every failure is typed — never a silent kds fallback', () async {
      transport.enqueue({'ok': false, 'error': 'invalid_session'});
      expect(
        await (await repo()).fetchMode(),
        isA<KitchenModeInvalidSession>(),
      );
      transport.enqueue({'ok': true, 'kitchen_workflow_mode': 'banana'});
      expect(
        await (await repo()).fetchMode(),
        isA<KitchenModeMalformedResponse>(),
      );
      transport.enqueue('not-a-map');
      expect(
        await (await repo()).fetchMode(),
        isA<KitchenModeMalformedResponse>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.auth),
      );
      expect(
        await (await repo()).fetchMode(),
        isA<KitchenModeInvalidSession>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.transient),
      );
      expect(
        await (await repo()).fetchMode(),
        isA<KitchenModeTransientFailure>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.server),
      );
      expect(await (await repo()).fetchMode(), isA<KitchenModeServerFailure>());
    });

    test('a missing credential is invalidSession without any call', () async {
      final repo = SupabaseDeviceKitchenModeRepository(
        transport: transport,
        secretStore: InMemoryDeviceSessionSecretStore(),
      );
      expect(await repo.fetchMode(), isA<KitchenModeInvalidSession>());
      expect(transport.calls, isEmpty);
    });
  });

  group('SupabaseKitchenDispatchPullRepository', () {
    late _FakeTransport transport;

    Future<SupabaseKitchenDispatchPullRepository> repo() async =>
        SupabaseKitchenDispatchPullRepository(
          transport: transport,
          secretStore: await _storeWithCred(),
        );

    setUp(() => transport = _FakeTransport());

    Map<String, Object?> row(String id, String type) => {
      'id': id,
      'dispatch_type': type,
      'order_id': 'ord-1',
      'service_round_id': type == 'service_round' ? 'round-1' : null,
      'payload_version': 1,
      'payload': {'v': 1, 'kind': type},
      'created_at': '2026-07-20T12:00:00Z',
      'claim_expires_at': '2026-07-20T12:10:00Z',
    };

    test(
      'a full page parses; the cursor tuple is forwarded VERBATIM',
      () async {
        transport.enqueue({
          'ok': true,
          'dispatches': [row('d-1', 'initial_order'), row('d-2', 'void')],
          'has_more': true,
          'next_cursor': {
            'created_at': '2026-07-20T12:00:00Z',
            'type_rank': 2,
            'id': 'd-2',
          },
        });
        final result = await (await repo()).pull(
          limit: 20,
          cursor: const KitchenDispatchCursor(
            createdAt: '2026-07-20T11:00:00Z',
            typeRank: 0,
            id: 'd-0',
          ),
        );
        expect(result, isA<KitchenDispatchPullSuccess>());
        final page = (result as KitchenDispatchPullSuccess).page;
        expect(page.dispatches.map((d) => d.dispatchId), ['d-1', 'd-2']);
        expect(page.dispatches.first.moneyFreePayload['kind'], 'initial_order');
        expect(page.hasMore, isTrue);
        expect(page.nextCursor!.typeRank, 2);
        final (_, params) = transport.calls.single;
        expect(params['p_cursor_created_at'], '2026-07-20T11:00:00Z');
        expect(params['p_cursor_type_rank'], 0);
        expect(params['p_cursor_id'], 'd-0');
        expect(params['p_limit'], 20);
      },
    );

    test('limit is validated client-side WITHOUT calling the server', () async {
      final r = await repo();
      for (final bad in [0, 51]) {
        final result = await r.pull(limit: bad);
        expect(result, isA<KitchenDispatchPullFailure>());
        expect(
          (result as KitchenDispatchPullFailure).error,
          KitchenDispatchPullError.invalidLimit,
        );
      }
      expect(transport.calls, isEmpty);
    });

    test('every server error string maps to its typed failure', () async {
      final expectations = {
        'invalid_session': KitchenDispatchPullError.invalidSession,
        'branch_not_printer_only':
            KitchenDispatchPullError.branchNotPrinterOnly,
        'readiness_required': KitchenDispatchPullError.readinessRequired,
        'invalid_cursor': KitchenDispatchPullError.invalidCursor,
        'invalid_limit': KitchenDispatchPullError.invalidLimit,
        'anything_else': KitchenDispatchPullError.serverFailure,
      };
      for (final entry in expectations.entries) {
        transport.enqueue({'ok': false, 'error': entry.key});
        final result = await (await repo()).pull();
        expect(
          (result as KitchenDispatchPullFailure).error,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test(
      'malformed pages are rejected (unknown type, contradiction)',
      () async {
        transport.enqueue({
          'ok': true,
          'dispatches': [row('d-1', 'reprint_surprise')],
          'has_more': false,
        });
        var result = await (await repo()).pull();
        expect(
          (result as KitchenDispatchPullFailure).error,
          KitchenDispatchPullError.malformedResponse,
        );
        // has_more without a cursor is a contradiction.
        transport.enqueue({'ok': true, 'dispatches': [], 'has_more': true});
        result = await (await repo()).pull();
        expect(
          (result as KitchenDispatchPullFailure).error,
          KitchenDispatchPullError.malformedResponse,
        );
      },
    );

    test('an empty page terminates cleanly', () async {
      transport.enqueue({'ok': true, 'dispatches': [], 'has_more': false});
      final result = await (await repo()).pull();
      final page = (result as KitchenDispatchPullSuccess).page;
      expect(page.dispatches, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('transport failures map to typed outcomes', () async {
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.transient),
      );
      final result = await (await repo()).pull();
      expect(
        (result as KitchenDispatchPullFailure).error,
        KitchenDispatchPullError.transientFailure,
      );
    });
  });

  group('SupabaseKitchenDispatchAckRepository (closed 001C2B API)', () {
    late _FakeTransport transport;

    Future<SupabaseKitchenDispatchAckRepository> repo() async =>
        SupabaseKitchenDispatchAckRepository(
          transport: transport,
          secretStore: await _storeWithCred(),
        );

    setUp(() => transport = _FakeTransport());

    test('imported ack succeeds; wire params are exact', () async {
      transport.enqueue({
        'ok': true,
        'dispatch_id': 'd-1',
        'completed': false,
        'idempotency_replay': false,
      });
      final result = await (await repo()).acknowledge(
        dispatchId: 'd-1',
        status: KitchenImportAckStatus.imported,
      );
      expect(result, isA<KitchenAckAccepted>());
      expect((result as KitchenAckAccepted).idempotencyReplay, isFalse);
      final (fn, params) = transport.calls.single;
      expect(fn, 'acknowledge_kitchen_print_dispatch');
      expect(params['p_client_status'], 'imported');
      expect(params['p_error_code'], isNull);
    });

    test('blocked_configuration carries a safe typed error code', () async {
      transport.enqueue({'ok': true, 'idempotency_replay': false});
      await (await repo()).acknowledge(
        dispatchId: 'd-2',
        status: KitchenImportAckStatus.blockedConfiguration,
        errorCode: 'kitchen_printer_not_configured',
      );
      final (_, params) = transport.calls.single;
      expect(params['p_client_status'], 'blocked_configuration');
      expect(params['p_error_code'], 'kitchen_printer_not_configured');
    });

    test('idempotent replays are accepted', () async {
      transport.enqueue({'ok': true, 'idempotency_replay': true});
      final result = await (await repo()).acknowledge(
        dispatchId: 'd-1',
        status: KitchenImportAckStatus.imported,
      );
      expect((result as KitchenAckAccepted).idempotencyReplay, isTrue);
    });

    test('every TERMINAL verdict maps to its closed code', () async {
      final expectations = {
        'not_claim_owner': KitchenAckTerminalCode.notClaimOwner,
        'conflict': KitchenAckTerminalCode.conflict,
        'not_found': KitchenAckTerminalCode.notFound,
        'ambiguous_print_hold': KitchenAckTerminalCode.ambiguousPrintHold,
      };
      for (final entry in expectations.entries) {
        transport.enqueue({'ok': false, 'error': entry.key});
        final result = await (await repo()).acknowledge(
          dispatchId: 'd-1',
          status: KitchenImportAckStatus.imported,
        );
        expect(
          (result as KitchenAckTerminal).code,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('session/transport failures stay typed', () async {
      transport.enqueue({'ok': false, 'error': 'invalid_session'});
      expect(
        await (await repo()).acknowledge(
          dispatchId: 'd-1',
          status: KitchenImportAckStatus.imported,
        ),
        isA<KitchenAckInvalidSession>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.transient),
      );
      expect(
        await (await repo()).acknowledge(
          dispatchId: 'd-1',
          status: KitchenImportAckStatus.imported,
        ),
        isA<KitchenAckTransientFailure>(),
      );
      transport.enqueue([1, 2, 3]);
      expect(
        await (await repo()).acknowledge(
          dispatchId: 'd-1',
          status: KitchenImportAckStatus.imported,
        ),
        isA<KitchenAckMalformedResponse>(),
      );
    });

    test('001C2C: the vocabulary is EXACTLY the five server statuses, each '
        'sent with its exact wire name', () async {
      expect(KitchenImportAckStatus.values, hasLength(5));
      final wires = {
        KitchenImportAckStatus.imported: 'imported',
        KitchenImportAckStatus.transportAccepted: 'transport_accepted',
        KitchenImportAckStatus.possiblyPrinted: 'possibly_printed',
        KitchenImportAckStatus.failedRetryable: 'failed_retryable',
        KitchenImportAckStatus.blockedConfiguration: 'blocked_configuration',
      };
      for (final entry in wires.entries) {
        transport.enqueue({'ok': true, 'idempotency_replay': false});
        await (await repo()).acknowledge(dispatchId: 'd-w', status: entry.key);
        expect(
          transport.calls.last.$2['p_client_status'],
          entry.value,
          reason: entry.key.name,
        );
      }
    });

    test('001C2C: transport_accepted parses the COMPLETED evidence', () async {
      transport.enqueue({
        'ok': true,
        'completed': true,
        'idempotency_replay': false,
      });
      final result = await (await repo()).acknowledge(
        dispatchId: 'd-c',
        status: KitchenImportAckStatus.transportAccepted,
      );
      expect((result as KitchenAckAccepted).completed, isTrue);
      // The completing device's replay keeps both facts.
      transport.enqueue({
        'ok': true,
        'completed': true,
        'idempotency_replay': true,
      });
      final replay = await (await repo()).acknowledge(
        dispatchId: 'd-c',
        status: KitchenImportAckStatus.transportAccepted,
      );
      expect((replay as KitchenAckAccepted).completed, isTrue);
      expect(replay.idempotencyReplay, isTrue);
    });

    test('001C2C: request-contract rejections are TYPED (never retried '
        'blindly as transport errors)', () async {
      transport.enqueue({'ok': false, 'error': 'invalid_status'});
      final invalidStatus = await (await repo()).acknowledge(
        dispatchId: 'd-1',
        status: KitchenImportAckStatus.imported,
      );
      expect(
        (invalidStatus as KitchenAckInvalidRequest).reason,
        KitchenAckInvalidRequestReason.invalidStatus,
      );
      transport.enqueue({'ok': false, 'error': 'invalid_error_code'});
      final invalidCode = await (await repo()).acknowledge(
        dispatchId: 'd-1',
        status: KitchenImportAckStatus.failedRetryable,
        errorCode: 'x',
      );
      expect(
        (invalidCode as KitchenAckInvalidRequest).reason,
        KitchenAckInvalidRequestReason.invalidErrorCode,
      );
    });
  });
}
