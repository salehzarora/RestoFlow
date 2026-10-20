import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_containment.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_permission.dart';

const org = '10000000-0000-4000-8000-000000000001';
const restaurant = '20000000-0000-4000-8000-000000000001';
const branch = '30000000-0000-4000-8000-000000000001';
const device = '40000000-0000-4000-8000-000000000001';
const dispatch = '50000000-0000-4000-8000-000000000001';
const request = '60000000-0000-4000-8000-000000000001';
const context = DeviceContext(
  organizationId: org,
  restaurantId: restaurant,
  branchId: branch,
  deviceId: device,
);
final now = DateTime.utc(2026, 10, 15);

class _Transport implements SyncRpcTransport {
  Object? response;
  bool fail = false;
  int calls = 0;
  Future<Object?> Function()? handler;
  @override
  Future<Object?> invoke(String rpc, Map<String, dynamic> args) async {
    expect(rpc, 'pos_kitchen_print_containment');
    expect(args, {
      'p_device_id': device,
      'p_session_token': 'synthetic-session',
    });
    calls++;
    if (fail) throw StateError('synthetic network failure');
    return handler != null ? handler!() : response;
  }
}

class _Row extends Fake implements KitchenSpoolJobRow {
  _Row({this.target = false, this.foreign = false, this.localId});
  final bool target, foreign;
  final String? localId;
  @override
  String get organizationId => foreign ? 'foreign' : org;
  @override
  String get restaurantId => restaurant;
  @override
  String get branchId => branch;
  @override
  String get deviceId => device;
  @override
  String get dispatchId => dispatch;
  @override
  String get localJobId =>
      localId ?? (target ? 'web-initial:$request' : 'ordinary');
}

Map<String, Object?> policy({
  String mode = 'ordinary',
  int revision = 1,
  List<String> held = const [],
  bool? webOrderPrinting,
}) => {
  'ok': true,
  'organization_id': org,
  'restaurant_id': restaurant,
  'branch_id': branch,
  'device_id': device,
  'mode': mode,
  'revision': revision,
  'target_request_id': mode == 'target_only' ? request : null,
  'expires_at': mode == 'target_only'
      ? now.add(const Duration(minutes: 5)).toIso8601String()
      : null,
  'held_dispatch_ids': held,
  if (webOrderPrinting != null) 'web_order_printing_enabled': webOrderPrinting,
};

void main() {
  late _Transport transport;
  late InMemoryDeviceSessionSecretStore secrets;
  late Map<String, String> cache;
  var current = true, offline = false;
  late DateTime clock;
  late KitchenPrintContainmentDomain domain;
  KitchenPrintContainment build() => KitchenPrintContainment(
    context: context,
    secretStore: secrets,
    transport: transport,
    isCurrent: () => current,
    isOffline: () => offline,
    readCache: (key) async => cache[key],
    writeCache: (key, value) async {
      cache[key] = value;
    },
    now: () => clock,
    domain: domain,
  );
  setUp(() async {
    transport = _Transport()..response = policy();
    secrets = InMemoryDeviceSessionSecretStore();
    await secrets.write(
      const DeviceSessionCredential(
        deviceId: device,
        sessionToken: 'synthetic-session',
      ),
    );
    cache = {};
    current = true;
    offline = false;
    clock = now;
    domain = KitchenPrintContainmentDomain();
  });
  test('unknown policy offline blocks startup; no online dependency', () async {
    offline = true;
    expect(await build().allowsOrdinary(), isFalse);
    expect(transport.calls, 0);
  });
  test(
    'platform web authority never enables broad import or old ACKs',
    () async {
      transport.response = policy(mode: 'blocked', webOrderPrinting: true);
      final guard = build();
      expect(await guard.allowsTarget(request), isTrue);
      expect(await guard.allowsTarget('not-a-request-uuid'), isFalse);
      expect(await guard.allowsOrdinary(), isFalse);
      expect(await guard.allowsDispatch(dispatch), isFalse);
      expect(await guard.allowsJob(_Row()), isFalse);
      expect(await guard.allowsJob(_Row(target: true)), isTrue);
      expect(
        await guard.allowsJob(_Row(localId: 'web-initial:malformed')),
        isFalse,
      );
      final exact = KitchenPrintTarget(
        requestId: request,
        orderId: '70000000-0000-4000-8000-000000000001',
        dispatchId: dispatch,
        decisionId: '80000000-0000-4000-8000-000000000001',
        printerAssignmentId: '90000000-0000-4000-8000-000000000001',
      );
      expect(
        await guard.authorizeOperation(
          KitchenPrintOperation.targetImport,
          dispatchId: dispatch,
          target: exact,
        ),
        isNotNull,
      );
      for (final operation in [
        KitchenPrintOperation.ordinaryImport,
        KitchenPrintOperation.ordinaryAck,
        KitchenPrintOperation.targetAck,
      ]) {
        expect(
          await guard.authorizeOperation(operation, dispatchId: dispatch),
          isNull,
        );
      }
    },
  );
  test(
    'web authority is fresh online only; retained cache grants nothing',
    () async {
      transport.response = policy(mode: 'blocked', webOrderPrinting: true);
      final guard = build();
      expect(await guard.allowsTarget(request), isTrue);
      expect(cache, isNotEmpty);
      offline = true;
      expect(await guard.allowsTarget(request), isFalse);
      expect(await guard.allowsJob(_Row(target: true)), isFalse);
      final restarted = build();
      expect(await restarted.allowsTarget(request), isFalse);
      expect(await restarted.allowsJob(_Row(target: true)), isFalse);
      offline = false;
      transport.fail = true;
      expect(await restarted.allowsTarget(request), isFalse);
      expect(await restarted.allowsJob(_Row(target: true)), isFalse);
      transport.fail = false;
      expect(await restarted.allowsJob(_Row(target: true)), isTrue);
    },
  );
  test('missing false or malformed platform grants fail closed', () async {
    final guard = build();
    for (final value in [null, false, 'true', 1]) {
      transport.response = {
        ...policy(mode: 'blocked'),
        if (value != null) 'web_order_printing_enabled': value,
      };
      expect(await guard.allowsTarget(request), isFalse);
      expect(await guard.allowsJob(_Row(target: true)), isFalse);
    }
    transport.response = policy(mode: 'blocked', webOrderPrinting: true);
    expect(await guard.allowsJob(_Row(target: true)), isTrue);
  });
  test(
    'later OFF or failed network read invalidates an issued web operation permit',
    () async {
      transport.response = policy(mode: 'blocked', webOrderPrinting: true);
      final guard = build();
      Future<KitchenPrintAuthorization?> permit() => guard.authorizeOperation(
        KitchenPrintOperation.targetImport,
        dispatchId: dispatch,
        target: KitchenPrintTarget(
          requestId: request,
          orderId: '70000000-0000-4000-8000-000000000001',
          dispatchId: dispatch,
          decisionId: '80000000-0000-4000-8000-000000000001',
          printerAssignmentId: '90000000-0000-4000-8000-000000000001',
        ),
      );
      final authorized = (await permit())!;
      expect(authorized.isCurrent, isTrue);
      transport.response = policy(mode: 'blocked', webOrderPrinting: false);
      expect(await guard.allowsTarget(request), isFalse);
      expect(authorized.isCurrent, isFalse);
      transport.response = policy(mode: 'blocked', webOrderPrinting: true);
      final renewed = (await permit())!;
      expect(renewed.isCurrent, isTrue);
      transport.fail = true;
      expect(await guard.synchronize(), isFalse);
      expect(renewed.isCurrent, isFalse);
      expect(await guard.allowsOrdinary(), isFalse);
    },
  );
  test('platform grant cannot release learned historical holds', () async {
    final guard = build();
    transport.response = policy(
      mode: 'blocked',
      webOrderPrinting: true,
      held: [dispatch],
    );
    expect(
      await guard.permissionForJob(_Row(target: true)),
      KitchenPrintPermission.held,
    );
    transport.response = policy(
      mode: 'blocked',
      webOrderPrinting: true,
      revision: 2,
    );
    expect(await guard.allowsTarget(request), isTrue);
    expect(
      await guard.permissionForJob(_Row(target: true)),
      KitchenPrintPermission.held,
    );
    expect(
      await guard.authorizeOperation(
        KitchenPrintOperation.targetImport,
        dispatchId: dispatch,
      ),
      isNull,
    );
    expect(await guard.allowsJob(_Row()), isFalse);
  });
  test(
    'failed persistence or replaced scope cannot install web authority',
    () async {
      transport.response = policy(mode: 'blocked', webOrderPrinting: true);
      final failing = KitchenPrintContainment(
        context: context,
        secretStore: secrets,
        transport: transport,
        isCurrent: () => current,
        isOffline: () => offline,
        readCache: (_) async => null,
        writeCache: (_, __) async =>
            throw StateError('synthetic persistence failure'),
        domain: domain,
      );
      expect(await failing.allowsTarget(request), isFalse);
      final replaced = build();
      expect(await replaced.allowsTarget(request), isTrue);
      expect(await failing.allowsTarget(request), isFalse);
      current = false;
      expect(await replaced.allowsJob(_Row(target: true)), isFalse);
    },
  );
  test(
    'current authority permits offline spool; cache alone cannot authorize restart',
    () async {
      final currentGuard = build();
      expect(await currentGuard.allowsOrdinary(), isTrue);
      offline = true;
      expect(await currentGuard.allowsOrdinary(), isTrue);
      expect(await currentGuard.allowsJob(_Row()), isTrue);
      final restarted = build();
      expect(await restarted.allowsOrdinary(), isFalse);
      expect(await restarted.allowsJob(_Row()), isFalse);
      expect(transport.calls, 1);
      offline = false;
      expect(await restarted.allowsOrdinary(), isTrue);
      offline = true;
      expect(await restarted.allowsJob(_Row()), isTrue);
    },
  );
  test(
    'target-only survives restart and expiry never releases ordinary',
    () async {
      transport.response = policy(mode: 'target_only');
      expect(await build().allowsOrdinary(), isFalse);
      clock = now.add(const Duration(hours: 1));
      offline = true;
      final restarted = build();
      expect(await restarted.allowsOrdinary(), isFalse);
      expect(await restarted.allowsTarget(request), isFalse);
      expect(await restarted.allowsJob(_Row(target: true)), isFalse);
    },
  );
  test(
    'exact target only and known holds remain when ordinary explicitly resumes',
    () async {
      final guard = build();
      transport.response = policy(mode: 'target_only');
      expect(await guard.allowsTarget(request), isTrue);
      expect(await guard.allowsTarget(branch), isFalse);
      expect(await guard.allowsJob(_Row()), isFalse);
      expect(await guard.allowsJob(_Row(target: true)), isTrue);
      transport.response = policy(
        mode: 'ordinary',
        revision: 2,
        held: [dispatch],
      );
      expect(await guard.allowsOrdinary(), isTrue);
      expect(await guard.allowsJob(_Row()), isFalse);
      transport.response = policy(
        revision: 3,
      ); // malformed future omission cannot release
      expect(await guard.allowsOrdinary(), isTrue);
      expect(await guard.allowsJob(_Row()), isFalse);
      offline = true;
      expect(await build().allowsJob(_Row()), isFalse);
    },
  );
  test('online network failure never grants from cached ordinary', () async {
    final guard = build();
    expect(await guard.allowsOrdinary(), isTrue);
    transport.fail = true;
    expect(await guard.allowsJob(_Row()), isFalse);
    expect(await guard.allowsOrdinary(), isFalse);
  });
  test(
    'cross-scope, missing session and malformed server policy fail closed',
    () async {
      expect(await build().allowsJob(_Row(foreign: true)), isFalse);
      transport.response = {...policy(), 'branch_id': org};
      expect(await build().allowsOrdinary(), isFalse);
      await secrets.clear();
      expect(await build().allowsOrdinary(), isFalse);
    },
  );
  test(
    'revoked generation during awaited response cannot persist or grant',
    () async {
      final reply = Completer<Object?>();
      transport.handler = () => reply.future;
      final result = build().allowsOrdinary();
      await Future<void>.delayed(Duration.zero);
      current = false;
      reply.complete(policy());
      expect(await result, isFalse);
      expect(cache, isEmpty);
    },
  );
  test(
    'a gate read does not reuse an earlier in-flight positive observation',
    () async {
      final reply = Completer<Object?>();
      transport.handler = () => reply.future;
      final guard = build();
      final first = guard.allowsOrdinary();
      await Future<void>.delayed(Duration.zero);
      final gateRead = guard.allowsJob(_Row());
      transport.handler = null;
      transport.response = policy(revision: 2, held: [dispatch]);
      reply.complete(policy());
      expect(await first, isTrue);
      expect(await gateRead, isFalse);
      expect(transport.calls, 2);
    },
  );
  test(
    'session change cannot reuse offline cache from previous credential',
    () async {
      expect(await build().allowsOrdinary(), isTrue);
      await secrets.write(
        const DeviceSessionCredential(
          deviceId: device,
          sessionToken: 'changed-session',
        ),
      );
      offline = true;
      expect(await build().allowsOrdinary(), isFalse);
    },
  );
  test(
    'expired target denied online; lower revision cannot roll policy back',
    () async {
      transport.response = policy(mode: 'target_only', revision: 2);
      final guard = build();
      expect(await guard.allowsTarget(request), isTrue);
      clock = now.add(const Duration(minutes: 6));
      expect(await guard.allowsTarget(request), isFalse);
      transport.response = policy(revision: 1);
      expect(await guard.allowsOrdinary(), isFalse);
    },
  );
}
