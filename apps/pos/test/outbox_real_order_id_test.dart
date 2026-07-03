import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// RFC-4122 v4 UUID shape (lowercase hex, version nibble 4, variant 8/9/a/b).
final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

/// Echoes each pushed op's `local_operation_id` back in an `applied` result, so
/// the (fail-closed) parser matches and applies. Records the request params.
class _EchoTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    params.add(p);
    final op = (p['p_operations'] as List).first as Map<String, dynamic>;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          'ok': true,
          'status': 'applied',
        },
      ],
      'server_ts': '2026-06-29T09:00:01Z',
    };
  }
}

List<CartLineView> _lines() => const [
  CartLineView(
    lineId: 'l1',
    menuItemId: 'm1',
    name: 'Burger',
    quantity: 2,
    unitPriceMinor: 2100,
    lineTotalMinor: 4200,
    currencyCode: 'ILS',
  ),
];

void main() {
  test(
    'RandomClientIdGenerator emits a valid RFC-4122 v4 UUID, distinct per call',
    () {
      final gen = RandomClientIdGenerator();
      final a = gen.newId();
      final b = gen.newId();
      expect(a, matches(_uuidV4));
      expect(b, matches(_uuidV4));
      expect(a, isNot(b));
    },
  );

  test(
    'real mode: the order.submit op sent to sync_push carries a UUID order_id (never demo-*)',
    () async {
      final transport = _EchoTransport();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(_session),
          outboxRepositoryProvider.overrideWithValue(
            RealOutboxRepository(transport, _session),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(outboxControllerProvider.notifier);
      final result = await controller.submit(
        lines: _lines(),
        subtotalMinor: 4200,
        currencyCode: 'ILS',
        orderType: OrderType.takeaway,
      );

      // Demo-readiness sprint: a REAL submit pushes AUTOMATICALLY — no manual
      // "sync now" — so the transport already carries exactly one push, and
      // the returned display number is the shared code (never DEMO-*).
      final op =
          (transport.params.single['p_operations'] as List).first
              as Map<String, dynamic>;
      final payload = op['payload'] as Map<String, dynamic>;
      expect(
        result.orderNumber,
        displayOrderCode(payload['order_id'] as String),
      );
      expect(result.orderNumber, isNot(startsWith('DEMO-')));

      // The real order_id is a client-generated UUID, never a demo label, and it
      // equals the op target_id.
      expect(payload['order_id'], matches(_uuidV4));
      expect(payload['order_id'].toString(), isNot(startsWith('demo-order')));
      expect(op['target_id'], payload['order_id']);
      // local_operation_id (the idempotency key) is a UUID too, never a demo label.
      expect(op['local_operation_id'], matches(_uuidV4));
      expect(op['local_operation_id'].toString(), isNot(startsWith('demo-op')));
    },
  );

  test(
    'real mode: local_operation_id is stable across retries (idempotency)',
    () async {
      final transport = _EchoTransport();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(_session),
          outboxRepositoryProvider.overrideWithValue(
            RealOutboxRepository(transport, _session),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(outboxControllerProvider.notifier);
      final result = await controller.submit(
        lines: _lines(),
        subtotalMinor: 4200,
        currencyCode: 'ILS',
        orderType: OrderType.takeaway,
      );

      // Submit auto-pushed once (sprint); a manual re-push re-sends the SAME op.
      await controller.pushEntry(result.entry.id);

      String localOpOf(Map<String, dynamic> params) =>
          ((params['p_operations'] as List).first
                  as Map<String, dynamic>)['local_operation_id']
              as String;

      expect(transport.params, hasLength(2));
      // The same submission keeps ONE local_operation_id across pushes (D-022).
      expect(localOpOf(transport.params[0]), result.entry.localOperationId);
      expect(localOpOf(transport.params[1]), result.entry.localOperationId);
    },
  );

  test('demo mode keeps its deterministic demo ids (unchanged)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(outboxControllerProvider.notifier);
    final result = await controller.submit(
      lines: _lines(),
      subtotalMinor: 4200,
      currencyCode: 'ILS',
      orderType: OrderType.takeaway,
    );

    final body = jsonDecode(result.entry.payloadJson) as Map<String, dynamic>;
    expect(body['order_id'], 'demo-order-0001');
    expect(result.entry.localOperationId, 'demo-op-0001');
  });
}
