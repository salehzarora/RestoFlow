/// PAYMENT-ATTEMPT-RECOVERY-001 — a CONTRACT-FAITHFUL, STATEFUL `sync_push`
/// server fake for the `payment.create` operation.
///
/// THIS IS A FAKE, NOT THE DATABASE. It models the FINAL source contract of
/// `app.sync_push` (supabase/migrations/20260905090001_sync_push_precondition_
/// detail_002.sql) and `app.record_payment` (supabase/migrations/
/// 20260716090000_settlement_and_void_error_contracts.sql) as read from source:
///
///   * per-device idempotency ledger keyed (device_id, local_operation_id);
///   * a payload FINGERPRINT (`payment.create` is one of the 12 prior ops:
///     `md5(op_type || '|' || payload::text)` — target_id and client_created_at
///     are NOT part of it);
///   * a same-key push REPLAYS the stored result whatever its status
///     (`applied`, `rejected`, `conflict`) with `idempotency_replay = true`;
///   * a same-key push with a DIFFERENT fingerprint answers
///     `{error: conflict, detail: 'idempotency key already used for a different
///     operation/payload', status: conflict}` and leaves the stored row intact;
///   * `record_payment` refusals: RAISED ones become `{error: rejected,
///     sqlstate, detail: precondition_failed|revoked_employee|null}`; RETURNED
///     ones (`permission_denied`, `order_not_chargeable`) pass through verbatim
///     with status `rejected`; SQLSTATE 40001 (revision conflict) becomes
///     `{error: conflict, sqlstate: '40001', status: conflict}`;
///   * a batch-level (preamble) raise rolls the WHOLE transaction back — nothing
///     is memoized and the transport surfaces a `SyncTransportException`;
///   * at most one completed payment per order (a second key is REJECTED, not
///     replayed).
///
/// On top of the contract it scripts TRANSPORT faults the real world produces:
/// a response lost AFTER the commit, a failure BEFORE the request reaches the
/// server, a HELD (late) response, and malformed / mismatched envelopes.
///
/// Role-accurate PostgreSQL/PostgREST proof is a SEPARATE approved evidence
/// gate; nothing here claims it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncTransportErrorKind, SyncTransportException;

/// One server-side order the fake knows about.
class FakeServerOrder {
  FakeServerOrder({
    required this.orderId,
    required this.grandTotalMinor,
    this.revision = 1,
    this.status = 'submitted',
  });

  final String orderId;
  int grandTotalMinor;
  int revision;
  String status;

  /// The completed payment id once settled (by ANY device), else null.
  String? paymentId;

  /// The device that settled it, else null.
  String? paidByDevice;

  bool get isPaid => paymentId != null;
}

class _LedgerRow {
  _LedgerRow({
    required this.fingerprint,
    required this.status,
    required this.result,
  });

  final String fingerprint;
  final String status;
  final Map<String, dynamic> result;
}

/// One recorded push (deep-copied so later mutation cannot rewrite history).
class RecordedPush {
  RecordedPush({
    required this.pinSessionId,
    required this.deviceId,
    required this.ops,
  });

  final String pinSessionId;
  final String deviceId;
  final List<Map<String, dynamic>> ops;
}

/// A scripted fault for the NEXT push (consumed once).
enum ServerFault {
  /// The request never reaches the server (socket dies first).
  failBeforeExecute,

  /// The server executes AND commits, then the response is lost.
  dropResponseAfterCommit,

  /// The server executes and commits, then the response is HELD until
  /// [PaymentAttemptServerFake.releaseHeld] is called (a late response).
  holdResponseAfterCommit,

  /// The request is held BEFORE execution until [releaseHeld] (a late commit).
  holdBeforeExecute,

  /// The server answers with an envelope that has no `results`.
  malformedEnvelope,

  /// The server answers with a result for a DIFFERENT local_operation_id.
  mismatchedResult,

  /// The gateway answers 504 (the request MAY have committed — modelled as
  /// committed, response lost, code '504').
  gatewayTimeoutAfterCommit,

  /// The batch preamble RAISES a non-session 42501 (a rolled-back
  /// transaction: nothing executed, nothing memoized).
  raiseBatch42501,
}

class PaymentAttemptServerFake implements SyncRpcTransport {
  PaymentAttemptServerFake({
    Iterable<FakeServerOrder> orders = const [],
    Iterable<String> devicesWithOpenShift = const [],
  }) : shiftOpenDevices = devicesWithOpenShift.toSet() {
    for (final o in orders) {
      this.orders[o.orderId] = o;
    }
  }

  final Map<String, FakeServerOrder> orders = <String, FakeServerOrder>{};

  /// Devices that hold an OPEN shift + active drawer (record_payment's
  /// `precondition_failed` otherwise).
  final Set<String> shiftOpenDevices;

  /// PIN sessions the preamble refuses (session-class 42501 → batch rollback).
  final Set<String> invalidPinSessions = <String>{};

  /// PIN sessions whose actor role is NOT cashier+ (typed `permission_denied`).
  final Set<String> deniedPinSessions = <String>{};

  final Map<String, _LedgerRow> _ledger = <String, _LedgerRow>{};

  /// The `operation_statuses` feed rows, in (updated_at, id) order: one per
  /// ledger row this device pushed, plus [ledgerNoise] filler rows (other
  /// operation types) so a scan can be made to exceed the client's page cap.
  final List<Map<String, dynamic>> _feed = <Map<String, dynamic>>[];
  int _feedSeq = 0;

  /// When set, every ledger row is REPORTED to `sync_pull` with this status
  /// word (e.g. `in_flight`) — modelling a row the server has not decided.
  String? ledgerStatusOverride;

  /// Filler rows injected AHEAD of any payment row in the feed.
  int ledgerNoise = 0;

  Map<String, dynamic> _feedRow({
    required String localOp,
    required String type,
    required String status,
    Map<String, dynamic>? result,
    required String device,
    String? targetId,
  }) {
    _feedSeq++;
    final at = DateTime.utc(
      2026,
      9,
      8,
      11,
    ).add(Duration(seconds: _feedSeq)).toIso8601String();
    return <String, dynamic>{
      'id': 'so-${_feedSeq.toString().padLeft(8, '0')}',
      'local_operation_id': localOp,
      'operation_type': type,
      'target_entity': type == 'payment.create' ? 'payment' : 'order',
      // The final `sync_push` stores the pushed `target_id` on the ledger row
      // and the operation-status feed projects it, so the fake does too.
      'target_id': targetId,
      'status': status,
      'result': result,
      'last_error_code': null,
      'last_error_class': null,
      'conflict_info': null,
      'rejection_reason': null,
      'retry_count': 0,
      'updated_at': at,
      'applied_at': status == 'applied' ? at : null,
      'server_received_at': at,
      '_device': device,
    };
  }

  /// `sync_pull` with `p_entities: ['operation_statuses']` — this org + this
  /// device only, keyset-paged by (updated_at, id) exactly like the final SQL.
  Object? _syncPull(Map<String, dynamic> params) {
    final device = params['p_device_id']?.toString() ?? '';
    final entities = params['p_entities'];
    final includeOps =
        entities == null ||
        (entities is List && entities.contains('operation_statuses'));
    final limit = (params['p_limit'] as int?) ?? 500;
    if (limit < 1 || limit > 1000) {
      throw const SyncTransportException(
        SyncTransportErrorKind.server,
        code: '42501',
        message: 'sync_pull: p_limit must be between 1 and 1000',
      );
    }
    if (ledgerNoise > 0 && _feed.where((r) => r['_noise'] == true).isEmpty) {
      for (var i = 0; i < ledgerNoise; i++) {
        _feed.add(
          _feedRow(
            localOp: 'noise-$i',
            type: 'order.status',
            status: 'applied',
            device: device,
          )..['_noise'] = true,
        );
      }
    }
    Map<String, dynamic> ops;
    if (!includeOps) {
      ops = {'rows': <dynamic>[], 'next_cursor': null, 'has_more': false};
    } else {
      final cursors = params['p_cursors'];
      final cur = cursors is Map ? cursors['operation_statuses'] : null;
      final cUat = cur is Map ? cur['updated_at']?.toString() : null;
      final cId = cur is Map ? cur['id']?.toString() : null;
      final rows =
          _feed.where((r) => r['_device'] == device).where((r) {
            if (cUat == null) return true;
            final uat = r['updated_at'] as String;
            final cmp = uat.compareTo(cUat);
            if (cmp > 0) return true;
            if (cmp == 0 && cId != null) {
              return (r['id'] as String).compareTo(cId) > 0;
            }
            return false;
          }).toList()..sort((x, y) {
            final c = (x['updated_at'] as String).compareTo(
              y['updated_at'] as String,
            );
            return c != 0
                ? c
                : (x['id'] as String).compareTo(y['id'] as String);
          });
      final page = rows.take(limit).toList();
      final hasMore = rows.length > limit;
      ops = {
        'rows': [
          for (final r in page)
            {
              for (final e in r.entries)
                if (!e.key.startsWith('_'))
                  e.key: e.key == 'status' && r['_noise'] != true
                      ? (ledgerStatusOverride ?? e.value)
                      : e.value,
            },
        ],
        'next_cursor': page.isEmpty
            ? null
            : {'updated_at': page.last['updated_at'], 'id': page.last['id']},
        'has_more': hasMore,
      };
    }
    return <String, dynamic>{
      'ok': true,
      'server_ts': '2026-09-08T12:00:00Z',
      'changes': <String, dynamic>{},
      'operation_statuses': ops,
    };
  }

  /// Every push that REACHED the server, in order (faults that fail before
  /// execution are NOT recorded here — the server never saw them).
  final List<RecordedPush> pushes = <RecordedPush>[];

  /// Every push ATTEMPTED by the client, including the ones that never arrived.
  final List<RecordedPush> attemptedPushes = <RecordedPush>[];

  int executions = 0;
  int replays = 0;
  int _paymentSeq = 0;

  ServerFault? _nextFault;
  Completer<void>? _held;

  /// Scripts [fault] for the next `sync_push` only.
  void faultNext(ServerFault fault) => _nextFault = fault;

  bool get isHolding => _held != null && !_held!.isCompleted;

  /// Releases a held response / held execution.
  void releaseHeld() {
    final h = _held;
    if (h != null && !h.isCompleted) h.complete();
  }

  /// Distinct payment.create local_operation_ids the server has SEEN from
  /// [deviceId].
  Set<String> paymentOpIdsFrom(String deviceId) => {
    for (final p in pushes)
      if (p.deviceId == deviceId)
        for (final op in p.ops)
          if (op['operation_type'] == 'payment.create')
            op['local_operation_id'] as String,
  };

  /// All payment.create ops the server has SEEN, in arrival order.
  List<Map<String, dynamic>> get paymentOpsSeen => [
    for (final p in pushes)
      for (final op in p.ops)
        if (op['operation_type'] == 'payment.create') op,
  ];

  int completedPaymentsFor(String orderId) =>
      orders[orderId]?.isPaid == true ? 1 : 0;

  /// The memoized status for (device, localOperationId), or null.
  String? ledgerStatus(String deviceId, String localOperationId) =>
      _ledger['$deviceId/$localOperationId']?.status;

  static String _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '"$k":${_canonical(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(_canonical).join(',')}]';
    return jsonEncode(v);
  }

  static List<Map<String, dynamic>> _deepCopyOps(List raw) => [
    for (final op in raw) jsonDecode(jsonEncode(op)) as Map<String, dynamic>,
  ];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'sync_pull') return _syncPull(params);
    if (function != 'sync_push') {
      throw StateError('PaymentAttemptServerFake serves sync_push/sync_pull');
    }
    final pin = params['p_pin_session_id']?.toString() ?? '';
    final device = params['p_device_id']?.toString() ?? '';
    final rawOps = params['p_operations'];
    if (rawOps is! List) {
      throw const SyncTransportException(
        SyncTransportErrorKind.server,
        code: '42501',
        message: 'sync_push: p_operations must be a JSON array',
      );
    }
    final ops = _deepCopyOps(rawOps);
    final recorded = RecordedPush(
      pinSessionId: pin,
      deviceId: device,
      ops: ops,
    );
    attemptedPushes.add(recorded);

    final fault = _nextFault;
    _nextFault = null;

    if (fault == ServerFault.failBeforeExecute) {
      throw const SyncTransportException(
        SyncTransportErrorKind.transient,
        message: 'SocketException: connection reset before request was sent',
      );
    }
    if (fault == ServerFault.holdBeforeExecute) {
      final c = _held = Completer<void>();
      await c.future;
    }
    if (fault == ServerFault.raiseBatch42501) {
      throw const SyncTransportException(
        SyncTransportErrorKind.server,
        code: '42501',
        message: 'sync_push: p_operations must be a JSON array',
      );
    }

    // ---- batch preamble (whole-transaction rollback on refusal) ----
    if (invalidPinSessions.contains(pin)) {
      throw const SyncTransportException(
        SyncTransportErrorKind.auth,
        code: '42501',
        message: 'sync_push: PIN session is not valid (inactive/ended/expired)',
      );
    }

    pushes.add(recorded);
    final results = <Map<String, dynamic>>[];
    for (final op in ops) {
      results.add(_applyOp(op, pin: pin, device: device));
    }
    final envelope = <String, dynamic>{
      'ok': true,
      'results': results,
      'server_ts': '2026-09-08T09:00:00Z',
    };

    switch (fault) {
      case ServerFault.dropResponseAfterCommit:
        throw const SyncTransportException(
          SyncTransportErrorKind.transient,
          message: 'TimeoutException after 0:00:15.000000: response lost',
        );
      case ServerFault.gatewayTimeoutAfterCommit:
        throw const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '504',
          message: 'gateway timeout',
        );
      case ServerFault.holdResponseAfterCommit:
        final c = _held = Completer<void>();
        await c.future;
        return envelope;
      // CHANGED IN S1-R5: both fault envelopes now carry a real `server_ts`.
      // The stamp is not the defect either fault is injecting — one omits
      // `results`, the other answers for a different operation — and a
      // placeholder would make the new envelope-shape rule answer first,
      // masking the exact contradiction each case exists to prove.
      case ServerFault.malformedEnvelope:
        return <String, dynamic>{
          'ok': true,
          'server_ts': '2026-09-08T09:00:00.000Z',
        };
      case ServerFault.mismatchedResult:
        return <String, dynamic>{
          'ok': true,
          'results': <Map<String, dynamic>>[
            {...results.first, 'local_operation_id': 'someone-elses-op'},
          ],
          'server_ts': '2026-09-08T09:00:00.000Z',
        };
      case ServerFault.failBeforeExecute:
      case ServerFault.holdBeforeExecute:
      case ServerFault.raiseBatch42501:
      case null:
        return envelope;
    }
  }

  Map<String, dynamic> _applyOp(
    Map<String, dynamic> op, {
    required String pin,
    required String device,
  }) {
    final localOp = op['local_operation_id']?.toString();
    final type = op['operation_type']?.toString();
    if (localOp == null || localOp.isEmpty) {
      return {
        'local_operation_id': localOp,
        'ok': false,
        'error': 'invalid_payload',
        'detail': 'local_operation_id is required',
        'status': 'rejected',
        'idempotency_replay': false,
      };
    }
    if (type != 'payment.create') {
      // Everything else (the sign-in's best-effort shift.open etc.) is blandly
      // applied; it is not the seam under test.
      return {
        'local_operation_id': localOp,
        'operation_type': type,
        'ok': true,
        'status': 'applied',
        'idempotency_replay': false,
      };
    }
    final payload = op['payload'];
    if (payload is! Map) {
      return {
        'local_operation_id': localOp,
        'operation_type': type,
        'ok': false,
        'error': 'invalid_payload',
        'detail': 'payload must be a JSON object',
        'status': 'rejected',
        'idempotency_replay': false,
      };
    }
    final fingerprint = 'payment.create|${_canonical(payload)}';
    final key = '$device/$localOp';

    final existing = _ledger[key];
    if (existing != null) {
      if (existing.fingerprint != fingerprint) {
        return {
          'local_operation_id': localOp,
          'operation_type': type,
          'ok': false,
          'error': 'conflict',
          'detail':
              'idempotency key already used for a different operation/payload',
          'status': 'conflict',
          'idempotency_replay': false,
        };
      }
      replays++;
      return {
        ...existing.result,
        'local_operation_id': localOp,
        'operation_type': type,
        'status': existing.status,
        'idempotency_replay': true,
      };
    }

    executions++;
    final outcome = _recordPayment(
      payload.cast<String, dynamic>(),
      localOp: localOp,
      pin: pin,
      device: device,
    );
    _ledger[key] = _LedgerRow(
      fingerprint: fingerprint,
      status: outcome.status,
      result: outcome.result,
    );
    _feed.add(
      _feedRow(
        localOp: localOp,
        type: 'payment.create',
        status: outcome.status,
        result: outcome.result,
        device: device,
        targetId: op['target_id']?.toString(),
      ),
    );
    return {
      ...outcome.result,
      'local_operation_id': localOp,
      'operation_type': type,
      'status': outcome.status,
      'idempotency_replay': false,
    };
  }

  ({String status, Map<String, dynamic> result}) _rejected(
    String sqlstate, {
    String? detail,
  }) => (
    status: 'rejected',
    result: <String, dynamic>{
      'ok': false,
      'error': 'rejected',
      'sqlstate': sqlstate,
      'detail': detail,
    },
  );

  ({String status, Map<String, dynamic> result}) _recordPayment(
    Map<String, dynamic> payload, {
    required String localOp,
    required String pin,
    required String device,
  }) {
    final orderId = payload['order_id']?.toString() ?? '';
    final order = orders[orderId];
    if (order == null) return _rejected('42501'); // order not found
    if (deniedPinSessions.contains(pin)) {
      return (
        status: 'rejected',
        result: <String, dynamic>{
          'ok': false,
          'error': 'permission_denied',
          'order_id': orderId,
          // CHANGED IN S1-R5: `record_payment` returns this refusal with its
          // own `server_ts` beside the order binding
          // (20260716090000_..._contracts.sql:187-188), and sync_push merges
          // the tuple through verbatim.
          'server_ts': '2026-09-09T15:00:00.000Z',
          'idempotency_replay': false,
        },
      );
    }
    final tender = payload['tender_type']?.toString();
    if (tender == null ||
        !const {'cash', 'card', 'bit', 'external'}.contains(tender)) {
      return _rejected('42501');
    }
    final tendered = payload['amount_tendered_minor'];
    if (tendered is! int || tendered < 0) return _rejected('42501');
    if (!const {
      'submitted',
      'accepted',
      'preparing',
      'ready',
      'served',
    }.contains(order.status)) {
      return _rejected('42501'); // not a legal payment source state
    }
    if (order.grandTotalMinor <= 0) {
      return (
        status: 'rejected',
        result: <String, dynamic>{
          'ok': false,
          'error': 'order_not_chargeable',
          'order_id': orderId,
          // CHANGED IN S1-R5: as above — this refusal is RETURNED with
          // `order_id` and `server_ts` together
          // (20260716090000_..._contracts.sql:256-258).
          'server_ts': '2026-09-09T15:00:00.000Z',
        },
      );
    }
    if (!shiftOpenDevices.contains(device)) {
      return _rejected('42501', detail: 'precondition_failed');
    }
    if (order.isPaid) return _rejected('42501'); // already completed payment
    final expected = payload['expected_revision'];
    if (expected is int && expected != order.revision) {
      return (
        status: 'conflict',
        result: <String, dynamic>{
          'ok': false,
          'error': 'conflict',
          'sqlstate': '40001',
        },
      );
    }
    final int effectiveTendered;
    final int change;
    if (tender == 'cash') {
      if (tendered < order.grandTotalMinor) return _rejected('42501');
      effectiveTendered = tendered;
      change = tendered - order.grandTotalMinor;
    } else {
      effectiveTendered = order.grandTotalMinor;
      change = 0;
    }
    _paymentSeq++;
    final paymentId = 'srv-pay-$_paymentSeq';
    order.paymentId = paymentId;
    order.paidByDevice = device;
    final autoCompleted = order.status == 'served';
    if (autoCompleted) {
      order.status = 'completed';
      order.revision += 1;
    }
    return (
      status: 'applied',
      result: <String, dynamic>{
        'ok': true,
        'payment_id': paymentId,
        'order_id': orderId,
        'method': tender,
        'receipt_number': 'R-$_paymentSeq',
        'change_due_minor': change,
        'amount_tendered_minor': effectiveTendered,
        'shift_id': 'shift-$device',
        'cash_drawer_session_id': 'drawer-$device',
        'payment_revision': 1,
        'order_revision': order.revision,
        'auto_completed': autoCompleted,
        'order_status': order.status,
        // S1-R4 / F002: `app.record_payment` closes with
        // `v_result || jsonb_build_object('server_ts', now(), ...)`
        // (20260716090000_..._contracts.sql:411), so a faithful applied result
        // carries the server stamp. The fake emits it too.
        'server_ts': '2026-09-09T15:00:0$_paymentSeq.000Z',
      },
    );
  }
}
