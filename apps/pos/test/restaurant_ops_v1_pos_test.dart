import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_center_view.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/table_move_repository.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// RESTAURANT-OPERATIONS-V1-001 — POS unit coverage for the pure seams:
/// move-table eligibility, the order-type filter + table-label search, the
/// type-aware wording inputs (the unified orderType getter + snapshot-first
/// table label), and the real move repository's wire/typed-refusal contract.
void main() {
  group('A. canMoveTable eligibility (central policy)', () {
    test('A1 an ACTIVE dine-in order with a server id can move', () {
      final actions = resolveOrderActions(_order(status: 'preparing'));
      expect(actions.canMoveTable, isTrue);
    });

    test('A2 a TAKEAWAY order can never move', () {
      final actions = resolveOrderActions(
        _order(status: 'preparing', orderType: 'takeaway'),
      );
      expect(actions.canMoveTable, isFalse);
    });

    test('A3 a TERMINAL order keeps its historical table', () {
      final actions = resolveOrderActions(_order(status: 'completed'));
      expect(actions.canMoveTable, isFalse);
    });

    test('A4 in-flight local work withholds the move', () {
      final actions = resolveOrderActions(
        _order(status: 'preparing'),
        pending: PosPendingKind.payment,
      );
      expect(actions.canMoveTable, isFalse);
    });

    test('A5 a local draft (no server order) offers nothing', () {
      final draft = PosRecentOrder(
        order: _view(),
        origin: PosOrderOrigin.localDraft,
      );
      expect(resolveOrderActions(draft).canMoveTable, isFalse);
    });
  });

  group('B. order-type filter + search (view model)', () {
    final rows = [
      _order(status: 'preparing', id: 'a1', table: 'T1'),
      _order(status: 'preparing', id: 'a2', orderType: 'takeaway'),
    ];

    test('B1 the type filter is EXACT', () {
      final dineIn = viewOrders(
        rows,
        section: PosOrderSection.open,
        type: PosOrderTypeFilter.dineIn,
      );
      final takeaway = viewOrders(
        rows,
        section: PosOrderSection.open,
        type: PosOrderTypeFilter.takeaway,
      );
      expect(dineIn.map((o) => o.orderId), ['a1']);
      expect(takeaway.map((o) => o.orderId), ['a2']);
    });

    test('B2 "All" keeps both', () {
      final all = viewOrders(rows, section: PosOrderSection.open);
      expect(all.length, 2);
    });

    test('B3 search matches the TABLE LABEL (a floor label is public)', () {
      final hit = viewOrders(rows, section: PosOrderSection.open, query: 't1');
      expect(hit.map((o) => o.orderId), ['a1']);
    });

    test('B4 search still matches the order code', () {
      final hit = viewOrders(
        rows,
        section: PosOrderSection.open,
        query: '#0000A2',
      );
      expect(hit.map((o) => o.orderId), ['a2']);
    });
  });

  group('C. the unified orderType + snapshot-first tableLabel', () {
    test('C1 the SERVER wire value wins over the order-time selection', () {
      // The order-time view says dine-in; the server snapshot says takeaway.
      // The server has spoken — the row is takeaway.
      final row = PosRecentOrder(
        order: _view(orderType: OrderType.dineIn),
        snapshot: _snapshot(id: 'x1', orderType: 'takeaway'),
      );
      expect(row.orderType, OrderType.takeaway);
    });

    test('C2 an unknown wire token falls back to the order-time view', () {
      final row = PosRecentOrder(
        order: _view(orderType: OrderType.dineIn),
        snapshot: _snapshot(id: 'x2', orderType: 'drive_through'),
      );
      expect(row.orderType, OrderType.dineIn);
    });

    test('C3 the SNAPSHOT table label wins (a move on another till shows)', () {
      final row = PosRecentOrder(
        order: _view(tableLabel: 'T1'),
        snapshot: _snapshot(id: 'x3', table: 'T4'),
      );
      expect(row.tableLabel, 'T4');
    });

    test(
      'C4 withServerSnapshot realigns the receipt view to the new table',
      () {
        final row = PosRecentOrder(order: _view(tableLabel: 'T1'));
        final moved = row.withServerSnapshot(_snapshot(id: 'x4', table: 'T7'));
        // The REPRINT reads the order-time view — after a move it must name the
        // CURRENT table (the lines/prices stay order-time, D-008).
        expect(moved.order!.tableLabel, 'T7');
      },
    );
  });

  group('D. RealMoveTableRepository — the wire + typed refusals', () {
    const session = SyncSession(pinSessionId: 'pin', deviceId: 'dev');

    test('D1 fail-closed without a session: no backend contact', () async {
      final t = _CapturingTransport(null);
      final repo = RealMoveTableRepository(t, null, const _Ids());
      await expectLater(
        repo.moveTable(orderId: 'o-1', tableId: 't-2', tableLabel: 'T2'),
        throwsA(isA<MoveTableException>()),
      );
      expect(t.calls, 0);
    });

    test(
      'D2 the op carries ONLY order_id + table_id + expected_revision',
      () async {
        final t = _CapturingTransport(
          _applied(<String, Object?>{'table_label': 'T2', 'revision': 3}),
        );
        final result = await RealMoveTableRepository(t, session, const _Ids())
            .moveTable(
              orderId: 'o-1',
              tableId: 't-2',
              tableLabel: 'T2',
              expectedRevision: 2,
            );
        expect(t.opType, 'order.table_move');
        expect(t.payload, <String, Object?>{
          'order_id': 'o-1',
          'table_id': 't-2',
          'expected_revision': 2,
        });
        expect(result.tableLabel, 'T2');
        expect(result.revision, 3);
        expect(result.noChange, isFalse);
      },
    );

    test(
      'D3 with NO known revision the key is OMITTED — never guessed',
      () async {
        final t = _CapturingTransport(
          _applied(<String, Object?>{'table_label': 'T2', 'revision': 5}),
        );
        await RealMoveTableRepository(
          t,
          session,
          const _Ids(),
        ).moveTable(orderId: 'o-1', tableId: 't-2', tableLabel: 'T2');
        expect(t.payload.containsKey('expected_revision'), isFalse);
      },
    );

    test('D4 each typed refusal maps to its EXACT flag', () async {
      Future<MoveTableException> refusal(Map<String, Object?> op) async {
        final t = _CapturingTransport(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{'local_operation_id': 'id-1', 'ok': false, ...op},
          ],
        });
        try {
          await RealMoveTableRepository(
            t,
            session,
            const _Ids(),
          ).moveTable(orderId: 'o-1', tableId: 't-2', tableLabel: 'T2');
          fail('expected a MoveTableException');
        } on MoveTableException catch (e) {
          return e;
        }
      }

      final conflict = await refusal({
        'status': 'conflict',
        'error': 'conflict',
      });
      expect(conflict.conflict, isTrue);

      final notMovable = await refusal({
        'status': 'rejected',
        'error': 'invalid_transition',
        'detail': 'order_not_movable',
      });
      expect(notMovable.notMovable, isTrue);

      final takeaway = await refusal({
        'status': 'rejected',
        'error': 'table_not_allowed',
        'detail': 'takeaway_order',
      });
      expect(takeaway.notAllowed, isTrue);

      final gone = await refusal({
        'status': 'rejected',
        'error': 'table_not_available',
      });
      expect(gone.tableUnavailable, isTrue);

      final denied = await refusal({
        'status': 'rejected',
        'error': 'permission_denied',
      });
      expect(denied.permissionDenied, isTrue);
    });

    test(
      'D5 a same-table no-op reports no_change + the unchanged revision',
      () async {
        final t = _CapturingTransport(
          _applied(<String, Object?>{
            'table_label': 'T2',
            'revision': 2,
            'no_change': true,
          }),
        );
        final result = await RealMoveTableRepository(
          t,
          session,
          const _Ids(),
        ).moveTable(orderId: 'o-1', tableId: 't-2', tableLabel: 'T2');
        expect(result.noChange, isTrue);
        expect(result.revision, 2);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// fixtures
// ---------------------------------------------------------------------------

SubmittedOrderView _view({
  OrderType orderType = OrderType.dineIn,
  String? tableLabel,
}) => SubmittedOrderView(
  orderNumber: '#LOCAL1',
  orderType: orderType,
  currencyCode: 'ILS',
  subtotalMinor: 2500,
  lines: const [],
  tableLabel: tableLabel,
  orderId: 'local-1',
  localOperationId: 'op-1',
);

PosOrderSnapshot _snapshot({
  required String id,
  String status = 'preparing',
  String orderType = 'dine_in',
  String? table,
}) => PosOrderSnapshot(
  orderId: id,
  orderCode: '#${id.toUpperCase().padLeft(6, '0')}',
  revision: 2,
  status: status,
  settlement: PosSettlement.unpaid,
  subtotalMinor: 2500,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 2500,
  createdAt: DateTime.utc(2026, 7, 14, 12),
  updatedAt: DateTime.utc(2026, 7, 14, 12),
  syncAt: DateTime.utc(2026, 7, 14, 12),
  orderType: orderType,
  tableLabel: table,
  currencyCode: 'ILS',
);

PosRecentOrder _order({
  required String status,
  String id = 'o-1',
  String orderType = 'dine_in',
  String? table,
}) => PosRecentOrder.discovered(
  _snapshot(id: id, status: status, orderType: orderType, table: table),
);

Map<String, Object?> _applied(Map<String, Object?> extra) => <String, Object?>{
  'results': <Object?>[
    <String, Object?>{
      'local_operation_id': 'id-1',
      'status': 'applied',
      'ok': true,
      ...extra,
    },
  ],
};

class _CapturingTransport implements SyncRpcTransport {
  _CapturingTransport(this._response);

  final Object? _response;
  int calls = 0;
  String? opType;
  Map<String, Object?> payload = <String, Object?>{};

  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> args) async {
    calls++;
    final ops = args['p_operations'] as List<dynamic>;
    final op = ops.single as Map<String, dynamic>;
    opType = op['operation_type'] as String?;
    payload = (op['payload'] as Map).cast<String, Object?>();
    return _response;
  }
}

class _Ids implements ClientIdGenerator {
  const _Ids();

  @override
  String newId() => 'id-1';
}
