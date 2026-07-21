@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_worker.dart';
import 'package:restoflow_pos/src/spool/kitchen_ticket_renderer.dart';
import 'package:restoflow_pos/src/spool/kitchen_void_reconciliation.dart';
import 'package:restoflow_pos/src/spool/pending_kitchen_ack_coordinator.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show
        KitchenTransportOutcome,
        KitchenTransportOutcomeKind,
        PrinterDestinationSendGate;

/// KITCHEN-MODE-001C2C — the crash-safe worker against a REAL on-disk
/// dedicated spool database, the REAL cipher and renderer, and scripted
/// transports. Covers eligibility, the outcome→state mapping, prep-failure
/// isolation, gate timing, pre-send durable revalidation, disposal, VOID
/// sweeps, and the ack pairings.
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

/// Scripted kitchen sends: each call pops the next outcome; records pinned
/// endpoints and payload bytes.
class _SendScript {
  final List<KitchenTransportOutcome> outcomes = [];
  final List<(String, int, Uint8List)> networkCalls = [];
  final List<(String, Uint8List)> bluetoothCalls = [];
  Completer<void>? holdUntil;

  Future<KitchenTransportOutcome> network({
    required String host,
    required int port,
    required Uint8List bytes,
  }) async {
    networkCalls.add((host, port, bytes));
    final hold = holdUntil;
    if (hold != null) await hold.future;
    return outcomes.removeAt(0);
  }

  Future<KitchenTransportOutcome> bluetooth({
    required String address,
    required Uint8List bytes,
  }) async {
    bluetoothCalls.add((address, bytes));
    return outcomes.removeAt(0);
  }
}

String _fp(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

void main() {
  late Directory tempDir;
  late KitchenSpoolDatabase db;
  late DriftKitchenSpoolStore store;
  late AesGcmKitchenSpoolCipher cipher;
  late SecretValue key;
  late _FakeTransport transport;
  late SupabaseKitchenDispatchAckRepository ackRepo;
  late _SendScript sends;
  late PrinterDestinationSendGate gate;
  final now = DateTime.utc(2026, 7, 20, 11);

  const scope = KitchenImportScope(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-1',
    deviceId: 'dev-1',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rf_worker_test');
    db = await KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: () async => tempDir,
    ).open();
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
    sends = _SendScript();
    gate = PrinterDestinationSendGate();
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  KitchenPrintWorker worker({
    int maxJobsPerRun = 20,
    bool Function()? isDisposed,
  }) => KitchenPrintWorker(
    store: store,
    cipher: cipher,
    key: key,
    renderer: const KitchenTicketRenderer(),
    networkSend: sends.network,
    bluetoothSend: sends.bluetooth,
    sendGate: gate,
    ackRepository: ackRepo,
    scope: scope,
    now: () => now,
    maxJobsPerRun: maxJobsPerRun,
    isDisposed: isDisposed,
  );

  KitchenDispatchDocument doc(
    KitchenSpoolDispatchType kind, {
    String? roundId,
  }) => KitchenDispatchDocument(
    serverPayloadVersion: 1,
    kind: kind,
    orderCode: '#000042',
    orderType: 'dine_in',
    roundId: roundId,
    roundNumber: roundId == null ? null : 2,
    voidMarker: kind == KitchenSpoolDispatchType.voidNotice,
    items: kind == KitchenSpoolDispatchType.voidNotice
        ? const []
        : [KitchenDispatchItem(qty: 1, name: 'Falafel')],
  );

  var seedSeq = 0;

  /// Seeds a fully ACKED runnable job with a REAL encrypted payload whose
  /// pinned destination matches the plaintext fingerprint columns.
  Future<KitchenSpoolJobRow> seedRunnable(
    String dispatchId, {
    String host = '10.0.0.5',
    int port = 9100,
    String? bluetoothAddress,
    KitchenSpoolDispatchType kind = KitchenSpoolDispatchType.initialOrder,
    String orderId = 'order-1',
    String? roundId,
    String? paperWidth = '80mm',
    SecretValue? encryptKey,
    String? fingerprintOverride,
    KitchenSpoolDispatchType? rowKindOverride,
    void Function(Uint8List envelope)? tamper,
  }) async {
    seedSeq++;
    final destination = bluetoothAddress != null
        ? BluetoothKitchenDestination(address: bluetoothAddress)
        : NetworkKitchenDestination(host: host, port: port);
    final payload = KitchenSpoolLocalPayload(
      dispatch: doc(kind, roundId: roundId),
      destination: destination,
      paperWidth: paperWidth,
      documentVersion: 1,
      rasterVersion: 1,
    );
    final envelope = await cipher.encrypt(
      plaintext: payload.toBytes(),
      aad: KitchenSpoolAad(
        dispatchId: dispatchId,
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        branchId: scope.branchId,
        deviceId: scope.deviceId,
        encryptionVersion: cipher.encryptionVersion,
      ),
      key: encryptKey ?? key,
    );
    tamper?.call(envelope);
    final fingerprint =
        fingerprintOverride ??
        (bluetoothAddress != null
            ? _fp('bluetooth|${bluetoothAddress.trim().toLowerCase()}')
            : _fp('network|${host.trim().toLowerCase()}|$port'));
    final row = await store.insertImportedJob(
      NewKitchenSpoolJob(
        localJobId: 'w-$seedSeq',
        dispatchId: dispatchId,
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        branchId: scope.branchId,
        deviceId: scope.deviceId,
        orderId: orderId,
        serviceRoundId: roundId,
        dispatchType: rowKindOverride ?? kind,
        initialStatus: KitchenSpoolJobStatus.imported,
        encryptedPayloadBlob: envelope,
        encryptionVersion: cipher.encryptionVersion,
        destinationFingerprint: fingerprint,
        destinationDisplayLabel: 'Kitchen',
        transportKind: bluetoothAddress != null ? 'bluetooth' : 'network',
        paperWidth: '80mm',
        payloadVersion: 1,
        documentVersion: 1,
        rasterVersion: 1,
        createdAt: now.add(Duration(seconds: seedSeq)),
      ),
    );
    await store.setPendingServerAck(
      row.localJobId,
      KitchenServerAckStatus.imported,
      now,
    );
    await store.markServerAcked(row.localJobId, now);
    return (await store.getByLocalJobId(row.localJobId))!;
  }

  group('bounded loop', () {
    test('no runnable jobs -> complete, zero footprint', () async {
      final report = await worker().run();
      expect(report.stoppedReason, KitchenWorkerStopReason.complete);
      expect(report.claimed, 0);
      expect(sends.networkCalls, isEmpty);
      expect(transport.calls, isEmpty);
    });

    test('one ACCEPTED network job: pinned endpoint, rendered bytes, atomic '
        'transportAccepted+ack, server told COMPLETED', () async {
      final row = await seedRunnable('d-1');
      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.accepted,
          'flushed',
        ),
      );
      transport.enqueue({'ok': true, 'completed': true});
      final report = await worker().run();
      expect(report.claimed, 1);
      expect(report.accepted, 1);
      expect(report.acked, 1);
      final (host, port, bytes) = sends.networkCalls.single;
      expect(host, '10.0.0.5');
      expect(port, 9100);
      expect(bytes, isNotEmpty);
      final done = (await store.getByLocalJobId(row.localJobId))!;
      expect(done.status, KitchenSpoolJobStatus.transportAccepted);
      expect(done.serverAcknowledgedAt, isNotNull);
      expect(done.pendingServerAckStatus, isNull);
      final (fn, params) = transport.calls.single;
      expect(fn, 'acknowledge_kitchen_print_dispatch');
      expect(params['p_client_status'], 'transport_accepted');
    });

    test('FIFO across destinations; run limit is enforced', () async {
      await seedRunnable('d-a', host: '10.0.0.5');
      await seedRunnable('d-b', host: '10.0.0.6');
      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.accepted,
          'flushed',
        ),
      );
      transport.enqueue({'ok': true, 'completed': true});
      final limited = await worker(maxJobsPerRun: 1).run();
      expect(limited.stoppedReason, KitchenWorkerStopReason.runLimitReached);
      expect(limited.claimed, 1);
      expect(sends.networkCalls.single.$1, '10.0.0.5', reason: 'FIFO head');

      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.accepted,
          'flushed',
        ),
      );
      transport.enqueue({'ok': true, 'completed': true});
      final rest = await worker().run();
      expect(rest.stoppedReason, KitchenWorkerStopReason.complete);
      expect(rest.claimed, 1);
      expect(sends.networkCalls.last.$1, '10.0.0.6');
    });

    test('a not-yet-due failedRetryable job is not claimed', () async {
      final row = await seedRunnable('d-due');
      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.definitelyNotSent,
          'connect_failed',
        ),
      );
      transport.enqueue({'ok': true});
      await worker().run();
      expect(
        (await store.getByLocalJobId(row.localJobId))!.status,
        KitchenSpoolJobStatus.failedRetryable,
      );
      // Immediately re-run: the 2s backoff is not due at the same clock.
      final again = await worker().run();
      expect(again.claimed, 0, reason: 'retry only when due');
    });

    test('disposal stops the loop before any send', () async {
      await seedRunnable('d-disposed');
      final report = await worker(isDisposed: () => true).run();
      expect(report.stoppedReason, KitchenWorkerStopReason.disposed);
      expect(report.claimed, 0);
      expect(sends.networkCalls, isEmpty);
    });
  });

  group('outcome → durable state mapping', () {
    Future<KitchenSpoolJobRow> runOne(
      KitchenTransportOutcome outcome, {
      Object? ackResponse,
    }) async {
      final row = await seedRunnable('d-map-${++seedSeq}');
      sends.outcomes.add(outcome);
      if (ackResponse != null) transport.enqueue(ackResponse);
      await worker().run();
      return (await store.getByLocalJobId(row.localJobId))!;
    }

    test(
      'definitelyNotSent -> failedRetryable + pending + 2s backoff',
      () async {
        final row = await runOne(
          const KitchenTransportOutcome(
            KitchenTransportOutcomeKind.definitelyNotSent,
            'connect_failed',
          ),
          ackResponse: {'ok': true},
        );
        expect(row.status, KitchenSpoolJobStatus.failedRetryable);
        expect(row.lastErrorCode, 'connect_failed');
        expect(row.nextAttemptAt, now.add(const Duration(seconds: 2)));
        expect(row.serverAcknowledgedAt, isNotNull, reason: 'ack flushed');
        final params = transport.calls.single.$2;
        expect(params['p_client_status'], 'failed_retryable');
        expect(params['p_error_code'], 'connect_failed');
      },
    );

    test('timeoutBeforeWrite -> failedRetryable (retry-safe)', () async {
      final row = await runOne(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.timeoutBeforeWrite,
          'connect_timeout',
        ),
        ackResponse: {'ok': true},
      );
      expect(row.status, KitchenSpoolJobStatus.failedRetryable);
    });

    test('temporary unavailable -> failedRetryable + transportUnavailable '
        'count', () async {
      final job = await seedRunnable('d-unavail');
      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.unavailable,
          'bluetooth_off',
        ),
      );
      transport.enqueue({'ok': true});
      final report = await worker().run();
      expect(report.failedRetryable, 1);
      expect(report.transportUnavailable, 1);
      expect(
        (await store.getByLocalJobId(job.localJobId))!.status,
        KitchenSpoolJobStatus.failedRetryable,
      );
    });

    test('ambiguous -> possiblyPrinted (NEVER retried)', () async {
      final row = await runOne(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.ambiguous,
          'partial_write',
        ),
        ackResponse: {'ok': true},
      );
      expect(row.status, KitchenSpoolJobStatus.possiblyPrinted);
      expect(row.nextAttemptAt, isNull);
      expect(transport.calls.single.$2['p_client_status'], 'possibly_printed');
      // Never claimed again.
      final again = await worker().run();
      expect(again.claimed, 0);
    });

    test('timeoutAfterPossibleWrite -> possiblyPrinted', () async {
      final row = await runOne(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.timeoutAfterPossibleWrite,
          'flush_timeout',
        ),
        ackResponse: {'ok': true},
      );
      expect(row.status, KitchenSpoolJobStatus.possiblyPrinted);
    });

    test('unsupported (proven zero-write) -> blockedConfiguration via the '
        'NARROW printing-source transition', () async {
      final row = await runOne(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.unsupported,
          'not_bonded',
        ),
        ackResponse: {'ok': true},
      );
      expect(row.status, KitchenSpoolJobStatus.blockedConfiguration);
      expect(row.lastErrorCode, 'not_bonded');
      expect(
        transport.calls.single.$2['p_client_status'],
        'blocked_configuration',
      );
    });

    test('an ack failure never rewinds the durable print state', () async {
      final job = await seedRunnable('d-ackfail');
      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.accepted,
          'flushed',
        ),
      );
      transport.enqueueThrow(
        const SyncTransportException(SyncTransportErrorKind.server),
      );
      final report = await worker().run();
      expect(report.accepted, 1);
      expect(report.ackRetriesScheduled, 1);
      final row = (await store.getByLocalJobId(job.localJobId))!;
      expect(row.status, KitchenSpoolJobStatus.transportAccepted);
      expect(
        row.pendingServerAckStatus,
        KitchenServerAckStatus.transportAccepted,
        reason: 'pending survives; no reprint ever',
      );
      // The widened pending-ack coordinator later recovers it (window 11).
      transport.enqueue({'ok': true, 'completed': true});
      final flush = PendingKitchenAckCoordinator(
        store: store,
        ackRepository: ackRepo,
        now: () => now.add(const Duration(hours: 1)),
      );
      final (acked, _, _) = await flush.flush(
        deviceId: scope.deviceId,
        branchId: scope.branchId,
      );
      expect(acked, 1);
    });

    test('BLUETOOTH job pins the payload address and maps partial writes to '
        'possiblyPrinted', () async {
      final row = await seedRunnable(
        'd-bt',
        bluetoothAddress: 'DC:0D:30:AA:BB:CC',
      );
      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.ambiguous,
          'partial_write',
        ),
      );
      transport.enqueue({'ok': true});
      await worker().run();
      expect(sends.bluetoothCalls.single.$1, 'DC:0D:30:AA:BB:CC');
      expect(
        (await store.getByLocalJobId(row.localJobId))!.status,
        KitchenSpoolJobStatus.possiblyPrinted,
      );
    });
  });

  group('prep failures (pre-boundary, zero paper risk, row-local)', () {
    Future<KitchenSpoolJobRow> expectBlocked(
      Future<KitchenSpoolJobRow> Function() seed,
      String code,
    ) async {
      final row = await seed();
      transport.enqueue({'ok': true});
      final report = await worker().run();
      expect(report.blockedConfiguration, 1);
      final blocked = (await store.getByLocalJobId(row.localJobId))!;
      expect(blocked.status, KitchenSpoolJobStatus.blockedConfiguration);
      expect(blocked.lastErrorCode, code);
      expect(blocked.encryptedPayloadBlob, isNotEmpty, reason: 'evidence');
      expect(sends.networkCalls, isEmpty, reason: 'never printed');
      expect(
        transport.calls.single.$2['p_client_status'],
        'blocked_configuration',
      );
      return blocked;
    }

    test('ciphertext tamper -> kitchen_payload_undecryptable', () async {
      await expectBlocked(
        () => seedRunnable('d-tamper', tamper: (e) => e[e.length - 1] ^= 0xff),
        'kitchen_payload_undecryptable',
      );
    });

    test('wrong key -> kitchen_payload_undecryptable', () async {
      final otherManager = KitchenSpoolKeyManager(
        FlutterSecureKitchenSpoolKeyStore(
          storage: _FakeSecureStorage(),
          platform: const PosKitchenSpoolPlatform(isWeb: false),
        ),
      );
      await otherManager.provisionKey();
      final otherKey = (await otherManager.readKey())!;
      await expectBlocked(
        () => seedRunnable('d-wrongkey', encryptKey: otherKey),
        'kitchen_payload_undecryptable',
      );
    });

    test(
      'destination fingerprint mismatch -> kitchen_destination_invalid',
      () async {
        await expectBlocked(
          () => seedRunnable('d-fp', fingerprintOverride: _fp('network|lie|1')),
          'kitchen_destination_invalid',
        );
      },
    );

    test(
      'row/payload kind mismatch -> kitchen_payload_identity_mismatch',
      () async {
        await expectBlocked(
          () => seedRunnable(
            'd-kind',
            rowKindOverride: KitchenSpoolDispatchType.serviceRound,
          ),
          'kitchen_payload_identity_mismatch',
        );
      },
    );

    test('non-80mm pinned payload -> kitchen_paper_width_not_80mm', () async {
      await expectBlocked(
        () => seedRunnable('d-58', paperWidth: '58mm'),
        'kitchen_paper_width_not_80mm',
      );
    });

    test('one corrupt row never poisons a valid sibling', () async {
      await seedRunnable('d-bad', tamper: (e) => e[e.length - 1] ^= 0xff);
      final good = await seedRunnable('d-good', host: '10.0.0.7');
      sends.outcomes.add(
        const KitchenTransportOutcome(
          KitchenTransportOutcomeKind.accepted,
          'flushed',
        ),
      );
      transport.enqueue({'ok': true}); // blocked ack for d-bad
      transport.enqueue({'ok': true, 'completed': true}); // ta ack for d-good
      final report = await worker().run();
      expect(report.blockedConfiguration, 1);
      expect(report.accepted, 1);
      expect(
        (await store.getByLocalJobId(good.localJobId))!.status,
        KitchenSpoolJobStatus.transportAccepted,
      );
    });
  });

  group('gate timing + pre-send durable revalidation', () {
    test(
      'a receipt holding the SAME physical gate delays the kitchen send',
      () async {
        await seedRunnable('d-gated');
        final receiptEntered = Completer<void>();
        final release = Completer<void>();
        final key = PrinterDestinationSendGate.networkKey('10.0.0.5', 9100);
        final receipt = gate.withDestination(key, () async {
          receiptEntered.complete();
          await release.future;
          return 'receipt-done';
        });
        await receiptEntered.future;
        sends.outcomes.add(
          const KitchenTransportOutcome(
            KitchenTransportOutcomeKind.accepted,
            'flushed',
          ),
        );
        transport.enqueue({'ok': true, 'completed': true});
        final run = worker().run();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(sends.networkCalls, isEmpty, reason: 'kitchen waits its turn');
        release.complete();
        final report = await run;
        expect(report.accepted, 1);
        expect(await receipt, 'receipt-done');
        expect(sends.networkCalls, hasLength(1));
      },
    );

    test('REVIEW NOTE F2: disposal while a CLAIMED job waits behind the '
        'shared gate — the in-gate check refuses the send, the row stays '
        'queued, and the gate stays usable', () async {
      final job = await seedRunnable('d-dispose-wait');
      var disposed = false;
      final receiptEntered = Completer<void>();
      final release = Completer<void>();
      final key = PrinterDestinationSendGate.networkKey('10.0.0.5', 9100);
      // A simulated RECEIPT send occupies the same physical destination.
      final receipt = gate.withDestination(key, () async {
        receiptEntered.complete();
        await release.future;
        return 'receipt-done';
      });
      await receiptEntered.future;
      final run = worker(isDisposed: () => disposed).run();
      // Let the worker claim + prepare + park behind the gate.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (await store.getByLocalJobId(job.localJobId))!.status,
        KitchenSpoolJobStatus.queued,
        reason: 'claimed and parked, waiting for the gate',
      );
      // Scope disposal happens WHILE waiting.
      disposed = true;
      release.complete();
      final report = await run;
      expect(report.revalidationSkips, 1, reason: 'the in-gate check fired');
      expect(report.accepted, 0);
      expect(sends.networkCalls, isEmpty, reason: 'zero transport calls');
      expect(sends.bluetoothCalls, isEmpty);
      expect(transport.calls, isEmpty, reason: 'no acknowledgement sent');
      final row = (await store.getByLocalJobId(job.localJobId))!;
      expect(
        row.status,
        KitchenSpoolJobStatus.queued,
        reason: 'markPrinting never succeeded; the row is preserved',
      );
      expect(await receipt, 'receipt-done');
      // The gate released cleanly: a following waiter proceeds immediately.
      expect(await gate.withDestination(key, () async => 42), 42);
    });

    test('a VOID landing while the job waits for the gate refuses the send '
        '(durable revalidation under the gate)', () async {
      final job = await seedRunnable('d-race', orderId: 'order-race');
      final receiptEntered = Completer<void>();
      final release = Completer<void>();
      final key = PrinterDestinationSendGate.networkKey('10.0.0.5', 9100);
      final receipt = gate.withDestination(key, () async {
        receiptEntered.complete();
        await release.future;
      });
      await receiptEntered.future;
      final run = worker().run();
      // Let the worker claim + prepare + start waiting on the gate.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Server void evidence supersedes the QUEUED job while it waits.
      expect(
        await store.markSupersededFromServerEvidence(
          dispatchId: 'd-race',
          supersededByDispatchId: 'void-9',
          now: now,
        ),
        isTrue,
      );
      release.complete();
      final report = await run;
      expect(report.revalidationSkips, 1);
      expect(report.accepted, 0);
      expect(sends.networkCalls, isEmpty, reason: 'nothing was sent');
      final row = (await store.getByLocalJobId(job.localJobId))!;
      expect(row.status, KitchenSpoolJobStatus.superseded);
      await receipt;
    });
  });

  group('crash windows against the real on-disk spool', () {
    test('death after markPrinting, before transport: the recovery sweep '
        'maps to possiblyPrinted + pending ack; the worker never touches '
        'the stale row', () async {
      final row = await seedRunnable('d-stale');
      expect(
        await store.claimRunnableForQueued(
          row.localJobId,
          organizationId: scope.organizationId,
          restaurantId: scope.restaurantId,
          branchId: scope.branchId,
          deviceId: scope.deviceId,
          now: now,
        ),
        isNotNull,
      );
      expect(await store.markPrinting(row.localJobId, now), isTrue);
      // "Process death": nothing else persisted. A worker run leaves the
      // printing row alone (not runnable).
      final untouched = await worker().run();
      expect(untouched.claimed, 0);
      // Restart recovery.
      final recovered = await store.markPossiblyPrintedOnRecoveryWithAck(
        deviceId: scope.deviceId,
        branchId: scope.branchId,
        now: now,
      );
      expect(recovered, 1);
      final held = (await store.getByLocalJobId(row.localJobId))!;
      expect(held.status, KitchenSpoolJobStatus.possiblyPrinted);
      expect(
        held.pendingServerAckStatus,
        KitchenServerAckStatus.possiblyPrinted,
      );
      // The pending ack flushes; the job never becomes runnable again.
      transport.enqueue({'ok': true});
      final (acked, _, _) = await PendingKitchenAckCoordinator(
        store: store,
        ackRepository: ackRepo,
        now: () => now,
      ).flush(deviceId: scope.deviceId, branchId: scope.branchId);
      expect(acked, 1);
      expect((await worker().run()).claimed, 0);
    });

    test(
      'ack replay after a lost local mark is idempotent (window 12)',
      () async {
        final job = await seedRunnable('d-replay');
        sends.outcomes.add(
          const KitchenTransportOutcome(
            KitchenTransportOutcomeKind.accepted,
            'flushed',
          ),
        );
        // First ack attempt fails AFTER the server recorded it server-side —
        // modeled as transient failure then a replay-accepted response.
        transport.enqueueThrow(
          const SyncTransportException(SyncTransportErrorKind.transient),
        );
        await worker().run();
        transport.enqueue({
          'ok': true,
          'completed': true,
          'idempotency_replay': true,
        });
        final (acked, _, _) = await PendingKitchenAckCoordinator(
          store: store,
          ackRepository: ackRepo,
          now: () => now.add(const Duration(hours: 1)),
        ).flush(deviceId: scope.deviceId, branchId: scope.branchId);
        expect(acked, 1);
        final row = (await store.getByLocalJobId(job.localJobId))!;
        expect(row.status, KitchenSpoolJobStatus.transportAccepted);
        expect(row.pendingServerAckStatus, isNull);
      },
    );
  });

  group('local VOID sweep', () {
    test('unresolved void evidence supersedes runnable priors, links '
        'possiblyPrinted, spares printing/void/cross-order', () async {
      final target = await seedRunnable('d-v1', orderId: 'order-v');
      final other = await seedRunnable(
        'd-other',
        orderId: 'order-KEEP',
        host: '10.0.0.8',
      );
      // The void itself (unresolved, same order).
      await seedRunnable(
        'd-void',
        orderId: 'order-v',
        kind: KitchenSpoolDispatchType.voidNotice,
        host: '10.0.0.9',
      );
      final result = await reconcileLocalVoidEvidence(
        store,
        deviceId: scope.deviceId,
        branchId: scope.branchId,
        now: now,
      );
      expect(result.superseded, 1);
      expect(result.links, 0);
      expect(
        (await store.getByLocalJobId(target.localJobId))!.status,
        KitchenSpoolJobStatus.superseded,
      );
      expect(
        (await store.getByLocalJobId(other.localJobId))!.status,
        KitchenSpoolJobStatus.imported,
        reason: 'cross-order untouched',
      );
      // The VOID job itself stays runnable/printable.
      final voids = await store.listRunnable(
        deviceId: scope.deviceId,
        branchId: scope.branchId,
        now: now.add(const Duration(minutes: 1)),
      );
      expect(voids.map((r) => r.dispatchId), contains('d-void'));
      // Idempotent.
      final again = await reconcileLocalVoidEvidence(
        store,
        deviceId: scope.deviceId,
        branchId: scope.branchId,
        now: now,
      );
      expect(again.superseded, 0);
    });
  });
}
