import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'demo_order_snapshots.dart';
import 'ids.dart';

/// A failure to move an order to another table. Each flag is set ONLY by the
/// server's EXACT stable domain code — never by a raw message, never by a
/// SQLSTATE, and never inferred from anything local. An unflagged
/// [MoveTableException] means exactly one thing: "we do not know why this
/// failed", and the UI must say so generically.
///
///   * [permissionDenied]  — `permission_denied`: the role gate refused
///                           (kitchen/accountant sessions may not move tables).
///   * [notMovable]        — `invalid_transition` + detail `order_not_movable`:
///                           the order is TERMINAL; its historical table stays.
///   * [notAllowed]        — `table_not_allowed` + detail `takeaway_order`:
///                           takeaway orders never sit at a table. The central
///                           eligibility policy never offers the action, so
///                           reaching this means our row was stale.
///   * [tableUnavailable]  — `table_not_available`: the TARGET stopped being a
///                           live, active table of this branch. The cashier may
///                           deliberately pick another from a refreshed list.
///   * [conflict]          — `conflict`: the order changed under us (stale
///                           revision). Reconcile; never blindly retry.
///   * [transport]         — the request never got a verdict. RETRYABLE; the
///                           order's true state is UNKNOWN.
class MoveTableException implements Exception {
  const MoveTableException(
    this.message, {
    this.permissionDenied = false,
    this.notMovable = false,
    this.notAllowed = false,
    this.tableUnavailable = false,
    this.conflict = false,
    this.transport = false,
  });

  final String message;
  final bool permissionDenied;
  final bool notMovable;
  final bool notAllowed;
  final bool tableUnavailable;
  final bool conflict;
  final bool transport;

  @override
  String toString() => 'MoveTableException: $message';
}

/// The successful outcome: the authoritative table label + revision the server
/// confirmed (and whether it was a same-table no-op).
class MoveTableResult {
  const MoveTableResult({
    required this.tableLabel,
    required this.revision,
    this.noChange = false,
  });

  final String tableLabel;
  final int revision;
  final bool noChange;
}

/// RESTAURANT-OPERATIONS-V1-001: the order table-move seam. [moveTable] maps
/// 1:1 to the `order.table_move` sync_push op -> `app.move_order_table`: an
/// ATOMIC, server-authoritative move of an ACTIVE dine-in order to a live
/// table of the SAME branch. MONEY-FREE: only `orders.table_id` + `revision`
/// change; the revision bump is what makes every other surface (POS snapshot
/// feed, KDS pull) converge on the new table by itself.
abstract class MoveTableRepository {
  /// Moves [orderId] onto [tableId]; returns the confirmed label + revision on
  /// success, throws [MoveTableException] on any failure.
  Future<MoveTableResult> moveTable({
    required String orderId,
    required String tableId,
    required String tableLabel,
    int? expectedRevision,
  });
}

/// In-memory, clearly-labelled DEMO move store. Succeeds locally and — when
/// given the demo snapshot repository — upserts the moved order's snapshot
/// (new table label, revision+1) so the demo Orders Centre reflects the move
/// through the SAME targeted-refresh path the real app uses. No backend.
class DemoMoveTableStore implements MoveTableRepository {
  const DemoMoveTableStore(this._snapshots);

  final DemoOrderSnapshotRepository? _snapshots;

  @override
  Future<MoveTableResult> moveTable({
    required String orderId,
    required String tableId,
    required String tableLabel,
    int? expectedRevision,
  }) async {
    final revision = (expectedRevision ?? 1) + 1;
    _snapshots?.recordTableMove(
      orderId: orderId,
      tableLabel: tableLabel,
      revision: revision,
    );
    return MoveTableResult(tableLabel: tableLabel, revision: revision);
  }
}

/// REAL table-move repository. Delivers an `order.table_move` op to the RF-126
/// `public.sync_push` wrapper (dispatched server-side to
/// `app.move_order_table`), reusing the SAME shared transport + PIN/device
/// session as the void/discount/payment paths. FAIL-CLOSED: with no session/
/// transport or no order id, every call throws — no backend contact, no fake
/// local success. A non-`applied` result throws; the honest server refusals
/// surface typed.
class RealMoveTableRepository implements MoveTableRepository {
  const RealMoveTableRepository(this._transport, this._session, this._ids);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final ClientIdGenerator _ids;

  @override
  Future<MoveTableResult> moveTable({
    required String orderId,
    required String tableId,
    required String tableLabel,
    int? expectedRevision,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const MoveTableException(
        'real move unavailable: an authenticated PIN session on a paired, '
        'active device is required - failing closed, no order is moved.',
      );
    }
    if (orderId.trim().isEmpty || tableId.trim().isEmpty) {
      throw const MoveTableException(
        'real move unavailable: the order/table id is missing - failing '
        'closed, no order is moved.',
      );
    }

    // A fresh idempotency key per attempt. app.move_order_table is ORDER-BOUND
    // idempotent server-side; the sheet's double-tap guard stops concurrent
    // duplicates, and a same-table retry is an explicit ok/no_change.
    final localOperationId = _ids.newId();
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': 'order.table_move',
      'target_entity': 'order',
      'target_id': orderId,
      'client_created_at': DateTime.now().toIso8601String(),
      // The server derives actor/org/branch from the PIN session; the client
      // sends ONLY the order + the target table. No money, no labels.
      'payload': <String, dynamic>{
        'order_id': orderId,
        'table_id': tableId,
        if (expectedRevision != null) 'expected_revision': expectedRevision,
      },
    };

    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[op],
      });
    } on SyncTransportException catch (e) {
      // TRANSPORT: the request never reached a verdict; the order's true state
      // is UNKNOWN. Never presented as any of the typed refusals.
      throw MoveTableException(
        'move failed: ${e.code ?? e.kind.name}',
        transport: true,
      );
    }

    return _checkMoveResult(raw: raw, localOperationId: localOperationId);
  }

  /// FAIL-CLOSED per-op result check. Only an `applied` result succeeds; the
  /// typed server refusals throw their exact flags; anything else (malformed /
  /// missing / rejected) throws a generic [MoveTableException].
  MoveTableResult _checkMoveResult({
    required Object? raw,
    required String localOperationId,
  }) {
    if (raw is! Map) {
      throw const MoveTableException('move rejected: malformed_response');
    }
    final results = raw['results'];
    if (results is! List || results.isEmpty) {
      throw const MoveTableException('move rejected: missing_results');
    }

    Map<String, dynamic>? op;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        op = r.cast<String, dynamic>();
        break;
      }
    }
    if (op == null) {
      throw const MoveTableException('move rejected: no_matching_operation');
    }

    final status = op['status'];
    if (status != 'applied' || op['ok'] == false) {
      final error = op['error'];
      final detail = op['detail'];
      if (error == 'permission_denied') {
        throw const MoveTableException(
          'permission_denied',
          permissionDenied: true,
        );
      }
      if (error == 'invalid_transition' && detail == 'order_not_movable') {
        throw const MoveTableException('order_not_movable', notMovable: true);
      }
      if (error == 'table_not_allowed') {
        throw const MoveTableException('takeaway_order', notAllowed: true);
      }
      if (error == 'table_not_available') {
        throw const MoveTableException(
          'table_not_available',
          tableUnavailable: true,
        );
      }
      if (error == 'conflict') {
        throw const MoveTableException('conflict', conflict: true);
      }
      throw MoveTableException(
        'move rejected: ${error is String ? error : (status is String ? status : 'unknown')}',
      );
    }

    // applied + ok:true -> the server confirmed the move (or the no_change
    // no-op). The label/revision it returns are AUTHORITATIVE.
    final label = op['table_label'];
    final revision = op['revision'];
    return MoveTableResult(
      tableLabel: label is String ? label : '',
      revision: revision is int ? revision : 0,
      noChange: op['no_change'] == true,
    );
  }
}
