import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';

/// A recording fake [SyncRpcTransport] (house style: hand-written, no mocktail).
/// Records every invoked function + params so a test can assert the EXACT
/// `public.sync_push` envelope - and that no `app.*` RPC is ever called. No
/// SupabaseClient, no network.
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);

  final Future<Object?> Function(String function, Map<String, dynamic> params)
  _handler;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    functions.add(function);
    params.add(p);
    return _handler(function, p);
  }
}

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-123',
  deviceId: 'device-abc',
);

OutboxEntry _entry({
  String localOperationId = 'op-1',
  String orderId = 'order-1',
}) {
  final payload = OrderSubmissionPayload(
    orderId: orderId,
    localOperationId: localOperationId,
    deviceId: 'device-abc',
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    orderType: OrderType.dineIn,
    tableId: 't3',
    currencyCode: 'ILS',
    subtotalMinor: 4200,
    grandTotalMinor: 4200,
    items: const [
      OrderSubmissionItem(
        menuItemId: 'm1',
        nameSnapshot: 'Burger',
        quantity: 2,
        unitPriceMinorSnapshot: 2100,
        lineTotalMinor: 4200,
      ),
    ],
    clientCreatedAt: DateTime.utc(2026, 6, 29, 9),
  );
  return OutboxEntry(
    id: 'outbox-$localOperationId',
    deviceId: 'device-abc',
    localOperationId: localOperationId,
    operationType: 'order.submit',
    targetEntity: 'order',
    targetId: orderId,
    payloadJson: jsonEncode(payload.toJson()),
    summary: const OrderSummary(
      orderNumber: 'DEMO-1',
      orderType: OrderType.dineIn,
      tableLabel: 'T3',
      itemCount: 2,
      subtotalMinor: 4200,
      currencyCode: 'ILS',
    ),
    syncState: OutboxSyncState.pending,
    clientCreatedAt: DateTime.utc(2026, 6, 29, 9),
  );
}

Map<String, dynamic> _envelope(Map<String, dynamic> opResult) =>
    <String, dynamic>{
      'ok': true,
      'results': <dynamic>[opResult],
      'server_ts': '2026-06-29T09:00:01Z',
    };

void main() {
  group('RealOutboxRepository -> public.sync_push (RF-129)', () {
    test(
      'pushes an order.submit op to public.sync_push (never app.*), integer-'
      'minor money, server-derived scope, and maps an applied result',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'operation_type': 'order.submit',
            'ok': true,
            'status': 'applied',
            'idempotency_replay': false,
          }),
        );
        final repo = RealOutboxRepository(transport, _session);
        final entry = _entry();

        await repo.enqueue(entry);
        final pushed = await repo.push(entry.id);

        // result mapping
        expect(pushed.syncState, OutboxSyncState.applied);
        expect(pushed.lastErrorCode, isNull);
        expect(pushed.attemptCount, 1);

        // exactly one call, to the PUBLIC wrapper - never the app schema.
        expect(transport.functions, <String>['sync_push']);
        expect(transport.functions.any((f) => f.contains('app.')), isFalse);

        // envelope: session-scoped, single op.
        final params = transport.params.single;
        expect(params['p_pin_session_id'], 'pin-123');
        expect(params['p_device_id'], 'device-abc');
        final ops = params['p_operations'] as List;
        expect(ops, hasLength(1));
        final op = ops.single as Map<String, dynamic>;
        expect(op['local_operation_id'], 'op-1');
        expect(op['operation_type'], 'order.submit');
        expect(op['target_entity'], 'order');
        expect(op['target_id'], 'order-1');

        final payload = op['payload'] as Map<String, dynamic>;
        expect(payload['order_id'], 'order-1');
        expect(payload['order_type'], 'dine_in');
        expect(payload['currency_code'], 'ILS');
        // integer minor money only - no float introduced.
        expect(payload['subtotal_minor'], isA<int>());
        expect(payload['grand_total_minor'], isA<int>());
        expect(payload['subtotal_minor'], 4200);
        expect(payload['grand_total_minor'], 4200);
        final items = payload['order_items'] as List;
        expect((items.single as Map)['unit_price_minor_snapshot'], 2100);
        // server derives tenant scope: NO org/restaurant/branch/device leaks in
        // the op payload (no demo tenant value is ever transmitted).
        expect(payload.containsKey('organization_id'), isFalse);
        expect(payload.containsKey('restaurant_id'), isFalse);
        expect(payload.containsKey('branch_id'), isFalse);
        expect(payload.containsKey('device_id'), isFalse);
      },
    );

    test(
      'a per-op rejected status marks the entry rejected with its error code',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'status': 'rejected',
            'error': 'invalid_payload',
            'idempotency_replay': false,
          }),
        );
        final repo = RealOutboxRepository(transport, _session);
        final entry = _entry();
        await repo.enqueue(entry);

        final pushed = await repo.push(entry.id);
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'invalid_payload');
      },
    );

    test('a per-op conflict status maps to OutboxSyncState.conflict', () async {
      final transport = _RecordingTransport(
        (_, _) async => _envelope(<String, dynamic>{
          'local_operation_id': 'op-1',
          'status': 'conflict',
        }),
      );
      final repo = RealOutboxRepository(transport, _session);
      final entry = _entry();
      await repo.enqueue(entry);

      final pushed = await repo.push(entry.id);
      expect(pushed.syncState, OutboxSyncState.conflict);
    });

    test(
      'an idempotency replay reflects the stored status; enqueue dedups',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'status': 'applied',
            'idempotency_replay': true,
          }),
        );
        final repo = RealOutboxRepository(transport, _session);
        final entry = _entry();

        await repo.enqueue(entry);
        // Re-enqueuing the same (deviceId, localOperationId) is idempotent (D-022).
        await repo.enqueue(entry);
        expect(await repo.recentEntries(), hasLength(1));

        final pushed = await repo.push(entry.id);
        expect(pushed.syncState, OutboxSyncState.applied);
      },
    );

    test(
      'a 42501 whole-batch failure marks the entry rejected (no throw)',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => throw const SyncTransportException(
            SyncTransportErrorKind.auth,
            code: '42501',
            message: 'revoked device / expired session',
          ),
        );
        final repo = RealOutboxRepository(transport, _session);
        final entry = _entry();
        await repo.enqueue(entry);

        final pushed = await repo.push(entry.id);
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, '42501');
      },
    );

    test('retry re-queues a rejected entry to pending', () async {
      var firstPush = true;
      final transport = _RecordingTransport((_, _) async {
        if (firstPush) {
          firstPush = false;
          return _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'status': 'rejected',
            'error': 'invalid_payload',
          });
        }
        return _envelope(<String, dynamic>{
          'local_operation_id': 'op-1',
          'status': 'applied',
        });
      });
      final repo = RealOutboxRepository(transport, _session);
      final entry = _entry();
      await repo.enqueue(entry);

      final rejected = await repo.push(entry.id);
      expect(rejected.syncState, OutboxSyncState.rejected);

      final requeued = await repo.retry(entry.id);
      expect(requeued.syncState, OutboxSyncState.pending);
      expect(requeued.lastErrorCode, isNull);
    });

    test(
      'fail-closed without a session: methods throw and no backend is called',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => fail('the real outbox must not contact a backend'),
        );
        final repo = RealOutboxRepository(transport, null);

        await expectLater(
          repo.enqueue(_entry()),
          throwsA(isA<OrderSubmissionException>()),
        );
        await expectLater(
          repo.recentEntries(),
          throwsA(isA<OrderSubmissionException>()),
        );
        expect(transport.functions, isEmpty);
      },
    );

    test('fail-closed without a transport (missing/invalid config)', () async {
      final repo = RealOutboxRepository(null, _session);
      await expectLater(
        repo.recentEntries(),
        throwsA(isA<OrderSubmissionException>()),
      );
    });
  });

  group(
    'RealOutboxRepository result parsing fails closed (RF-129 hardening)',
    () {
      Future<OutboxEntry> pushWith(Object? envelope) async {
        final transport = _RecordingTransport((_, _) async => envelope);
        final repo = RealOutboxRepository(transport, _session);
        final entry = _entry();
        await repo.enqueue(entry);
        return repo.push(entry.id);
      }

      test('a malformed (non-Map) envelope -> rejected', () async {
        final pushed = await pushWith('not-a-map');
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'malformed_response');
      });

      test('a missing results array -> rejected', () async {
        final pushed = await pushWith(<String, dynamic>{
          'ok': true,
          'server_ts': '2026-06-29T09:00:01Z',
        });
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'missing_results');
      });

      test('an empty results array -> rejected', () async {
        final pushed = await pushWith(<String, dynamic>{
          'ok': true,
          'results': <dynamic>[],
          'server_ts': '2026-06-29T09:00:01Z',
        });
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'empty_results');
      });

      test(
        'no result matching this op local_operation_id -> rejected',
        () async {
          final pushed = await pushWith(
            _envelope(<String, dynamic>{
              'local_operation_id': 'some-other-op',
              'status': 'applied',
            }),
          );
          expect(pushed.syncState, OutboxSyncState.rejected);
          expect(pushed.lastErrorCode, 'no_matching_operation');
        },
      );

      test('a matched result with a missing status -> rejected', () async {
        final pushed = await pushWith(
          _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'ok': true,
          }),
        );
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'missing_status');
      });

      test('a matched result with an unknown status -> rejected', () async {
        final pushed = await pushWith(
          _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'status': 'teleported',
          }),
        );
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'unknown_status');
      });

      test('an applied status contradicted by ok:false -> rejected', () async {
        final pushed = await pushWith(
          _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'status': 'applied',
            'ok': false,
          }),
        );
        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'applied_not_ok');
      });

      test('the diagnostic code never leaks raw backend JSON', () async {
        final pushed = await pushWith('not-a-map');
        expect(pushed.lastErrorCode, isNot(contains('{')));
      });
    },
  );
}
