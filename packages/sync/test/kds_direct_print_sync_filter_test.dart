import 'dart:async';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_sync/restoflow_sync.dart';
import 'package:test/test.dart';

/// KITCHEN-PRINT-DUAL-001C (KDS-SYNC-FILTER) — the CLIENT half of the server
/// filter, driven through the REAL KdsSyncCoordinator + SyncPullApi.
///
/// The authoritative fix is server-side (app.sync_pull drops the direct_print
/// order graph for a KDS device — proven in pgTAP). This proves the KDS pull
/// engine consumes the resulting feed correctly:
///   * a page the server filtered to ZERO visible rows still ADVANCES + COMMITS
///     the cursor (no replay, no stall) and puts NOTHING into local _rows;
///   * a normal order that follows such a filtered page is DELIVERED, and the
///     next request carries the advanced cursor (never re-scans the filtered run).
/// Local "storage" is the coordinator's in-memory _rows (RF-063 A3, no Drift).
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport(this._steps);
  final List<Object? Function()> _steps;
  int calls = 0;
  final List<Map<String, dynamic>> paramsLog = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    paramsLog.add(params);
    final i = calls++;
    return (i < _steps.length ? _steps[i] : _steps.last)();
  }
}

Map<String, dynamic> _env(Map<String, dynamic> changes) => {
  'ok': true,
  'server_ts': '2026-07-22T10:00:00+00:00',
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

void main() {
  const session = SyncSession(pinSessionId: 'pin-1', deviceId: 'kds-dev-1');

  KdsSyncCoordinator build(_ScriptedTransport transport) => KdsSyncCoordinator(
    api: SyncPullApi(transport),
    session: session,
    ticks: StreamController<void>.broadcast().stream,
    random: () => 1.0,
  );

  test('a server-filtered page (zero visible order rows) stores NOTHING yet '
      'advances + commits the cursor', () async {
    // The server examined a page that was entirely direct_print and returned
    // an EMPTY visible page whose next_cursor points PAST those rows.
    final transport = _ScriptedTransport([
      () => _env(
        _ordersPage(
          const [],
          nextCursor: {'updated_at': 't-dp', 'id': 'dp-2'},
          hasMore: false,
        ),
      ),
    ]);
    final c = build(transport);
    addTearDown(c.dispose);

    await c.start();

    // Nothing direct_print (indeed nothing at all) entered local storage.
    expect(c.state.rowsFor('orders'), isEmpty);
    // The cursor was COMMITTED even though the visible page was empty — a
    // follow-up pull resumes from PAST the filtered rows (no replay/stall).
    await c.refresh();
    expect(transport.paramsLog.last['p_cursors'], {
      'orders': {'updated_at': 't-dp', 'id': 'dp-2'},
    });
  });

  test('a normal kds order after a filtered (empty) page is delivered, and the '
      'second request carries the advanced cursor', () async {
    final transport = _ScriptedTransport([
      // Page 1: the server filtered every row out, but reports more + a cursor.
      () => _env(
        _ordersPage(
          const [],
          nextCursor: {'updated_at': 't-dp', 'id': 'dp-2'},
          hasMore: true,
        ),
      ),
      // Page 2: the normal kds order beyond the filtered run.
      () => _env(
        _ordersPage(
          [
            {'id': 'o-kds', 'status': 'preparing'},
          ],
          nextCursor: {'updated_at': 't-kds', 'id': 'o-kds'},
          hasMore: false,
        ),
      ),
    ]);
    final c = build(transport);
    addTearDown(c.dispose);

    await c.start();

    // The drain crossed the empty filtered page and delivered the normal order.
    expect(transport.calls, 2, reason: 'drained past the filtered page');
    expect(c.state.rowsFor('orders').single['id'], 'o-kds');
    // Page 2's request carried page 1's advanced cursor — the filtered run is
    // never re-examined by the KDS again.
    expect(transport.paramsLog[1]['p_cursors'], {
      'orders': {'updated_at': 't-dp', 'id': 'dp-2'},
    });
  });
}
