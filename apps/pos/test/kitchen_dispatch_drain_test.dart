@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_drain_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';

/// KITCHEN-MODE-001C2B-CORRECTION-001 — the end-to-end dormant drain seam:
/// pull → durable import → ack → EXACT next cursor → next page → typed stop.
/// Everything runs against a REAL on-disk dedicated spool database and the
/// REAL AES-256-GCM cipher; only the RPC transport is scripted.
class _FakeTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];
  final List<Object? Function()> _script = [];

  void enqueue(Object? response) => _script.add(() => response);
  void enqueueThrow(Object error) => _script.add(() => throw error);

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, Map.of(params)));
    if (_script.isEmpty) fail('unexpected transport call: $function');
    return _script.removeAt(0)();
  }
}

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key] = value!;

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(values);
}

const _scope = KitchenImportScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

const _resolved = ResolvedKitchenDestination(
  destination: NetworkKitchenDestination(host: '10.0.0.5', port: 9100),
  fingerprint: 'fp-net-1',
  displayLabel: 'Kitchen',
  transportKind: 'network',
  paperWidth: '80mm',
);

Map<String, Object?> _ticketPayload() => {
  'v': 1,
  'kind': 'initial_order',
  'order_code': '#000042',
  'order_type': 'dine_in',
  'items': [
    {'qty': 1, 'name': 'Burger', 'modifiers': <Object?>[]},
  ],
};

Map<String, Object?> _row(String id, {Map<String, Object?>? payload}) => {
  'id': id,
  'dispatch_type': 'initial_order',
  'order_id': 'order-$id',
  'payload_version': 1,
  'payload': payload ?? _ticketPayload(),
  'created_at': '2026-07-20T10:00:00Z',
};

Map<String, Object?> _page(
  List<Map<String, Object?>> rows, {
  bool hasMore = false,
  Map<String, Object?>? nextCursor,
}) => {
  'ok': true,
  'dispatches': rows,
  'has_more': hasMore,
  if (nextCursor != null) 'next_cursor': nextCursor,
};

Map<String, Object?> _cursor(String createdAt, int rank, String id) => {
  'created_at': createdAt,
  'type_rank': rank,
  'id': id,
};

void main() {
  late Directory tempDir;
  late KitchenSpoolDatabase db;
  late DriftKitchenSpoolStore store;
  late _FakeTransport transport;
  late SupabaseKitchenDispatchAckRepository ackRepo;
  late SupabaseKitchenDispatchPullRepository pullRepo;
  late SecretValue key;
  late int idCounter;
  final now = DateTime.utc(2026, 7, 20, 11);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rf_drain_test');
    final factory = KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: () async => tempDir,
    );
    db = await factory.open();
    store = DriftKitchenSpoolStore(db);
    final manager = KitchenSpoolKeyManager(
      FlutterSecureKitchenSpoolKeyStore(
        storage: _FakeSecureStorage(),
        platform: const PosKitchenSpoolPlatform(isWeb: false),
      ),
    );
    await manager.provisionKey();
    key = (await manager.readKey())!;
    transport = _FakeTransport();
    final secretStore = InMemoryDeviceSessionSecretStore();
    await secretStore.write(
      const DeviceSessionCredential(
        deviceId: 'dev-1',
        sessionToken: 'tok-secret-1',
      ),
    );
    ackRepo = SupabaseKitchenDispatchAckRepository(
      transport: transport,
      secretStore: secretStore,
    );
    pullRepo = SupabaseKitchenDispatchPullRepository(
      transport: transport,
      secretStore: secretStore,
    );
    idCounter = 0;
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  KitchenDispatchDrainCoordinator drain({
    int pageLimit = 20,
    int maxPages = 50,
  }) => KitchenDispatchDrainCoordinator(
    pullRepository: pullRepo,
    importCoordinator: KitchenDispatchImportCoordinator(
      store: store,
      cipher: AesGcmKitchenSpoolCipher(),
      key: key,
      scope: _scope,
      destination: _resolved,
      ackRepository: ackRepo,
      localJobIdGenerator: () => 'drain-${++idCounter}',
      now: () => now,
    ),
    pageLimit: pageLimit,
    maxPages: maxPages,
  );

  test('single page (has_more false) drains to complete', () async {
    transport.enqueue(_page([_row('d-1'), _row('d-2')]));
    transport.enqueue({'ok': true});
    transport.enqueue({'ok': true});
    final report = await drain().drain();
    expect(report.stoppedReason, KitchenDrainStopReason.complete);
    expect(report.isSuccess, isTrue);
    expect(report.pagesPulled, 1);
    expect(report.rowsReceived, 2);
    expect(report.rowsImported, 2);
    expect(report.acknowledgementsSucceeded, 2);
    expect(await store.countTotalRows(), 2);
    // Ack rows are durably imported + acknowledged.
    for (final id in ['d-1', 'd-2']) {
      final row = (await store.findByDispatchId(id))!;
      expect(row.serverAcknowledgedAt, isNotNull);
    }
  });

  test(
    'multi-page drain: current page imports (and acks) BEFORE the next pull, '
    'and the EXACT three-field cursor is forwarded verbatim',
    () async {
      final c1 = _cursor('2026-07-20T10:00:02Z', 1, 'd-2');
      transport.enqueue(
        _page([_row('d-1'), _row('d-2')], hasMore: true, nextCursor: c1),
      );
      transport.enqueue({'ok': true}); // ack d-1
      transport.enqueue({'ok': true}); // ack d-2
      transport.enqueue(_page([_row('d-3')]));
      transport.enqueue({'ok': true}); // ack d-3
      final report = await drain().drain();
      expect(report.stoppedReason, KitchenDrainStopReason.complete);
      expect(report.pagesPulled, 2);
      expect(report.rowsImported, 3);

      final sequence = [for (final (fn, _) in transport.calls) fn];
      expect(sequence, [
        'pull_kitchen_print_dispatches',
        'acknowledge_kitchen_print_dispatch',
        'acknowledge_kitchen_print_dispatch',
        'pull_kitchen_print_dispatches',
        'acknowledge_kitchen_print_dispatch',
      ], reason: 'page 1 fully imported+acked before pull 2');

      final firstPull = transport.calls[0].$2;
      expect(firstPull['p_cursor_created_at'], isNull);
      expect(firstPull['p_cursor_id'], isNull);
      expect(firstPull['p_cursor_type_rank'], isNull);
      final secondPull = transport.calls[3].$2;
      expect(secondPull['p_cursor_created_at'], '2026-07-20T10:00:02Z');
      expect(secondPull['p_cursor_type_rank'], 1);
      expect(secondPull['p_cursor_id'], 'd-2');
      expect(secondPull['p_limit'], 20);
    },
  );

  test('empty page stops successfully with zero footprint', () async {
    transport.enqueue(_page(const []));
    final report = await drain().drain();
    expect(report.stoppedReason, KitchenDrainStopReason.emptyPage);
    expect(report.isSuccess, isTrue);
    expect(report.rowsReceived, 0);
    expect(transport.calls, hasLength(1));
  });

  test('has_more with a MISSING cursor is a typed malformed page', () async {
    transport.enqueue({
      'ok': true,
      'dispatches': [_row('d-1')],
      'has_more': true,
      // next_cursor deliberately absent.
    });
    final report = await drain().drain();
    expect(report.stoppedReason, KitchenDrainStopReason.malformedPage);
    expect(report.isSuccess, isFalse);
  });

  test(
    'a REPEATED cursor stalls the drain (typed, never an endless loop)',
    () async {
      final c1 = _cursor('2026-07-20T10:00:01Z', 1, 'd-1');
      transport.enqueue(_page([_row('d-1')], hasMore: true, nextCursor: c1));
      transport.enqueue({'ok': true});
      transport.enqueue(_page([_row('d-2')], hasMore: true, nextCursor: c1));
      transport.enqueue({'ok': true});
      final report = await drain().drain();
      expect(report.stoppedReason, KitchenDrainStopReason.cursorStalled);
      expect(report.pagesPulled, 2);
      expect(report.rowsImported, 2, reason: 'page rows still imported');
    },
  );

  test('the page cap stops a runaway drain (typed)', () async {
    final c1 = _cursor('2026-07-20T10:00:01Z', 1, 'd-1');
    final c2 = _cursor('2026-07-20T10:00:02Z', 1, 'd-2');
    transport.enqueue(_page([_row('d-1')], hasMore: true, nextCursor: c1));
    transport.enqueue({'ok': true});
    transport.enqueue(_page([_row('d-2')], hasMore: true, nextCursor: c2));
    transport.enqueue({'ok': true});
    final report = await drain(maxPages: 2).drain();
    expect(report.stoppedReason, KitchenDrainStopReason.pageCapExceeded);
    expect(report.pagesPulled, 2);
    expect(report.rowsImported, 2);
  });

  test('typed pull errors stop the drain without inventing work', () async {
    for (final (wire, reason) in [
      ('readiness_required', KitchenDrainStopReason.readinessRequired),
      ('branch_not_printer_only', KitchenDrainStopReason.branchNotPrinterOnly),
      ('invalid_session', KitchenDrainStopReason.invalidSession),
      ('invalid_cursor', KitchenDrainStopReason.invalidCursor),
    ]) {
      final localTransport = _FakeTransport();
      final secretStore = InMemoryDeviceSessionSecretStore();
      await secretStore.write(
        const DeviceSessionCredential(
          deviceId: 'dev-1',
          sessionToken: 'tok-secret-1',
        ),
      );
      localTransport.enqueue({'ok': false, 'error': wire});
      final report = await KitchenDispatchDrainCoordinator(
        pullRepository: SupabaseKitchenDispatchPullRepository(
          transport: localTransport,
          secretStore: secretStore,
        ),
        importCoordinator: KitchenDispatchImportCoordinator(
          store: store,
          cipher: AesGcmKitchenSpoolCipher(),
          key: key,
          scope: _scope,
          destination: _resolved,
          ackRepository: ackRepo,
          localJobIdGenerator: () => 'err-${++idCounter}',
          now: () => now,
        ),
      ).drain();
      expect(report.stoppedReason, reason, reason: wire);
      expect(report.rowsImported, 0);
      // readiness_required is TYPED ONLY — the drain never calls readiness
      // reporting (or anything else) in response.
      expect(localTransport.calls, hasLength(1));
      expect(localTransport.calls.single.$1, 'pull_kitchen_print_dispatches');
    }
  });

  test('a transient pull failure returns a typed retryable stop', () async {
    transport.enqueueThrow(
      const SyncTransportException(SyncTransportErrorKind.transient),
    );
    final report = await drain().drain();
    expect(report.stoppedReason, KitchenDrainStopReason.transientFailure);
  });

  test('a malformed pull response is a typed malformed page', () async {
    transport.enqueue({'ok': true, 'dispatches': 'not-a-list'});
    final report = await drain().drain();
    expect(report.stoppedReason, KitchenDrainStopReason.malformedPage);
  });

  test(
    'one hostile row does not poison its page siblings; the drain continues',
    () async {
      final hostile = _ticketPayload();
      hostile['price'] = 1;
      transport.enqueue(
        _page([_row('d-bad', payload: hostile), _row('d-good')]),
      );
      transport.enqueue({'ok': true}); // ack d-good only
      final report = await drain().drain();
      expect(report.stoppedReason, KitchenDrainStopReason.complete);
      expect(report.rowsRejected, 1);
      expect(report.rowsImported, 1);
      expect(await store.findByDispatchId('d-bad'), isNull);
      expect(await store.findByDispatchId('d-good'), isNotNull);
    },
  );

  test('duplicate rows across pages stay harmless (idempotent)', () async {
    final c1 = _cursor('2026-07-20T10:00:01Z', 1, 'd-1');
    transport.enqueue(_page([_row('d-1')], hasMore: true, nextCursor: c1));
    transport.enqueue({'ok': true});
    transport.enqueue(_page([_row('d-1')])); // the SAME dispatch again
    final report = await drain().drain();
    expect(report.stoppedReason, KitchenDrainStopReason.complete);
    expect(report.rowsImported, 1);
    expect(report.rowsAlreadyPresent, 1);
    expect(await store.countTotalRows(), 1);
  });

  test('a FATAL database failure stops the drain by propagating (never '
      'swallowed into a fake success)', () async {
    transport.enqueue(_page([_row('d-1')]));
    await db.close(); // the dedicated spool database dies mid-run
    await expectLater(drain().drain(), throwsA(anything));
  });

  test('an acknowledgement failure leaves a DURABLE pending ack that a later '
      'flush recovers (survives the failed run)', () async {
    transport.enqueue(_page([_row('d-1')]));
    transport.enqueueThrow(
      const SyncTransportException(SyncTransportErrorKind.server),
    );
    final report = await drain().drain();
    expect(report.stoppedReason, KitchenDrainStopReason.complete);
    expect(report.rowsImported, 1);
    expect(report.acknowledgementsPending, 1);

    final row = (await store.findByDispatchId('d-1'))!;
    expect(row.pendingServerAckStatus, KitchenServerAckStatus.imported);

    // A later pending-ack flush (next startup/resume) completes it.
    transport.enqueue({'ok': true});
    final secretStore = InMemoryDeviceSessionSecretStore();
    await secretStore.write(
      const DeviceSessionCredential(
        deviceId: 'dev-1',
        sessionToken: 'tok-secret-1',
      ),
    );
    var flushed = 0;
    final due = await store.listPendingServerAcks(
      deviceId: 'dev-1',
      branchId: 'branch-1',
      now: now.add(const Duration(hours: 1)),
    );
    for (final job in due) {
      final outcome = await flushAck(
        store,
        ackRepo,
        job,
        now.add(const Duration(hours: 1)),
        backoffBase: const Duration(seconds: 2),
        backoffCap: const Duration(minutes: 5),
      );
      if (outcome == KitchenAckFlushOutcome.acked) flushed++;
    }
    expect(flushed, 1);
    expect(
      (await store.findByDispatchId('d-1'))!.serverAcknowledgedAt,
      isNotNull,
    );
  });
}
