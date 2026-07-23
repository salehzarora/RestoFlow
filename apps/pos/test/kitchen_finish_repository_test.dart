import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';

/// KITCHEN-PRINT-DUAL-001D (concurrency correction) — RealKitchenFinishRepository
/// drives an active order to `served` with a BOUNDED authoritative-progress loop:
/// one single-step `order.status` op at a time, reclassifying from the server's
/// real current status (the `from` of an invalid_transition) instead of a stale
/// locally-captured status. It never sends a payment / cancel / void / complete
/// op, and concurrent KDS/cashier action can never corrupt or misreport a result.

/// A faithful in-memory `sync_push` server for `order.status` ops. It applies the
/// single legal forward edge from the order's CURRENT status (mutating it), or
/// returns invalid_transition carrying `from` = that current status; it keeps an
/// idempotency ledger so a re-sent op id replays its stored result; and it can be
/// scripted for conflicts, transport throws, denials, and auto-completion.
class _FakeServer implements SyncRpcTransport {
  _FakeServer(this.status);

  /// orderId -> current authoritative status (the "server truth").
  final Map<String, String> status;

  /// local_operation_id -> stored terminal result (replayed on re-send).
  final Map<String, Map<String, dynamic>> _ledger = {};

  /// Every op envelope pushed, in order (including re-sends and thrown attempts).
  final List<Map<String, dynamic>> ops = [];

  /// op id -> remaining transport throws before it answers (idempotent retry).
  final Map<String, int> transportThrows = {};

  /// op ids that answer `conflict` once (then advance the order per
  /// [conflictAdvancesTo], modelling the winning concurrent transaction).
  final Set<String> conflictOnce = {};
  final Map<String, String> conflictAdvancesTo = {};
  final Set<String> _conflicted = {};

  /// op ids that answer `permission_denied`.
  final Set<String> denyOps = {};

  /// op ids whose successful apply also auto-completes the order.
  final Set<String> autoCompleteOps = {};

  static const _legal = {
    'submitted': 'accepted',
    'accepted': 'preparing',
    'preparing': 'ready',
    'ready': 'served',
    'served': 'completed',
  };

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    expect(function, 'sync_push');
    final op = (params['p_operations'] as List).single as Map<String, dynamic>;
    ops.add(op);
    final localOp = op['local_operation_id'] as String;
    final payload = op['payload'] as Map<String, dynamic>;
    final orderId = payload['order_id'] as String;
    final newStatus = payload['new_status'] as String;

    // Transport failure — before any ledger effect (genuinely ambiguous).
    final throwsLeft = transportThrows[localOp] ?? 0;
    if (throwsLeft > 0) {
      transportThrows[localOp] = throwsLeft - 1;
      throw SyncTransportException(SyncTransportErrorKind.transient);
    }

    // Idempotent replay of a stored terminal result (applied/rejected/conflict).
    final stored = _ledger[localOp];
    if (stored != null) {
      return _wrap({...stored, 'idempotency_replay': true});
    }

    if (denyOps.contains(localOp)) {
      final result = {
        'local_operation_id': localOp,
        'operation_type': 'order.status',
        'ok': false,
        'error': 'permission_denied',
        'status': 'rejected',
      };
      _ledger[localOp] = result;
      return _wrap(result);
    }

    if (conflictOnce.contains(localOp) && !_conflicted.contains(localOp)) {
      _conflicted.add(localOp);
      final advance = conflictAdvancesTo[localOp];
      if (advance != null) status[orderId] = advance;
      final result = {
        'local_operation_id': localOp,
        'operation_type': 'order.status',
        'ok': false,
        'error': 'conflict',
        'status': 'conflict',
      };
      _ledger[localOp] = result; // the server stores + replays a conflict
      return _wrap(result);
    }

    final current = status[orderId];
    final Map<String, dynamic> result;
    if (current != null && _legal[current] == newStatus) {
      status[orderId] = newStatus; // apply the single legal forward edge
      result = {
        'local_operation_id': localOp,
        'operation_type': 'order.status',
        'ok': true,
        'status': 'applied',
        'order_id': orderId,
        'revision': 1,
        if (autoCompleteOps.contains(localOp)) ...{
          'auto_completed': true,
          'order_status': 'completed',
        },
      };
    } else {
      // invalid_transition — `from` is the order's authoritative current status.
      result = {
        'local_operation_id': localOp,
        'operation_type': 'order.status',
        'ok': false,
        'error': 'invalid_transition',
        'status': 'rejected',
        'from': current,
        'to': newStatus,
        'order_id': orderId,
      };
    }
    _ledger[localOp] = result;
    return _wrap(result);
  }

  Map<String, dynamic> _wrap(Map<String, dynamic> result) => {
    'ok': true,
    'results': <dynamic>[result],
  };
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

RealKitchenFinishRepository _repo(_FakeServer s) =>
    RealKitchenFinishRepository(s, _session);

/// A refreshStatus backed by the fake server's truth (used for the conflict path).
Future<String?> Function(String) _serverRefresh(_FakeServer s) =>
    (orderId) async => s.status[orderId];

/// A refreshStatus that must NOT be consulted on the common (non-conflict) paths.
Future<String?> _neverRefresh(String orderId) async {
  fail('refreshStatus must not be called on a non-conflict path');
}

List<String> _newStatuses(_FakeServer s) => [
  for (final o in s.ops) (o['payload'] as Map)['new_status'] as String,
];

void main() {
  test('the single next step is one forward hop only', () {
    expect(kitchenNextStatus('submitted'), 'accepted');
    expect(kitchenNextStatus('accepted'), 'preparing');
    expect(kitchenNextStatus('preparing'), 'ready');
    expect(kitchenNextStatus('ready'), 'served');
    for (final s in ['served', 'completed', 'cancelled', 'voided', 'draft']) {
      expect(kitchenNextStatus(s), isNull, reason: s);
    }
    // The whole-chain helper still describes the ordered steps to served.
    expect(kitchenStepsToServed('submitted'), [
      'accepted',
      'preparing',
      'ready',
      'served',
    ]);
    expect(kitchenStepsToServed('ready'), ['served']);
  });

  test('A: submitted reaches served through FOUR applied order.status ops with '
      'STABLE batchRunId:orderId:target ids', () async {
    final s = _FakeServer({'o1': 'submitted'});
    final r = await _repo(s).advanceToServed(
      orderId: 'o1',
      fromStatus: 'submitted',
      batchRunId: 'b1',
      refreshStatus: _neverRefresh,
    );
    expect(r.isFinished, isTrue);
    expect(s.status['o1'], 'served');
    expect(_newStatuses(s), ['accepted', 'preparing', 'ready', 'served']);
    for (final o in s.ops) {
      expect(o['operation_type'], 'order.status');
      expect(o['target_entity'], 'order');
      expect(o['target_id'], 'o1');
      expect((o['payload'] as Map)['order_id'], 'o1');
    }
    // Stable, deterministic, one-per-target idempotency keys.
    expect(s.ops.map((o) => o['local_operation_id']).toList(), [
      'b1:o1:accepted',
      'b1:o1:preparing',
      'b1:o1:ready',
      'b1:o1:served',
    ]);
  });

  test('B: accepted->3, preparing->2, ready->1 ops', () async {
    for (final (from, count) in [
      ('accepted', 3),
      ('preparing', 2),
      ('ready', 1),
    ]) {
      final s = _FakeServer({'o': from});
      final r = await _repo(s).advanceToServed(
        orderId: 'o',
        fromStatus: from,
        batchRunId: 'b',
        refreshStatus: _neverRefresh,
      );
      expect(r.isFinished, isTrue, reason: from);
      expect(s.ops, hasLength(count), reason: from);
      expect(_newStatuses(s).last, 'served', reason: from);
    }
  });

  test('C: an ALREADY-resolved status is finished (not failed), zero ops; a '
      'draft is failed', () async {
    for (final resolved in ['served', 'completed', 'cancelled', 'voided']) {
      final s = _FakeServer({'o': resolved});
      final r = await _repo(s).advanceToServed(
        orderId: 'o',
        fromStatus: resolved,
        batchRunId: 'b',
        refreshStatus: _neverRefresh,
      );
      expect(
        r.isFinished,
        isTrue,
        reason: resolved,
      ); // off the board == finished
      expect(s.ops, isEmpty, reason: resolved);
    }
    final s = _FakeServer({'o': 'draft'});
    final r = await _repo(s).advanceToServed(
      orderId: 'o',
      fromStatus: 'draft',
      batchRunId: 'b',
      refreshStatus: _neverRefresh,
    );
    expect(r.isFinished, isFalse);
    expect(s.ops, isEmpty);
  });

  test('D: concurrent KDS advancement — a step the KDS already made comes back '
      'invalid_transition; the loop reclassifies from the server `from` and '
      'still reaches served', () async {
    // Captured as submitted, but the KDS pushed it to preparing first.
    final s = _FakeServer({'o1': 'preparing'});
    final r = await _repo(s).advanceToServed(
      orderId: 'o1',
      fromStatus: 'submitted',
      batchRunId: 'b1',
      refreshStatus: _neverRefresh,
    );
    expect(r.isFinished, isTrue);
    expect(s.status['o1'], 'served');
    // ->accepted (invalid: order was preparing), then ->ready, ->served (applied).
    expect(_newStatuses(s), ['accepted', 'ready', 'served']);
  });

  test('E: an order another device already carried to served resolves as '
      'FINISHED, not failed', () async {
    final s = _FakeServer({'o1': 'served'}); // captured ready, now served
    final r = await _repo(s).advanceToServed(
      orderId: 'o1',
      fromStatus: 'ready',
      batchRunId: 'b1',
      refreshStatus: _neverRefresh,
    );
    expect(r.isFinished, isTrue);
    expect(_newStatuses(s), ['served']); // one probe, then reclassified to done
  });

  test(
    'F: an order cancelled/voided concurrently resolves as FINISHED (off the '
    'board), never failed',
    () async {
      for (final terminal in ['cancelled', 'voided', 'completed']) {
        final s = _FakeServer({'o1': terminal}); // captured preparing
        final r = await _repo(s).advanceToServed(
          orderId: 'o1',
          fromStatus: 'preparing',
          batchRunId: 'b1',
          refreshStatus: _neverRefresh,
        );
        expect(r.isFinished, isTrue, reason: terminal);
        expect(_newStatuses(s), ['ready'], reason: terminal);
      }
    },
  );

  test(
    'G: a transient transport failure retries the SAME op id (idempotent) and '
    'still finishes',
    () async {
      final s = _FakeServer({'o': 'ready'})..transportThrows['b1:o:served'] = 1;
      final r = await _repo(s).advanceToServed(
        orderId: 'o',
        fromStatus: 'ready',
        batchRunId: 'b1',
        refreshStatus: _neverRefresh,
      );
      expect(r.isFinished, isTrue);
      // The same idempotency key was sent twice: throw, then the retry applied.
      final served = s.ops
          .where((o) => o['local_operation_id'] == 'b1:o:served')
          .toList();
      expect(served, hasLength(2));
    },
  );

  test(
    'G2: a serialization conflict re-reads the authoritative status; an order '
    'the winning txn carried to served is FINISHED',
    () async {
      final s = _FakeServer({'o': 'ready'})
        ..conflictOnce.add('b1:o:served')
        ..conflictAdvancesTo['b1:o:served'] = 'served';
      final r = await _repo(s).advanceToServed(
        orderId: 'o',
        fromStatus: 'ready',
        batchRunId: 'b1',
        refreshStatus: _serverRefresh(s),
      );
      expect(r.isFinished, isTrue);
    },
  );

  test(
    'a PAID order that auto-completes on served stops cleanly (finished)',
    () async {
      final s = _FakeServer({'o': 'ready'})..autoCompleteOps.add('b1:o:served');
      final r = await _repo(s).advanceToServed(
        orderId: 'o',
        fromStatus: 'ready',
        batchRunId: 'b1',
        refreshStatus: _neverRefresh,
      );
      expect(r.isFinished, isTrue);
      expect(s.ops, hasLength(1));
    },
  );

  test('a permission denial fails immediately (no retry helps)', () async {
    final s = _FakeServer({'o': 'ready'})..denyOps.add('b1:o:served');
    final r = await _repo(s).advanceToServed(
      orderId: 'o',
      fromStatus: 'ready',
      batchRunId: 'b1',
      refreshStatus: _neverRefresh,
    );
    expect(r.isFinished, isFalse);
    expect(r.error, 'permission_denied');
    expect(s.ops, hasLength(1));
  });

  test('a persistent transport outage fails after the bounded attempts '
      '(retryable, never a false success)', () async {
    final s = _FakeServer({'o': 'ready'})..transportThrows['b1:o:served'] = 999;
    final r = await _repo(s).advanceToServed(
      orderId: 'o',
      fromStatus: 'ready',
      batchRunId: 'b1',
      refreshStatus: _neverRefresh,
    );
    expect(r.isFinished, isFalse);
    // Bounded — it does not spin forever.
    expect(s.ops.length, lessThanOrEqualTo(12));
  });

  test('no session/transport => fails closed, sends nothing', () async {
    final r = await RealKitchenFinishRepository(null, null).advanceToServed(
      orderId: 'o',
      fromStatus: 'ready',
      batchRunId: 'b1',
      refreshStatus: _neverRefresh,
    );
    expect(r.isFinished, isFalse);
    expect(r.error, 'unavailable');
  });
}
