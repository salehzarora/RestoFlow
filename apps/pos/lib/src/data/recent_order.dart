import 'package:restoflow_domain/restoflow_domain.dart';

import 'order_snapshot.dart';
import 'payment.dart';
import '../state/submitted_order_view.dart';

/// POS-ORDERS-AND-PAYMENT-001 + POS-OPERATIONS-SYNC-001: one recent order in the
/// cashier's local recent/unpaid-orders surface.
///
/// It began life as a faithful snapshot of what THIS device SUBMITTED — and then
/// never heard from the server again. Its own doc used to say so: "it carries no
/// live fulfillment status (the POS does not pull orders back)". That is precisely
/// what made a comped order sit on the till showing its old total, an old
/// non-terminal status, and payment/cancel buttons that could not possibly work.
///
/// It now carries TWO views of the same order, and the distinction matters:
///
///   * [order] — the ORDER-TIME snapshot: the lines and the prices as they were
///     captured (D-008). This is what a receipt reprints. It is never recomputed.
///   * [snapshot] — the AUTHORITATIVE server state: revision, canonical status,
///     the current money, and the SERVER-COMPUTED settlement. Null until this
///     device has heard from the server about this order.
///
/// Where the two disagree about money or status, THE SERVER WINS — every getter
/// below prefers [snapshot]. Money is integer minor units (D-007), always.
class PosRecentOrder {
  const PosRecentOrder({
    required this.order,
    required this.submittedAt,
    this.payment,
    this.voidedAt,
    this.voidReason,
    this.status,
    this.snapshot,
    this.syncState = PosOrderSyncState.synchronized,
    this.lastSyncError,
  });

  final SubmittedOrderView order;

  /// POS-OPERATIONS-SYNC-001: the last AUTHORITATIVE server snapshot, or null when
  /// this device has never heard back about this order (offline, or pre-upgrade
  /// data). Where present it is the source of truth for money, status and
  /// settlement.
  final PosOrderSnapshot? snapshot;

  /// Where THIS DEVICE stands with the server — NOT where the order stands in its
  /// lifecycle. An order can be `served` (lifecycle) while its discount is still
  /// queued (sync). Conflating the two is what let stale actions survive.
  final PosOrderSyncState syncState;

  /// The last server refusal for this order, as a SAFE domain token (e.g.
  /// `order_not_chargeable`) — never raw server text, never JSON, never a secret.
  /// Retained so the UI can explain the refusal instead of silently retrying it.
  final String? lastSyncError;

  /// The server revision, or null if never synced. The POS stored NONE before
  /// this ticket, which is why `expected_revision` was dead code.
  int? get revision => snapshot?.revision;

  /// MONEY-SETTLEMENT-CONSISTENCY-001: the last CANONICAL order status this device
  /// heard from the SERVER (`submitted` on submit, then whatever a server envelope
  /// reports — e.g. `record_payment` returns `order_status`, which is `completed` when
  /// the served+settled rule auto-closed the order).
  ///
  /// NULL means "this device has not been told" — the POS does not pull orders back, so
  /// a status change driven purely by the KDS (a bump that auto-completes a comped
  /// order) never reaches this device. We therefore treat null as NOT-known-terminal and
  /// let the SERVER be the authority: it refuses the write and the UI explains why. What
  /// we must never do is infer terminality from the payment marker.
  final String? status;

  /// The recorded payment once the order is settled, or null while unpaid.
  final CashPayment? payment;

  /// When this device submitted the order (local time; drives the window +
  /// newest-first ordering).
  final DateTime submittedAt;

  /// MONEY-VOID-001: when this order was CANCELLED (voided), or null. Set once
  /// the server confirms the void; persisted so a cancelled order stays
  /// cancelled across a restart. A cancelled order carries no payment and cannot
  /// be paid or reprinted as a receipt.
  final DateTime? voidedAt;

  /// MONEY-VOID-001: the cancellation reason (as entered by the cashier), or
  /// null. Display only — never money.
  final String? voidReason;

  String get orderNumber => order.orderNumber;
  String? get orderId => order.orderId;

  /// THE settlement of this order — the SERVER's answer when we have it.
  ///
  /// POS-OPERATIONS-SYNC-001: when a [snapshot] exists, the server has already
  /// computed this with `app.order_is_fully_settled` and we simply report it. The
  /// client does not re-derive it, because re-deriving it from the STALE
  /// submit-time total is exactly the bug: a comped order read "unpaid" forever.
  ///
  /// The fallback below applies ONLY to an order this device has never heard back
  /// about (offline before the first pull, or pre-upgrade persisted data). It
  /// mirrors the server rule against the best local figures:
  ///   total == 0 -> notChargeable   (owes nothing; carries no payment row)
  ///   total  > 0 -> paid only when a completed payment COVERS the current total
  ///   total  < 0 -> FAIL CLOSED to unpaid (a money defect must stay visible)
  PosSettlement get settlement {
    final snap = snapshot;
    if (snap != null) return snap.settlement;

    final total = grandTotalMinor;
    if (total < 0) return PosSettlement.unpaid; // fail closed
    if (total == 0) return PosSettlement.notChargeable;
    final p = payment;
    if (p == null || !p.status.isPaid) return PosSettlement.unpaid;
    return p.amountMinor >= total ? PosSettlement.paid : PosSettlement.unpaid;
  }

  /// True once a COMPLETED payment row is attached. A MARKER — "was money taken?" —
  /// NOT the settlement question. It is the right test for "can we reprint a
  /// receipt?" and the WRONG test for "does this order still owe money?".
  bool get isPaid => payment != null && payment!.status.isPaid;

  /// Does this order still owe money? Server-authoritative via [settlement].
  bool get isFullySettled => settlement.isSettled;

  /// A ZERO-TOTAL (comped / 100%-discounted) order: it owes nothing, and the server
  /// REFUSES to take a payment for it (no zero-value payment, no burned receipt
  /// number). A NEGATIVE total is NOT this — it is a money defect, and it fails
  /// closed to `unpaid` so it keeps every control and stays visible.
  bool get isNonChargeable => settlement == PosSettlement.notChargeable;

  /// MONEY-VOID-001: true once the order has been cancelled (voided).
  bool get isVoided => voidedAt != null || snapshot?.status == 'voided';

  /// The order is in a CANONICAL TERMINAL state, so no mutation (payment,
  /// cancel/void, discount) can succeed. THE SERVER WINS: once a snapshot says
  /// terminal, it is terminal — that is how a KDS bump or an auto-completion this
  /// device never saw finally reaches it. An UNKNOWN server status is NOT terminal;
  /// we will not invent a lifecycle state and strip a live order's controls.
  bool get isTerminal {
    final snap = snapshot;
    if (snap != null) return snap.isTerminal;
    return voidedAt != null || kPosTerminalStatuses.contains(status);
  }

  /// The AUTHORITATIVE total. Server first — this is the "stale 40" fix.
  int get grandTotalMinor => snapshot?.grandTotalMinor ?? order.grandTotalMinor;

  int get subtotalMinor => snapshot?.subtotalMinor ?? order.subtotalMinor;

  int get discountTotalMinor =>
      snapshot?.discountTotalMinor ?? order.discountTotalMinor;

  int get taxTotalMinor => snapshot?.taxTotalMinor ?? order.taxTotalMinor;

  /// The canonical server status, when known.
  String? get serverStatus => snapshot?.status ?? status;

  String get currencyCode => order.currencyCode;

  PosRecentOrder copyWith({
    CashPayment? payment,
    DateTime? voidedAt,
    String? voidReason,
    String? status,
    PosOrderSnapshot? snapshot,
    PosOrderSyncState? syncState,
    String? lastSyncError,
    bool clearSyncError = false,
  }) => PosRecentOrder(
    order: order,
    submittedAt: submittedAt,
    payment: payment ?? this.payment,
    voidedAt: voidedAt ?? this.voidedAt,
    voidReason: voidReason ?? this.voidReason,
    status: status ?? this.status,
    snapshot: snapshot ?? this.snapshot,
    syncState: syncState ?? this.syncState,
    lastSyncError: clearSyncError
        ? null
        : (lastSyncError ?? this.lastSyncError),
  );

  /// Adopts an AUTHORITATIVE server snapshot.
  ///
  /// The order-time [SubmittedOrderView] money is realigned to the server's, so the
  /// confirmation/receipt path (which reads `.order`) cannot keep showing a total
  /// the server has already changed. The order LINES are untouched — they are the
  /// order-time price snapshot (D-008) and are never recomputed.
  ///
  /// The queued-operation record is NOT touched here: a snapshot is not an
  /// acknowledgement (see order_reconciler.dart, rule 3).
  PosRecentOrder withServerSnapshot(
    PosOrderSnapshot snap, {
    PosOrderSyncState? syncState,
  }) => PosRecentOrder(
    order: order.copyWith(
      subtotalMinor: snap.subtotalMinor,
      discountTotalMinor: snap.discountTotalMinor,
      taxTotalMinor: snap.taxTotalMinor,
    ),
    submittedAt: submittedAt,
    payment: payment,
    // A server-voided order is terminal even if THIS device never ran the void.
    voidedAt: voidedAt ?? (snap.status == 'voided' ? snap.updatedAt : null),
    voidReason: voidReason,
    status: snap.status,
    snapshot: snap,
    syncState: syncState ?? this.syncState,
    lastSyncError: lastSyncError,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'submitted_at': submittedAt.toIso8601String(),
    'order': _orderToJson(order),
    if (payment != null) 'payment': _paymentToJson(payment!),
    if (voidedAt != null) 'voided_at': voidedAt!.toIso8601String(),
    if (voidReason != null) 'void_reason': voidReason,
    if (status != null) 'status': status,
    // POS-OPERATIONS-SYNC-001 — additive. A record written by an OLDER build simply
    // lacks these keys and still parses (see fromJson): the upgrade preserves
    // existing recent orders rather than discarding the cashier's day.
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    'sync_state': syncState.name,
    if (lastSyncError != null) 'last_sync_error': lastSyncError,
  };

  /// Parses a persisted recent order. Throws [FormatException] on a
  /// missing/foreign shape so a corrupt single entry is dropped on load (never
  /// crashes the POS).
  static PosRecentOrder fromJson(Map<String, Object?> json) {
    final submittedAtRaw = json['submitted_at'];
    final orderRaw = json['order'];
    if (submittedAtRaw is! String || orderRaw is! Map) {
      throw const FormatException('recent order: missing order/submitted_at');
    }
    final submittedAt = DateTime.tryParse(submittedAtRaw);
    if (submittedAt == null) {
      throw const FormatException('recent order: bad submitted_at');
    }
    final paymentRaw = json['payment'];
    final voidedAtRaw = json['voided_at'];
    final voidReasonRaw = json['void_reason'];

    // POS-OPERATIONS-SYNC-001 UPGRADE PATH. A record written by an older build has
    // no `snapshot` and no `sync_state`. It is NOT corrupt and must NOT be dropped —
    // it is the cashier's real day's work. It loads with no server snapshot (so the
    // local fallback answers until the first pull tells us better) and is treated as
    // `synchronized`, which is the honest reading: this device has no queued work
    // for it and has simply never heard back.
    //
    // A snapshot that fails to parse is DISCARDED rather than throwing: the order
    // itself is still perfectly good, and the next pull will re-authoritative it.
    // Throwing here would drop a real order over a bad optional field.
    final snapshot = PosOrderSnapshot.fromJson(json['snapshot']);
    final syncState = _syncStateFromName(json['sync_state']);

    return PosRecentOrder(
      order: _orderFromJson(orderRaw.cast<String, Object?>()),
      submittedAt: submittedAt,
      payment: paymentRaw is Map
          ? _paymentFromJson(paymentRaw.cast<String, Object?>())
          : null,
      voidedAt: voidedAtRaw is String ? DateTime.tryParse(voidedAtRaw) : null,
      voidReason: _strOrNull(voidReasonRaw),
      status: _strOrNull(json['status']),
      snapshot: snapshot,
      syncState: syncState,
      lastSyncError: _strOrNull(json['last_sync_error']),
    );
  }
}

/// An unknown/missing sync state resolves to `synchronized` — never to a state that
/// would make the UI claim work is pending when none is.
PosOrderSyncState _syncStateFromName(Object? name) {
  for (final s in PosOrderSyncState.values) {
    if (s.name == name) return s;
  }
  return PosOrderSyncState.synchronized;
}

// --- SubmittedOrderView (+ lines) serialization -----------------------------

Map<String, Object?> _orderToJson(SubmittedOrderView o) => <String, Object?>{
  'order_number': o.orderNumber,
  'order_type': o.orderType.name,
  'currency_code': o.currencyCode,
  'subtotal_minor': o.subtotalMinor,
  'discount_total_minor': o.discountTotalMinor,
  'tax_total_minor': o.taxTotalMinor,
  'tax_rate_bp': o.taxRateBp,
  if (o.tableLabel != null) 'table_label': o.tableLabel,
  if (o.customerName != null) 'customer_name': o.customerName,
  if (o.orderId != null) 'order_id': o.orderId,
  if (o.outboxEntryId != null) 'outbox_entry_id': o.outboxEntryId,
  if (o.localOperationId != null) 'local_operation_id': o.localOperationId,
  'lines': [for (final l in o.lines) _lineToJson(l)],
};

SubmittedOrderView _orderFromJson(Map<String, Object?> j) {
  final orderNumber = j['order_number'];
  final currencyCode = j['currency_code'];
  if (orderNumber is! String || currencyCode is! String) {
    throw const FormatException('recent order: bad order header');
  }
  final linesRaw = j['lines'];
  return SubmittedOrderView(
    orderNumber: orderNumber,
    orderType: _orderTypeFromName(j['order_type']),
    currencyCode: currencyCode,
    subtotalMinor: _int(j['subtotal_minor']),
    discountTotalMinor: _int(j['discount_total_minor']),
    taxTotalMinor: _int(j['tax_total_minor']),
    taxRateBp: _int(j['tax_rate_bp']),
    tableLabel: _strOrNull(j['table_label']),
    customerName: _strOrNull(j['customer_name']),
    orderId: _strOrNull(j['order_id']),
    outboxEntryId: _strOrNull(j['outbox_entry_id']),
    localOperationId: _strOrNull(j['local_operation_id']),
    lines: linesRaw is List
        ? [
            for (final l in linesRaw)
              if (l is Map) _lineFromJson(l.cast<String, Object?>()),
          ]
        : const <SubmittedLineView>[],
  );
}

Map<String, Object?> _lineToJson(SubmittedLineView l) => <String, Object?>{
  'name': l.name,
  'quantity': l.quantity,
  'line_total_minor': l.lineTotalMinor,
  'currency_code': l.currencyCode,
  'modifiers': l.modifiers,
  if (l.note != null) 'note': l.note,
};

SubmittedLineView _lineFromJson(Map<String, Object?> j) {
  final name = j['name'];
  final currencyCode = j['currency_code'];
  if (name is! String || currencyCode is! String) {
    throw const FormatException('recent order: bad line');
  }
  final modsRaw = j['modifiers'];
  return SubmittedLineView(
    name: name,
    quantity: _int(j['quantity']),
    lineTotalMinor: _int(j['line_total_minor']),
    currencyCode: currencyCode,
    modifiers: modsRaw is List
        ? [for (final m in modsRaw) '$m']
        : const <String>[],
    note: _strOrNull(j['note']),
  );
}

// --- CashPayment serialization ----------------------------------------------

Map<String, Object?> _paymentToJson(CashPayment p) => <String, Object?>{
  'payment_id': p.paymentId,
  'order_number': p.orderNumber,
  'device_id': p.deviceId,
  'local_operation_id': p.localOperationId,
  'method': p.method.wire,
  'status': p.status.wire,
  'amount_minor': p.amountMinor,
  'tendered_minor': p.tenderedMinor,
  'change_minor': p.changeMinor,
  'currency_code': p.currencyCode,
  'receipt_number': p.receiptNumber,
  'paid_at': p.paidAt.toIso8601String(),
  if (p.orderStatus != null) 'order_status': p.orderStatus,
};

CashPayment _paymentFromJson(Map<String, Object?> j) {
  final paidAt = DateTime.tryParse('${j['paid_at']}');
  if (paidAt == null) {
    throw const FormatException('recent order: bad payment paid_at');
  }
  return CashPayment(
    paymentId: '${j['payment_id'] ?? ''}',
    orderNumber: '${j['order_number'] ?? ''}',
    deviceId: '${j['device_id'] ?? ''}',
    localOperationId: '${j['local_operation_id'] ?? ''}',
    method: PaymentMethod.fromWire(j['method']) ?? PaymentMethod.cash,
    status: _statusFromWire(j['status']),
    amountMinor: _int(j['amount_minor']),
    tenderedMinor: _int(j['tendered_minor']),
    changeMinor: _int(j['change_minor']),
    currencyCode: '${j['currency_code'] ?? ''}',
    receiptNumber: '${j['receipt_number'] ?? ''}',
    paidAt: paidAt,
    orderStatus: _strOrNull(j['order_status']),
  );
}

OrderType _orderTypeFromName(Object? name) {
  for (final t in OrderType.values) {
    if (t.name == name) return t;
  }
  return OrderType.takeaway;
}

PaymentStatus _statusFromWire(Object? wire) {
  for (final s in PaymentStatus.values) {
    if (s.wire == wire) return s;
  }
  return PaymentStatus.completed;
}

int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}
