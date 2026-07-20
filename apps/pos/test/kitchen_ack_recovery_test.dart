@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';

/// KITCHEN-MODE-001C2B-CORRECTION-001 — durable-row acknowledgement
/// authority. The crash window under test: a dispatch was DURABLY inserted,
/// the app died before `setPendingServerAck`, and the printer configuration
/// changed before the re-drive. The acknowledgement must come from the
/// stored row status — never from freshly recomputed destination state —
/// and the re-drive must not re-decode, re-resolve, re-pin, or re-encrypt
/// anything. Real on-disk dedicated spool database throughout.
class _FakeTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];
  final List<Object? Function()> _script = [];

  void enqueue(Object? response) => _script.add(() => response);

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, Map.of(params)));
    if (_script.isEmpty) {
      fail('unexpected transport call: $function');
    }
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

const _validDestination = ResolvedKitchenDestination(
  destination: NetworkKitchenDestination(host: '10.0.0.5', port: 9100),
  fingerprint: 'fp-net-1',
  displayLabel: 'Kitchen',
  transportKind: 'network',
  paperWidth: '80mm',
);

const _blockedDestination = BlockedKitchenDestination(
  'kitchen_printer_not_selected',
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

PulledKitchenDispatch _dispatch(String id, {String orderId = 'order-1'}) =>
    PulledKitchenDispatch(
      dispatchId: id,
      dispatchType: 'initial_order',
      orderId: orderId,
      payloadVersion: 1,
      moneyFreePayload: _ticketPayload(),
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
    tempDir = await Directory.systemTemp.createTemp('rf_ack_recovery_test');
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
    idCounter = 100;
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  KitchenDispatchImportCoordinator coordinator(
    KitchenDestinationResolution destination,
  ) => KitchenDispatchImportCoordinator(
    store: store,
    cipher: cipher,
    key: key,
    scope: _scope,
    destination: destination,
    ackRepository: ackRepo,
    localJobIdGenerator: () => 'redrive-${++idCounter}',
    now: () => now,
  );

  /// The exact crash-window state: durable insert COMMITTED, app died
  /// before `setPendingServerAck` — no pending ack, no acknowledgement.
  Future<KitchenSpoolJobRow> seedCrashWindowRow({
    required String dispatchId,
    required bool blocked,
    String orderId = 'order-1',
  }) => store.insertImportedJob(
    NewKitchenSpoolJob(
      localJobId: 'seed-$dispatchId',
      dispatchId: dispatchId,
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
      deviceId: 'dev-1',
      orderId: orderId,
      serviceRoundId: null,
      dispatchType: KitchenSpoolDispatchType.initialOrder,
      initialStatus: blocked
          ? KitchenSpoolJobStatus.blockedConfiguration
          : KitchenSpoolJobStatus.imported,
      encryptedPayloadBlob: Uint8List.fromList(
        List.generate(48, (i) => (i * 7 + dispatchId.hashCode) & 0xff),
      ),
      encryptionVersion: 1,
      destinationFingerprint: blocked ? null : 'fp-original',
      destinationDisplayLabel: blocked ? null : 'Original Kitchen',
      transportKind: blocked ? null : 'network',
      paperWidth: blocked ? null : '80mm',
      lastErrorCode: blocked ? 'kitchen_printer_not_selected' : null,
      payloadVersion: 1,
      documentVersion: 1,
      rasterVersion: 1,
      serverClaimExpiresAt: null,
      createdAt: now,
    ),
  );

  test(
    'A. blocked row + configuration becomes VALID before re-drive: the '
    'acknowledgement is blocked_configuration from the durable row; '
    'ciphertext/status/destination/reason all unchanged; no imported ack',
    () async {
      final seeded = await seedCrashWindowRow(
        dispatchId: 'd-crash-blocked',
        blocked: true,
      );
      expect(seeded.pendingServerAckStatus, isNull);
      expect(seeded.serverAcknowledgedAt, isNull);
      final originalBlob = seeded.encryptedPayloadBlob;

      // The printer configuration is now VALID — but the row is authority.
      transport.enqueue({'ok': true});
      final summary = await coordinator(
        _validDestination,
      ).importDispatches([_dispatch('d-crash-blocked')]);

      expect(summary.duplicates, 1);
      expect(summary.imported, 0);
      expect(summary.blocked, 0);
      expect(summary.acked, 1);
      expect(summary.localStateConflicts, 0);

      final row = (await store.findByDispatchId('d-crash-blocked'))!;
      expect(row.localJobId, seeded.localJobId, reason: 'no new row');
      expect(row.encryptedPayloadBlob, originalBlob, reason: 'no re-encrypt');
      expect(row.status, KitchenSpoolJobStatus.blockedConfiguration);
      expect(row.destinationFingerprint, isNull, reason: 'no re-pin');
      expect(row.transportKind, isNull);
      expect(row.paperWidth, isNull);
      expect(row.lastErrorCode, 'kitchen_printer_not_selected');
      expect(row.serverAcknowledgedAt, isNotNull);
      expect(row.pendingServerAckStatus, isNull);

      for (final (fn, params) in transport.calls) {
        expect(fn, 'acknowledge_kitchen_print_dispatch');
        expect(
          params['p_client_status'],
          'blocked_configuration',
          reason: 'an imported ack here would silently lose the ticket',
        );
        expect(params['p_error_code'], 'kitchen_printer_not_selected');
      }
      expect(transport.calls, hasLength(1));
    },
  );

  test('B. imported row + configuration becomes INVALID before re-drive: the '
      'acknowledgement is imported from the durable row; pinned destination '
      'and ciphertext unchanged; no blocked_configuration ack', () async {
    final seeded = await seedCrashWindowRow(
      dispatchId: 'd-crash-imported',
      blocked: false,
    );
    final originalBlob = seeded.encryptedPayloadBlob;

    // The printer configuration is now BROKEN — but the row is authority.
    transport.enqueue({'ok': true});
    final summary = await coordinator(
      _blockedDestination,
    ).importDispatches([_dispatch('d-crash-imported')]);

    expect(summary.duplicates, 1);
    expect(summary.blocked, 0);
    expect(summary.acked, 1);
    expect(summary.localStateConflicts, 0);

    final row = (await store.findByDispatchId('d-crash-imported'))!;
    expect(row.encryptedPayloadBlob, originalBlob, reason: 'no re-encrypt');
    expect(row.status, KitchenSpoolJobStatus.imported);
    expect(row.destinationFingerprint, 'fp-original', reason: 'no re-pin');
    expect(row.transportKind, 'network');
    expect(row.paperWidth, '80mm');
    expect(row.serverAcknowledgedAt, isNotNull);

    for (final (fn, params) in transport.calls) {
      expect(fn, 'acknowledge_kitchen_print_dispatch');
      expect(params['p_client_status'], 'imported');
      expect(params['p_error_code'], isNull);
    }
    expect(transport.calls, hasLength(1));
  });

  test('C. rows in later/terminal states refuse any new acknowledgement: typed '
      'local-state conflict, rows untouched, ZERO transport calls', () async {
    // transportAccepted (d-ta): full lifecycle to transport-accepted.
    await seedCrashWindowRow(dispatchId: 'd-ta', blocked: false);
    await store.setPendingServerAck(
      'seed-d-ta',
      KitchenServerAckStatus.imported,
      now,
    );
    await store.markServerAcked('seed-d-ta', now);
    expect(await store.claimRunnableForPrinting('seed-d-ta', now), isNotNull);
    expect(await store.markTransportAccepted('seed-d-ta', now), isTrue);

    // possiblyPrinted (d-pp): crash during print.
    await seedCrashWindowRow(dispatchId: 'd-pp', blocked: false);
    await store.setPendingServerAck(
      'seed-d-pp',
      KitchenServerAckStatus.imported,
      now,
    );
    await store.markServerAcked('seed-d-pp', now);
    expect(await store.claimRunnableForPrinting('seed-d-pp', now), isNotNull);
    expect(await store.markPossiblyPrintedOnRecovery(now), 1);

    // superseded (d-sup): server void evidence.
    await seedCrashWindowRow(dispatchId: 'd-sup', blocked: false);
    expect(
      await store.markSupersededFromServerEvidence(
        dispatchId: 'd-sup',
        supersededByDispatchId: 'd-ta',
        now: now,
      ),
      isTrue,
    );

    // terminal ownership verdict (d-term): status imported + terminal code.
    await seedCrashWindowRow(dispatchId: 'd-term', blocked: false);
    await store.setPendingServerAck(
      'seed-d-term',
      KitchenServerAckStatus.imported,
      now,
    );
    expect(
      await store.markServerAckTerminal(
        'seed-d-term',
        terminalCode: 'not_claim_owner',
        now: now,
      ),
      isTrue,
    );

    final before = {
      for (final id in ['d-ta', 'd-pp', 'd-sup', 'd-term'])
        id: (await store.findByDispatchId(id))!,
    };

    // Re-drive all four. The transport has NO scripted responses — any
    // acknowledgement attempt fails the test loudly.
    final summary = await coordinator(_validDestination).importDispatches([
      for (final id in ['d-ta', 'd-pp', 'd-sup', 'd-term']) _dispatch(id),
    ]);

    expect(summary.duplicates, 4);
    expect(summary.localStateConflicts, 4);
    expect(summary.acked, 0);
    expect(summary.ackRetriesScheduled, 0);
    expect(summary.ackTerminal, 0);
    expect(transport.calls, isEmpty, reason: 'no acknowledgement invented');

    for (final entry in before.entries) {
      final after = (await store.findByDispatchId(entry.key))!;
      expect(after.status, entry.value.status, reason: entry.key);
      expect(
        after.encryptedPayloadBlob,
        entry.value.encryptedPayloadBlob,
        reason: '${entry.key} ciphertext untouched',
      );
      expect(
        after.serverAckTerminalCode,
        entry.value.serverAckTerminalCode,
        reason: '${entry.key} terminal verdict preserved',
      );
      expect(
        after.pendingServerAckStatus,
        entry.value.pendingServerAckStatus,
        reason: '${entry.key} no invented pending ack',
      );
    }
  });

  test('unsupported payload version is a row-local rejection (never persisted, '
      'never acked)', () async {
    final summary = await coordinator(_validDestination).importDispatches([
      PulledKitchenDispatch(
        dispatchId: 'd-v2',
        dispatchType: 'initial_order',
        orderId: 'order-1',
        payloadVersion: 2,
        moneyFreePayload: _ticketPayload(),
        createdAt: '2026-07-20T10:00:00Z',
      ),
    ]);
    expect(summary.rejected, 1);
    expect(await store.findByDispatchId('d-v2'), isNull);
    expect(transport.calls, isEmpty);
  });
}
