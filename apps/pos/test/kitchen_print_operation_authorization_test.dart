@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';
import 'package:restoflow_pos/src/spool/kitchen_contained_ack.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_pos/src/spool/kitchen_dispatch_import_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_containment.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_permission.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_worker.dart';
import 'package:restoflow_pos/src/spool/pending_kitchen_ack_coordinator.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

// R3 client-side boundary regressions. All policy, ACK and printer transports
// are synthetic; the encrypted spool and conditional transitions are real.
const _dispatchId = '50000000-0000-4000-8000-000000000001';
const _otherDispatchId = '50000000-0000-4000-8000-000000000002';
const _requestId = '60000000-0000-4000-8000-000000000001';
const _otherRequestId = '60000000-0000-4000-8000-000000000002';
const _orderId = '70000000-0000-4000-8000-000000000001';
const _otherOrderId = '70000000-0000-4000-8000-000000000002';
const _decisionId = '80000000-0000-4000-8000-000000000001';
const _assignmentId = '90000000-0000-4000-8000-000000000001';
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
  sessionToken: 'synthetic-session',
);
final _at = DateTime.utc(2026, 10, 15);
final _destination = ResolvedKitchenDestination(
  destination: const NetworkKitchenDestination(host: '192.0.2.1', port: 9100),
  fingerprint: kitchenDestinationFingerprint('network|192.0.2.1|9100'),
  displayLabel: 'Synthetic kitchen',
  transportKind: 'network',
  paperWidth: '80mm',
);

KitchenPrintTarget _target({
  String requestId = _requestId,
  String dispatchId = _dispatchId,
  String orderId = _orderId,
  bool Function()? isCurrent,
}) => KitchenPrintTarget(
  requestId: requestId,
  orderId: orderId,
  dispatchId: dispatchId,
  decisionId: _decisionId,
  printerAssignmentId: _assignmentId,
  isCurrent: isCurrent,
);

Map<String, Object?> _policy({
  String mode = 'ordinary',
  int revision = 1,
  List<String> held = const [],
}) => {
  'ok': true,
  'organization_id': 'org',
  'restaurant_id': 'restaurant',
  'branch_id': 'branch',
  'device_id': 'device',
  'mode': mode,
  'revision': revision,
  'held_dispatch_ids': held,
  'target_request_id': mode == 'target_only' ? _requestId : null,
  'expires_at': mode == 'target_only'
      ? _at.add(const Duration(minutes: 5)).toIso8601String()
      : null,
};

PulledKitchenDispatch _dispatch({String id = _dispatchId}) =>
    PulledKitchenDispatch(
      dispatchId: id,
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
    );

class _Transport implements GuardedKitchenAckTransport {
  Object? response = _policy();
  bool failPolicy = false;
  final acknowledgements = <Map<String, dynamic>>[];

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

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'pos_kitchen_print_containment') {
      if (failPolicy) throw StateError('synthetic unavailable policy');
      return response;
    }
    expect(function, 'acknowledge_kitchen_print_dispatch');
    acknowledgements.add(Map.of(params));
    return {'ok': true, 'completed': true};
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

// Only the methods these scenarios exercise are forwarded. Unused port
// methods retain Fake's throwing implementation, exposing accidental paths.
class _HookedStore extends Fake implements KitchenSpoolStore {
  _HookedStore(this.delegate);
  final DriftKitchenSpoolStore delegate;
  Future<void> Function()? afterInsert, afterPending, afterAccepted;

  @override
  Future<KitchenSpoolJobRow> insertImportedJob(NewKitchenSpoolJob job) async {
    final row = await delegate.insertImportedJob(job);
    final hook = afterInsert;
    afterInsert = null;
    await hook?.call();
    return row;
  }

  @override
  Future<KitchenSpoolJobRow?> findByDispatchId(String id) =>
      delegate.findByDispatchId(id);

  @override
  Future<KitchenSpoolJobRow?> getByLocalJobId(String id) =>
      delegate.getByLocalJobId(id);

  @override
  Future<bool> setPendingServerAck(
    String id,
    KitchenServerAckStatus status,
    DateTime at,
  ) async {
    final changed = await delegate.setPendingServerAck(id, status, at);
    final hook = afterPending;
    afterPending = null;
    await hook?.call();
    return changed;
  }

  @override
  Future<bool> markTransportAcceptedWithAck(String id, DateTime at) async {
    final changed = await delegate.markTransportAcceptedWithAck(id, at);
    final hook = afterAccepted;
    afterAccepted = null;
    await hook?.call();
    return changed;
  }

  @override
  Future<bool> markServerAcked(String id, DateTime at) =>
      delegate.markServerAcked(id, at);

  @override
  Future<bool> markServerAckTerminal(
    String id, {
    required String terminalCode,
    required DateTime now,
  }) =>
      delegate.markServerAckTerminal(id, terminalCode: terminalCode, now: now);

  @override
  Future<bool> updateServerAckRetry(
    String id, {
    required String errorCode,
    required DateTime nextAttemptAt,
    required DateTime now,
  }) => delegate.updateServerAckRetry(
    id,
    errorCode: errorCode,
    nextAttemptAt: nextAttemptAt,
    now: now,
  );

  @override
  Future<List<KitchenSpoolJobRow>> listPendingServerAcks({
    required String deviceId,
    required String branchId,
    required DateTime now,
    int limit = 20,
  }) => delegate.listPendingServerAcks(
    deviceId: deviceId,
    branchId: branchId,
    now: now,
    limit: limit,
  );

  @override
  Future<List<KitchenSpoolJobRow>> listRunnable({
    required String deviceId,
    required String branchId,
    required DateTime now,
    int limit = 20,
  }) => delegate.listRunnable(
    deviceId: deviceId,
    branchId: branchId,
    now: now,
    limit: limit,
  );

  @override
  Future<List<KitchenSpoolJobRow>> listUnresolved({
    required String deviceId,
    required String branchId,
  }) => delegate.listUnresolved(deviceId: deviceId, branchId: branchId);

  @override
  Future<KitchenSpoolJobRow?> claimRunnableForQueued(
    String id, {
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required DateTime now,
    Set<String> policyExcludedQueuedJobIds = const {},
  }) => delegate.claimRunnableForQueued(
    id,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    deviceId: deviceId,
    now: now,
    policyExcludedQueuedJobIds: policyExcludedQueuedJobIds,
  );

  @override
  Future<bool> markPrinting(
    String id,
    DateTime now, {
    Set<String> policyExcludedQueuedJobIds = const {},
  }) => delegate.markPrinting(
    id,
    now,
    policyExcludedQueuedJobIds: policyExcludedQueuedJobIds,
  );

  @override
  Future<int> countTotalRows() => delegate.countTotalRows();
}

class _Renderer implements KitchenDispatchBytesRenderer {
  @override
  Future<Uint8List> renderToBytes(
    KitchenDispatchDocument dispatch, {
    String? customerPhoneOverride,
  }) async => Uint8List.fromList([1, 2, 3]);
}

class _Harness {
  late Directory directory;
  late KitchenSpoolDatabase database;
  late DriftKitchenSpoolStore durable;
  late _HookedStore store;
  final cipher = AesGcmKitchenSpoolCipher();
  final key = SecretValue(base64UrlEncode(List<int>.filled(32, 42)));
  final transport = _Transport();
  final secrets = InMemoryDeviceSessionSecretStore();
  final ackSecrets = _HookedSecrets();
  final domain = KitchenPrintContainmentDomain();
  late KitchenPrintContainment guard;
  late SupabaseKitchenDispatchAckRepository repository;
  late KitchenContainedAck ack;
  bool current = true;
  DateTime clock = _at;
  int sequence = 0;
  final printerSends = <String>[];

  Future<void> open() async {
    directory = await Directory.systemTemp.createTemp('rf_r3_operations_');
    database = await KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: () async => directory,
    ).open();
    durable = DriftKitchenSpoolStore(database);
    store = _HookedStore(durable);
    await secrets.write(_credential);
    await ackSecrets.write(_credential);
    final cache = <String, String>{};
    guard = KitchenPrintContainment(
      context: _context,
      secretStore: secrets,
      transport: transport,
      isCurrent: () => current,
      isOffline: () => false,
      readCache: (key) async => cache[key],
      writeCache: (key, value) async {
        cache[key] = value;
      },
      now: () => clock,
      domain: domain,
    );
    repository = SupabaseKitchenDispatchAckRepository(
      transport: transport,
      secretStore: ackSecrets,
    );
    ack = KitchenContainedAck(
      transport: transport,
      secretStore: ackSecrets,
      authorize: guard.authorizeOperation,
    );
  }

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }

  Future<void> block() async {
    transport.response = _policy(mode: 'blocked', revision: 2);
    expect(await guard.synchronize(), isTrue);
  }

  void recover() {
    transport.response = _policy(revision: 3);
  }

  KitchenDispatchImportCoordinator importer({
    PosRoundPrintClaimState? Function(String)? mirror,
    KitchenPrintTarget? target,
  }) => KitchenDispatchImportCoordinator(
    store: store,
    cipher: cipher,
    key: key,
    scope: _scope,
    destination: _destination,
    ackRepository: repository,
    localJobIdGenerator: () => target == null
        ? 'synthetic-job-${++sequence}'
        : 'web-initial:${target.requestId}',
    now: () => clock,
    readInitialPrintClaim: mirror,
    authorizeOperation: guard.authorizeOperation,
    acknowledge: ack.acknowledge,
    target: target,
  );

  PendingKitchenAckCoordinator pending() => PendingKitchenAckCoordinator(
    store: store,
    ackRepository: repository,
    acknowledge: ack.acknowledge,
    now: () => clock,
  );

  KitchenPrintWorker worker() => KitchenPrintWorker(
    store: store,
    cipher: cipher,
    key: key,
    renderer: _Renderer(),
    networkSend: ({required host, required port, required bytes}) async {
      printerSends.add('network');
      return const KitchenTransportOutcome(
        KitchenTransportOutcomeKind.accepted,
        'synthetic',
      );
    },
    bluetoothSend: ({required address, required bytes}) async {
      printerSends.add('bluetooth');
      return const KitchenTransportOutcome(
        KitchenTransportOutcomeKind.accepted,
        'synthetic',
      );
    },
    sendGate: PrinterDestinationSendGate(),
    ackRepository: repository,
    acknowledge: ack.acknowledge,
    scope: _scope,
    permission: guard.permissionForJob,
    now: () => clock,
  );

  Future<KitchenSpoolJobRow> row() async =>
      (await durable.findByDispatchId(_dispatchId))!;
}

void main() {
  late _Harness h;
  setUp(() async {
    h = _Harness();
    await h.open();
  });
  tearDown(() async {
    await h.close();
  });

  test(
    'coherent importer without guarded ACK wiring retains pending evidence',
    () async {
      final importer = KitchenDispatchImportCoordinator(
        store: h.store,
        cipher: h.cipher,
        key: h.key,
        scope: _scope,
        destination: _destination,
        ackRepository: h.repository,
        localJobIdGenerator: () => 'synthetic-job',
        now: () => h.clock,
        authorizeOperation: h.guard.authorizeOperation,
      );
      final result = await importer.importDispatches([_dispatch()]);
      expect(result.acked, 0);
      expect(h.transport.acknowledgements, isEmpty);
      final row = await h.row();
      expect(row.pendingServerAckStatus, KitchenServerAckStatus.imported);
      expect(row.serverAcknowledgedAt, isNull);
    },
  );

  test(
    'malformed dispatch and target identity never reach ACK transport',
    () async {
      expect(
        await h.guard.authorizeOperation(
          KitchenPrintOperation.ordinaryImport,
          dispatchId: 'malformed',
        ),
        isNull,
      );
      expect(
        await h.ack.acknowledge(
          dispatchId: 'malformed',
          status: KitchenImportAckStatus.imported,
        ),
        isNull,
      );
      h.transport.response = _policy(mode: 'target_only');
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
          target: _target(orderId: 'malformed'),
        ),
        isNull,
      );
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'replacement controller during credential await invalidates previous generation',
    () async {
      h.ackSecrets.beforeRead = () async {
        KitchenPrintContainment(
          context: _context,
          secretStore: h.secrets,
          transport: h.transport,
          isCurrent: () => true,
          isOffline: () => false,
          readCache: (_) async => null,
          writeCache: (_, _) async {},
          domain: h.domain,
        );
      };
      expect((await h.importer().importDispatches([_dispatch()])).acked, 0);
      expect(
        (await h.row()).pendingServerAckStatus,
        KitchenServerAckStatus.imported,
      );
      expect((await h.row()).serverAcknowledgedAt, isNull);
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'target runtime invalidation during credential await prevents ACK',
    () async {
      h.transport.response = _policy(mode: 'target_only');
      var current = true;
      final target = _target(isCurrent: () => current);
      h.ackSecrets.beforeRead = () async {
        current = false;
      };
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
          target: target,
        ),
        isNull,
      );
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'an import permit cannot authorize ACK and target outcomes retain separate finish contract',
    () async {
      final importPermit = (await h.guard.authorizeOperation(
        KitchenPrintOperation.ordinaryImport,
        dispatchId: _dispatchId,
      ))!;
      final wrongOperation = KitchenContainedAck(
        transport: h.transport,
        secretStore: h.ackSecrets,
        authorize: (_, {required dispatchId, target}) async => importPermit,
      );
      expect(
        await wrongOperation.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
        ),
        isNull,
      );
      h.transport.response = _policy(mode: 'target_only', revision: 2);
      for (final status in [
        KitchenImportAckStatus.transportAccepted,
        KitchenImportAckStatus.possiblyPrinted,
      ]) {
        expect(
          await h.ack.acknowledge(
            dispatchId: _dispatchId,
            status: status,
            target: _target(),
          ),
          isNull,
        );
      }
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'ordinary observation followed by blocked never grants dispatch authority',
    () async {
      expect(await h.guard.allowsOrdinary(), isTrue);
      await h.block();
      expect(
        await h.guard.authorizeOperation(
          KitchenPrintOperation.ordinaryImport,
          dispatchId: _dispatchId,
        ),
        isNull,
      );
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
        ),
        isNull,
      );
      expect(h.transport.acknowledgements, isEmpty);
      expect(await h.durable.countTotalRows(), 0);
    },
  );

  test(
    'same-revision restriction invalidates an already issued operation',
    () async {
      final permit = (await h.guard.authorizeOperation(
        KitchenPrintOperation.ordinaryAck,
        dispatchId: _dispatchId,
      ))!;
      expect(permit.isCurrent, isTrue);
      h.transport.response = _policy(mode: 'blocked');
      expect(await h.guard.synchronize(), isTrue);
      expect(permit.isCurrent, isFalse);
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
        ),
        isNull,
      );
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'exact holds deny held work but ordinary unheld work remains authorized',
    () async {
      h.transport.response = _policy(held: [_dispatchId]);
      expect(
        await h.guard.authorizeOperation(
          KitchenPrintOperation.ordinaryImport,
          dispatchId: _dispatchId,
        ),
        isNull,
      );
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
        ),
        isNull,
      );
      expect(
        await h.guard.authorizeOperation(
          KitchenPrintOperation.ordinaryImport,
          dispatchId: _otherDispatchId,
        ),
        isNotNull,
      );
      expect(
        await h.ack.acknowledge(
          dispatchId: _otherDispatchId,
          status: KitchenImportAckStatus.imported,
        ),
        isA<KitchenAckAccepted>(),
      );
      expect(
        h.transport.acknowledgements.single['p_dispatch_id'],
        _otherDispatchId,
      );
    },
  );

  for (final sample in <(String, Object?)>[
    ('missing', null),
    ('malformed mode', {..._policy(), 'mode': 'future_mode'}),
    (
      'malformed holds',
      {
        ..._policy(),
        'held_dispatch_ids': ['not-a-uuid'],
      },
    ),
    ('wrong scope', {..._policy(), 'branch_id': 'other-branch'}),
    ('missing scope', {..._policy()}..remove('restaurant_id')),
  ]) {
    test(
      '${sample.$1} after ordinary cannot reuse earlier authority for ACK',
      () async {
        final previous = (await h.guard.authorizeOperation(
          KitchenPrintOperation.ordinaryAck,
          dispatchId: _dispatchId,
        ))!;
        h.transport.response = sample.$2;
        expect(
          await h.ack.acknowledge(
            dispatchId: _dispatchId,
            status: KitchenImportAckStatus.imported,
          ),
          isNull,
        );
        expect(previous.isCurrent, isFalse);
        expect(h.transport.acknowledgements, isEmpty);
      },
    );
  }

  test(
    'transient policy failure cannot reuse earlier authority for ACK',
    () async {
      final previous = (await h.guard.authorizeOperation(
        KitchenPrintOperation.ordinaryAck,
        dispatchId: _dispatchId,
      ))!;
      h.transport.failPolicy = true;
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
        ),
        isNull,
      );
      expect(previous.isCurrent, isFalse);
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'target-only binds both request and dispatch without ordinary authority',
    () async {
      h.transport.response = _policy(mode: 'target_only');
      expect(
        await h.guard.authorizeOperation(
          KitchenPrintOperation.ordinaryImport,
          dispatchId: _dispatchId,
        ),
        isNull,
      );
      expect(
        await h.guard.authorizeOperation(
          KitchenPrintOperation.targetImport,
          dispatchId: _dispatchId,
          target: _target(requestId: _otherRequestId),
        ),
        isNull,
      );
      expect(
        await h.guard.authorizeOperation(
          KitchenPrintOperation.targetImport,
          dispatchId: _otherDispatchId,
          target: _target(),
        ),
        isNull,
      );
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
          target: _target(requestId: _otherRequestId),
        ),
        isNull,
      );
      final permit = await h.guard.authorizeOperation(
        KitchenPrintOperation.targetImport,
        dispatchId: _dispatchId,
        target: _target(),
      );
      expect(permit, isNotNull);
      expect(permit!.operation, KitchenPrintOperation.targetImport);
      expect(permit.dispatchId, _dispatchId);
      expect(permit.matchesCredential('device', 'synthetic-session'), isTrue);
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'target expiry during ACK credential await prevents invocation',
    () async {
      h.transport.response = _policy(mode: 'target_only');
      h.ackSecrets.beforeRead = () async {
        h.clock = _at.add(const Duration(hours: 1));
      };
      expect(
        await h.ack.acknowledge(
          dispatchId: _dispatchId,
          status: KitchenImportAckStatus.imported,
          target: _target(),
        ),
        isNull,
      );
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'valid exact target imports and ACKs the same validated dispatch',
    () async {
      h.transport.response = _policy(mode: 'target_only');
      final summary = await h.importer(target: _target()).importDispatches([
        _dispatch(),
      ]);
      expect(summary.imported, 1);
      expect(summary.acked, 1);
      final row = await h.row();
      expect(row.localJobId, 'web-initial:$_requestId');
      expect(row.serverAcknowledgedAt, isNotNull);
      expect(h.transport.acknowledgements.single['p_dispatch_id'], _dispatchId);
      expect(h.printerSends, isEmpty);
    },
  );

  test(
    'target import refuses a pulled order different from validated target',
    () async {
      h.transport.response = _policy(mode: 'target_only');
      final summary = await h
          .importer(target: _target(orderId: _otherOrderId))
          .importDispatches([_dispatch()]);
      expect(summary.imported, 0);
      expect(summary.acked, 0);
      expect(await h.durable.countTotalRows(), 0);
      expect(h.transport.acknowledgements, isEmpty);
    },
  );

  test(
    'restriction learned after durable insert preserves row for re-import',
    () async {
      h.store.afterInsert = h.block;
      final denied = await h.importer().importDispatches([_dispatch()]);
      expect(denied.acked, 0);
      final preserved = await h.row();
      expect(preserved.serverAcknowledgedAt, isNull);
      expect(preserved.encryptedPayloadBlob, isNotEmpty);
      expect(h.transport.acknowledgements, isEmpty);
      expect(
        await h.durable.listRunnable(
          deviceId: 'device',
          branchId: 'branch',
          now: _at,
        ),
        isEmpty,
      );
      h.recover();
      final recovered = await h.importer().importDispatches([_dispatch()]);
      expect(recovered.imported, 0);
      expect(recovered.duplicates, 1);
      expect(recovered.acked, 1);
      final after = await h.row();
      expect(after.localJobId, preserved.localJobId);
      expect(after.encryptedPayloadBlob, preserved.encryptedPayloadBlob);
      expect(await h.durable.countTotalRows(), 1);
      expect(h.printerSends, isEmpty);
    },
  );

  test(
    'restriction after pending write retains ACK through repeated concurrent denial and recovery',
    () async {
      h.store.afterPending = h.block;
      expect((await h.importer().importDispatches([_dispatch()])).acked, 0);
      final preserved = await h.row();
      expect(preserved.pendingServerAckStatus, KitchenServerAckStatus.imported);
      expect(preserved.serverAcknowledgedAt, isNull);
      final pending = h.pending();
      expect(
        await Future.wait([
          pending.flush(deviceId: 'device', branchId: 'branch'),
          h.pending().flush(deviceId: 'device', branchId: 'branch'),
          h.importer().importDispatches([_dispatch()]).then((_) => (0, 0, 0)),
        ]),
        everyElement((0, 0, 0)),
      );
      expect(h.transport.acknowledgements, isEmpty);
      final denied = await h.row();
      expect(denied.pendingServerAckStatus, preserved.pendingServerAckStatus);
      expect(denied.serverAckAttemptCount, preserved.serverAckAttemptCount);
      expect(denied.encryptedPayloadBlob, preserved.encryptedPayloadBlob);
      h.recover();
      expect(await pending.flush(deviceId: 'device', branchId: 'branch'), (
        1,
        0,
        0,
      ));
      expect(await pending.flush(deviceId: 'device', branchId: 'branch'), (
        0,
        0,
        0,
      ));
      expect((await h.importer().importDispatches([_dispatch()])).acked, 0);
      expect(h.transport.acknowledgements, hasLength(1));
      expect((await h.row()).pendingServerAckStatus, isNull);
      expect(
        (await h.row()).encryptedPayloadBlob,
        preserved.encryptedPayloadBlob,
      );
      expect(await h.durable.countTotalRows(), 1);
      expect(h.printerSends, isEmpty);
    },
  );

  for (final change in ['restriction', 'scope', 'session']) {
    test(
      '$change learned during repository credential await preserves pending ACK',
      () async {
        h.ackSecrets.beforeRead = () async {
          switch (change) {
            case 'restriction':
              await h.block();
            case 'scope':
              h.current = false;
            case 'session':
              const rotated = DeviceSessionCredential(
                deviceId: 'device',
                sessionToken: 'rotated-synthetic-session',
              );
              await h.secrets.write(rotated);
              await h.ackSecrets.write(rotated);
          }
        };
        final denied = await h.importer().importDispatches([_dispatch()]);
        expect(denied.acked, 0);
        final row = await h.row();
        expect(row.pendingServerAckStatus, KitchenServerAckStatus.imported);
        expect(row.serverAcknowledgedAt, isNull);
        expect(
          row.serverAckAttemptCount,
          0,
          reason: 'a deferred invocation is not a transport failure',
        );
        expect(h.transport.acknowledgements, isEmpty);
        expect(h.printerSends, isEmpty);
      },
    );
  }

  for (final claim in [
    PosRoundPrintClaimState.sent,
    PosRoundPrintClaimState.claimed,
  ]) {
    test(
      'authentic ${claim.name} mirror survives denied repository await then reconciles',
      () async {
        final localEvidence = claim;
        h.ackSecrets.beforeRead = h.block;
        final importer = h.importer(mirror: (_) => localEvidence);
        expect((await importer.importDispatches([_dispatch()])).acked, 0);
        expect(localEvidence, claim);
        expect(await h.durable.countTotalRows(), 0);
        expect(h.transport.acknowledgements, isEmpty);
        h.recover();
        expect((await importer.importDispatches([_dispatch()])).acked, 1);
        expect(localEvidence, claim);
        expect(await h.durable.countTotalRows(), 0);
        expect(
          h.transport.acknowledgements.single['p_client_status'],
          claim == PosRoundPrintClaimState.sent
              ? 'transport_accepted'
              : 'possibly_printed',
        );
        expect(h.printerSends, isEmpty);
      },
    );
  }

  test(
    'genuine send evidence recorded before restriction reconciles by ACK without retransmission',
    () async {
      expect((await h.importer().importDispatches([_dispatch()])).acked, 1);
      h.transport.acknowledgements.clear();
      h.store.afterAccepted = h.block;
      final sent = await h.worker().run();
      expect(sent.accepted, 1);
      expect(h.printerSends, ['network']);
      final evidence = await h.row();
      expect(evidence.status, KitchenSpoolJobStatus.transportAccepted);
      expect(
        evidence.pendingServerAckStatus,
        KitchenServerAckStatus.transportAccepted,
      );
      expect(h.transport.acknowledgements, isEmpty);
      expect(await h.pending().flush(deviceId: 'device', branchId: 'branch'), (
        0,
        0,
        0,
      ));
      h.recover();
      expect(await h.pending().flush(deviceId: 'device', branchId: 'branch'), (
        1,
        0,
        0,
      ));
      await h.worker().run();
      await h.worker().run();
      expect(h.printerSends, ['network']);
      expect(
        h.transport.acknowledgements.single['p_client_status'],
        'transport_accepted',
      );
      final recovered = await h.row();
      expect(recovered.status, KitchenSpoolJobStatus.transportAccepted);
      expect(recovered.pendingServerAckStatus, isNull);
      expect(recovered.encryptedPayloadBlob, evidence.encryptedPayloadBlob);
    },
  );
}
