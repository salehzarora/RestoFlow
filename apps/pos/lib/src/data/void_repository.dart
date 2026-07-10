import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'ids.dart';

/// MONEY-VOID-001: a failure to cancel (void) an order. [permissionDenied] marks
/// the honest server role-gate refusal ("only a manager can cancel this order");
/// [alreadyPaid] marks the "order has a completed payment" refusal (paid orders
/// cannot be cancelled in the MVP — refunds are a separate, deferred flow).
class VoidException implements Exception {
  const VoidException(
    this.message, {
    this.permissionDenied = false,
    this.alreadyPaid = false,
  });

  final String message;
  final bool permissionDenied;
  final bool alreadyPaid;

  @override
  String toString() => 'VoidException: $message';
}

/// MONEY-VOID-001: the order-cancellation (void) seam. [voidOrder] maps 1:1 to
/// the `order.void` sync_push op -> `app.void_order` (RF-053, hardened by
/// RF-062): cancel a WRONG UNPAID order with a mandatory reason.
///
/// SERVER-AUTHORITATIVE + role-gated: the server allows
/// manager/restaurant_owner/org_owner (or a cashier with the `void_order`
/// permission) and rejects everyone else; a paid order (any completed payment)
/// is refused server-side. MONEY-FREE: the void creates/deletes NO payment and
/// recomputes NO total — it only marks the order voided.
abstract class VoidRepository {
  /// Cancels [orderId] with a non-empty [reason]; returns normally on success,
  /// throws [VoidException] on any failure (with [VoidException.permissionDenied]
  /// / [VoidException.alreadyPaid] for the honest server refusals).
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  });
}

/// In-memory, clearly-labelled DEMO void store. Validates the mandatory reason,
/// then succeeds locally (no backend). Mirrors [DemoDiscountStore].
class DemoVoidStore implements VoidRepository {
  const DemoVoidStore();

  @override
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  }) async {
    if (reason.trim().isEmpty) {
      throw const VoidException('a reason is required');
    }
  }
}

/// REAL order-void repository (MONEY-VOID-001). Delivers an `order.void` op to
/// the RF-126 `public.sync_push` wrapper (dispatched server-side to
/// `app.void_order`), reusing the SAME shared public-schema [SyncRpcTransport] +
/// [SyncSession] as the outbox/payment/discount paths (anon key + the PIN/device
/// session, never the `app` schema, never a service-role key).
///
/// FAIL-CLOSED: with no [SyncSession]/[SyncRpcTransport] (sign-in not wired) or
/// no [orderId], every call throws [VoidException] — no backend contact, no fake
/// local success. A non-`applied` result throws; the honest server refusals
/// (`permission_denied`, `order_has_completed_payment`) are surfaced typed.
class RealVoidRepository implements VoidRepository {
  const RealVoidRepository(this._transport, this._session, this._ids);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final ClientIdGenerator _ids;

  @override
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const VoidException(
        'real cancel unavailable: an authenticated PIN session on a paired, '
        'active device is required (sign-in flow not wired yet) - failing '
        'closed, no order is cancelled.',
      );
    }
    if (orderId.trim().isEmpty) {
      throw const VoidException(
        'real cancel unavailable: the submitted order id is missing - failing '
        'closed, no order is cancelled.',
      );
    }
    if (reason.trim().isEmpty) {
      throw const VoidException('a reason is required');
    }

    // A fresh idempotency key per attempt. app.void_order is naturally terminal:
    // a genuine retry against an already-voided order is rejected at its
    // state-legality check (not silently double-applied), and the double-tap
    // guard in the cancel sheet stops concurrent duplicates.
    final localOperationId = _ids.newId();
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': 'order.void',
      'target_entity': 'order',
      'target_id': orderId,
      'client_created_at': DateTime.now().toIso8601String(),
      // The server derives actor/org/branch from the PIN session; the client
      // sends ONLY the order + the mandatory reason. No money, no totals.
      'payload': <String, dynamic>{
        'order_id': orderId,
        'reason': reason,
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
      // A whole-batch failure (e.g. 42501 - revoked device / expired PIN
      // session). Carry only the error code, never raw backend text.
      throw VoidException('cancel failed: ${e.code ?? e.kind.name}');
    }

    _checkVoidResult(raw: raw, localOperationId: localOperationId);
  }

  /// FAIL-CLOSED per-op result check. Only an `applied` result (server set the
  /// order `voided`) succeeds; `permission_denied` /
  /// `order_has_completed_payment` throw typed refusals; anything else
  /// (malformed / missing / rejected / conflict) throws a generic
  /// [VoidException]. No money value is read back — a void is money-free.
  void _checkVoidResult({
    required Object? raw,
    required String localOperationId,
  }) {
    if (raw is! Map) {
      throw const VoidException('cancel rejected: malformed_response');
    }
    final results = raw['results'];
    if (results is! List || results.isEmpty) {
      throw const VoidException('cancel rejected: missing_results');
    }

    Map<String, dynamic>? op;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        op = r.cast<String, dynamic>();
        break;
      }
    }
    if (op == null) {
      throw const VoidException('cancel rejected: no_matching_operation');
    }

    final status = op['status'];
    if (status != 'applied' || op['ok'] == false) {
      final error = op['error'];
      if (error == 'permission_denied') {
        if (op['detail'] == 'order_has_completed_payment') {
          throw const VoidException(
            'order_has_completed_payment',
            alreadyPaid: true,
          );
        }
        throw const VoidException('permission_denied', permissionDenied: true);
      }
      throw VoidException(
        'cancel rejected: ${error is String ? error : (status is String ? status : 'unknown')}',
      );
    }
    // applied + ok:true -> the server set orders.status='voided'. Done.
  }
}
