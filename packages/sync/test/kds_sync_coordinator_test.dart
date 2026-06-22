import 'dart:async';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_sync/restoflow_sync.dart';
import 'package:test/test.dart';

/// A scripted transport: each `invoke` runs the next step (returns a decoded
/// envelope or throws a typed transport error). When the script is exhausted it
/// repeats the last step (so periodic ticks keep getting a stable response).
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport(this._steps);
  final List<Object? Function()> _steps;

  int calls = 0;
  final List<Map<String, dynamic>> paramsLog = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    paramsLog.add(params);
    final i = calls++;
    final step = i < _steps.length ? _steps[i] : _steps.last;
    return step();
  }
}

Map<String, dynamic> _env(
  Map<String, dynamic> changes, {
  String serverTs = '2026-06-22T10:00:00+00:00',
}) => {
  'ok': true,
  'server_ts': serverTs,
  'changes': changes,
  'operation_statuses': {
    'rows': <Map<String, dynamic>>[],
    'next_cursor': null,
    'has_more': false,
  },
};

Map<String, dynamic> _ordersPage(
  List<Map<String, dynamic>> rows, {
  Map<String, dynamic>? nextCursor,
  bool hasMore = false,
}) => {
  'orders': {'rows': rows, 'next_cursor': nextCursor, 'has_more': hasMore},
};

Object? Function() _throws(SyncTransportErrorKind kind, {String? code}) =>
    () => throw SyncTransportException(kind, code: code);

/// Drain microtasks/event-loop turns until [predicate] holds or [max] reached.
Future<void> _settleUntil(bool Function() predicate, {int max = 50}) async {
  for (var i = 0; i < max && !predicate(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

  KdsSyncCoordinator build(
    _ScriptedTransport transport, {
    StreamController<void>? ticks,
    Future<void> Function(Duration)? delay,
  }) {
    return KdsSyncCoordinator(
      api: SyncPullApi(transport),
      session: session,
      ticks: (ticks ?? StreamController<void>.broadcast()).stream,
      delay: delay,
      random: () => 1.0, // deterministic full-ceiling backoff
    );
  }

  test(
    'pulls on start and reaches data state (requests only kitchen entities)',
    () async {
      final transport = _ScriptedTransport([
        () => _env(
          _ordersPage([
            {'id': 'o1', 'status': 'preparing'},
          ]),
        ),
      ]);
      final c = build(transport);
      addTearDown(c.dispose);

      await c.start();

      expect(c.state.status, KdsSyncStatus.data);
      expect(c.state.rowsFor('orders').single['id'], 'o1');
      expect(transport.calls, 1);
      expect(transport.paramsLog.first['p_entities'], [
        'orders',
        'order_items',
        'order_item_modifiers',
      ]);
    },
  );

  test('advances cursors and drains has_more pages in one cycle', () async {
    final transport = _ScriptedTransport([
      () => _env(
        _ordersPage(
          [
            {'id': 'o1', 'status': 'preparing'},
            {'id': 'o2', 'status': 'ready'},
          ],
          nextCursor: {'updated_at': 't1', 'id': 'o2'},
          hasMore: true,
        ),
      ),
      () => _env(
        _ordersPage(
          [
            {'id': 'o3', 'status': 'preparing'},
          ],
          nextCursor: {'updated_at': 't2', 'id': 'o3'},
          hasMore: false,
        ),
      ),
    ]);
    final c = build(transport);
    addTearDown(c.dispose);

    await c.start();

    expect(transport.calls, 2, reason: 'has_more drained a second page');
    expect(c.state.rowsFor('orders').map((r) => r['id']).toList()..sort(), [
      'o1',
      'o2',
      'o3',
    ]);
    // The second request carried the first page's next_cursor.
    expect(transport.paramsLog[1]['p_cursors'], {
      'orders': {'updated_at': 't1', 'id': 'o2'},
    });
  });

  test(
    'stops draining when has_more is reported but the cursor does not advance',
    () async {
      // A misbehaving server returns has_more:true with the SAME valid cursor
      // forever. The no-progress guard must stop after detecting no advance,
      // NOT hammer the RPC up to the page cap.
      Map<String, dynamic> sameCursorPage() => _env(
        _ordersPage(
          [
            {'id': 'o1', 'status': 'preparing'},
          ],
          nextCursor: {'updated_at': 'tFIXED', 'id': 'oFIXED'},
          hasMore: true,
        ),
      );
      final transport = _ScriptedTransport([sameCursorPage]); // repeats forever
      final c = build(transport);
      addTearDown(c.dispose);

      await c.start();

      // First pull advances (null -> tFIXED); second sees the same cursor (no
      // progress) and stops. So exactly 2 calls, not 1000.
      expect(transport.calls, 2);
      expect(c.state.status, KdsSyncStatus.data);
    },
  );

  test('manual refresh performs another pull', () async {
    final transport = _ScriptedTransport([
      () => _env(
        _ordersPage([
          {'id': 'o1', 'status': 'preparing'},
        ]),
      ),
      () => _env(
        _ordersPage([
          {'id': 'o2', 'status': 'ready'},
        ]),
      ),
    ]);
    final c = build(transport);
    addTearDown(c.dispose);

    await c.start();
    expect(transport.calls, 1);
    await c.refresh();
    expect(transport.calls, 2);
    expect(c.state.rowsFor('orders').map((r) => r['id']).toSet(), {'o1', 'o2'});
  });

  test('a tombstone (deleted_at) removes the row locally', () async {
    final transport = _ScriptedTransport([
      () => _env(
        _ordersPage([
          {'id': 'o1', 'status': 'preparing'},
          {'id': 'o2', 'status': 'ready'},
        ]),
      ),
      () => _env(
        _ordersPage([
          {
            'id': 'o1',
            'status': 'voided',
            'deleted_at': '2026-06-22T11:00:00+00:00',
          },
        ]),
      ),
    ]);
    final c = build(transport);
    addTearDown(c.dispose);

    await c.start();
    expect(c.state.rowsFor('orders').length, 2);
    await c.refresh();
    expect(
      c.state.rowsFor('orders').map((r) => r['id']).toList(),
      ['o2'],
      reason: 'o1 tombstoned -> dropped; o2 remains',
    );
  });

  test('transient failure keeps last good data and emits offlineStale', () async {
    final observed = <KdsSyncStatus>[];
    final transport = _ScriptedTransport([
      () => _env(
        _ordersPage([
          {'id': 'o1', 'status': 'preparing'},
        ]),
      ),
      _throws(SyncTransportErrorKind.transient),
    ]);
    // delay never completes -> the backoff retry stays pending for the assertion.
    final c = build(transport, delay: (_) => Completer<void>().future);
    addTearDown(c.dispose);
    c.states.listen((s) => observed.add(s.status));

    await c.start(); // ok -> data (o1)
    await c.refresh(); // transient -> offlineStale, o1 retained
    await _settleUntil(() => observed.contains(KdsSyncStatus.offlineStale));

    expect(c.state.status, KdsSyncStatus.offlineStale);
    expect(
      c.state.rowsFor('orders').single['id'],
      'o1',
      reason: 'last successful data is kept on transient failure',
    );
    expect(observed, contains(KdsSyncStatus.offlineStale));
  });

  test('transient failures back off then recover to data', () async {
    final delays = <Duration>[];
    final transport = _ScriptedTransport([
      _throws(SyncTransportErrorKind.transient),
      _throws(SyncTransportErrorKind.transient),
      () => _env(
        _ordersPage([
          {'id': 'o9', 'status': 'ready'},
        ]),
      ),
    ]);
    final c = build(transport, delay: (d) async => delays.add(d));
    addTearDown(c.dispose);

    await c.start();
    await _settleUntil(() => c.state.status == KdsSyncStatus.data);

    expect(c.state.status, KdsSyncStatus.data);
    expect(c.state.rowsFor('orders').single['id'], 'o9');
    expect(
      delays,
      [const Duration(seconds: 2), const Duration(seconds: 4)],
      reason: 'two transient failures -> backoff 2s then 4s (full ceiling)',
    );
  });

  test(
    'reauthRequired (42501) stops polling and ignores further ticks',
    () async {
      final ticks = StreamController<void>.broadcast();
      final transport = _ScriptedTransport([
        () => _env(
          _ordersPage([
            {'id': 'o1', 'status': 'preparing'},
          ]),
        ),
        _throws(SyncTransportErrorKind.auth, code: '42501'),
      ]);
      final c = build(transport, ticks: ticks);
      addTearDown(c.dispose);
      addTearDown(ticks.close);

      await c.start(); // ok -> data
      expect(c.state.status, KdsSyncStatus.data);

      ticks.add(null); // tick -> 42501 -> reauthRequired + stop
      await _settleUntil(() => c.state.status == KdsSyncStatus.reauthRequired);
      expect(c.state.status, KdsSyncStatus.reauthRequired);
      final callsAtReauth = transport.calls;

      // Further ticks must NOT trigger any pull (polling stopped; no silent retry).
      ticks.add(null);
      ticks.add(null);
      await _settleUntil(() => false, max: 5);
      expect(transport.calls, callsAtReauth);
      expect(c.state.status, KdsSyncStatus.reauthRequired);

      // Manual refresh after reauth is also a no-op.
      await c.refresh();
      expect(transport.calls, callsAtReauth);
    },
  );

  test('timer ticks drive periodic pulls', () async {
    final ticks = StreamController<void>.broadcast();
    final transport = _ScriptedTransport([
      () => _env(
        _ordersPage([
          {'id': 'o1', 'status': 'preparing'},
        ]),
      ),
    ]);
    final c = build(transport, ticks: ticks);
    addTearDown(c.dispose);
    addTearDown(ticks.close);

    await c.start();
    expect(transport.calls, 1);

    ticks.add(null);
    await _settleUntil(() => transport.calls >= 2);
    expect(transport.calls, 2);

    ticks.add(null);
    await _settleUntil(() => transport.calls >= 3);
    expect(transport.calls, 3);
  });
}
