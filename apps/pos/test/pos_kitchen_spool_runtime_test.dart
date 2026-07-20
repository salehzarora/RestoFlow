@TestOn('vm')
library;

import 'dart:async' show Completer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_drain_coordinator.dart';
import 'package:restoflow_pos/src/spool/pending_kitchen_ack_coordinator.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_runtime.dart';
import 'package:restoflow_pos/src/spool/pos_secure_kitchen_mode_cache.dart';

/// KITCHEN-MODE-001C2B — runtime gating (D1/D3/D4) + pending-ack
/// reconciliation against a REAL dedicated spool database and scripted
/// transports. The critical negatives: web is a typed no-op, verified kds
/// with no spool leaves ZERO footprint, printer_only without a trusted
/// revision never pulls, and blocked key states never wipe anything.
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

const _context = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
);

NewKitchenSpoolJob _job(String n, {DateTime? createdAt}) => NewKitchenSpoolJob(
  localJobId: 'job-$n',
  dispatchId: 'd-$n',
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
  orderId: 'order-$n',
  serviceRoundId: null,
  dispatchType: KitchenSpoolDispatchType.initialOrder,
  initialStatus: KitchenSpoolJobStatus.imported,
  encryptedPayloadBlob: Uint8List.fromList([1, 2, 3, n.hashCode & 0xff]),
  encryptionVersion: 1,
  destinationFingerprint: 'fp-1',
  destinationDisplayLabel: 'Kitchen',
  transportKind: 'network',
  paperWidth: '80mm',
  payloadVersion: 1,
  documentVersion: 1,
  rasterVersion: 1,
  serverClaimExpiresAt: null,
  createdAt: createdAt ?? DateTime.utc(2026, 7, 20, 9),
);

void main() {
  const native = PosKitchenSpoolPlatform(isWeb: false);
  const web = PosKitchenSpoolPlatform(isWeb: true);
  final now = DateTime.utc(2026, 7, 20, 12);

  late Directory tempDir;
  late _FakeTransport transport;
  late InMemoryDeviceSessionSecretStore secretStore;
  late _FakeSecureStorage secureStorage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rf_spool_runtime_test');
    transport = _FakeTransport();
    secretStore = InMemoryDeviceSessionSecretStore();
    await secretStore.write(
      const DeviceSessionCredential(
        deviceId: 'dev-1',
        sessionToken: 'tok-secret-1',
      ),
    );
    secureStorage = _FakeSecureStorage();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  KitchenSpoolDatabaseFactory factory() => KitchenSpoolDatabaseFactory(
    documentsDirectoryProvider: () async => tempDir,
  );

  var localJobCounter = 0;

  PosKitchenSpoolRuntime runtime({
    PosKitchenSpoolPlatform platform = native,
    DeviceContext? Function()? deviceContext,
    PosSecureKitchenModeCache? modeCache,
    Future<KitchenModeResult> Function()? fetchMode,
    Future<KitchenDestinationResolution> Function()? destinationResolver,
    bool wireDrain = false,
  }) => PosKitchenSpoolRuntime(
    platform: platform,
    deviceContext: deviceContext ?? () => _context,
    secretStore: secretStore,
    modeRepository: SupabaseDeviceKitchenModeRepository(
      transport: transport,
      secretStore: secretStore,
      now: () => now,
    ),
    ackRepository: SupabaseKitchenDispatchAckRepository(
      transport: transport,
      secretStore: secretStore,
    ),
    databaseFactoryBuilder: factory,
    pullRepository: wireDrain
        ? SupabaseKitchenDispatchPullRepository(
            transport: transport,
            secretStore: secretStore,
          )
        : null,
    fetchMode: fetchMode,
    destinationResolver: destinationResolver,
    localJobIdGenerator: wireDrain ? () => 'rt-${++localJobCounter}' : null,
    modeCache: modeCache,
    keyStore: FlutterSecureKitchenSpoolKeyStore(
      storage: secureStorage,
      platform: native,
    ),
    now: () => now,
  );

  Future<void> provisionKey() => KitchenSpoolKeyManager(
    FlutterSecureKitchenSpoolKeyStore(storage: secureStorage, platform: native),
  ).provisionKey();

  group('PendingKitchenAckCoordinator', () {
    late KitchenSpoolDatabase db;
    late DriftKitchenSpoolStore store;

    setUp(() async {
      db = await factory().open();
      store = DriftKitchenSpoolStore(db);
    });

    tearDown(() => db.close());

    PendingKitchenAckCoordinator coordinator() => PendingKitchenAckCoordinator(
      store: store,
      ackRepository: SupabaseKitchenDispatchAckRepository(
        transport: transport,
        secretStore: secretStore,
      ),
      now: () => now,
    );

    test('flushes DUE pending acks only; not-due jobs wait', () async {
      // job-1: due (no next-attempt gate yet).
      await store.insertImportedJob(_job('1'));
      await store.setPendingServerAck(
        'job-1',
        KitchenServerAckStatus.imported,
        now,
      );
      // job-2: pending but scheduled in the future.
      await store.insertImportedJob(_job('2'));
      await store.setPendingServerAck(
        'job-2',
        KitchenServerAckStatus.imported,
        now,
      );
      await store.updateServerAckRetry(
        'job-2',
        errorCode: 'network_unreachable',
        nextAttemptAt: now.add(const Duration(minutes: 5)),
        now: now,
      );
      // job-3: already fully acked.
      await store.insertImportedJob(_job('3'));
      await store.setPendingServerAck(
        'job-3',
        KitchenServerAckStatus.imported,
        now,
      );
      await store.markServerAcked('job-3', now);

      transport.enqueue({'ok': true});
      final (acked, retries, terminal) = await coordinator().flush(
        deviceId: 'dev-1',
        branchId: 'branch-1',
      );
      expect((acked, retries, terminal), (1, 0, 0));
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.$2['p_dispatch_id'], 'd-1');
      expect(
        (await store.getByLocalJobId('job-1'))!.serverAcknowledgedAt,
        isNotNull,
      );
      expect(
        (await store.getByLocalJobId('job-2'))!.pendingServerAckStatus,
        KitchenServerAckStatus.imported,
      );
    });

    test('terminal verdict stops the retry loop permanently', () async {
      await store.insertImportedJob(_job('1'));
      await store.setPendingServerAck(
        'job-1',
        KitchenServerAckStatus.imported,
        now,
      );
      transport.enqueue({'ok': false, 'error': 'conflict'});
      final (acked, retries, terminal) = await coordinator().flush(
        deviceId: 'dev-1',
        branchId: 'branch-1',
      );
      expect((acked, retries, terminal), (0, 0, 1));
      final row = (await store.getByLocalJobId('job-1'))!;
      expect(row.serverAckTerminalCode, 'conflict');
      expect(row.pendingServerAckStatus, isNull);
      // A later flush has nothing left to send.
      expect(
        await coordinator().flush(deviceId: 'dev-1', branchId: 'branch-1'),
        (0, 0, 0),
      );
      expect(transport.calls, hasLength(1));
    });

    test(
      'transient failure schedules backoff and keeps the pending ack',
      () async {
        await store.insertImportedJob(_job('1'));
        await store.setPendingServerAck(
          'job-1',
          KitchenServerAckStatus.imported,
          now,
        );
        transport.enqueueThrow(
          const SyncTransportException(SyncTransportErrorKind.transient),
        );
        final (acked, retries, terminal) = await coordinator().flush(
          deviceId: 'dev-1',
          branchId: 'branch-1',
        );
        expect((acked, retries, terminal), (0, 1, 0));
        final row = (await store.getByLocalJobId('job-1'))!;
        expect(row.pendingServerAckStatus, KitchenServerAckStatus.imported);
        expect(row.serverAckNextAttemptAt!.isAfter(now), isTrue);
        expect(row.serverAckLastErrorCode, 'network_unreachable');
      },
    );
  });

  group('PosKitchenSpoolRuntime gating', () {
    test('web -> typed skip; NOTHING is touched', () async {
      final report = await runtime(platform: web).onStartup();
      expect(report, isA<KitchenSpoolRunSkipped>());
      expect(report.detail, 'web_unsupported');
      expect(transport.calls, isEmpty);
      expect(
        Directory(p.join(tempDir.path, 'restoflow_kitchen_spool')).existsSync(),
        isFalse,
      );
    });

    test('no restored device context -> no_device_scope', () async {
      final report = await runtime(deviceContext: () => null).onResume();
      expect(report.detail, 'no_device_scope');
      expect(transport.calls, isEmpty);
    });

    test(
      'incomplete tuple (null restaurant/device) -> no_device_scope',
      () async {
        final report = await runtime(
          deviceContext: () => const DeviceContext(
            organizationId: 'org-1',
            branchId: 'branch-1',
          ),
        ).onStartup();
        expect(report.detail, 'no_device_scope');
        expect(transport.calls, isEmpty);
      },
    );

    test('verified kds with NO spool file -> ZERO footprint skip + cached '
        'mode', () async {
      transport.enqueue({
        'ok': true,
        'entity': 'kitchen_workflow_mode',
        'kitchen_workflow_mode': 'kds',
        'server_ts': 'x',
      });
      final cache = PosSecureKitchenModeCache(
        storage: secureStorage,
        platform: native,
        now: () => now,
      );
      final report = await runtime(modeCache: cache).onStartup();
      expect(report.detail, 'kds_no_spool_footprint');
      // ZERO footprint: no directory, no database file.
      expect(
        Directory(p.join(tempDir.path, 'restoflow_kitchen_spool')).existsSync(),
        isFalse,
      );
      // The verified mode IS cached, bound to the session fingerprint.
      final record = await cache.read(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        deviceId: 'dev-1',
        sessionFingerprint: sessionFingerprint('tok-secret-1'),
      );
      expect(record, isNotNull);
      expect(record!.mode, 'kds');
      expect(record.modeRevision, isNull); // D1
      expect(record.verifiedAt, now);
    });

    test('mode failure with no spool -> mode_unknown_no_spool; the cache is '
        'NEVER overwritten by a failure', () async {
      final cache = PosSecureKitchenModeCache(
        storage: secureStorage,
        platform: native,
        now: () => now,
      );
      await cache.write(
        KitchenModeCacheRecord(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          sessionFingerprint: sessionFingerprint('tok-secret-1'),
          mode: 'kds',
          verifiedAt: now.subtract(const Duration(minutes: 5)),
        ),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.transient),
      );
      final report = await runtime(modeCache: cache).onStartup();
      expect(report.detail, 'mode_unknown_no_spool');
      final record = await cache.read(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        deviceId: 'dev-1',
        sessionFingerprint: sessionFingerprint('tok-secret-1'),
      );
      expect(record!.mode, 'kds');
      expect(record.verifiedAt, now.subtract(const Duration(minutes: 5)));
    });

    test('printer_only (revision unavailable, D1) with no spool -> fail-closed '
        'skip; the runtime NEVER pulls dispatches', () async {
      transport.enqueue({
        'ok': true,
        'entity': 'kitchen_workflow_mode',
        'kitchen_workflow_mode': 'printer_only',
        'server_ts': 'x',
      });
      final report = await runtime().onStartup();
      expect(report.detail, 'printer_only_unavailable');
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.$1, 'get_device_kitchen_workflow_mode');
    });

    test('existing spool + ready key -> safe reconciliation (pending acks '
        'flushed), still NO pull', () async {
      // Seed: spool with one pending-ack row + a provisioned key.
      final db = await factory().open();
      final store = DriftKitchenSpoolStore(db);
      await store.insertImportedJob(_job('1'));
      await store.setPendingServerAck(
        'job-1',
        KitchenServerAckStatus.imported,
        now,
      );
      await db.close();
      await provisionKey();

      transport.enqueue({
        'ok': true,
        'entity': 'kitchen_workflow_mode',
        'kitchen_workflow_mode': 'printer_only',
        'server_ts': 'x',
      });
      transport.enqueue({'ok': true}); // the pending ack
      final rt = runtime();
      final report = await rt.onResume();
      expect(report, isA<KitchenSpoolRunReconciled>());
      final reconciled = report as KitchenSpoolRunReconciled;
      expect(reconciled.acked, 1);
      expect(reconciled.terminal, 0);
      expect(
        [for (final (fn, _) in transport.calls) fn],
        [
          'get_device_kitchen_workflow_mode',
          'acknowledge_kitchen_print_dispatch',
        ],
      );
      await rt.dispose();

      // The row survives, fully acknowledged (never wiped by the runtime).
      final verifyDb = await factory().open();
      final verifyStore = DriftKitchenSpoolStore(verifyDb);
      final row = (await verifyStore.getByLocalJobId('job-1'))!;
      expect(row.serverAcknowledgedAt, isNotNull);
      expect(row.pendingServerAckStatus, isNull);
      await verifyDb.close();
    });

    test('existing spool + MISSING key over rows -> BLOCKED; rows and spool '
        'file preserved (D3: never wipe, never regenerate)', () async {
      final db = await factory().open();
      final store = DriftKitchenSpoolStore(db);
      await store.insertImportedJob(_job('1'));
      await db.close();
      // NO key provisioned.
      transport.enqueue({
        'ok': true,
        'entity': 'kitchen_workflow_mode',
        'kitchen_workflow_mode': 'kds',
        'server_ts': 'x',
      });
      final rt = runtime();
      final report = await rt.onStartup();
      expect(report, isA<KitchenSpoolRunBlocked>());
      expect(report.detail, 'KitchenSpoolKeyMissingWithRows');
      expect(secureStorage.values, isEmpty, reason: 'no key regenerated');
      await rt.dispose();

      final verifyDb = await factory().open();
      expect(await DriftKitchenSpoolStore(verifyDb).countTotalRows(), 1);
      await verifyDb.close();
    });

    test(
      're-entrancy: an overlapping run is skipped, then the guard resets',
      () async {
        // Park the first run on a mode call that only completes on demand.
        final gate = Completer<Object?>();
        transport.enqueue(null); // placeholder; replaced by the gate below.
        transport._script[0] = () => gate.future;
        final rt = runtime();
        final first = rt.onStartup();
        // Give the first run a microtask turn to take the guard.
        await Future<void>.delayed(Duration.zero);
        expect((await rt.onResume()).detail, 'already_running');
        gate.complete({
          'ok': true,
          'entity': 'kitchen_workflow_mode',
          'kitchen_workflow_mode': 'kds',
          'server_ts': 'x',
        });
        expect((await first).detail, 'kds_no_spool_footprint');
        // The guard released: a fresh run proceeds normally.
        transport.enqueue({
          'ok': true,
          'entity': 'kitchen_workflow_mode',
          'kitchen_workflow_mode': 'kds',
          'server_ts': 'x',
        });
        expect((await rt.onResume()).detail, 'kds_no_spool_footprint');
      },
    );
  });

  group('CORRECTION-001: trusted printer-only drain path (test-injected)', () {
    Future<KitchenModeResult> trustedMode() async =>
        KitchenModePrinterOnlyWithRevision(revision: 3, verifiedAt: now);

    Map<String, Object?> pageOf(List<Map<String, Object?>> rows) => {
      'ok': true,
      'dispatches': rows,
      'has_more': false,
    };

    Map<String, Object?> dispatchRow(String id) => {
      'id': id,
      'dispatch_type': 'initial_order',
      'order_id': 'order-$id',
      'payload_version': 1,
      'payload': {
        'v': 1,
        'kind': 'initial_order',
        'order_code': '#000042',
        'order_type': 'dine_in',
        'items': [
          {'qty': 1, 'name': 'Burger', 'modifiers': <Object?>[]},
        ],
      },
      'created_at': '2026-07-20T10:00:00Z',
    };

    const resolved = ResolvedKitchenDestination(
      destination: NetworkKitchenDestination(host: '10.0.0.9', port: 9100),
      fingerprint: 'fp-rt',
      displayLabel: 'Kitchen',
      transportKind: 'network',
      paperWidth: '80mm',
    );

    test(
      'an injected trusted revision executes the FULL dormant chain: '
      'provision key (zero rows) -> pull -> durable import -> ack -> cursor',
      () async {
        transport.enqueue(pageOf([dispatchRow('d-1')]));
        transport.enqueue({'ok': true}); // ack d-1
        final cache = PosSecureKitchenModeCache(
          storage: secureStorage,
          platform: native,
          now: () => now,
        );
        final rt = runtime(
          fetchMode: trustedMode,
          destinationResolver: () async => resolved,
          wireDrain: true,
          modeCache: cache,
        );
        final report = await rt.onStartup();
        expect(report, isA<KitchenSpoolRunDrained>());
        final drained = report as KitchenSpoolRunDrained;
        expect(drained.drain.stoppedReason, KitchenDrainStopReason.complete);
        expect(drained.drain.rowsImported, 1);
        expect(drained.drain.acknowledgementsSucceeded, 1);
        await rt.dispose();

        // The dedicated spool now exists with the durable acked row, the key
        // was provisioned (zero rows at first run), and the TRUSTED revision
        // is cached.
        final verifyDb = await factory().open();
        final verifyStore = DriftKitchenSpoolStore(verifyDb);
        final row = (await verifyStore.findByDispatchId('d-1'))!;
        expect(row.status, KitchenSpoolJobStatus.imported);
        expect(row.serverAcknowledgedAt, isNotNull);
        await verifyDb.close();
        expect(
          secureStorage.values.keys,
          contains('restoflow.pos.kitchen_spool.ref:kitchen-spool-aes-key-v1'),
        );
        final record = await cache.read(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          sessionFingerprint: sessionFingerprint('tok-secret-1'),
        );
        expect(record!.mode, 'printer_only');
        expect(record.modeRevision, 3);
      },
    );

    test('readiness_required stops the drain TYPED and triggers no readiness '
        'reporting call', () async {
      transport.enqueue({'ok': false, 'error': 'readiness_required'});
      final rt = runtime(
        fetchMode: trustedMode,
        destinationResolver: () async => resolved,
        wireDrain: true,
      );
      final report = await rt.onStartup();
      final drained = report as KitchenSpoolRunDrained;
      expect(
        drained.drain.stoppedReason,
        KitchenDrainStopReason.readinessRequired,
      );
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.$1, 'pull_kitchen_print_dispatches');
      await rt.dispose();
    });

    test('trusted mode + missing key OVER ROWS stays BLOCKED: no pull, no key '
        'regeneration, rows preserved', () async {
      final db = await factory().open();
      await DriftKitchenSpoolStore(db).insertImportedJob(_job('9'));
      await db.close();
      final rt = runtime(
        fetchMode: trustedMode,
        destinationResolver: () async => resolved,
        wireDrain: true,
      );
      final report = await rt.onStartup();
      expect(report, isA<KitchenSpoolRunBlocked>());
      expect(report.detail, 'KitchenSpoolKeyMissingWithRows');
      expect(secureStorage.values, isEmpty, reason: 'never regenerated');
      expect(transport.calls, isEmpty, reason: 'no pull while blocked');
      await rt.dispose();
    });

    test('an UNDETERMINABLE destination fails closed BEFORE any pull (never '
        'imports rows as blocked on a guess)', () async {
      final rt = runtime(
        fetchMode: trustedMode,
        destinationResolver: () async =>
            throw const KitchenSpoolDestinationUnresolvableException(),
        wireDrain: true,
      );
      final report = await rt.onStartup();
      expect(report, isA<KitchenSpoolRunBlocked>());
      expect(report.detail, 'kitchen_destination_unresolvable');
      expect(transport.calls, isEmpty);
      await rt.dispose();
    });

    test('trusted mode without the drain wiring stays a typed skip (never a '
        'partial drain)', () async {
      final report = await runtime(fetchMode: trustedMode).onStartup();
      expect(report.detail, 'real_backend_not_wired');
      expect(transport.calls, isEmpty);
    });
  });

  group('CORRECTION-001: lifecycle async safety', () {
    test('an UNEXPECTED error during startup becomes a typed redacted Blocked '
        'report (no unhandled async error, no raw message), and the guard '
        'resets for the next run', () async {
      var calls = 0;
      final rt = runtime(
        fetchMode: () async {
          calls++;
          if (calls == 1) {
            throw StateError('SECRET-ENDPOINT-10.0.0.9-SHOULD-NOT-LEAK');
          }
          return KitchenModeVerifiedKds(verifiedAt: now);
        },
      );
      final report = await rt.onStartup();
      expect(report, isA<KitchenSpoolRunBlocked>());
      expect(report.detail, 'unexpected_failure');
      expect(report.detail, isNot(contains('SECRET')));
      expect(report.detail, isNot(contains('10.0.0.9')));
      // The re-entry guard reset: the following invocation runs normally.
      expect((await rt.onResume()).detail, 'kds_no_spool_footprint');
    });

    test('an UNEXPECTED error during resume is equally contained', () async {
      final rt = runtime(fetchMode: () async => throw ArgumentError('boom'));
      final report = await rt.onResume();
      expect(report, isA<KitchenSpoolRunBlocked>());
      expect(report.detail, 'unexpected_failure');
      expect(
        (await rt.onResume()).detail,
        'unexpected_failure',
        reason: 'guard reset — the error path is repeatable, not latched',
      );
    });
  });
}
