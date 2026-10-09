@TestOn('vm')
library;

import 'dart:convert' show json, jsonDecode, utf8;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/order_submission.dart'
    show OrderSummary, OutboxEntry, OutboxSyncState;
import 'package:restoflow_pos/src/data/outbox_repository.dart'
    show OrderSubmitPhoneLookupKey, customerPhoneFromOrderSubmitEntries;
import 'package:restoflow_pos/src/data/order_edit_slip_store.dart'
    show OrderEditSlipEvidence;
import 'package:restoflow_pos/src/data/round_print_claim_store.dart'
    show PosRoundPrintClaimState;
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_worker.dart';
import 'package:restoflow_pos/src/spool/kitchen_void_reconciliation.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition_native.dart'
    show orderEditSupersessionEvidenceFrom;
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'support/pos_package_root.dart';

/// KITCHEN-MODE-001C2B — the durable import transaction against a REAL
/// dedicated spool database (temp file), the REAL AES-256-GCM cipher, and a
/// scripted acknowledgement transport. The core invariants under test:
/// durable insert BEFORE any acknowledgement, idempotent duplicates without
/// re-encryption, encrypted blocked variants, terminal-verdict handling, and
/// VOID supersession that preserves possiblyPrinted ambiguity.
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

Map<String, Object?> _ticketPayload({String orderCode = '#000042'}) => {
  'v': 1,
  'kind': 'initial_order',
  'order_code': orderCode,
  'order_type': 'dine_in',
  'items': [
    {
      'qty': 2,
      'name': 'Burger',
      'modifiers': [
        {'qty': 1, 'name': 'Extra pickles'},
      ],
    },
  ],
};

Map<String, Object?> _voidPayload({String orderCode = '#000042'}) => {
  'v': 1,
  'kind': 'void',
  'order_code': orderCode,
  'order_type': 'dine_in',
  'void': true,
  'reason': 'entry_error',
};

// ORDER-EDIT-001F: the STORED server payload of a real paper edit (captured
// on local PostgreSQL by test/fixtures/order_edit_slip/capture_probe.sql),
// with only `created_at` / `edit_number` overridden per test.
const String _editCreatedAt = '2026-10-09T05:31:12.606845+00:00';
const String _beforeEdit = '2026-10-09T05:20:00Z';
const String _afterEdit = '2026-10-09T05:40:00Z';

Map<String, Object?> _fixtureEditPayload() {
  final file = File(
    p.join(
      locatePosPackageRoot().path,
      'test',
      'fixtures',
      'order_edit_slip',
      'a_every_op.json',
    ),
  );
  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return Map<String, Object?>.from(fixture['dispatch']! as Map);
}

Map<String, Object?> _editPayload({
  String createdAt = _editCreatedAt,
  int editNumber = 1,
}) => {
  ..._fixtureEditPayload(),
  'created_at': createdAt,
  'edit_number': editNumber,
};

Map<String, Object?> _initialPayloadAt(String createdAt) => {
  ..._ticketPayload(),
  'created_at': createdAt,
};

Map<String, Object?> _roundPayload(String createdAt, {int number = 2}) => {
  'v': 1,
  'kind': 'service_round',
  'order_code': '#000042',
  'order_type': 'dine_in',
  'created_at': createdAt,
  'round_id': 'round-$number',
  'round_number': number,
  'items': [
    {'qty': 1, 'name': 'Fries', 'modifiers': <Object?>[]},
  ],
};

PulledKitchenDispatch _dispatch({
  required String dispatchId,
  String dispatchType = 'initial_order',
  String orderId = 'order-1',
  Map<String, Object?>? payload,
}) => PulledKitchenDispatch(
  dispatchId: dispatchId,
  dispatchType: dispatchType,
  orderId: orderId,
  payloadVersion: 1,
  moneyFreePayload: payload ?? _ticketPayload(),
  createdAt: '2026-07-20T10:00:00Z',
);

void main() {
  late Directory tempDir;
  late KitchenSpoolDatabase db;
  late DriftKitchenSpoolStore store;
  late AesGcmKitchenSpoolCipher cipher;
  late SecretValue key;
  late _FakeTransport transport;
  late SupabaseKitchenDispatchAckRepository ackRepo;
  late int idCounter;
  final now = DateTime.utc(2026, 7, 20, 11);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rf_spool_import_test');
    final factory = KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: () async => tempDir,
    );
    db = await factory.open();
    store = DriftKitchenSpoolStore(db);
    cipher = AesGcmKitchenSpoolCipher();
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
    idCounter = 0;
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  KitchenDispatchImportCoordinator coordinator({
    KitchenDestinationResolution destination = _resolved,
    Future<String?> Function(OrderSubmitPhoneLookupKey key)? resolvePhone,
    PosRoundPrintClaimState? Function(String orderId)? readInitialPrintClaim,
  }) => KitchenDispatchImportCoordinator(
    store: store,
    cipher: cipher,
    key: key,
    scope: _scope,
    destination: destination,
    ackRepository: ackRepo,
    localJobIdGenerator: () => 'job-${++idCounter}',
    now: () => now,
    resolveCustomerPhone: resolvePhone,
    readInitialPrintClaim: readInitialPrintClaim,
  );

  KitchenSpoolAad aad(String dispatchId) => KitchenSpoolAad(
    dispatchId: dispatchId,
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-1',
    deviceId: 'dev-1',
    encryptionVersion: cipher.encryptionVersion,
  );

  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2): the customer phone stored in
  // the ENCRYPTED spool row for [dispatchId] (null when the row carries none).
  Future<String?> storedPhone(String dispatchId) async {
    final row = (await store.findByDispatchId(dispatchId))!;
    final plaintext = await cipher.decrypt(
      envelope: row.encryptedPayloadBlob,
      aad: aad(dispatchId),
      key: key,
    );
    return KitchenSpoolLocalPayload.fromJson(
      json.decode(utf8.decode(plaintext)) as Map<String, Object?>,
    ).customerPhone;
  }

  test('happy path: durable encrypted import, then imported ack', () async {
    transport.enqueue({'ok': true});
    final summary = await coordinator().importDispatches([
      _dispatch(dispatchId: 'd-1'),
    ]);
    expect(summary.imported, 1);
    expect(summary.acked, 1);
    expect(summary.rejected, 0);

    final row = (await store.findByDispatchId('d-1'))!;
    expect(row.localJobId, 'job-1');
    expect(row.status, KitchenSpoolJobStatus.imported);
    expect(row.serverAcknowledgedAt, isNotNull);
    expect(row.pendingServerAckStatus, isNull);
    expect(row.destinationFingerprint, 'fp-net-1');
    expect(row.transportKind, 'network');
    expect(row.paperWidth, '80mm');

    // The blob decrypts under the canonical AAD back to the pinned payload.
    final plaintext = await cipher.decrypt(
      envelope: row.encryptedPayloadBlob,
      aad: aad('d-1'),
      key: key,
    );
    final payload = KitchenSpoolLocalPayload.fromJson(
      json.decode(utf8.decode(plaintext)) as Map<String, Object?>,
    );
    expect(payload.paperWidth, '80mm');
    expect(payload.dispatch.orderCode, '#000042');
    expect(payload.destination, isA<NetworkKitchenDestination>());

    final (fn, params) = transport.calls.single;
    expect(fn, 'acknowledge_kitchen_print_dispatch');
    expect(params['p_dispatch_id'], 'd-1');
    expect(params['p_client_status'], 'imported');
    expect(params['p_error_code'], isNull);
  });

  test(
    'DURABLE BEFORE ACK: an ack transport failure leaves the encrypted row '
    'committed with a scheduled retry (never deleted/re-encrypted)',
    () async {
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.server),
      );
      final summary = await coordinator().importDispatches([
        _dispatch(dispatchId: 'd-1'),
      ]);
      expect(summary.imported, 1);
      expect(summary.acked, 0);
      expect(summary.ackRetriesScheduled, 1);

      final row = (await store.findByDispatchId('d-1'))!;
      expect(row.pendingServerAckStatus, KitchenServerAckStatus.imported);
      expect(row.serverAcknowledgedAt, isNull);
      expect(row.serverAckAttemptCount, 1);
      expect(row.serverAckNextAttemptAt, isNotNull);
      expect(row.serverAckLastErrorCode, 'server_failure');
      expect(row.encryptedPayloadBlob, isNotEmpty);

      // PRINT-ELIGIBILITY INVARIANT: unacked jobs are never runnable.
      expect(
        await store.listRunnable(
          deviceId: 'dev-1',
          branchId: 'branch-1',
          now: now.add(const Duration(hours: 1)),
        ),
        isEmpty,
      );
    },
  );

  test(
    'duplicate import is idempotent: no re-encrypt, no second row',
    () async {
      transport.enqueue({'ok': true});
      await coordinator().importDispatches([_dispatch(dispatchId: 'd-1')]);
      final firstBlob = (await store.findByDispatchId(
        'd-1',
      ))!.encryptedPayloadBlob;

      final summary = await coordinator().importDispatches([
        _dispatch(dispatchId: 'd-1'),
      ]);
      expect(summary.duplicates, 1);
      expect(summary.imported, 0);
      expect(summary.acked, 0, reason: 'already acked -> flush skips');
      expect(await store.countTotalRows(), 1);

      final row = (await store.findByDispatchId('d-1'))!;
      expect(row.localJobId, 'job-1', reason: 'the FIRST row survives');
      expect(row.encryptedPayloadBlob, firstBlob);
      expect(transport.calls, hasLength(1), reason: 'no second ack call');
    },
  );

  test('blocked destination: encrypted blockedConfiguration import + '
      'blocked_configuration ack carrying the typed reason code', () async {
    transport.enqueue({'ok': true});
    final summary = await coordinator(
      destination: const BlockedKitchenDestination(
        'kitchen_printer_not_selected',
      ),
    ).importDispatches([_dispatch(dispatchId: 'd-1')]);
    expect(summary.blocked, 1);
    expect(summary.acked, 1);

    final row = (await store.findByDispatchId('d-1'))!;
    expect(row.status, KitchenSpoolJobStatus.blockedConfiguration);
    expect(row.lastErrorCode, 'kitchen_printer_not_selected');
    expect(row.destinationFingerprint, isNull);
    expect(row.paperWidth, isNull);

    // The authoritative document is still fully encrypted and preserved.
    final plaintext = await cipher.decrypt(
      envelope: row.encryptedPayloadBlob,
      aad: aad('d-1'),
      key: key,
    );
    final payload = KitchenSpoolLocalPayload.fromJson(
      json.decode(utf8.decode(plaintext)) as Map<String, Object?>,
    );
    expect(payload.destination, isA<MissingKitchenDestination>());
    expect(payload.paperWidth, isNull);

    final (_, params) = transport.calls.single;
    expect(params['p_client_status'], 'blocked_configuration');
    expect(params['p_error_code'], 'kitchen_printer_not_selected');
  });

  test('terminal server verdict stops retries permanently and preserves the '
      'job (never overloaded onto blockedConfiguration)', () async {
    transport.enqueue({'ok': false, 'error': 'not_claim_owner'});
    final summary = await coordinator().importDispatches([
      _dispatch(dispatchId: 'd-1'),
    ]);
    expect(summary.imported, 1);
    expect(summary.ackTerminal, 1);

    final row = (await store.findByDispatchId('d-1'))!;
    expect(row.serverAckTerminalCode, 'not_claim_owner');
    expect(row.pendingServerAckStatus, isNull);
    expect(row.serverAckNextAttemptAt, isNull);
    expect(
      row.status,
      KitchenSpoolJobStatus.imported,
      reason: 'local status is NOT rewritten by a server ack verdict',
    );
    expect(row.encryptedPayloadBlob, isNotEmpty);

    // Terminal code makes the job permanently non-runnable.
    expect(
      await store.listRunnable(
        deviceId: 'dev-1',
        branchId: 'branch-1',
        now: now.add(const Duration(days: 1)),
      ),
      isEmpty,
    );
    // And it no longer appears in the pending-ack retry feed.
    expect(
      await store.listPendingServerAcks(
        deviceId: 'dev-1',
        branchId: 'branch-1',
        now: now.add(const Duration(days: 1)),
      ),
      isEmpty,
    );
  });

  test(
    'VOID supersession: unresolved same-order jobs supersede; possiblyPrinted '
    'keeps its ambiguity and only gains the evidence link',
    () async {
      // d-1: a normally imported + acked ticket for order-1.
      transport.enqueue({'ok': true});
      await coordinator().importDispatches([_dispatch(dispatchId: 'd-1')]);

      // d-2: a possiblyPrinted job for the same order (crash during print).
      final seeded = await store.insertImportedJob(
        NewKitchenSpoolJob(
          localJobId: 'seed-2',
          dispatchId: 'd-2',
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          orderId: 'order-1',
          serviceRoundId: null,
          dispatchType: KitchenSpoolDispatchType.serviceRound,
          initialStatus: KitchenSpoolJobStatus.imported,
          encryptedPayloadBlob: (await store.findByDispatchId(
            'd-1',
          ))!.encryptedPayloadBlob,
          encryptionVersion: 1,
          destinationFingerprint: 'fp-net-1',
          destinationDisplayLabel: 'Kitchen',
          transportKind: 'network',
          paperWidth: '80mm',
          payloadVersion: 1,
          documentVersion: 1,
          rasterVersion: 1,
          serverClaimExpiresAt: null,
          createdAt: now,
        ),
      );
      await store.setPendingServerAck(
        seeded.localJobId,
        KitchenServerAckStatus.imported,
        now,
      );
      await store.markServerAcked(seeded.localJobId, now);
      expect(
        await store.claimRunnableForQueued(
          seeded.localJobId,
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          now: now,
        ),
        isNotNull,
      );
      expect(await store.markPrinting(seeded.localJobId, now), isTrue);
      expect(
        await store.markPossiblyPrintedWithAck(seeded.localJobId, now),
        isTrue,
      );

      // d-3: the void notice for order-1 arrives and imports durably.
      transport.enqueue({'ok': true});
      final summary = await coordinator().importDispatches([
        _dispatch(
          dispatchId: 'd-3',
          dispatchType: 'void',
          payload: _voidPayload(),
        ),
      ]);
      expect(summary.imported, 1);
      expect(summary.superseded, 1, reason: 'd-1 (imported) superseded');
      expect(summary.supersessionLinks, 1, reason: 'd-2 linked only');

      final d1 = (await store.findByDispatchId('d-1'))!;
      expect(d1.status, KitchenSpoolJobStatus.superseded);
      expect(d1.supersededByDispatchId, 'd-3');

      final d2 = (await store.findByDispatchId('d-2'))!;
      expect(
        d2.status,
        KitchenSpoolJobStatus.possiblyPrinted,
        reason: 'ambiguity preserved — paper may exist',
      );
      expect(d2.supersededByDispatchId, 'd-3');

      // Idempotent: re-importing the void changes nothing further.
      final again = await coordinator().importDispatches([
        _dispatch(
          dispatchId: 'd-3',
          dispatchType: 'void',
          payload: _voidPayload(),
        ),
      ]);
      expect(again.duplicates, 1);
      expect(again.superseded, 0);
      expect(again.supersessionLinks, 0);
    },
  );

  test(
    'a hostile payload (money key) is REJECTED and never persisted',
    () async {
      final hostile = _ticketPayload();
      hostile['total_minor'] = 1;
      final summary = await coordinator().importDispatches([
        _dispatch(dispatchId: 'd-1', payload: hostile),
      ]);
      expect(summary.rejected, 1);
      expect(summary.imported, 0);
      expect(await store.countTotalRows(), 0);
      expect(transport.calls, isEmpty, reason: 'no ack for a rejected row');
    },
  );

  test('row/payload dispatch-type mismatch is REJECTED', () async {
    final summary = await coordinator().importDispatches([
      _dispatch(dispatchId: 'd-1', dispatchType: 'void'),
    ]);
    expect(summary.rejected, 1);
    expect(await store.countTotalRows(), 0);
  });

  test('a rejected dispatch does not poison the rest of the page', () async {
    transport.enqueue({'ok': true});
    final hostile = _ticketPayload();
    hostile['price'] = 1;
    final summary = await coordinator().importDispatches([
      _dispatch(dispatchId: 'd-bad', payload: hostile),
      _dispatch(dispatchId: 'd-good', orderId: 'order-2'),
    ]);
    expect(summary.rejected, 1);
    expect(summary.imported, 1);
    expect(await store.findByDispatchId('d-good'), isNotNull);
    expect(await store.findByDispatchId('d-bad'), isNull);
  });

  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2): the phone stored in the
  // encrypted spool comes from a LOCAL authoritative source resolved by orderId
  // (the durable order.submit op or recent-orders), so a crash-recovery replay
  // keeps it — even when the dispatch is imported before recent-orders exists.
  group('Finding 2 — durable phone resolution + enrichment', () {
    test('the FIRST import stores a phone resolved by orderId', () async {
      transport.enqueue({'ok': true});
      final summary = await coordinator(
        resolvePhone: (key) async =>
            key.orderId == 'order-1' ? '050-7654321' : null,
      ).importDispatches([_dispatch(dispatchId: 'd-1')]);
      expect(summary.imported, 1);
      expect(await storedPhone('d-1'), '050-7654321');
    });

    test(
      'a re-drive ENRICHES a previously phone-less row (no duplicate, status + '
      'attempts + identity unchanged)',
      () async {
        transport.enqueue({'ok': true});
        await coordinator(
          resolvePhone: (_) async => null,
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        final before = (await store.findByDispatchId('d-1'))!;
        expect(await storedPhone('d-1'), isNull);

        final summary = await coordinator(
          resolvePhone: (_) async => '050-7654321',
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(summary.duplicates, 1);
        expect(summary.imported, 0);
        expect(await storedPhone('d-1'), '050-7654321');

        final after = (await store.findByDispatchId('d-1'))!;
        expect(after.localJobId, before.localJobId, reason: 'no duplicate row');
        expect(after.status, before.status);
        expect(after.serverAckAttemptCount, before.serverAckAttemptCount);
        expect(after.dispatchId, before.dispatchId);
        expect(after.destinationFingerprint, before.destinationFingerprint);
      },
    );

    test('an existing NON-NULL phone is NEVER overwritten', () async {
      transport.enqueue({'ok': true});
      await coordinator(
        resolvePhone: (_) async => '054-1111111',
      ).importDispatches([_dispatch(dispatchId: 'd-1')]);
      expect(await storedPhone('d-1'), '054-1111111');
      await coordinator(
        resolvePhone: (_) async => '099-9999999',
      ).importDispatches([_dispatch(dispatchId: 'd-1')]);
      expect(await storedPhone('d-1'), '054-1111111');
    });

    test(
      'a re-drive with NO resolvable phone leaves the blob byte-identical',
      () async {
        transport.enqueue({'ok': true});
        await coordinator(
          resolvePhone: (_) async => null,
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        final before = (await store.findByDispatchId(
          'd-1',
        ))!.encryptedPayloadBlob;
        await coordinator(
          resolvePhone: (_) async => null,
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        final after = (await store.findByDispatchId(
          'd-1',
        ))!.encryptedPayloadBlob;
        expect(after, before);
      },
    );

    test(
      'a resolver that THROWS never blocks the import (row imported, no phone)',
      () async {
        transport.enqueue({'ok': true});
        final summary = await coordinator(
          resolvePhone: (_) async => throw StateError('boom'),
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(summary.imported, 1);
        expect(await storedPhone('d-1'), isNull);
      },
    );

    test(
      'THE RACE: dispatch imported before recent-orders -> the encrypted spool '
      'carries the phone and the replay ticket shows it exactly once',
      () async {
        transport.enqueue({'ok': true});
        // recent-orders is empty at import time; the durable source supplies it.
        await coordinator(
          resolvePhone: (key) async =>
              key.orderId == 'order-1' ? '050-7654321' : null,
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(await storedPhone('d-1'), '050-7654321');

        // Restart/replay: render the money-free ticket from the DECRYPTED payload.
        final row = (await store.findByDispatchId('d-1'))!;
        final payload = KitchenSpoolLocalPayload.fromBytes(
          await cipher.decrypt(
            envelope: row.encryptedPayloadBlob,
            aad: aad('d-1'),
            key: key,
          ),
        );
        final doc = const KitchenTicketRenderer().buildDocument(
          payload.dispatch,
          customerPhoneOverride: payload.customerPhone,
        );
        final phoneLines = doc.lines
            .whereType<pp.PrintTextLine>()
            .where((l) => l.text.contains('050-7654321'))
            .length;
        expect(phoneLines, 1);
      },
    );

    OutboxEntry outboxEntry({
      required String phone,
      String branch = 'branch-1',
    }) => OutboxEntry(
      id: 'ob-1',
      deviceId: 'dev-1',
      localOperationId: 'op-1',
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'order-1',
      payloadJson: json.encode(<String, Object?>{
        'order_id': 'order-1',
        'customer_phone': phone,
      }),
      summary: const OrderSummary(
        orderNumber: 'X',
        orderType: OrderType.dineIn,
        tableLabel: null,
        itemCount: 1,
        subtotalMinor: 0,
        currencyCode: 'ILS',
      ),
      syncState: OutboxSyncState.pending,
      clientCreatedAt: DateTime.utc(2026, 7, 20),
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: branch,
    );

    test(
      'an INVALID durable phone (letters) never enters the encrypted spool or '
      'the replay ticket (Codex HIGH)',
      () async {
        transport.enqueue({'ok': true});
        final entries = [outboxEntry(phone: '050-ABC-1234')];
        await coordinator(
          resolvePhone: (key) async =>
              customerPhoneFromOrderSubmitEntries(entries, key),
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(await storedPhone('d-1'), isNull);
        final row = (await store.findByDispatchId('d-1'))!;
        final payload = KitchenSpoolLocalPayload.fromBytes(
          await cipher.decrypt(
            envelope: row.encryptedPayloadBlob,
            aad: aad('d-1'),
            key: key,
          ),
        );
        final texts = const KitchenTicketRenderer()
            .buildDocument(
              payload.dispatch,
              customerPhoneOverride: payload.customerPhone,
            )
            .lines
            .whereType<pp.PrintTextLine>()
            .map((l) => l.text)
            .join('\n');
        expect(texts.contains('ABC'), isFalse);
      },
    );

    test(
      'a CROSS-SCOPE durable entry (different branch) never supplies the phone '
      '(Codex HIGH)',
      () async {
        transport.enqueue({'ok': true});
        final entries = [
          outboxEntry(phone: '054-1234567', branch: 'branch-OTHER'),
        ];
        await coordinator(
          resolvePhone: (key) async =>
              customerPhoneFromOrderSubmitEntries(entries, key),
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(await storedPhone('d-1'), isNull);
      },
    );
  });

  // [POS-OFFLINE-OPERATIONS-002] Pass C (C1) — the mirror-claim consult: the
  // drain-side defence against re-printing an initial ticket the POS already
  // printed locally at submit (offline direct-print). Pinned in BOTH
  // directions: with a claim the dispatch is acknowledged and NEVER becomes a
  // print job (zero print bytes even with a live worker); without one the
  // import + worker path prints exactly as before.
  group('Pass C (C1) — the mirror-claim consult before import', () {
    final networkCalls = <(String, int)>[];

    // The worker revalidates the row's destination fingerprint against the
    // decrypted destination before sending, so the print-through test needs
    // the CANONICAL fingerprint (the resolver's own format), not a token.
    final printableDestination = ResolvedKitchenDestination(
      destination: const NetworkKitchenDestination(
        host: '10.0.0.5',
        port: 9100,
      ),
      fingerprint: sha256
          .convert(utf8.encode('network|10.0.0.5|9100'))
          .toString(),
      displayLabel: 'Kitchen',
      transportKind: 'network',
      paperWidth: '80mm',
    );

    KitchenPrintWorker liveWorker() => KitchenPrintWorker(
      store: store,
      cipher: cipher,
      key: key,
      renderer: const KitchenTicketRenderer(),
      networkSend: ({required host, required port, required bytes}) async {
        networkCalls.add((host, port));
        return const pp.KitchenTransportOutcome(
          pp.KitchenTransportOutcomeKind.accepted,
          'flushed',
        );
      },
      bluetoothSend: ({required address, required bytes}) async =>
          const pp.KitchenTransportOutcome(
            pp.KitchenTransportOutcomeKind.unsupported,
            'not_in_this_test',
          ),
      sendGate: pp.PrinterDestinationSendGate(),
      ackRepository: ackRepo,
      scope: _scope,
      now: () => now,
    );

    setUp(networkCalls.clear);

    test('mirror claim `sent` => acknowledged transport_accepted, NO local '
        'row, ZERO print bytes through a live worker', () async {
      transport.enqueue({'ok': true}); // the skip acknowledgement
      final summary = await coordinator(
        readInitialPrintClaim: (orderId) =>
            orderId == 'order-1' ? PosRoundPrintClaimState.sent : null,
      ).importDispatches([_dispatch(dispatchId: 'd-1')]);

      expect(summary.alreadyPrintedLocally, 1);
      expect(summary.imported, 0);
      expect(summary.acked, 1);
      expect(await store.findByDispatchId('d-1'), isNull);
      final (fn, params) = transport.calls.single;
      expect(fn, 'acknowledge_kitchen_print_dispatch');
      expect(params['p_client_status'], 'transport_accepted');

      // Zero print bytes, proven at the transport: nothing exists to run.
      final report = await liveWorker().run();
      expect(report.claimed, 0);
      expect(networkCalls, isEmpty);
    });

    test('mirror claim `claimed` (crash window / unreadable) => acknowledged '
        'possibly_printed, NO local row', () async {
      transport.enqueue({'ok': true});
      final summary = await coordinator(
        readInitialPrintClaim: (_) => PosRoundPrintClaimState.claimed,
      ).importDispatches([_dispatch(dispatchId: 'd-1')]);
      expect(summary.alreadyPrintedLocally, 1);
      expect(summary.imported, 0);
      expect(await store.findByDispatchId('d-1'), isNull);
      expect(transport.calls.single.$2['p_client_status'], 'possibly_printed');
      final report = await liveWorker().run();
      expect(report.claimed, 0);
      expect(networkCalls, isEmpty);
    });

    test(
      'a THROWING reader reads as `claimed` (fail toward not printing)',
      () async {
        transport.enqueue({'ok': true});
        final summary = await coordinator(
          readInitialPrintClaim: (_) => throw StateError('torn down'),
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(summary.alreadyPrintedLocally, 1);
        expect(await store.findByDispatchId('d-1'), isNull);
        expect(
          transport.calls.single.$2['p_client_status'],
          'possibly_printed',
        );
      },
    );

    test('NO claim => imports and prints exactly as before (the other-till '
        'order the drain exists for)', () async {
      transport.enqueue({'ok': true}); // import ack
      final summary = await coordinator(
        destination: printableDestination,
        readInitialPrintClaim: (_) => null,
      ).importDispatches([_dispatch(dispatchId: 'd-1')]);
      expect(summary.alreadyPrintedLocally, 0);
      expect(summary.imported, 1);
      final row = (await store.findByDispatchId('d-1'))!;
      expect(row.status, KitchenSpoolJobStatus.imported);

      transport.enqueue({'ok': true, 'completed': true}); // worker ack
      final report = await liveWorker().run();
      expect(report.claimed, 1);
      expect(report.accepted, 1);
      expect(networkCalls.single, ('10.0.0.5', 9100));
    });

    test(
      'a `failed` claim was RELEASED => imports normally (the local '
      'attempt failed; the drain printing it is the desired outcome)',
      () async {
        transport.enqueue({'ok': true});
        final summary = await coordinator(
          readInitialPrintClaim: (_) => PosRoundPrintClaimState.failed,
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(summary.alreadyPrintedLocally, 0);
        expect(summary.imported, 1);
        expect(await store.findByDispatchId('d-1'), isNotNull);
      },
    );

    test('the gate is INITIAL-only: a void dispatch imports untouched even '
        'with a `sent` mirror claim', () async {
      transport.enqueue({'ok': true});
      final summary =
          await coordinator(
            readInitialPrintClaim: (_) => PosRoundPrintClaimState.sent,
          ).importDispatches([
            _dispatch(
              dispatchId: 'd-void',
              dispatchType: 'void',
              payload: _voidPayload(),
            ),
          ]);
      expect(summary.alreadyPrintedLocally, 0);
      expect(summary.imported, 1);
      expect(await store.findByDispatchId('d-void'), isNotNull);
    });
  });

  // ORDER-EDIT-001F — the order-edit consult (keyed by the DISPATCH id: a
  // pulled row carries no edit id), the hand-over to the spool (D3), the
  // in-flight skip (D11) and the ORDERED supersession sweep (D4).
  group(
    'ORDER-EDIT-001F — order_edit consult, hand-over and ordered sweep',
    () {
      late List<String> mirrorReads;
      late List<String> handedOver;
      late int phoneResolves;

      setUp(() {
        mirrorReads = [];
        handedOver = [];
        phoneResolves = 0;
      });

      KitchenDispatchImportCoordinator editCoordinator({
        PosRoundPrintClaimState? Function(String dispatchId)? mirror,
        bool inFlight = false,
        bool wireHandOver = true,
      }) => KitchenDispatchImportCoordinator(
        store: store,
        cipher: cipher,
        key: key,
        scope: _scope,
        destination: _resolved,
        ackRepository: ackRepo,
        localJobIdGenerator: () => 'job-${++idCounter}',
        now: () => now,
        resolveCustomerPhone: (_) async {
          phoneResolves++;
          return '054-1234567';
        },
        readOrderEditPrintClaim: (dispatchId) {
          mirrorReads.add(dispatchId);
          return mirror?.call(dispatchId);
        },
        isOrderEditSlipInFlight: (_) => inFlight,
        onOrderEditImported: wireHandOver
            ? (dispatchId) async => handedOver.add(dispatchId)
            : null,
      );

      PulledKitchenDispatch edit(
        String id, {
        String orderId = 'order-1',
        String createdAt = _editCreatedAt,
        int editNumber = 1,
      }) => _dispatch(
        dispatchId: id,
        dispatchType: 'order_edit',
        orderId: orderId,
        payload: _editPayload(createdAt: createdAt, editNumber: editNumber),
      );

      // Seeds a durable, server-acknowledged job whose blob is the REAL
      // encrypted local payload of [payload] (or [rawBlob], e.g. garbage).
      Future<KitchenSpoolJobRow> seed(
        String dispatchId, {
        Map<String, Object?>? payload,
        KitchenSpoolDispatchType? type,
        String orderId = 'order-1',
        Uint8List? rawBlob,
        bool possiblyPrinted = false,
      }) async {
        final document = payload == null
            ? null
            : KitchenDispatchDocument.fromJson(payload);
        final blob =
            rawBlob ??
            await cipher.encrypt(
              plaintext: KitchenSpoolLocalPayload(
                dispatch: document!,
                destination: _resolved.destination,
                paperWidth: '80mm',
                documentVersion: 1,
                rasterVersion: 1,
              ).toBytes(),
              aad: aad(dispatchId),
              key: key,
            );
        final row = await store.insertImportedJob(
          NewKitchenSpoolJob(
            localJobId: 'seed-$dispatchId',
            dispatchId: dispatchId,
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: 'branch-1',
            deviceId: 'dev-1',
            orderId: orderId,
            serviceRoundId: null,
            dispatchType: type ?? document!.kind,
            initialStatus: KitchenSpoolJobStatus.imported,
            encryptedPayloadBlob: blob,
            encryptionVersion: cipher.encryptionVersion,
            // possiblyPrinted needs its own destination to be claimable.
            destinationFingerprint: possiblyPrinted ? 'fp-pp' : 'fp-net-1',
            destinationDisplayLabel: 'Kitchen',
            transportKind: 'network',
            paperWidth: '80mm',
            payloadVersion: 1,
            documentVersion: 1,
            rasterVersion: 1,
            serverClaimExpiresAt: null,
            createdAt: now,
          ),
        );
        await store.setPendingServerAck(
          row.localJobId,
          KitchenServerAckStatus.imported,
          now,
        );
        await store.markServerAcked(row.localJobId, now);
        if (possiblyPrinted) {
          expect(
            await store.claimRunnableForQueued(
              row.localJobId,
              organizationId: 'org-1',
              restaurantId: 'rest-1',
              branchId: 'branch-1',
              deviceId: 'dev-1',
              now: now,
            ),
            isNotNull,
          );
          expect(await store.markPrinting(row.localJobId, now), isTrue);
          expect(
            await store.markPossiblyPrintedWithAck(row.localJobId, now),
            isTrue,
          );
        }
        return (await store.findByDispatchId(dispatchId))!;
      }

      Future<KitchenSpoolJobRow> rowOf(String dispatchId) async =>
          (await store.findByDispatchId(dispatchId))!;

      test('IN FLIGHT (D11): skipped untouched — no row, no acknowledgement, '
          'the mirror never read, re-served later', () async {
        final summary = await editCoordinator(
          inFlight: true,
          mirror: (_) => PosRoundPrintClaimState.claimed,
        ).importDispatches([edit('d-edit')]);
        expect(summary.deferredInFlight, 1);
        expect(summary.imported, 0);
        expect(summary.alreadyPrintedLocally, 0);
        expect(await store.findByDispatchId('d-edit'), isNull);
        expect(transport.calls, isEmpty, reason: 'no possibly_printed hold');
        expect(mirrorReads, isEmpty);
        expect(handedOver, isEmpty);
      });

      test('mirror `sent` => acknowledged transport_accepted, NO local row, '
          'never handed over', () async {
        transport.enqueue({'ok': true});
        final summary = await editCoordinator(
          mirror: (id) => id == 'd-edit' ? PosRoundPrintClaimState.sent : null,
        ).importDispatches([edit('d-edit')]);
        expect(summary.alreadyPrintedLocally, 1);
        expect(summary.acked, 1);
        expect(summary.imported, 0);
        expect(await store.findByDispatchId('d-edit'), isNull);
        expect(mirrorReads, ['d-edit'], reason: 'keyed by the DISPATCH id');
        final (fn, params) = transport.calls.single;
        expect(fn, 'acknowledge_kitchen_print_dispatch');
        expect(params['p_dispatch_id'], 'd-edit');
        expect(params['p_client_status'], 'transport_accepted');
        expect(handedOver, isEmpty);
      });

      test('mirror `claimed` (pending / crash mid-print) and a THROWING '
          'reader => possibly_printed, NO local row', () async {
        for (final mirror in <PosRoundPrintClaimState? Function(String)>[
          (_) => PosRoundPrintClaimState.claimed,
          (_) => throw StateError('torn down'),
        ]) {
          transport.calls.clear();
          transport.enqueue({'ok': true});
          final summary = await editCoordinator(
            mirror: mirror,
          ).importDispatches([edit('d-edit')]);
          expect(summary.alreadyPrintedLocally, 1);
          expect(summary.imported, 0);
          expect(await store.findByDispatchId('d-edit'), isNull);
          expect(
            transport.calls.single.$2['p_client_status'],
            'possibly_printed',
          );
        }
        expect(handedOver, isEmpty);
      });

      test('mirror `failed` or ABSENT => imported, acknowledged `imported`, '
          'handed over once; the phone is never resolved', () async {
        for (final (id, claim) in [
          ('d-failed', PosRoundPrintClaimState.failed),
          ('d-absent', null),
        ]) {
          transport.enqueue({'ok': true});
          final summary = await editCoordinator(
            mirror: (_) => claim,
          ).importDispatches([edit(id)]);
          expect(summary.imported, 1, reason: id);
          expect(summary.acked, 1, reason: id);
          expect(summary.alreadyPrintedLocally, 0, reason: id);
          expect(summary.orderEditsHandedOver, 1, reason: id);
          final row = await rowOf(id);
          expect(row.dispatchType, KitchenSpoolDispatchType.orderEdit);
          expect(row.status, KitchenSpoolJobStatus.imported);
          expect(transport.calls.last.$2['p_client_status'], 'imported');
        }
        expect(handedOver, ['d-failed', 'd-absent']);
        expect(phoneResolves, 0, reason: 'a change slip prints no phone');
      });

      test(
        'a RE-DRIVE is idempotent: the durable row is the authority (no '
        'consult), the hand-over repeats harmlessly, no second row or ack',
        () async {
          transport.enqueue({'ok': true});
          await editCoordinator().importDispatches([edit('d-edit')]);
          final blob = (await rowOf('d-edit')).encryptedPayloadBlob;
          mirrorReads.clear();

          final again = await editCoordinator(
            inFlight: true, // even "in flight" never touches an existing row
            mirror: (_) => PosRoundPrintClaimState.sent,
          ).importDispatches([edit('d-edit')]);
          expect(again.duplicates, 1);
          expect(again.deferredInFlight, 0);
          expect(again.alreadyPrintedLocally, 0);
          expect(again.orderEditsHandedOver, 1);
          expect(mirrorReads, isEmpty);
          expect(await store.countTotalRows(), 1);
          expect((await rowOf('d-edit')).encryptedPayloadBlob, blob);
          expect(transport.calls, hasLength(1), reason: 'no second ack');
          expect(handedOver, ['d-edit', 'd-edit']);
          expect(phoneResolves, 0);
        },
      );

      test('the edit consult is order_edit-ONLY: an initial dispatch never '
          'reads the edit mirror, and an edit with no 001F wiring imports as '
          'before', () async {
        transport.enqueue({'ok': true});
        await editCoordinator(
          mirror: (_) => PosRoundPrintClaimState.sent,
        ).importDispatches([_dispatch(dispatchId: 'd-1')]);
        expect(mirrorReads, isEmpty);
        expect((await rowOf('d-1')).status, KitchenSpoolJobStatus.imported);

        transport.enqueue({'ok': true});
        final summary = await coordinator().importDispatches([edit('d-edit')]);
        expect(summary.imported, 1);
        expect(summary.orderEditsHandedOver, 0);
      });

      test(
        'ORDERED sweep at import (D4): the edit supersedes this order\'s '
        'OLDER jobs only — a newer round, a tie, an unreadable payload, a '
        'void and other orders are kept; possiblyPrinted is only linked',
        () async {
          await seed('d-initial', payload: _initialPayloadAt(_beforeEdit));
          await seed('d-round-old', payload: _roundPayload(_beforeEdit));
          // Imported BEFORE the edit (the acting till held the edit's claim),
          // yet created AFTER it on the server: it must still print.
          await seed(
            'd-round-new',
            payload: _roundPayload(_afterEdit, number: 3),
          );
          await seed('d-round-tie', payload: _roundPayload(_editCreatedAt));
          await seed(
            'd-round-garbage',
            type: KitchenSpoolDispatchType.serviceRound,
            rawBlob: Uint8List.fromList(List<int>.filled(64, 7)),
          );
          await seed(
            'd-edit-1',
            payload: _editPayload(createdAt: _beforeEdit, editNumber: 1),
          );
          await seed(
            'd-round-pp',
            payload: _roundPayload(_beforeEdit, number: 4),
            possiblyPrinted: true,
          );
          await seed('d-void', payload: _voidPayload());
          await seed(
            'd-other',
            payload: _initialPayloadAt(_beforeEdit),
            orderId: 'order-2',
          );

          transport.enqueue({'ok': true});
          final summary = await editCoordinator().importDispatches([
            edit('d-edit-2', editNumber: 2),
          ]);
          expect(summary.imported, 1);
          expect(summary.superseded, 3, reason: 'initial, old round, edit 1');
          expect(
            summary.supersessionLinks,
            1,
            reason: 'possiblyPrinted linked',
          );

          for (final id in ['d-initial', 'd-round-old', 'd-edit-1']) {
            final row = await rowOf(id);
            expect(row.status, KitchenSpoolJobStatus.superseded, reason: id);
            expect(row.supersededByDispatchId, 'd-edit-2', reason: id);
          }
          final pp = await rowOf('d-round-pp');
          expect(pp.status, KitchenSpoolJobStatus.possiblyPrinted);
          expect(pp.supersededByDispatchId, 'd-edit-2');
          for (final id in [
            'd-round-new',
            'd-round-tie',
            'd-round-garbage',
            'd-void',
            'd-other',
          ]) {
            final row = await rowOf(id);
            expect(row.status, KitchenSpoolJobStatus.imported, reason: id);
            expect(row.supersededByDispatchId, isNull, reason: id);
          }
          expect(
            (await rowOf('d-edit-2')).status,
            KitchenSpoolJobStatus.imported,
            reason: 'the evidence never supersedes itself',
          );

          // Idempotent on a re-drive.
          final again = await editCoordinator().importDispatches([
            edit('d-edit-2', editNumber: 2),
          ]);
          expect(again.duplicates, 1);
          expect(again.superseded, 0);
          expect(again.supersessionLinks, 0);
        },
      );

      test('the RUN-LEVEL sweep: this till\'s DIRECT slip prints are evidence '
          'with no imported edit row; imported edit rows are evidence too; '
          'VOID numbers stay apart', () async {
        await seed('d-initial', payload: _initialPayloadAt(_beforeEdit));
        await seed('d-round-old', payload: _roundPayload(_beforeEdit));
        await seed(
          'd-round-new',
          payload: _roundPayload(_afterEdit, number: 3),
        );
        // order-2: an imported (unresolved) edit row is the evidence.
        await seed(
          'd-o2-round',
          payload: _roundPayload(_beforeEdit),
          orderId: 'order-2',
        );
        await seed('d-o2-edit', payload: _editPayload(), orderId: 'order-2');
        // order-3: a VOID supersedes everything, as before.
        await seed(
          'd-o3-initial',
          payload: _initialPayloadAt(_afterEdit),
          orderId: 'order-3',
        );
        await seed('d-o3-void', payload: _voidPayload(), orderId: 'order-3');

        final result = await reconcileLocalSupersessionEvidence(
          store,
          cipher: cipher,
          key: key,
          deviceId: 'dev-1',
          branchId: 'branch-1',
          now: now,
          externalEdits: [
            KitchenEditSupersessionEvidence(
              orderId: 'order-1',
              dispatchId: 'd-direct',
              createdAt: DateTime.parse(_editCreatedAt),
            ),
          ],
        );
        expect(result.voidSuperseded, 1);
        expect(result.voidLinks, 0);
        expect(result.editSuperseded, 3);
        expect(result.editLinks, 0);

        for (final (id, by) in [
          ('d-initial', 'd-direct'),
          ('d-round-old', 'd-direct'),
          ('d-o2-round', 'd-o2-edit'),
          ('d-o3-initial', 'd-o3-void'),
        ]) {
          final row = await rowOf(id);
          expect(row.status, KitchenSpoolJobStatus.superseded, reason: id);
          expect(row.supersededByDispatchId, by, reason: id);
        }
        for (final id in ['d-round-new', 'd-o2-edit', 'd-o3-void']) {
          expect(
            (await rowOf(id)).status,
            KitchenSpoolJobStatus.imported,
            reason: id,
          );
        }

        // Idempotent.
        final again = await reconcileLocalSupersessionEvidence(
          store,
          cipher: cipher,
          key: key,
          deviceId: 'dev-1',
          branchId: 'branch-1',
          now: now,
          externalEdits: [
            KitchenEditSupersessionEvidence(
              orderId: 'order-1',
              dispatchId: 'd-direct',
              createdAt: DateTime.parse(_editCreatedAt),
            ),
          ],
        );
        expect(again.editSuperseded + again.voidSuperseded, 0);
      });

      test(
        'an UNREADABLE imported edit row is no evidence (keeps every job)',
        () async {
          await seed('d-initial', payload: _initialPayloadAt(_beforeEdit));
          await seed(
            'd-edit-garbage',
            type: KitchenSpoolDispatchType.orderEdit,
            rawBlob: Uint8List.fromList(List<int>.filled(64, 9)),
          );
          final result = await reconcileLocalSupersessionEvidence(
            store,
            cipher: cipher,
            key: key,
            deviceId: 'dev-1',
            branchId: 'branch-1',
            now: now,
          );
          expect(result.editSuperseded, 0);
          expect(
            (await rowOf('d-initial')).status,
            KitchenSpoolJobStatus.imported,
          );
        },
      );

      test('the composition maps the slip store evidence; an entry without a '
          'dispatch id cannot be linked and is dropped', () {
        final created = DateTime.parse(_editCreatedAt);
        final mapped = orderEditSupersessionEvidenceFrom([
          OrderEditSlipEvidence(
            orderId: 'order-1',
            dispatchId: 'd-1',
            editCreatedAt: created,
            recordedAt: now,
          ),
          OrderEditSlipEvidence(
            orderId: 'order-2',
            editCreatedAt: created,
            recordedAt: now,
          ),
          OrderEditSlipEvidence(
            orderId: 'order-3',
            dispatchId: '',
            editCreatedAt: created,
            recordedAt: now,
          ),
        ]);
        expect(mapped, hasLength(1));
        expect(mapped.single.orderId, 'order-1');
        expect(mapped.single.dispatchId, 'd-1');
        expect(mapped.single.createdAt, created);
      });
    },
  );
}
