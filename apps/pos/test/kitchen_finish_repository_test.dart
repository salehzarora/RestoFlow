import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';

/// KITCHEN-PRINT-DUAL-001D — RealKitchenFinishRepository advances an active order
/// to `served` using ONLY single-step `order.status` sync_push ops (the existing
/// state machine + RPC), and never a payment / cancel / void / complete op.

/// Deterministic ids so the echoed result matches by local_operation_id.
class _SeqIds implements ClientIdGenerator {
  int _n = 0;
  @override
  String newId() => 'op-${++_n}';
}

/// Records every sync_push call and echoes a scripted per-op result. By default
/// every op is `applied`; [failNewStatus] makes the op for that new_status fail
/// with invalid_transition; [autoCompleteNewStatus] returns applied+auto_completed.
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport({
    this.failNewStatus,
    this.autoCompleteNewStatus,
    this.throwKind,
  });
  final String? failNewStatus;
  final String? autoCompleteNewStatus;
  final SyncTransportErrorKind? throwKind;
  final List<Map<String, dynamic>> ops = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (throwKind != null) throw SyncTransportException(throwKind!);
    expect(function, 'sync_push');
    final op = (params['p_operations'] as List).single as Map<String, dynamic>;
    ops.add(op);
    final localOp = op['local_operation_id'];
    final newStatus =
        (op['payload'] as Map<String, dynamic>)['new_status'] as String;
    final result = <String, dynamic>{
      'local_operation_id': localOp,
      'operation_type': op['operation_type'],
      if (newStatus == failNewStatus) ...{
        'status': 'invalid_transition',
        'ok': false,
        'error': 'invalid_transition',
      } else ...{
        'status': 'applied',
        'ok': true,
        if (newStatus == autoCompleteNewStatus) ...{
          'auto_completed': true,
          'order_status': 'completed',
        },
      },
    };
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[result],
    };
  }
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

RealKitchenFinishRepository _repo(_ScriptedTransport t) =>
    RealKitchenFinishRepository(t, _session, _SeqIds());

void main() {
  test('the step chain to served is single-step forward only', () {
    expect(kitchenStepsToServed('submitted'), [
      'accepted',
      'preparing',
      'ready',
      'served',
    ]);
    expect(kitchenStepsToServed('accepted'), ['preparing', 'ready', 'served']);
    expect(kitchenStepsToServed('preparing'), ['ready', 'served']);
    expect(kitchenStepsToServed('ready'), ['served']);
    // Not active / terminal -> no steps (never targeted).
    for (final s in ['served', 'completed', 'cancelled', 'voided', 'draft']) {
      expect(kitchenStepsToServed(s), isEmpty, reason: s);
    }
  });

  test('submitted reaches served through FOUR order.status ops', () async {
    final t = _ScriptedTransport();
    final r = await _repo(
      t,
    ).advanceToServed(orderId: 'o1', fromStatus: 'submitted');
    expect(r.isFinished, isTrue);
    expect(t.ops, hasLength(4));
    expect(t.ops.map((o) => (o['payload'] as Map)['new_status']).toList(), [
      'accepted',
      'preparing',
      'ready',
      'served',
    ]);
    // Every op is the order.status op keyed to the order (never a payment/void op).
    for (final o in t.ops) {
      expect(o['operation_type'], 'order.status');
      expect(o['target_entity'], 'order');
      expect(o['target_id'], 'o1');
      expect((o['payload'] as Map)['order_id'], 'o1');
    }
    // Fresh idempotency key per op.
    expect(t.ops.map((o) => o['local_operation_id']).toSet(), hasLength(4));
  });

  test('accepted->3, preparing->2, ready->1 ops', () async {
    for (final (from, count) in [
      ('accepted', 3),
      ('preparing', 2),
      ('ready', 1),
    ]) {
      final t = _ScriptedTransport();
      final r = await _repo(t).advanceToServed(orderId: 'o', fromStatus: from);
      expect(r.isFinished, isTrue, reason: from);
      expect(t.ops, hasLength(count), reason: from);
      expect((t.ops.last['payload'] as Map)['new_status'], 'served');
    }
  });

  test('a non-active/terminal status is never advanced (zero ops)', () async {
    for (final s in ['served', 'completed', 'cancelled', 'voided']) {
      final t = _ScriptedTransport();
      final r = await _repo(t).advanceToServed(orderId: 'o', fromStatus: s);
      expect(r.isFinished, isFalse, reason: s);
      expect(t.ops, isEmpty, reason: s);
    }
  });

  test('a blocking transition stops the order and reports failed', () async {
    // 'preparing' is refused -> only the first op (->accepted) landed.
    final t = _ScriptedTransport(failNewStatus: 'preparing');
    final r = await _repo(
      t,
    ).advanceToServed(orderId: 'o1', fromStatus: 'submitted');
    expect(r.isFinished, isFalse);
    expect(r.error, 'invalid_transition');
    expect(t.ops, hasLength(2)); // ->accepted (applied), ->preparing (refused)
  });

  test(
    'a PAID order that auto-completes on served stops cleanly (finished)',
    () async {
      final t = _ScriptedTransport(autoCompleteNewStatus: 'served');
      final r = await _repo(
        t,
      ).advanceToServed(orderId: 'o', fromStatus: 'ready');
      expect(r.isFinished, isTrue);
      expect(t.ops, hasLength(1)); // ->served, which auto-completed
    },
  );

  test('a transport failure reports failed (best-effort, retryable)', () async {
    final t = _ScriptedTransport(throwKind: SyncTransportErrorKind.transient);
    final r = await _repo(t).advanceToServed(orderId: 'o', fromStatus: 'ready');
    expect(r.isFinished, isFalse);
  });

  test('no session/transport => fails closed, sends nothing', () async {
    final r = await RealKitchenFinishRepository(
      null,
      null,
      _SeqIds(),
    ).advanceToServed(orderId: 'o', fromStatus: 'ready');
    expect(r.isFinished, isFalse);
    expect(r.error, 'unavailable');
  });
}
