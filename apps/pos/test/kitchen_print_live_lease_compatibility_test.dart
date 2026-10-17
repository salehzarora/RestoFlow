import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_containment.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_permission.dart';

// Exercise the unchanged v63 client against the persistent rollout's wire
// projection. This fixture grants exact targets, never ordinary authority.
const _org = '10000000-0000-4000-8000-000000000001';
const _restaurant = '20000000-0000-4000-8000-000000000001';
const _branch = '30000000-0000-4000-8000-000000000001';
const _device = '40000000-0000-4000-8000-000000000001';
const _first = '50000000-0000-4000-8000-000000000001';
const _second = '50000000-0000-4000-8000-000000000002';
const _dispatch = '60000000-0000-4000-8000-000000000001';
const _oldDispatch = '60000000-0000-4000-8000-000000000002';
const _order = '70000000-0000-4000-8000-000000000001';
const _decision = '80000000-0000-4000-8000-000000000001';
const _assignment = '90000000-0000-4000-8000-000000000001';

class _Transport implements SyncRpcTransport {
  late Map<String, Object?> response;
  @override
  Future<Object?> invoke(String name, Map<String, dynamic> args) async {
    expect(name, 'pos_kitchen_print_containment');
    expect(args.keys.toSet(), {'p_device_id', 'p_session_token'});
    return response;
  }
}

class _Row extends Fake implements KitchenSpoolJobRow {
  _Row(this.request, {this.held = false});
  final String? request;
  final bool held;
  @override
  String get organizationId => _org;
  @override
  String get restaurantId => _restaurant;
  @override
  String get branchId => _branch;
  @override
  String get deviceId => _device;
  @override
  String get dispatchId => held ? _oldDispatch : _dispatch;
  @override
  String get localJobId =>
      request == null ? 'ordinary' : 'web-initial:$request';
}

void main() {
  late _Transport transport;
  late InMemoryDeviceSessionSecretStore secrets;
  late Map<String, String> cache;
  late KitchenPrintContainmentDomain domain;
  late DateTime clock;
  var offline = false;

  Map<String, Object?> projection(int revision, {String? request}) => {
    'ok': true,
    'organization_id': _org,
    'restaurant_id': _restaurant,
    'branch_id': _branch,
    'device_id': _device,
    'revision': revision,
    'mode': request == null ? 'blocked' : 'target_only',
    'target_request_id': request,
    'expires_at': request == null
        ? null
        : clock.add(const Duration(minutes: 5)).toIso8601String(),
    'held_dispatch_ids': [_oldDispatch],
  };

  KitchenPrintContainment build() => KitchenPrintContainment(
    context: const DeviceContext(
      organizationId: _org,
      restaurantId: _restaurant,
      branchId: _branch,
      deviceId: _device,
    ),
    secretStore: secrets,
    transport: transport,
    isCurrent: () => true,
    isOffline: () => offline,
    readCache: (key) async => cache[key],
    writeCache: (key, value) async => cache[key] = value,
    now: () => clock,
    domain: domain,
  );

  setUp(() async {
    clock = DateTime.utc(2026, 10, 17);
    offline = false;
    cache = {};
    domain = KitchenPrintContainmentDomain();
    transport = _Transport()..response = projection(100);
    secrets = InMemoryDeviceSessionSecretStore();
    await secrets.write(
      const DeviceSessionCredential(
        deviceId: _device,
        sessionToken: 'synthetic-local-session',
      ),
    );
  });

  test(
    'successive server leases work in one retained v63 controller',
    () async {
      final guard = build();
      expect(await guard.allowsTarget(_first), isFalse);
      transport.response = projection(101, request: _first);
      expect(await guard.allowsTarget(_first), isTrue);
      expect(await guard.allowsTarget(_second), isFalse);
      expect(await guard.allowsOrdinary(), isFalse);
      expect(await guard.allowsJob(_Row(null)), isFalse);
      expect(await guard.allowsJob(_Row(_first)), isTrue);
      expect(await guard.allowsJob(_Row(_first, held: true)), isFalse);

      // Terminal/expiry tombstone, followed by a NEW acceptance revision.
      transport.response = projection(102);
      expect(await guard.allowsTarget(_first), isFalse);
      transport.response = projection(103, request: _second);
      expect(await guard.allowsTarget(_second), isTrue);
      expect(await guard.allowsTarget(_first), isFalse);
      expect(await guard.allowsJob(_Row(_first)), isFalse);
      expect(await guard.allowsJob(_Row(_second)), isTrue);
      expect(await guard.allowsOrdinary(), isFalse);
    },
  );

  test('OFF invalidates acquired authority before transport', () async {
    final guard = build();
    transport.response = projection(101, request: _first);
    final permit = await guard.authorizeOperation(
      KitchenPrintOperation.targetImport,
      dispatchId: _dispatch,
      target: KitchenPrintTarget(
        requestId: _first,
        orderId: _order,
        dispatchId: _dispatch,
        decisionId: _decision,
        printerAssignmentId: _assignment,
        isCurrent: () => true,
      ),
    );
    expect(permit?.isCurrent, isTrue);
    transport.response = projection(102);
    expect(await guard.synchronize(), isTrue);
    expect(permit?.isCurrent, isFalse);
    expect(await guard.allowsTarget(_first), isFalse);
  });

  test('late responses cannot restore a retired exact lease', () async {
    final guard = build();
    transport.response = projection(101, request: _first);
    expect(await guard.allowsTarget(_first), isTrue);
    transport.response = projection(102);
    expect(await guard.allowsTarget(_first), isFalse);
    transport.response = projection(101, request: _first);
    expect(await guard.allowsTarget(_first), isFalse);
    expect(await guard.allowsOrdinary(), isFalse);
  });

  test(
    'expiry and offline restart never authorize old imported work',
    () async {
      final guard = build();
      transport.response = projection(101, request: _first);
      expect(await guard.allowsTarget(_first), isTrue);
      clock = clock.add(const Duration(minutes: 6));
      offline = true;
      expect(await guard.allowsTarget(_first), isFalse);
      expect(await guard.allowsOrdinary(), isFalse);
      final restarted = build();
      expect(await restarted.allowsTarget(_first), isFalse);
      expect(await restarted.allowsJob(_Row(_first)), isFalse);
      expect(await restarted.allowsJob(_Row(null)), isFalse);
    },
  );

  test('foreign device projection fails closed', () async {
    transport.response = projection(101, request: _first)
      ..['device_id'] = '40000000-0000-4000-8000-000000000002';
    final guard = build();
    expect(await guard.allowsTarget(_first), isFalse);
    expect(await guard.allowsOrdinary(), isFalse);
  });

  test('a new unknown policy mode is not a v63 compatibility bridge', () async {
    transport.response = projection(101)..['mode'] = 'new_web_only';
    final guard = build();
    expect(await guard.allowsTarget(_first), isFalse);
    expect(await guard.allowsOrdinary(), isFalse);
  });
}
