import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// KITCHEN-MODE-001C3A — the trusted-revision mode parsing, the readiness
/// reporting client, and the member dispatch inspection client.
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

const _report = KitchenReadinessReport(
  appBuild: 'pos-test-build',
  transportKind: KitchenReadinessTransportKind.network,
  paperWidth: KitchenReadinessPaperWidth.mm80,
  printerFingerprint:
      'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111',
  secureSpoolAvailable: true,
  unresolvedLocalJobs: 0,
  modeRevision: 3,
);

void main() {
  group('mode getter: additive trusted revision (001C3A)', () {
    late _FakeTransport transport;

    Future<SupabaseDeviceKitchenModeRepository> repo() async =>
        SupabaseDeviceKitchenModeRepository(
          transport: transport,
          secretStore: await _storeWithCred(),
          now: () => DateTime.utc(2026, 7, 21, 12),
        );

    setUp(() => transport = _FakeTransport());

    test('kds + positive revision -> verified KDS WITH the revision', () async {
      transport.enqueue({
        'ok': true,
        'kitchen_workflow_mode': 'kds',
        'mode_revision': 7,
        'server_ts': 'x',
      });
      final result = await (await repo()).fetchMode();
      expect(result, isA<KitchenModeVerifiedKds>());
      expect((result as KitchenModeVerifiedKds).revision, 7);
    });

    test('kds WITHOUT the key (old server) -> verified KDS, null revision '
        '(readiness-ineligible, normal KDS behavior preserved)', () async {
      transport.enqueue({
        'ok': true,
        'kitchen_workflow_mode': 'kds',
        'server_ts': 'x',
      });
      final result = await (await repo()).fetchMode();
      expect(result, isA<KitchenModeVerifiedKds>());
      expect((result as KitchenModeVerifiedKds).revision, isNull);
    });

    test('printer_only + positive revision -> the TRUSTED result', () async {
      transport.enqueue({
        'ok': true,
        'kitchen_workflow_mode': 'printer_only',
        'mode_revision': 4,
        'server_ts': 'x',
      });
      final result = await (await repo()).fetchMode();
      expect(result, isA<KitchenModePrinterOnlyWithRevision>());
      expect((result as KitchenModePrinterOnlyWithRevision).revision, 4);
    });

    test('printer_only WITHOUT the key stays fail-closed '
        '(revisionUnavailable)', () async {
      transport.enqueue({
        'ok': true,
        'kitchen_workflow_mode': 'printer_only',
        'server_ts': 'x',
      });
      expect(
        await (await repo()).fetchMode(),
        isA<KitchenModeRevisionUnavailable>(),
      );
    });

    test('PRESENT-but-invalid revision is MALFORMED in either mode — never '
        'fabricated, never defaulted to 1, never clamped', () async {
      for (final bad in [0, -3, 'x', 2.5, true, null]) {
        transport.enqueue({
          'ok': true,
          'kitchen_workflow_mode': 'kds',
          'mode_revision': bad,
        });
        expect(
          await (await repo()).fetchMode(),
          isA<KitchenModeMalformedResponse>(),
          reason: 'kds with mode_revision=$bad must be malformed',
        );
        transport.enqueue({
          'ok': true,
          'kitchen_workflow_mode': 'printer_only',
          'mode_revision': bad,
        });
        expect(
          await (await repo()).fetchMode(),
          isA<KitchenModeMalformedResponse>(),
          reason: 'printer_only with mode_revision=$bad must be malformed',
        );
      }
    });
  });

  group('SupabaseKitchenReadinessRepository', () {
    late _FakeTransport transport;

    Future<SupabaseKitchenReadinessRepository> repo() async =>
        SupabaseKitchenReadinessRepository(
          transport: transport,
          secretStore: await _storeWithCred(),
        );

    setUp(() => transport = _FakeTransport());

    test('exact wire payload: pinned capability/purpose + typed evidence; '
        'token read per request; NO endpoint-shaped keys', () async {
      transport.enqueue({
        'ok': true,
        'entity': 'kitchen_printer_readiness',
        'activation_ready': true,
        'expires_at': 'x',
        'server_ts': 'x',
      });
      final result = await (await repo()).report(_report);
      expect(result, isA<KitchenReadinessAccepted>());
      expect((result as KitchenReadinessAccepted).activationReady, isTrue);
      final (fn, params) = transport.calls.single;
      expect(fn, 'report_kitchen_printer_readiness');
      expect(params, {
        'p_device_id': 'dev-1',
        'p_session_token': 'tok-secret-1',
        'p_capability': 'kitchen_printer_only_v1',
        'p_app_build': 'pos-test-build',
        'p_printer_purpose': 'kitchen_ticket',
        'p_transport_kind': 'network',
        'p_paper_width': '80mm',
        'p_printer_fingerprint': _report.printerFingerprint,
        'p_secure_spool_available': true,
        'p_unresolved_local_jobs': 0,
        'p_mode_revision': 3,
        // 001C3B1A: the assignment-aware 12-arg signature; null here (the base
        // fixture pins no assignment) is a legal, non-qualifying value.
        'p_printer_assignment_id': null,
      });
      // Privacy: the request map carries NO endpoint/payload/money keys.
      // ('p_transport_kind' legitimately contains "port"; everything else on
      // the wire is pinned above by the exact-map assertion.)
      for (final banned in [
        'host',
        'address',
        'endpoint',
        'payload',
        'customer',
        'note',
        'minor',
        'secret',
      ]) {
        expect(
          params.keys.where((k) => k.toLowerCase().contains(banned)),
          isEmpty,
          reason: 'no request key may contain "$banned"',
        );
      }
      expect(params.keys, isNot(contains('p_host')));
      expect(params.keys, isNot(contains('p_port')));
    });

    test('non-qualifying acceptance surfaces activation_ready=false', () async {
      transport.enqueue({'ok': true, 'activation_ready': false});
      final result = await (await repo()).report(_report);
      expect((result as KitchenReadinessAccepted).activationReady, isFalse);
    });

    test(
      'stale_mode_revision carries the AUTHORITATIVE server revision',
      () async {
        transport.enqueue({
          'ok': false,
          'error': 'stale_mode_revision',
          'mode_revision': 9,
        });
        final result = await (await repo()).report(_report);
        expect(result, isA<KitchenReadinessStaleModeRevision>());
        expect((result as KitchenReadinessStaleModeRevision).serverRevision, 9);
      },
    );

    test('stale_mode_revision WITHOUT a usable revision is malformed '
        '(never guessed)', () async {
      for (final bad in [null, 0, -1, 'x']) {
        transport.enqueue({
          'ok': false,
          'error': 'stale_mode_revision',
          'mode_revision': bad,
        });
        expect(
          await (await repo()).report(_report),
          isA<KitchenReadinessMalformedResponse>(),
        );
      }
    });

    test('every server rejection maps to its closed typed reason', () async {
      for (final reason in KitchenReadinessRejectionReason.values) {
        transport.enqueue({'ok': false, 'error': reason.wireName});
        final result = await (await repo()).report(_report);
        expect(result, isA<KitchenReadinessRejected>());
        expect((result as KitchenReadinessRejected).reason, reason);
      }
    });

    test('session/transport failure taxonomy', () async {
      transport.enqueue({'ok': false, 'error': 'invalid_session'});
      expect(
        await (await repo()).report(_report),
        isA<KitchenReadinessInvalidSession>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.auth),
      );
      expect(
        await (await repo()).report(_report),
        isA<KitchenReadinessInvalidSession>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.transient),
      );
      expect(
        await (await repo()).report(_report),
        isA<KitchenReadinessTransientFailure>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.server),
      );
      expect(
        await (await repo()).report(_report),
        isA<KitchenReadinessServerFailure>(),
      );
      transport.enqueue('not-a-map');
      expect(
        await (await repo()).report(_report),
        isA<KitchenReadinessMalformedResponse>(),
      );
      transport.enqueue({'ok': true, 'activation_ready': 'yes'});
      expect(
        await (await repo()).report(_report),
        isA<KitchenReadinessMalformedResponse>(),
      );
    });

    test(
      'missing credential -> invalidSession WITHOUT any network call',
      () async {
        final r = SupabaseKitchenReadinessRepository(
          transport: transport,
          secretStore: InMemoryDeviceSessionSecretStore(),
        );
        expect(await r.report(_report), isA<KitchenReadinessInvalidSession>());
        expect(transport.calls, isEmpty);
      },
    );

    test('001C3B1A: an assignment-aware report sends the STABLE assignment id '
        'and never leaks an endpoint', () async {
      transport.enqueue({'ok': true, 'activation_ready': true});
      const report = KitchenReadinessReport(
        appBuild: 'pos-test-build',
        transportKind: KitchenReadinessTransportKind.network,
        paperWidth: KitchenReadinessPaperWidth.mm80,
        printerFingerprint:
            'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111',
        secureSpoolAvailable: true,
        unresolvedLocalJobs: 0,
        modeRevision: 3,
        printerAssignmentId: 'assign-42',
      );
      final result = await (await repo()).report(report);
      expect(result, isA<KitchenReadinessAccepted>());
      final (_, params) = transport.calls.single;
      expect(params['p_printer_assignment_id'], 'assign-42');
      // The assignment id is an opaque server uuid, never an endpoint.
      expect(params.keys, isNot(contains('p_host')));
      expect(params.keys, isNot(contains('p_port')));
      expect(params.keys, isNot(contains('p_address')));
    });

    test('001C3B1A: the server invalid_printer_assignment rejection maps to '
        'its typed reason', () async {
      transport.enqueue({'ok': false, 'error': 'invalid_printer_assignment'});
      final result = await (await repo()).report(_report);
      expect(result, isA<KitchenReadinessRejected>());
      expect(
        (result as KitchenReadinessRejected).reason,
        KitchenReadinessRejectionReason.invalidPrinterAssignment,
      );
    });
  });

  group('SupabaseKitchenPosStatusRepository', () {
    late _FakeTransport transport;

    Future<SupabaseKitchenPosStatusRepository> repo() async =>
        SupabaseKitchenPosStatusRepository(
          transport: transport,
          secretStore: await _storeWithCred(),
        );

    setUp(() => transport = _FakeTransport());

    const status = KitchenPosStatusReport(
      appBuild: 'pos-test-build',
      modeRevision: 4,
      secureSpoolAvailable: true,
      unresolvedLocalJobs: 2,
    );

    test('exact wire payload: NO printer/endpoint/assignment/money keys; token '
        'read per request', () async {
      transport.enqueue({
        'ok': true,
        'entity': 'kitchen_pos_status',
        'expires_at': 'x',
        'server_ts': 'x',
      });
      final result = await (await repo()).report(status);
      expect(result, isA<KitchenPosStatusAccepted>());
      final (fn, params) = transport.calls.single;
      expect(fn, 'report_kitchen_pos_status');
      expect(params, {
        'p_device_id': 'dev-1',
        'p_session_token': 'tok-secret-1',
        'p_app_build': 'pos-test-build',
        'p_mode_revision': 4,
        'p_secure_spool_available': true,
        'p_unresolved_local_jobs': 2,
      });
      for (final banned in [
        'host',
        'address',
        'endpoint',
        'payload',
        'customer',
        'note',
        'minor',
        'secret',
        'assignment',
        'fingerprint',
        'printer',
        'transport',
        'paper',
      ]) {
        expect(
          params.keys.where((k) => k.toLowerCase().contains(banned)),
          isEmpty,
          reason: 'no status request key may contain "$banned"',
        );
      }
    });

    test('stale_mode_revision carries the authoritative revision; a bad value '
        'is malformed', () async {
      transport.enqueue({
        'ok': false,
        'error': 'stale_mode_revision',
        'mode_revision': 8,
      });
      final r = await (await repo()).report(status);
      expect(r, isA<KitchenPosStatusStaleModeRevision>());
      expect((r as KitchenPosStatusStaleModeRevision).serverRevision, 8);
      for (final bad in [null, 0, -2, 'x']) {
        transport.enqueue({
          'ok': false,
          'error': 'stale_mode_revision',
          'mode_revision': bad,
        });
        expect(
          await (await repo()).report(status),
          isA<KitchenPosStatusMalformedResponse>(),
        );
      }
    });

    test('closed rejection + session/transport taxonomy', () async {
      for (final reason in KitchenPosStatusRejectionReason.values) {
        transport.enqueue({'ok': false, 'error': reason.wireName});
        final r = await (await repo()).report(status);
        expect(r, isA<KitchenPosStatusRejected>());
        expect((r as KitchenPosStatusRejected).reason, reason);
      }
      transport.enqueue({'ok': false, 'error': 'invalid_session'});
      expect(
        await (await repo()).report(status),
        isA<KitchenPosStatusInvalidSession>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.transient),
      );
      expect(
        await (await repo()).report(status),
        isA<KitchenPosStatusTransientFailure>(),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.server),
      );
      expect(
        await (await repo()).report(status),
        isA<KitchenPosStatusServerFailure>(),
      );
      transport.enqueue('nope');
      expect(
        await (await repo()).report(status),
        isA<KitchenPosStatusMalformedResponse>(),
      );
    });

    test(
      'missing credential -> invalidSession WITHOUT any network call',
      () async {
        final r = SupabaseKitchenPosStatusRepository(
          transport: transport,
          secretStore: InMemoryDeviceSessionSecretStore(),
        );
        expect(await r.report(status), isA<KitchenPosStatusInvalidSession>());
        expect(transport.calls, isEmpty);
      },
    );
  });

  group('SupabaseKitchenDispatchInspectionRepository', () {
    late _FakeTransport transport;
    late SupabaseKitchenDispatchInspectionRepository repo;

    setUp(() {
      transport = _FakeTransport();
      repo = SupabaseKitchenDispatchInspectionRepository(transport: transport);
    });

    Map<String, Object?> row({
      String id = 'd-1',
      String type = 'initial_order',
      bool possiblyPrinted = false,
    }) => {
      'dispatch_id': id,
      'dispatch_type': type,
      'order_id': 'o-1',
      'created_at': '2026-07-20T10:00:00+00:00',
      'claimed': possiblyPrinted,
      'last_client_status': possiblyPrinted ? 'possibly_printed' : null,
      'last_error_code': possiblyPrinted ? 'kitchen_transport_ambiguous' : null,
      'completed_at': null,
      'possibly_printed': possiblyPrinted,
      'superseded': false,
    };

    test(
      'wire request carries the closed filter + bounded page + cursor',
      () async {
        transport.enqueue({
          'ok': true,
          'dispatches': [row()],
          'has_more': false,
          'next_cursor': null,
        });
        final result = await repo.list(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          filter: KitchenDispatchInspectionFilter.possiblyPrinted,
          limit: 5,
          cursor: KitchenDispatchInspectionCursor(
            createdAt: DateTime.utc(2026, 7, 20, 10),
            id: 'd-0',
          ),
        );
        expect(result, isA<KitchenDispatchInspectionPage>());
        final (fn, params) = transport.calls.single;
        expect(fn, 'list_kitchen_print_dispatches');
        expect(params['p_status_filter'], 'possibly_printed');
        expect(params['p_limit'], 5);
        expect(params['p_cursor_id'], 'd-0');
        expect(params['p_cursor_created_at'], '2026-07-20T10:00:00.000Z');
      },
    );

    test(
      'safe page parse: entries model ONLY the safe scalar fields',
      () async {
        transport.enqueue({
          'ok': true,
          'dispatches': [
            row(possiblyPrinted: true),
            row(id: 'd-2', type: 'void'),
          ],
          'has_more': true,
          'next_cursor': {
            'created_at': '2026-07-20T09:00:00+00:00',
            'id': 'd-2',
          },
        });
        final page =
            await repo.list(
                  organizationId: 'org-1',
                  restaurantId: 'rest-1',
                  branchId: 'branch-1',
                )
                as KitchenDispatchInspectionPage;
        expect(page.entries, hasLength(2));
        expect(page.entries.first.possiblyPrinted, isTrue);
        expect(page.entries.first.claimed, isTrue);
        expect(page.entries.first.lastClientStatus, 'possibly_printed');
        expect(page.entries.first.lastErrorCode, 'kitchen_transport_ambiguous');
        expect(page.entries.last.dispatchType, 'void');
        expect(page.hasMore, isTrue);
        expect(page.nextCursor?.id, 'd-2');
      },
    );

    test('typed denials and request-contract rejections', () async {
      transport.enqueue({'ok': false, 'error': 'not_found'});
      expect(
        await repo.list(organizationId: 'o', restaurantId: 'r', branchId: 'b'),
        isA<KitchenDispatchInspectionNotFound>(),
      );
      for (final error in [
        'invalid_status_filter',
        'invalid_limit',
        'invalid_cursor',
      ]) {
        transport.enqueue({'ok': false, 'error': error});
        expect(
          await repo.list(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: 'b',
          ),
          isA<KitchenDispatchInspectionInvalidRequest>(),
        );
      }
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.auth),
      );
      expect(
        await repo.list(organizationId: 'o', restaurantId: 'r', branchId: 'b'),
        isA<KitchenDispatchInspectionUnauthorized>(),
      );
    });

    test(
      'malformed responses are rejected as a whole (no partial trust)',
      () async {
        transport.enqueue('nope');
        expect(
          await repo.list(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: 'b',
          ),
          isA<KitchenDispatchInspectionMalformedResponse>(),
        );
        transport.enqueue({
          'ok': true,
          'dispatches': [
            {'dispatch_id': 'd-1'},
          ],
          'has_more': false,
        });
        expect(
          await repo.list(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: 'b',
          ),
          isA<KitchenDispatchInspectionMalformedResponse>(),
        );
        transport.enqueue({
          'ok': true,
          'dispatches': [row(type: 'reprint')],
          'has_more': false,
        });
        expect(
          await repo.list(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: 'b',
          ),
          isA<KitchenDispatchInspectionMalformedResponse>(),
          reason: 'an unknown dispatch_type is a contract violation',
        );
        transport.enqueue({
          'ok': true,
          'dispatches': [row()],
          'has_more': true,
        });
        expect(
          await repo.list(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: 'b',
          ),
          isA<KitchenDispatchInspectionMalformedResponse>(),
          reason: 'has_more without a cursor cannot be paginated truthfully',
        );
      },
    );
  });
}
