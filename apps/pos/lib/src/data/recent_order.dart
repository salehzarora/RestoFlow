import 'package:restoflow_domain/restoflow_domain.dart';

import 'order_identity.dart';
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
///     NULL for a BRANCH-DISCOVERED order: another till took it, so this device
///     never saw its lines — and fabricating empty ones to print would be a forged
///     receipt.
///   * [snapshot] — the AUTHORITATIVE server state: revision, canonical status,
///     the current money, and the SERVER-COMPUTED settlement. Null only for an order
///     this device has never heard back about (offline, or pre-upgrade data).
///
/// At least ONE of the two is always present. Where they disagree about money or
/// status, THE SERVER WINS — every getter below prefers [snapshot]. Money is integer
/// minor units (D-007), always.
class PosRecentOrder {
  const PosRecentOrder({
    this.order,
    DateTime? submittedAt,
    this.payment,
    this.voidedAt,
    this.voidReason,
    this.status,
    this.snapshot,
    this.syncState = PosOrderSyncState.synchronized,
    this.origin = PosOrderOrigin.deviceOwned,
    this.lastSyncError,
  }) : assert(
         order != null || snapshot != null,
         'an order is either something this device submitted or something the '
         'server told us about — a row that is neither does not exist',
       ),
       _submittedAt = submittedAt;

  /// Builds a row for an order DISCOVERED on the branch feed. It carries the server
  /// snapshot and NOTHING local: no lines, no receipt, and — critically — none of
  /// the originating till's queued work.
  factory PosRecentOrder.discovered(PosOrderSnapshot snapshot) =>
      PosRecentOrder(
        snapshot: snapshot,
        origin: PosOrderOrigin.branchDiscovered,
        syncState: snapshot.isTerminal
            ? PosOrderSyncState.terminal
            : PosOrderSyncState.synchronized,
      );

  /// The ORDER-TIME view captured when THIS device submitted the order, or NULL for
  /// a branch-discovered one (another till took it; we never saw its lines).
  final SubmittedOrderView? order;

  /// Where this row came from. Ownership — not lifecycle, not sync state.
  final PosOrderOrigin origin;

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

  /// When THIS device submitted the order (local time), or null for a
  /// branch-discovered one — another till submitted it and we were not there.
  final DateTime? _submittedAt;

  /// When this device submitted the order. For a discovered order this falls back
  /// to the SERVER's `created_at`, which is the honest answer to "when was this
  /// order opened" and is what the list sorts by.
  DateTime get submittedAt =>
      _submittedAt ??
      snapshot?.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// The ONE timestamp the operational centre sorts by. The SERVER's creation time
  /// when we have it, so a device-owned row and a discovered row sort against the
  /// same clock rather than against one local and one remote one.
  DateTime get sortAt => snapshot?.createdAt ?? submittedAt;

  /// MONEY-VOID-001: when this order was CANCELLED (voided), or null. Set once
  /// the server confirms the void; persisted so a cancelled order stays
  /// cancelled across a restart. A cancelled order carries no payment and cannot
  /// be paid or reprinted as a receipt.
  final DateTime? voidedAt;

  /// MONEY-VOID-001: the cancellation reason (as entered by the cashier), or
  /// null. Display only — never money.
  final String? voidReason;

  /// The cashier-visible code. A device-owned order shows the code it was submitted
  /// with; a discovered order shows the SERVER's safe `#XXXXXX` reference. Never a
  /// raw UUID, either way.
  String get orderNumber => order?.orderNumber ?? snapshot?.orderCode ?? '';

  /// The authoritative server order id, or null while the server has not named this
  /// order yet.
  String? get orderId => order?.orderId ?? snapshot?.orderId;

  /// THE identity of this row — for dedupe, payment, void, receipt and recovery.
  ///
  /// The server id when we have one; this device's own operation id until then; the
  /// display code ONLY for pre-upgrade persisted rows that carry neither. Never the
  /// display code by preference: two different orders can share one, and keying on it
  /// is what let a payment attach to the wrong order (see [PosOrderIdentity]).
  PosOrderIdentity get identity => PosOrderIdentity.of(
    orderId: orderId,
    localOperationId: order?.localOperationId,
    outboxEntryId: order?.outboxEntryId,
    orderNumber: orderNumber,
  );

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
    if (snap != null) {
      // A LOCALLY-HELD SERVER CONFIRMATION CAN BE NEWER THAN THE RETAINED SNAPSHOT.
      // `record_payment` succeeded on THIS device — a server fact — but the payment
      // does not bump the order's revision, and the follow-up targeted refresh can
      // fail (offline blip right after the payment RPC returned). The stale snapshot
      // then still says `unpaid`, and preferring it re-entered a genuinely PAID order
      // into the unpaid badge until the next successful pull. This is NOT client
      // re-derivation from submit-time figures (the forbidden thing): it combines two
      // SERVER statements — the snapshot's authoritative total and the confirmed
      // payment — under exactly the `app.order_is_fully_settled` coverage rule, and
      // the next snapshot (whose sync_at includes the payment) says the same thing.
      final p = payment;
      if (snap.settlement == PosSettlement.unpaid &&
          p != null &&
          p.status.isPaid &&
          p.amountMinor >= snap.grandTotalMinor) {
        return PosSettlement.paid;
      }
      return snap.settlement;
    }

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
  ///
  /// THE RATCHET SPANS EVERY SERVER-CONFIRMED CHANNEL, not just the snapshot feed.
  /// [voidedAt] is set only AFTER the server confirmed a void, and [status] only ever
  /// carries what a server envelope reported (`record_payment`'s `order_status`, the
  /// void confirmation, a snapshot). A snapshot RETAINED FROM BEFORE one of those
  /// confirmations is the OLDER fact — and it used to OUTVOTE them: a just-voided
  /// order whose targeted refresh failed (network blip right after the void RPC
  /// returned) read `served`/`unpaid` off its stale snapshot, re-entered the unpaid
  /// badge, and re-offered Pay and Cancel — on an order the server had already
  /// confirmed dead. Terminal-by-any-confirmed-channel can never wrongly fire,
  /// because every one of these inputs is a server statement.
  bool get isTerminal {
    if (voidedAt != null) return true;
    if (kPosTerminalStatuses.contains(status)) return true;
    return snapshot?.isTerminal ?? false;
  }

  /// The AUTHORITATIVE total. Server first — this is the "stale 40" fix.
  int get grandTotalMinor =>
      snapshot?.grandTotalMinor ?? order?.grandTotalMinor ?? 0;

  int get subtotalMinor => snapshot?.subtotalMinor ?? order?.subtotalMinor ?? 0;

  int get discountTotalMinor =>
      snapshot?.discountTotalMinor ?? order?.discountTotalMinor ?? 0;

  int get taxTotalMinor => snapshot?.taxTotalMinor ?? order?.taxTotalMinor ?? 0;

  /// The canonical server status, when known.
  String? get serverStatus => snapshot?.status ?? status;

  String get currencyCode =>
      order?.currencyCode ?? snapshot?.currencyCode ?? '';

  /// The dine-in table label, when the server or the local view knows one.
  String? get tableLabel => order?.tableLabel ?? snapshot?.tableLabel;

  /// True when a receipt can actually be rebuilt: it needs the ORDER-TIME lines,
  /// which only a device-owned order has, plus a real payment. A discovered order
  /// has no lines — printing "a receipt" for it would be printing a forgery.
  bool get canReprintReceipt => order != null && payment != null;

  PosRecentOrder copyWith({
    CashPayment? payment,
    DateTime? voidedAt,
    String? voidReason,
    String? status,
    PosOrderSnapshot? snapshot,
    PosOrderSyncState? syncState,
    PosOrderOrigin? origin,
    String? lastSyncError,
    bool clearSyncError = false,
  }) => PosRecentOrder(
    order: order,
    submittedAt: _submittedAt,
    payment: payment ?? this.payment,
    voidedAt: voidedAt ?? this.voidedAt,
    voidReason: voidReason ?? this.voidReason,
    status: status ?? this.status,
    snapshot: snapshot ?? this.snapshot,
    syncState: syncState ?? this.syncState,
    origin: origin ?? this.origin,
    lastSyncError: clearSyncError
        ? null
        : (lastSyncError ?? this.lastSyncError),
  );

  /// Adopts an AUTHORITATIVE server snapshot.
  ///
  /// The order-time [SubmittedOrderView] money is realigned to the server's, so the
  /// confirmation/receipt path (which reads it) cannot keep showing a total the
  /// server has already changed. The order LINES are untouched — they are the
  /// order-time price snapshot (D-008) and are never recomputed.
  ///
  /// ORIGIN IS PRESERVED. A snapshot arriving for a device-owned order does NOT
  /// demote it to "discovered": we still hold its lines and its receipt.
  ///
  /// The queued-operation record is NOT touched here: a snapshot is not an
  /// acknowledgement (see order_reconciler.dart, rule 3).
  PosRecentOrder withServerSnapshot(
    PosOrderSnapshot snap, {
    PosOrderSyncState? syncState,
  }) => PosRecentOrder(
    order: order?.copyWith(
      subtotalMinor: snap.subtotalMinor,
      discountTotalMinor: snap.discountTotalMinor,
      taxTotalMinor: snap.taxTotalMinor,
    ),
    submittedAt: _submittedAt,
    payment: payment,
    // A server-voided order is terminal even if THIS device never ran the void.
    voidedAt: voidedAt ?? (snap.status == 'voided' ? snap.updatedAt : null),
    voidReason: voidReason,
    status: snap.status,
    snapshot: snap,
    syncState: syncState ?? this.syncState,
    origin: origin,
    lastSyncError: lastSyncError,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (_submittedAt != null) 'submitted_at': _submittedAt.toIso8601String(),
    if (order != null) 'order': _orderToJson(order!),
    if (payment != null) 'payment': _paymentToJson(payment!),
    if (voidedAt != null) 'voided_at': voidedAt!.toIso8601String(),
    if (voidReason != null) 'void_reason': voidReason,
    if (status != null) 'status': status,
    // POS-OPERATIONS-SYNC-001 — additive. A record written by an OLDER build simply
    // lacks these keys and still parses (see fromJson): the upgrade preserves
    // existing recent orders rather than discarding the cashier's day.
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    'sync_state': syncState.name,
    'origin': origin.name,
    if (lastSyncError != null) 'last_sync_error': lastSyncError,
  };

  /// Parses a persisted recent order. Throws [FormatException] on a
  /// missing/foreign shape so a corrupt single entry is dropped on load (never
  /// crashes the POS).
  static PosRecentOrder fromJson(Map<String, Object?> json) {
    final submittedAtRaw = json['submitted_at'];
    final orderRaw = json['order'];

    // A record must be ONE of the two things it can be: something this device
    // submitted (an `order` view) or something the server told us about (a
    // `snapshot`). Neither is not an order.
    final snapshotEarly = PosOrderSnapshot.fromJson(json['snapshot']);
    if (orderRaw is! Map && snapshotEarly == null) {
      throw const FormatException('recent order: neither order nor snapshot');
    }
    final submittedAt = submittedAtRaw is String
        ? DateTime.tryParse(submittedAtRaw)
        : null;
    if (orderRaw is Map && submittedAt == null) {
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
    final snapshot = snapshotEarly;
    final syncState = _syncStateFromName(json['sync_state']);
    final parsedOrder = orderRaw is Map
        ? _orderFromJson(orderRaw.cast<String, Object?>())
        : null;

    return PosRecentOrder(
      order: parsedOrder,
      submittedAt: submittedAt,
      payment: paymentRaw is Map
          ? _paymentFromJson(paymentRaw.cast<String, Object?>())
          : null,
      voidedAt: voidedAtRaw is String ? DateTime.tryParse(voidedAtRaw) : null,
      voidReason: _strOrNull(voidReasonRaw),
      status: _strOrNull(json['status']),
      snapshot: snapshot,
      syncState: syncState,
      // A record with no `order` view was never submitted here, so it can only be
      // one we discovered — that is the honest default for a pre-origin record too.
      origin: _originFromName(
        json['origin'],
        fallback: parsedOrder != null
            ? PosOrderOrigin.deviceOwned
            : PosOrderOrigin.branchDiscovered,
      ),
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

PosOrderOrigin _originFromName(
  Object? name, {
  required PosOrderOrigin fallback,
}) {
  for (final o in PosOrderOrigin.values) {
    if (o.name == name) return o;
  }
  return fallback;
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
  // ADDITIVE. A record written by an older build simply lacks it and still loads —
  // and cannot be misfiled by its absence, because a persisted payment is stored
  // INSIDE its own order row (see _paymentFromJson).
  if (p.orderId != null) 'order_id': p.orderId,
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

/// Parses a persisted payment.
///
/// LEGACY DATA (POS-OPERATIONS-SYNC-001, second review correction). A record written
/// before this ticket carries only `order_number`, never `order_id`. That is SAFE, and
/// it is safe for a structural reason rather than a lucky one: a persisted payment is
/// stored INSIDE the order row it settles, so its association is already unambiguous —
/// there is no lookup to get wrong and nothing to guess. A legacy payment therefore
/// stays attached to exactly the order that recorded it, even when another order shares
/// its display code, and it simply reports a null [CashPayment.orderId] until the next
/// authoritative refresh. We do NOT try to re-derive its order from the code: guessing
/// between two orders that share one is precisely the misfiling this correction exists
/// to end.
CashPayment _paymentFromJson(Map<String, Object?> j) {
  final paidAt = DateTime.tryParse('${j['paid_at']}');
  if (paidAt == null) {
    throw const FormatException('recent order: bad payment paid_at');
  }
  return CashPayment(
    paymentId: '${j['payment_id'] ?? ''}',
    orderId: _strOrNull(j['order_id']),
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
