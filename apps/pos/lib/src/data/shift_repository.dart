import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'ids.dart';

/// The current open shift as read back from the server (RF-113 recovery). Lets
/// the close/reconcile UI recover its handle after a browser refresh / re-sign-in
/// where the in-memory handle was lost but a server shift is still open. Money is
/// integer minor units (DECISION D-007).
class OpenShiftInfo {
  const OpenShiftInfo({
    required this.shiftId,
    required this.cashDrawerSessionId,
    required this.openingFloatMinor,
    required this.openedAt,
    this.expectedCashMinor,
    this.canClose = true,
    this.ownerMismatch = false,
    this.closeNotAllowed = false,
    this.openedByEmployeeProfileId,
  });

  final String shiftId;
  final String cashDrawerSessionId;
  final int openingFloatMinor;
  final DateTime openedAt;

  /// The SERVER-authoritative expected cash (opening float + completed cash
  /// payments on the drawer) computed by `app.get_open_shift_summary` with the
  /// exact `app.close_shift` formula. Null when the server did not supply it —
  /// notably on an owner-mismatch (the drawer figure belongs to the owner, not this
  /// actor). PILOT-OPERATIONS-CORRECTIONS-001. Integer minor units (D-007).
  final int? expectedCashMinor;

  /// B1 (PILOT-OPERATIONS-CORRECTIONS-001): whether the CURRENT actor is authorized to
  /// close this shift, mirroring `app.close_shift` (manager+ any; a cashier only their
  /// own). Defaults true so an older server (no `can_close` key) is unaffected.
  final bool canClose;

  /// B1: true when the open shift belongs to a DIFFERENT employee (a new cashier on
  /// the same device) — the server returned `shift_owner_mismatch`. The close UI then
  /// shows an owner-mismatch state instead of a close form under the wrong name.
  final bool ownerMismatch;

  /// Finding 2 (PILOT-OPERATIONS-CORRECTIONS-001): true when the current actor OWNS the
  /// shift but lacks the `close_shift` capability — the server returned
  /// `shift_close_not_allowed`. The close UI then shows a capability-denied state (no
  /// close form, no money, no counted-cash input) — never the same as an owner
  /// mismatch, and never a retry that could bypass the capability.
  final bool closeNotAllowed;

  /// B1: the actual shift owner's employee-profile id (display only; never a secret).
  final String? openedByEmployeeProfileId;
}

/// The result of closing a shift: the server-authoritative cash reconciliation.
/// All money is integer minor units (DECISION D-007). `varianceMinor` is signed —
/// `counted - expected` (negative = shortage/short, positive = overage/over).
class ShiftCloseOutcome {
  const ShiftCloseOutcome({
    required this.expectedMinor,
    required this.countedMinor,
    required this.varianceMinor,
    required this.currencyCode,
  });

  final int expectedMinor;
  final int countedMinor;
  final int varianceMinor;
  final String currencyCode;

  bool get isBalanced => varianceMinor == 0;
  bool get isOver => varianceMinor > 0;
  bool get isShort => varianceMinor < 0;
}

/// Thrown when a shift cannot be closed. Carries only a safe, mapped reason code
/// — never raw backend text or secrets.
class ShiftException implements Exception {
  const ShiftException(this.code);

  /// A stable, safe code the UI maps to a localized message (e.g.
  /// 'unavailable', 'permission_denied', 'reason_required', 'not_open',
  /// 'rejected', 'malformed_response').
  final String code;

  @override
  String toString() => 'ShiftException: $code';
}

/// The shift close/reconcile seam. [closeShift] maps to the RF-055
/// `app.close_shift` RPC via the `public.sync_push` `shift.close` operation
/// (RF-056): the SERVER computes expected cash (opening float + completed cash
/// payments for the drawer), records the counted amount, and returns the signed
/// variance. The client sends only the counted amount + optional reason; it never
/// invents the reconciliation figures.
abstract class ShiftRepository {
  Future<ShiftCloseOutcome> closeShift({
    required String shiftId,
    required int countedMinor,
    String? reason,
    required String currencyCode,
  });

  /// Read the current OPEN shift for this device via `sync_pull` (secure,
  /// role/tenant-scoped read), or null when none is open / it can't be read.
  /// Used to recover the shift handle after a refresh or re-sign-in.
  Future<OpenShiftInfo?> readOpenShift();
}

/// REAL shift-close repository (RF-113). Posts a `shift.close` op to the RF-126
/// `public.sync_push` wrapper (dispatched server-side to `app.close_shift`,
/// RF-055), reusing the SAME shared public-schema [SyncRpcTransport] +
/// [SyncSession] as the real payment/outbox path (anon key + signed-in JWT; never
/// the `app` schema, never a service-role key — D-011).
///
/// FAIL-CLOSED: with no session/transport it throws [ShiftException]('unavailable')
/// — no backend contact, no fake close. A non-`applied` result (permission denied,
/// the RF-055 reason-required / illegal-state precondition, a conflict, or a
/// malformed envelope) also throws; the reconciliation figures come ONLY from a
/// positively-parsed applied result. Money is integer minor units (D-007).
class RealShiftRepository implements ShiftRepository {
  const RealShiftRepository(this._transport, this._session, this._idGenerator);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final ClientIdGenerator _idGenerator;

  @override
  Future<ShiftCloseOutcome> closeShift({
    required String shiftId,
    required int countedMinor,
    String? reason,
    required String currencyCode,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const ShiftException('unavailable');
    }
    if (shiftId.trim().isEmpty) throw const ShiftException('not_open');
    if (countedMinor < 0) throw const ShiftException('invalid_amount');

    final localOperationId = _idGenerator.newId();
    final trimmedReason = reason?.trim();
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': 'shift.close',
      'target_entity': 'shift',
      'target_id': shiftId,
      'client_created_at': DateTime.now().toIso8601String(),
      'payload': <String, dynamic>{
        'shift_id': shiftId,
        // Integer minor units, passed through verbatim (no float).
        'counted_amount_minor': countedMinor,
        if (trimmedReason != null && trimmedReason.isNotEmpty)
          'reason': trimmedReason,
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
      throw ShiftException('transport_${e.code ?? e.kind.name}');
    }

    return _applyResult(raw, localOperationId, currencyCode);
  }

  @override
  Future<OpenShiftInfo?> readOpenShift() async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) return null;
    // PILOT-OPERATIONS-CORRECTIONS-001: recover the open shift through the
    // dedicated read RPC `get_open_shift_summary`, which returns the
    // SERVER-authoritative expected cash (opening float + completed cash payments
    // on the drawer, the SAME SQL as app.close_shift) — unlike sync_pull, whose
    // expected_total_minor is NULL for a live shift. This is what lets the
    // shift-close UI show the real expected after an app restart instead of 0.
    final Object? raw;
    try {
      raw = await transport.invoke('get_open_shift_summary', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
      });
    } on SyncTransportException {
      return null; // fail-closed: no recovery -> honest "no open shift"
    }
    if (raw is! Map) return null;
    if (raw['ok'] == false) return null;
    if (raw['has_open_shift'] != true) return null;
    final shiftId = raw['shift_id']?.toString();
    if (shiftId == null || shiftId.isEmpty) return null;

    int? asInt(Object? v) => v is int ? v : int.tryParse('$v');
    final openingFloatMinor = asInt(raw['opening_float_minor']) ?? 0;
    final expectedCashMinor = asInt(raw['expected_cash_minor']);
    final openedAt =
        DateTime.tryParse('${raw['opened_at']}')?.toLocal() ?? DateTime.now();
    // B1 + Finding 2/3: the close-authorization verdict is FAIL-CLOSED at the parse
    // layer — `can_close` must be EXPLICITLY true (never a missing/malformed key
    // defaulting to closable). `get_open_shift_summary` always returns it for an open
    // shift, so an absent value is an anomaly and is treated as NOT closable. A denial
    // reports can_close=false + the owner id and NO money keys, with an honest reason:
    // `shift_owner_mismatch` (a different employee owns it) or `shift_close_not_allowed`
    // (the owning cashier lacks the close capability).
    final ownerMismatch = raw['error'] == 'shift_owner_mismatch';
    final closeNotAllowed = raw['error'] == 'shift_close_not_allowed';
    final canClose =
        raw['can_close'] == true && !ownerMismatch && !closeNotAllowed;
    return OpenShiftInfo(
      shiftId: shiftId,
      cashDrawerSessionId: raw['cash_drawer_session_id']?.toString() ?? '',
      openingFloatMinor: openingFloatMinor,
      openedAt: openedAt,
      expectedCashMinor: expectedCashMinor,
      canClose: canClose,
      ownerMismatch: ownerMismatch,
      closeNotAllowed: closeNotAllowed,
      openedByEmployeeProfileId: raw['opened_by_employee_profile_id']
          ?.toString(),
    );
  }

  /// Maps a `public.sync_push` envelope to a [ShiftCloseOutcome], FAIL-CLOSED.
  /// Only an `applied` per-op result carrying integer `expected_total_minor`,
  /// `counted_total_minor` and `variance_minor` yields an outcome; anything else
  /// throws [ShiftException] with a safe, mapped code.
  ShiftCloseOutcome _applyResult(
    Object? raw,
    String localOperationId,
    String currencyCode,
  ) {
    if (raw is! Map) throw const ShiftException('malformed_response');
    final results = raw['results'];
    if (results is! List || results.isEmpty) {
      throw const ShiftException('malformed_response');
    }

    Map<String, dynamic>? op;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        op = r.cast<String, dynamic>();
        break;
      }
    }
    if (op == null) throw const ShiftException('malformed_response');

    final status = op['status'];
    if (status != 'applied' || op['ok'] == false) {
      // Map the safe error to a UI code. The RF-055 reason-required and
      // illegal-state raises surface as sqlstate 42501; permission denials as the
      // 'permission_denied' error string.
      final error = op['error'];
      if (error == 'permission_denied') {
        throw const ShiftException('permission_denied');
      }
      if (op['sqlstate'] == '42501')
        throw const ShiftException('rejected_42501');
      throw ShiftException(error is String ? 'rejected_$error' : 'rejected');
    }

    final expected = op['expected_total_minor'];
    final counted = op['counted_total_minor'];
    final variance = op['variance_minor'];
    if (expected is! int || counted is! int || variance is! int) {
      throw const ShiftException('malformed_response');
    }
    return ShiftCloseOutcome(
      expectedMinor: expected,
      countedMinor: counted,
      varianceMinor: variance,
      currencyCode: currencyCode,
    );
  }
}
