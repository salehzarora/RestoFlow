// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B) — the explicit printer-only
// COMPLETE safety net: the action gate (resolveOrderActions.canComplete), the
// single-op double-click guard (PosOrderCompleteController), and the idempotent
// server-already-completed handling (RealKitchenFinishRepository.completeServedOrder).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/kitchen_finish_controller.dart'
    show kitchenFinishRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_order_complete_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

SubmittedOrderView _view(String number, {int total = 0}) => SubmittedOrderView(
  orderNumber: number,
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: total,
  lines: const [],
  orderId: 'oid-$number',
);

PosRecentOrder _order(
  String number, {
  String status = 'served',
  int total = 0,
}) => PosRecentOrder(
  order: _view(number, total: total),
  submittedAt: DateTime.utc(2026, 7, 28),
  status: status,
);

class _FakeFinishRepo implements KitchenFinishRepository {
  _FakeFinishRepo({this.gate});
  final Completer<void>? gate;
  final List<String> completed = [];

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async => KitchenFinishResult(orderId, KitchenFinishStatus.finished);

  @override
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  }) async {
    completed.add(orderId);
    if (gate != null) await gate!.future;
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }
}

class _StubTransport implements SyncRpcTransport {
  _StubTransport(this._result);
  final Object? _result;
  final List<Map<String, dynamic>> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(params);
    return _result;
  }
}

Object _pushResult(Map<String, dynamic> opResult) => <String, dynamic>{
  'ok': true,
  'results': [opResult],
};

void main() {
  group('resolveOrderActions.canComplete', () {
    test('a served order with completeEligible -> canComplete', () {
      final a = resolveOrderActions(_order('#S1'), completeEligible: true);
      expect(a.canComplete, isTrue);
      expect(a.isEmpty, isFalse);
    });
    test('completeEligible=false -> no Complete action', () {
      expect(resolveOrderActions(_order('#S2')).canComplete, isFalse);
    });
    test('a TERMINAL order never shows Complete, even if eligible', () {
      final a = resolveOrderActions(
        _order('#C1', status: 'completed'),
        completeEligible: true,
      );
      expect(a.canComplete, isFalse);
    });
  });

  group('PosOrderCompleteController', () {
    ProviderContainer make(_FakeFinishRepo repo) => ProviderContainer(
      overrides: [
        kitchenFinishRepositoryProvider.overrideWithValue(repo),
        clientIdGeneratorProvider.overrideWithValue(
          FixedClientIdGenerator(const ['op-1']),
        ),
      ],
    );

    test('one tap dispatches exactly one completion op', () async {
      final repo = _FakeFinishRepo();
      final c = make(repo);
      addTearDown(c.dispose);
      await c
          .read(posOrderCompleteControllerProvider.notifier)
          .complete('oid-1');
      expect(repo.completed, ['oid-1']);
      expect(c.read(posOrderCompleteControllerProvider), isEmpty);
    });

    test('a double-tap while in flight enqueues EXACTLY ONE op', () async {
      final gate = Completer<void>();
      final repo = _FakeFinishRepo(gate: gate);
      final c = make(repo);
      addTearDown(c.dispose);
      final n = c.read(posOrderCompleteControllerProvider.notifier);
      final f1 = n.complete('oid-1');
      final f2 = n.complete('oid-1'); // suppressed while the first is in flight
      expect(
        c.read(posOrderCompleteControllerProvider).contains('oid-1'),
        isTrue,
      );
      gate.complete();
      await Future.wait([f1, f2]);
      expect(repo.completed, ['oid-1']); // only ONE op
      expect(c.read(posOrderCompleteControllerProvider), isEmpty);
    });

    test('an empty order id is a no-op', () async {
      final repo = _FakeFinishRepo();
      final c = make(repo);
      addTearDown(c.dispose);
      expect(
        await c.read(posOrderCompleteControllerProvider.notifier).complete(''),
        isNull,
      );
      expect(repo.completed, isEmpty);
    });
  });

  group('RealKitchenFinishRepository.completeServedOrder', () {
    const session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

    test(
      'sends ONE order.status(completed) op and reports finished on applied',
      () async {
        final t = _StubTransport(
          _pushResult({
            'local_operation_id': 'op-1',
            'ok': true,
            'status': 'applied',
          }),
        );
        final r = RealKitchenFinishRepository(t, session);
        final res = await r.completeServedOrder(
          orderId: 'oid-1',
          localOperationId: 'op-1',
        );
        expect(res.status, KitchenFinishStatus.finished);
        final op = (t.calls.single['p_operations'] as List).single as Map;
        expect(op['operation_type'], 'order.status');
        expect((op['payload'] as Map)['new_status'], 'completed');
      },
    );

    test(
      'an ALREADY-completed order replays idempotently as finished',
      () async {
        final t = _StubTransport(
          _pushResult({
            'local_operation_id': 'op-1',
            'ok': false,
            'error': 'invalid_transition',
            'from': 'completed',
          }),
        );
        final r = RealKitchenFinishRepository(t, session);
        expect(
          (await r.completeServedOrder(
            orderId: 'oid-1',
            localOperationId: 'op-1',
          )).status,
          KitchenFinishStatus.finished,
        );
      },
    );

    test(
      'a permission_denied is an honest failure (no silent success)',
      () async {
        final t = _StubTransport(
          _pushResult({
            'local_operation_id': 'op-1',
            'ok': false,
            'error': 'permission_denied',
          }),
        );
        final r = RealKitchenFinishRepository(t, session);
        expect(
          (await r.completeServedOrder(
            orderId: 'oid-1',
            localOperationId: 'op-1',
          )).status,
          KitchenFinishStatus.failed,
        );
      },
    );

    test('no session -> unavailable (never a guessed success)', () async {
      final r = RealKitchenFinishRepository(_StubTransport(null), null);
      expect(
        (await r.completeServedOrder(
          orderId: 'oid-1',
          localOperationId: 'op-1',
        )).status,
        KitchenFinishStatus.failed,
      );
    });
  });
}
