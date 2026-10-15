@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/testing.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/online_order_print_repository.dart';
import 'package:restoflow_pos/src/spool/kitchen_contained_ack.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_worker.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_permission.dart';
import 'package:restoflow_pos/src/spool/online_order_print_hooks.dart';
import 'package:restoflow_pos/src/spool/pending_kitchen_ack_coordinator.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_runtime.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

const _context = DeviceContext(
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: 'device',
);
const _assignment = 'a0000000-0000-4000-8000-000000000001';
final _destination = ResolvedKitchenDestination(
  destination: const NetworkKitchenDestination(host: '10.0.0.5', port: 9100),
  fingerprint: kitchenDestinationFingerprint('network|10.0.0.5|9100'),
  displayLabel: 'Kitchen',
  transportKind: 'network',
  paperWidth: '80mm',
);
const _scope = KitchenImportScope(
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: 'device',
);

PulledKitchenDispatch _dispatch(String id) => PulledKitchenDispatch(
  dispatchId: id,
  dispatchType: 'initial_order',
  orderId: 'order-$id',
  payloadVersion: 1,
  createdAt: '2026-10-15T00:00:00Z',
  moneyFreePayload: const {
    'v': 1,
    'kind': 'initial_order',
    'order_code': '#000042',
    'order_type': 'takeaway',
    'items': [
      {'qty': 1, 'name': 'Synthetic burger', 'modifiers': <Object?>[]},
    ],
  },
);

class _Transport implements GuardedKitchenAckTransport {
  @override
  Future<Object?> invokeGuardedKitchenAck(
    Map<String, dynamic> params, {
    required bool Function() isCurrent,
  }) {
    if (!isCurrent()) {
      return Future.error(const KitchenAckDispatchDeferred());
    }
    return invoke('acknowledge_kitchen_print_dispatch', params);
  }

  final calls = <String>[];
  Future<Object?> Function(String)? handler;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    if (handler != null) return handler!(function);
    if (function == 'pull_kitchen_print_dispatches') {
      return {'ok': true, 'dispatches': <Object?>[], 'has_more': false};
    }
    return {'ok': true};
  }
}

class _TargetRepository implements OnlineOrderPrintRepository {
  _TargetRepository(this.events);
  final List<String> events;
  var claims = 0, begins = 0, finishes = 0;
  var state = OnlineOrderPrintState.claimed;
  String? attempt;
  Future<void> Function()? beforeClaim;
  Future<void> Function()? afterBegin;

  OnlineOrderPrintResult _result({bool grant = false}) =>
      OnlineOrderPrintResult(
        requestId: 'request',
        orderId: 'order-target',
        dispatchId: 'target',
        decisionId: 'decision',
        printerAssignmentId: _assignment,
        state: state,
        attemptId: attempt,
        sendAuthorized: grant,
        dispatch: state == OnlineOrderPrintState.claimed
            ? _dispatch('target')
            : null,
      );

  @override
  Future<OnlineOrderPrintResult> claim(String requestId) async {
    events.add('claim');
    claims++;
    await beforeClaim?.call();
    return _result();
  }

  @override
  Future<OnlineOrderPrintResult> begin(
    String requestId,
    String attemptId,
  ) async {
    events.add('begin');
    begins++;
    if (attempt != null) return _result();
    attempt = attemptId;
    state = OnlineOrderPrintState.sendReserved;
    await afterBegin?.call();
    return _result(grant: true);
  }

  @override
  Future<OnlineOrderPrintResult> finish(
    String requestId,
    String attemptId,
    String clientStatus, {
    String? errorCode,
  }) async {
    events.add('finish');
    finishes++;
    state = clientStatus == 'transport_accepted'
        ? OnlineOrderPrintState.transportAccepted
        : OnlineOrderPrintState.reconciliationRequired;
    return _result();
  }

  @override
  Future<OnlineOrderPrintResult> status(String requestId) async => _result();
}

NewKitchenSpoolJob _legacy(
  String id, {
  KitchenSpoolDispatchType type = KitchenSpoolDispatchType.initialOrder,
}) => NewKitchenSpoolJob(
  localJobId: 'legacy-$id',
  dispatchId: 'legacy-dispatch-$id',
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: 'device',
  orderId: 'legacy-order-$id',
  serviceRoundId: null,
  dispatchType: type,
  initialStatus: KitchenSpoolJobStatus.imported,
  encryptedPayloadBlob: Uint8List.fromList([1, 2, 3]),
  encryptionVersion: 1,
  destinationFingerprint: _destination.fingerprint,
  destinationDisplayLabel: 'Kitchen',
  transportKind: 'network',
  paperWidth: '80mm',
  payloadVersion: 1,
  documentVersion: 1,
  rasterVersion: 1,
  serverClaimExpiresAt: null,
  createdAt: DateTime.utc(2026, 10, 1),
);

void main() {
  late Directory temp;
  late InMemorySecureKeyStore keys;
  late InMemoryDeviceSessionSecretStore credentials;
  late _Transport transport;
  late _TargetRepository target;
  late List<String> events;
  late DeviceContext? context;
  var sends = 0;
  var ordinaryAllowed = false;
  var targetAllowed = true;
  final held = <String>{};
  final now = DateTime.utc(2026, 10, 15, 1);

  KitchenSpoolDatabaseFactory factory() =>
      KitchenSpoolDatabaseFactory(documentsDirectoryProvider: () async => temp);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rf_containment_runtime_');
    keys = InMemorySecureKeyStore();
    credentials = InMemoryDeviceSessionSecretStore();
    await credentials.write(
      const DeviceSessionCredential(deviceId: 'device', sessionToken: 'token'),
    );
    transport = _Transport();
    events = [];
    target = _TargetRepository(events);
    context = _context;
    sends = 0;
    ordinaryAllowed = false;
    targetAllowed = true;
    held.clear();
  });
  tearDown(() => temp.delete(recursive: true));

  PosKitchenSpoolRuntime runtime({
    KitchenSpoolDatabaseFactory Function()? buildFactory,
    Future<bool> Function()? ordinary,
    Future<bool> Function(String)? targetGuard,
    Future<KitchenModeResult> Function()? mode,
    Future<void> Function()? initialized,
    bool Function()? session,
    Future<KitchenPrintPermission> Function(KitchenSpoolJobRow)? permission,
    KitchenPrintAuthorizer? authorizeOperation,
    KitchenAckInvoke? acknowledge,
  }) => PosKitchenSpoolRuntime(
    platform: const PosKitchenSpoolPlatform(isWeb: false),
    deviceContext: () => context,
    secretStore: credentials,
    modeRepository: SupabaseDeviceKitchenModeRepository(
      transport: transport,
      secretStore: credentials,
    ),
    ackRepository: SupabaseKitchenDispatchAckRepository(
      transport: transport,
      secretStore: credentials,
    ),
    pullRepository: SupabaseKitchenDispatchPullRepository(
      transport: transport,
      secretStore: credentials,
    ),
    databaseFactoryBuilder: buildFactory ?? factory,
    fetchMode:
        mode ??
        () async =>
            KitchenModePrinterOnlyWithRevision(revision: 24, verifiedAt: now),
    destinationResolver: () async => _destination,
    localJobIdGenerator: () => 'synthetic-attempt',
    renderer: const KitchenTicketRenderer(),
    networkSend: ({required host, required port, required bytes}) async {
      events.add('send');
      sends++;
      return const KitchenTransportOutcome(
        KitchenTransportOutcomeKind.accepted,
        'fake_accepted',
      );
    },
    bluetoothSend: ({required address, required bytes}) async {
      fail('no Bluetooth bytes authorized in this synthetic network fixture');
    },
    sendGate: PrinterDestinationSendGate(),
    keyStore: keys,
    now: () => now,
    webOrderPrintRepository: target,
    webOrderDestinationResolver: (assignment) async {
      expect(assignment, _assignment);
      return _destination;
    },
    canPrintWebOrder: session ?? () => true,
    ordinaryRunAllowed: ordinary ?? () async => ordinaryAllowed,
    targetRunAllowed: targetGuard ?? (_) async => targetAllowed,
    jobPermission:
        permission ??
        (job) async {
          if (held.contains(job.dispatchId)) {
            return KitchenPrintPermission.held;
          }
          final allowed = isTargetedWebPrintJob(job)
              ? targetAllowed && job.localJobId == 'web-initial:request'
              : ordinaryAllowed;
          return allowed
              ? KitchenPrintPermission.permitted
              : KitchenPrintPermission.blocked;
        },
    dispatchAllowed: (dispatchId) async => !held.contains(dispatchId),
    authorizeOperation: authorizeOperation,
    acknowledge: acknowledge,
    onTargetSpoolInitialized: initialized ?? () async => events.add('ready'),
  );

  Future<List<KitchenSpoolJobRow>> seedLegacy({bool resolved = false}) async {
    final db = await factory().open();
    try {
      final store = DriftKitchenSpoolStore(db);
      for (final type in KitchenSpoolDispatchType.values) {
        final row = await store.insertImportedJob(
          _legacy(type.wireName, type: type),
        );
        await store.markServerAcked(row.localJobId, now);
        // Synthetic pre-existing crash/restart fixture. No live database or
        // transport is involved; runtime containment must preserve it exactly.
        if (resolved) {
          await store.claimRunnableForQueued(
            row.localJobId,
            organizationId: 'org',
            restaurantId: 'restaurant',
            branchId: 'branch',
            deviceId: 'device',
            now: now,
          );
          await store.markPrinting(row.localJobId, now);
          await store.markTransportAcceptedWithAck(row.localJobId, now);
          await store.markServerAcked(row.localJobId, now);
        } else {
          await db.customStatement(
            'UPDATE kitchen_spool_jobs SET status = ? WHERE local_job_id = ?',
            ['queued', row.localJobId],
          );
        }
      }
      return [
        for (final type in KitchenSpoolDispatchType.values)
          (await store.getByLocalJobId('legacy-${type.wireName}'))!,
      ];
    } finally {
      await db.close();
    }
  }

  test(
    'target init with queued history sends only exact target; readiness precedes claim',
    () async {
      await KitchenSpoolKeyManager(keys).provisionKey();
      final historical = await seedLegacy();
      held.addAll(historical.map((job) => job.dispatchId));
      late PosKitchenSpoolRuntime rt;
      rt = runtime(
        initialized: () async {
          events.add('ready');
          expect(rt.targetSpoolInitialization.ready, isTrue);
          expect(rt.targetSpoolInitialization.totalRows, historical.length);
          expect(await rt.onStartup(), isA<KitchenSpoolRunSkipped>());
        },
      );
      addTearDown(rt.dispose);
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.sent,
      );
      expect(events, ['ready', 'claim', 'begin', 'send', 'finish']);
      expect(sends, 1);
      expect(transport.calls, ['acknowledge_kitchen_print_dispatch']);
      expect(await rt.onResume(), isA<KitchenSpoolRunBlocked>());
      await rt.dispose();
      final db = await factory().open();
      try {
        final store = DriftKitchenSpoolStore(db);
        for (final old in historical) {
          expect(await store.getByLocalJobId(old.localJobId), old);
        }
      } finally {
        await db.close();
      }
      expect(sends, 1);
    },
  );

  for (final permission in [
    KitchenPrintPermission.unknown,
    KitchenPrintPermission.blocked,
  ]) {
    test(
      'target initialization preserves $permission queued owners without transmitting',
      () async {
        await KitchenSpoolKeyManager(keys).provisionKey();
        final historical = await seedLegacy();
        final rt = runtime(
          permission: (job) async => isTargetedWebPrintJob(job)
              ? KitchenPrintPermission.permitted
              : permission,
        );
        addTearDown(rt.dispose);
        expect(
          await rt.onAcceptedWebOrder('request', 'order-target'),
          WebOrderPrintOutcome.reconciliationRequired,
        );
        expect(rt.targetSpoolInitialization.ready, isTrue);
        expect(target.claims, 1);
        expect(target.begins, 0);
        expect(sends, 0);
        await rt.dispose();
        final db = await factory().open();
        try {
          final store = DriftKitchenSpoolStore(db);
          for (final old in historical) {
            expect(await store.getByLocalJobId(old.localJobId), old);
          }
          final targetJob = await store.getByLocalJobId('web-initial:request');
          expect(targetJob!.status, KitchenSpoolJobStatus.imported);
        } finally {
          await db.close();
        }
      },
    );
  }

  test(
    'fresh absent spool provisions only proven empty DB before claim',
    () async {
      final rt = runtime();
      addTearDown(rt.dispose);
      target.beforeClaim = () async {
        expect(
          rt.targetSpoolInitialization.countState,
          KitchenSpoolCountState.counted,
        );
        expect(rt.targetSpoolInitialization.totalRows, 0);
        expect(await KitchenSpoolKeyManager(keys).readKey(), isNotNull);
      };
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.sent,
      );
      expect(events.first, 'ready');
      expect(sends, 1);
    },
  );

  for (final resolved in [false, true]) {
    test(
      'missing key with ${resolved ? "zero unresolved but nonempty" : "queued"} DB is blocked without claim',
      () async {
        final old = await seedLegacy(resolved: resolved);
        final rt = runtime();
        addTearDown(rt.dispose);
        expect(
          await rt.onAcceptedWebOrder('request', 'order-target'),
          WebOrderPrintOutcome.blocked,
        );
        expect(rt.targetSpoolInitialization.totalRows, old.length);
        expect(
          rt.targetSpoolInitialization.countState,
          KitchenSpoolCountState.counted,
        );
        expect(
          rt.targetSpoolInitialization.blockerCode,
          'kitchen_spool_key_missing_with_rows',
        );
        expect(await keys.read(KitchenSpoolKeyManager.keyRef), isNull);
        expect(target.claims, 0);
        expect(events, isEmpty);
        expect(transport.calls, isEmpty);
      },
    );
  }

  test('corrupt key is retained and blocks claim even for empty DB', () async {
    await KitchenSpoolKeyManager(keys).provisionKey();
    keys.markCorrupted(KitchenSpoolKeyManager.keyRef);
    final rt = runtime();
    addTearDown(rt.dispose);
    expect(
      await rt.onAcceptedWebOrder('request', 'order-target'),
      WebOrderPrintOutcome.blocked,
    );
    expect(
      rt.targetSpoolInitialization.blockerCode,
      'kitchen_spool_key_corrupted',
    );
    expect(
      await KitchenSpoolKeyManager(keys).inspectState(),
      KitchenSpoolKeyState.corrupted,
    );
    expect(target.claims, 0);
  });

  test(
    'unavailable secure storage never provisions or files readiness',
    () async {
      keys.setAvailable(available: false);
      final rt = runtime();
      addTearDown(rt.dispose);
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.blocked,
      );
      expect(
        rt.targetSpoolInitialization.blockerCode,
        'secure_storage_unavailable',
      );
      expect(target.claims, 0);
      expect(events, isEmpty);
    },
  );

  test(
    'unknown presence preserves unknown count and performs no create/claim',
    () async {
      final rt = runtime(
        buildFactory: () => KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async =>
              throw StateError('unreadable'),
        ),
      );
      addTearDown(rt.dispose);
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.blocked,
      );
      expect(
        rt.targetSpoolInitialization.countState,
        KitchenSpoolCountState.unknown,
      );
      expect(rt.targetSpoolInitialization.totalRows, isNull);
      expect(
        rt.targetSpoolInitialization.blockerCode,
        'spool_presence_unknown',
      );
      expect(target.claims, 0);
      expect(await factory().spoolFileExists(), isFalse);
    },
  );

  test(
    'corrupt DB remains byte identical, unknown count, no key or claim',
    () async {
      final file = File(KitchenSpoolDatabaseFactory.databasePathUnder(temp));
      await file.parent.create(recursive: true);
      final bytes = List<int>.generate(90, (i) => i);
      await file.writeAsBytes(bytes);
      final rt = runtime();
      addTearDown(rt.dispose);
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.blocked,
      );
      expect(
        rt.targetSpoolInitialization.countState,
        KitchenSpoolCountState.unknown,
      );
      expect(rt.targetSpoolInitialization.totalRows, isNull);
      expect(
        rt.targetSpoolInitialization.blockerCode,
        'spool_database_unavailable',
      );
      expect(await file.readAsBytes(), bytes);
      expect(await keys.read(KitchenSpoolKeyManager.keyRef), isNull);
      expect(target.claims, 0);
    },
  );

  test(
    'startup resume restart and expired/unknown containment never drain old queue',
    () async {
      await KitchenSpoolKeyManager(keys).provisionKey();
      await seedLegacy();
      for (var restart = 0; restart < 2; restart++) {
        final rt = runtime();
        expect(await rt.onStartup(), isA<KitchenSpoolRunBlocked>());
        targetAllowed =
            false; // expired target-only remains closed for ordinary
        expect(await rt.onResume(), isA<KitchenSpoolRunBlocked>());
        await rt.dispose();
      }
      final unknown = runtime(
        ordinary: () async => throw StateError('unknown'),
      );
      addTearDown(unknown.dispose);
      expect(await unknown.onStartup(), isA<KitchenSpoolRunBlocked>());
      expect(transport.calls, isEmpty);
      expect(sends, 0);
    },
  );

  test(
    'scope change during mode await blocks target before DB/claim',
    () async {
      final entered = Completer<void>();
      final released = Completer<KitchenModeResult>();
      final rt = runtime(
        mode: () {
          entered.complete();
          return released.future;
        },
      );
      addTearDown(rt.dispose);
      final operation = rt.onAcceptedWebOrder('request', 'order-target');
      await entered.future;
      context = const DeviceContext(
        organizationId: 'org',
        restaurantId: 'restaurant',
        branchId: 'other',
        deviceId: 'device',
      );
      released.complete(
        KitchenModePrinterOnlyWithRevision(revision: 24, verifiedAt: now),
      );
      expect(await operation, WebOrderPrintOutcome.unavailable);
      expect(target.claims, 0);
      expect(await factory().spoolFileExists(), isFalse);
    },
  );

  test(
    'expiry during genuine readiness cannot claim or unlock ordinary sending',
    () async {
      final rt = runtime(
        initialized: () async {
          events.add('ready');
          targetAllowed = false;
        },
      );
      addTearDown(rt.dispose);
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.blocked,
      );
      expect(rt.targetSpoolInitialization.ready, isTrue);
      expect(target.claims, 0);
      expect(await rt.onResume(), isA<KitchenSpoolRunBlocked>());
      expect(sends, 0);
    },
  );

  test(
    'ordinary permission changed during pull discards delayed response without import or ACK',
    () async {
      ordinaryAllowed = true;
      final entered = Completer<void>();
      final released = Completer<Object?>();
      transport.handler = (function) async {
        expect(function, 'pull_kitchen_print_dispatches');
        entered.complete();
        return released.future;
      };
      final rt = runtime();
      addTearDown(rt.dispose);
      final operation = rt.onStartup();
      await entered.future;
      ordinaryAllowed = false;
      released.complete({
        'ok': true,
        'dispatches': [
          {
            'id': 'delayed',
            'dispatch_type': 'initial_order',
            'order_id': 'old-order',
            'payload_version': 1,
            'payload': _dispatch('delayed').moneyFreePayload,
            'created_at': '2026-10-15T00:00:00Z',
          },
        ],
        'has_more': false,
      });
      expect(await operation, isA<KitchenSpoolRunBlocked>());
      await rt.dispose();
      final db = await factory().open();
      try {
        expect(await DriftKitchenSpoolStore(db).countTotalRows(), 0);
      } finally {
        await db.close();
      }
      expect(transport.calls, ['pull_kitchen_print_dispatches']);
      expect(sends, 0);
    },
  );

  test(
    'import rechecks containment after async phone resolution before durable write',
    () async {
      await KitchenSpoolKeyManager(keys).provisionKey();
      final key = (await KitchenSpoolKeyManager(keys).readKey())!;
      final db = await factory().open();
      addTearDown(db.close);
      final entered = Completer<void>();
      final released = Completer<String?>();
      ordinaryAllowed = true;
      final operation = KitchenDispatchImportCoordinator(
        store: DriftKitchenSpoolStore(db),
        cipher: AesGcmKitchenSpoolCipher(),
        key: key,
        scope: _scope,
        destination: _destination,
        ackRepository: SupabaseKitchenDispatchAckRepository(
          transport: transport,
          secretStore: credentials,
        ),
        localJobIdGenerator: () => 'delayed',
        canContinue: () async => ordinaryAllowed,
        resolveCustomerPhone: (_) {
          entered.complete();
          return released.future;
        },
      ).importDispatches([_dispatch('delayed')]);
      await entered.future;
      ordinaryAllowed = false;
      released.complete(null);
      final result = await operation;
      expect(result.imported, 0);
      expect(await DriftKitchenSpoolStore(db).countTotalRows(), 0);
      expect(transport.calls, isEmpty);
    },
  );

  test(
    'hold activated during pull preserves unheld import and refuses held ACK',
    () async {
      ordinaryAllowed = true;
      final entered = Completer<void>();
      final released = Completer<Object?>();
      transport.handler = (function) async {
        if (function == 'pull_kitchen_print_dispatches') {
          entered.complete();
          return released.future;
        }
        return {'ok': true};
      };
      final rt = runtime();
      addTearDown(rt.dispose);
      final operation = rt.onStartup();
      await entered.future;
      held.add('held');
      released.complete({
        'ok': true,
        'dispatches': [
          for (final id in ['held', 'unheld'])
            {
              'id': id,
              'dispatch_type': 'initial_order',
              'order_id': 'order-$id',
              'payload_version': 1,
              'payload': _dispatch(id).moneyFreePayload,
              'created_at': '2026-10-15T00:00:00Z',
            },
        ],
        'has_more': false,
      });
      expect(await operation, isA<KitchenSpoolRunWorked>());
      await rt.dispose();
      final db = await factory().open();
      try {
        final store = DriftKitchenSpoolStore(db);
        expect(await store.findByDispatchId('held'), isNull);
        expect(await store.findByDispatchId('unheld'), isNotNull);
      } finally {
        await db.close();
      }
      expect(
        transport.calls.where((c) => c == 'acknowledge_kitchen_print_dispatch'),
        hasLength(2),
      );
      expect(sends, 1);
    },
  );

  test(
    'pending ACK containment preserves held evidence without starving later unheld ACK',
    () async {
      final db = await factory().open();
      addTearDown(db.close);
      final store = DriftKitchenSpoolStore(db);
      final before = <KitchenSpoolJobRow>[];
      for (var i = 0; i < 21; i++) {
        final row = await store.insertImportedJob(_legacy('held-$i'));
        await store.setPendingServerAck(
          row.localJobId,
          KitchenServerAckStatus.imported,
          now,
        );
        held.add(row.dispatchId);
        before.add((await store.getByLocalJobId(row.localJobId))!);
      }
      final allowed = await store.insertImportedJob(_legacy('z-unheld'));
      await store.setPendingServerAck(
        allowed.localJobId,
        KitchenServerAckStatus.imported,
        now,
      );
      final result = await PendingKitchenAckCoordinator(
        store: store,
        ackRepository: SupabaseKitchenDispatchAckRepository(
          transport: transport,
          secretStore: credentials,
        ),
        now: () => now,
        mayFlush: (job) async => !held.contains(job.dispatchId),
      ).flush(deviceId: 'device', branchId: 'branch');
      expect(result, (1, 0, 0));
      expect(transport.calls, ['acknowledge_kitchen_print_dispatch']);
      for (final row in before) {
        expect(await store.getByLocalJobId(row.localJobId), row);
      }
      expect(
        (await store.getByLocalJobId(allowed.localJobId))!.serverAcknowledgedAt,
        now,
      );
    },
  );

  test(
    'containment activated during irreversible begin consumes fence without sending or later retry',
    () async {
      target.afterBegin = () async => targetAllowed = false;
      final rt = runtime();
      addTearDown(rt.dispose);
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.reconciliationRequired,
      );
      expect(target.begins, 1);
      expect(sends, 0);
      targetAllowed = true;
      expect(
        await rt.onAcceptedWebOrder('request', 'order-target'),
        WebOrderPrintOutcome.reconciliationRequired,
      );
      expect(target.begins, 1);
      expect(sends, 0);
    },
  );
}
