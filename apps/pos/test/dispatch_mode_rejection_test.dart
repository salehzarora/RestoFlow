import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';

/// KITCHEN-DISPATCH-ENFORCE-001 — the client side of the server dispatch-mode
/// guard.
///
/// The server now rejects an `order.submit` carrying
/// `dispatch_mode='direct_print'` when the branch's authoritative
/// `kitchen_workflow_mode` is not `printer_only`, with the typed error
/// `dispatch_mode_not_allowed`. Replaying that SAME operation identity returns
/// the SAME stored rejection forever (the dispatch mode is part of the op's
/// content fingerprint), so the client must treat it as TERMINAL:
///
///   * no auto-resweep — `outbox_controller.dart` `_sweep` (:88-100) skips any
///     entry whose `isPermanentBusinessRejection` is true;
///   * no Retry affordance — `order_confirmation.dart` (:346-351) gates on the
///     same predicate;
///   * the phantom recent-order row is retired to a non-actionable rejected
///     shell — `outbox_controller.dart` (:445-466) `markLocallyRejected`;
///   * the kitchen ticket is suppressed — there is no server order to cook.
///
/// All four behaviours hang off ONE predicate, so these tests pin the predicate
/// and the two pure seams that consume it, plus a real repository push proving
/// the wire code is parsed into it.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._result);

  final Map<String, dynamic> _result;
  int calls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls++;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[_result],
      'server_ts': '2026-07-29T09:00:01Z',
    };
  }
}

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-123',
  deviceId: 'device-abc',
);

OutboxEntry _entry() {
  final payload = OrderSubmissionPayload(
    orderId: 'order-1',
    localOperationId: 'op-1',
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
    clientCreatedAt: DateTime.utc(2026, 7, 29, 9),
  );
  return OutboxEntry(
    id: 'outbox-op-1',
    deviceId: 'device-abc',
    localOperationId: 'op-1',
    operationType: 'order.submit',
    targetEntity: 'order',
    targetId: 'order-1',
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
    clientCreatedAt: DateTime.utc(2026, 7, 29, 9),
  );
}

Future<OutboxEntry> _pushWith(Map<String, dynamic> result) async {
  final transport = _FakeTransport(result);
  final repo = RealOutboxRepository(transport, _session);
  final entry = _entry();
  await repo.enqueue(entry);
  return repo.push(entry.id);
}

void main() {
  group('KITCHEN-DISPATCH-ENFORCE-001 dispatch_mode_not_allowed is terminal', () {
    test('1. the code is in the canonical permanent-rejection set', () {
      expect(
        kPermanentRejectionCodes.contains('dispatch_mode_not_allowed'),
        isTrue,
      );
    });

    test(
      '2. a rejected push maps to the typed code and IS permanent',
      () async {
        final pushed = await _pushWith(<String, dynamic>{
          'local_operation_id': 'op-1',
          'operation_type': 'order.submit',
          'ok': false,
          'status': 'rejected',
          'error': 'dispatch_mode_not_allowed',
          'detail': 'direct_print_requires_printer_only_branch',
          'idempotency_replay': false,
        });

        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.lastErrorCode, 'dispatch_mode_not_allowed');
        // The ONE predicate every terminal behaviour hangs off.
        expect(pushed.isPermanentBusinessRejection, isTrue);
      },
    );

    test('3. it is excluded from the auto-resweep candidate set', () async {
      final pushed = await _pushWith(<String, dynamic>{
        'local_operation_id': 'op-1',
        'status': 'rejected',
        'error': 'dispatch_mode_not_allowed',
        'idempotency_replay': false,
      });

      // Mirrors outbox_controller._sweep (:88-100): failed AND not a permanent
      // business rejection AND under the attempt cap.
      expect(pushed.syncState.isFailed, isTrue);
      expect(
        pushed.syncState.isFailed && !pushed.isPermanentBusinessRejection,
        isFalse,
        reason: 'a foregone rejection must never burn another auto attempt',
      );
    });

    test('4. the kitchen ticket is suppressed (no server order to cook)', () {
      expect(
        isOrderEligibleForKitchenPrint(
          orderId: 'order-1',
          isDemoMode: false,
          rejectionCode: 'dispatch_mode_not_allowed',
        ),
        isFalse,
      );
      // Sanity: the SAME order prints when it was not permanently rejected.
      expect(
        isOrderEligibleForKitchenPrint(
          orderId: 'order-1',
          isDemoMode: false,
          rejectionCode: null,
        ),
        isTrue,
      );
    });

    test(
      '5. the entry carries the identity phantom-row retirement needs',
      () async {
        final pushed = await _pushWith(<String, dynamic>{
          'local_operation_id': 'op-1',
          'status': 'rejected',
          'error': 'dispatch_mode_not_allowed',
          'idempotency_replay': false,
        });

        // outbox_controller (:445-466) retires the recent-order row by this exact
        // identity triple + order number.
        expect(pushed.targetId, 'order-1');
        expect(pushed.localOperationId, 'op-1');
        expect(pushed.id, 'outbox-op-1');
        expect(pushed.summary.orderNumber, 'DEMO-1');
      },
    );

    test(
      '6. an UNKNOWN server code stays retryable and print-eligible',
      () async {
        final pushed = await _pushWith(<String, dynamic>{
          'local_operation_id': 'op-1',
          'status': 'rejected',
          'error': 'some_future_code',
          'idempotency_replay': false,
        });

        // The guard is specific: only canonical permanent codes are terminal, so
        // an older/newer server vocabulary degrades gracefully instead of
        // silently retiring an order that may still be alive.
        expect(pushed.lastErrorCode, 'some_future_code');
        expect(pushed.isPermanentBusinessRejection, isFalse);
        expect(
          isOrderEligibleForKitchenPrint(
            orderId: 'order-1',
            isDemoMode: false,
            rejectionCode: 'some_future_code',
          ),
          isTrue,
        );
      },
    );

    test(
      '7. a replayed rejection is still terminal (stored verdict)',
      () async {
        final pushed = await _pushWith(<String, dynamic>{
          'local_operation_id': 'op-1',
          'status': 'rejected',
          'error': 'dispatch_mode_not_allowed',
          'idempotency_replay': true,
        });

        expect(pushed.syncState, OutboxSyncState.rejected);
        expect(pushed.isPermanentBusinessRejection, isTrue);
      },
    );
  });
}
