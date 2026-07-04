import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import '../format/tax_math.dart';
import 'discount.dart';
import 'ids.dart';

/// The order-level discount seam (RF-117 part C). [applyOrderDiscount] maps 1:1
/// to the `order.discount` sync_push op -> `app.apply_discount` (RF-053): apply
/// a fixed or percentage discount to the whole order and return the recomputed
/// totals. SERVER-AUTHORITATIVE and AUTHORIZED in real mode; a clearly-labelled
/// local computation in demo mode. Money is integer minor units (D-007).
abstract class DiscountRepository {
  /// Applies an order-level discount to [orderId] and returns the recomputed
  /// [OrderDiscount] totals. [type] selects how [value] is read (fixed minor
  /// units vs. percentage basis points). [subtotalMinor]/[taxTotalMinor] are the
  /// current order figures (demo baseline; the server recomputes from snapshots).
  /// [reason] is REQUIRED (non-empty). Throws [DiscountException] on any failure
  /// — with `permissionDenied: true` for the honest cashier-without-permission
  /// case (real mode).
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  });
}

/// In-memory, clearly-labelled DEMO discount store (RF-117). Computes the
/// discount locally with the SAME clamp + half-away rounding the server uses
/// (clamp discount <= subtotal), so the demo confirmation reflects an honest
/// discounted total. No backend, no persistence. Money is integer minor units.
class DemoDiscountStore implements DiscountRepository {
  const DemoDiscountStore();

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async {
    if (reason.trim().isEmpty) {
      throw const DiscountException('a reason is required');
    }
    if (value <= 0) {
      throw const DiscountException('discount must be greater than zero');
    }
    if (type == DiscountType.percentage && value > 10000) {
      throw const DiscountException('percentage must be 0..100%');
    }
    // fixed: value is the amount; percentage: round-half-away of subtotal*bp.
    final raw = type == DiscountType.fixed
        ? value
        : percentMinor(subtotalMinor, value);
    // Clamp discount <= subtotal (mirrors the server; keeps grand >= tax >= 0).
    final discount = raw > subtotalMinor ? subtotalMinor : raw;
    final grand = subtotalMinor - discount + taxTotalMinor;
    return OrderDiscount(
      discountTotalMinor: discount,
      grandTotalMinor: grand < 0 ? 0 : grand,
    );
  }
}

/// REAL order-level discount repository (RF-117). Delivers an `order.discount` op
/// to the RF-126 `public.sync_push` wrapper (dispatched server-side to
/// `app.apply_discount`, RF-053), reusing the same shared public-schema
/// [SyncRpcTransport] + [SyncSession] as the outbox/payment paths (anon key + the
/// PIN/device session, never the `app` schema, never a service-role key).
///
/// SERVER-AUTHORITATIVE: the recomputed `discount_total_minor` + `grand_total_minor`
/// are read back from the per-op result — the client never computes the
/// authoritative discounted total. AUTHORIZED: a cashier without the
/// `apply_discount` permission gets `{ok:false, error:'permission_denied'}`,
/// surfaced HONESTLY as [DiscountException] with `permissionDenied: true`.
///
/// FAIL-CLOSED: with no [SyncSession]/[SyncRpcTransport] (sign-in not wired) or no
/// [orderId], every call throws [DiscountException] — no backend contact, no fake
/// local discount. A non-`applied` result (rejected/conflict/malformed) also
/// throws; nothing is ever invented. Money is integer minor units (D-007).
class RealDiscountRepository implements DiscountRepository {
  const RealDiscountRepository(this._transport, this._session, this._ids);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final ClientIdGenerator _ids;

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const DiscountException(
        'real discount unavailable: an authenticated PIN session on a paired, '
        'active device is required (sign-in flow not wired yet) - failing '
        'closed, no discount is applied.',
      );
    }
    if (orderId.trim().isEmpty) {
      throw const DiscountException(
        'real discount unavailable: the submitted order id is missing - failing '
        'closed, no discount is applied.',
      );
    }
    if (reason.trim().isEmpty) {
      throw const DiscountException('a reason is required');
    }

    final localOperationId = _ids.newId();
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': 'order.discount',
      'target_entity': 'order',
      'target_id': orderId,
      'client_created_at': DateTime.now().toIso8601String(),
      'payload': <String, dynamic>{
        'order_id': orderId,
        'scope': 'order',
        'discount_type': type.wire,
        'value': value,
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
      throw DiscountException('discount failed: ${e.code ?? e.kind.name}');
    }

    return _applyDiscountResult(raw: raw, localOperationId: localOperationId);
  }

  /// Maps a `public.sync_push` envelope to the recomputed [OrderDiscount],
  /// FAIL-CLOSED. Only an `applied` per-op result carrying integer
  /// `discount_total_minor` + `grand_total_minor` yields a result; a
  /// `permission_denied` denial throws with `permissionDenied: true`; anything
  /// else (malformed / missing / rejected / conflict / non-integer money) throws
  /// a generic [DiscountException].
  OrderDiscount _applyDiscountResult({
    required Object? raw,
    required String localOperationId,
  }) {
    if (raw is! Map) {
      throw const DiscountException('discount rejected: malformed_response');
    }
    final results = raw['results'];
    if (results is! List || results.isEmpty) {
      throw const DiscountException('discount rejected: missing_results');
    }

    Map<String, dynamic>? op;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        op = r.cast<String, dynamic>();
        break;
      }
    }
    if (op == null) {
      throw const DiscountException('discount rejected: no_matching_operation');
    }

    final status = op['status'];
    if (status != 'applied' || op['ok'] == false) {
      final error = op['error'];
      if (error == 'permission_denied') {
        throw const DiscountException(
          'permission_denied',
          permissionDenied: true,
        );
      }
      throw DiscountException(
        'discount rejected: ${error is String ? error : (status is String ? status : 'unknown')}',
      );
    }

    final discount = op['discount_total_minor'];
    final grand = op['grand_total_minor'];
    if (discount is! int || grand is! int) {
      throw const DiscountException('discount rejected: invalid_totals');
    }
    return OrderDiscount(
      discountTotalMinor: discount,
      grandTotalMinor: grand < 0 ? 0 : grand,
    );
  }
}
