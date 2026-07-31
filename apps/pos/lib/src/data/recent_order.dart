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
    this.neverCreated = false,
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

  /// PILOT-OPERATIONS-CORRECTIONS-001 (A3): this row is the shell of a NEW submit
  /// the server PERMANENTLY refused (item_unavailable) — so NO server order was ever
  /// created. Its locally-generated order id is NOT proof of acceptance: the
  /// authoritative submit result was a permanent rejection. A row in this state must
  /// fail closed for every accepted-order action (pay / discount / comp / void / move
  /// / receipt / lifecycle / KDS) and must never be counted as open, needs-payment,
  /// completed, or table occupancy. It is retired (removed) once the cashier recovers
  /// its draft (Back to cart) or discards it. Never true for an accepted order (a
  /// server snapshot arriving would clear it — see [withServerSnapshot]).
  final bool neverCreated;

  /// True while this row is a permanently-rejected submit shell (see [neverCreated]).
  /// The ONE predicate the action policy and the operational sections read.
  bool get isNeverCreated => neverCreated;

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

  /// The dine-in table label. SERVER FIRST (RESTAURANT-OPERATIONS-V1-001): a
  /// table move on another till arrives through the snapshot, and the order-time
  /// label must not mask it. The order-time label remains the fallback for rows
  /// the server has not spoken about yet.
  String? get tableLabel => snapshot?.tableLabel ?? order?.tableLabel;

  /// THE order type (RESTAURANT-OPERATIONS-V1-001): the server's word when it
  /// has spoken, else the order-time selection. Wire values are the canonical
  /// 'dine_in'/'takeaway'; an unknown token falls back to the local view rather
  /// than inventing a type. Null only for a discovered row whose snapshot
  /// somehow carried none.
  OrderType? get orderType => switch (snapshot?.orderType) {
    'dine_in' => OrderType.dineIn,
    'takeaway' => OrderType.takeaway,
    _ => order?.orderType,
  };

  /// True when a receipt can actually be rebuilt: it needs the ORDER-TIME lines,
  /// which only a device-owned order has, plus a real payment. A discovered order
  /// has no lines — printing "a receipt" for it would be printing a forgery.
  /// MONEY-LOCAL-ATOMICITY-003A: a receipt needs a SETTLEMENT, not merely a
  /// payment object. The decoder already refuses to build a non-completed
  /// persisted payment, and this gate states the same rule independently — the
  /// eligibility must not depend on a construction detail one refactor away.
  bool get canReprintReceipt =>
      order != null && payment != null && payment!.status.isPaid;

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
    bool? neverCreated,
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
    neverCreated: neverCreated ?? this.neverCreated,
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
      // RESTAURANT-OPERATIONS-V1-001: a table move realigns the view's table
      // like money — a reprint must name the CURRENT table. Lines stay D-008.
      tableLabel: snap.tableLabel,
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
    // A3: persist the rejected-shell flag so a permanently-rejected submit stays
    // non-actionable across a restart (never reloading as a live phantom order).
    if (neverCreated) 'never_created': true,
  };

  /// Parses a persisted recent order. Throws [FormatException] on a
  /// missing/foreign shape so a corrupt single entry is dropped on load (never
  /// crashes the POS).
  static PosRecentOrder fromJson(Map<String, Object?> json) {
    final submittedAtRaw = json['submitted_at'];
    final orderRaw = json['order'];

    // MONEY-LOCAL-ATOMICITY-003A — ABSENT and MALFORMED are different things.
    //
    // `PosOrderSnapshot.fromJson` is a strict all-or-nothing parse that returns
    // null for BOTH, and this used to treat both as "no snapshot" and fall back
    // to the older local money and status. So a corrupt authoritative snapshot
    // silently showed a stale total as if it were current — the opposite of
    // what an authoritative record is for.
    //
    // The key's ABSENCE stays legitimate: records written before
    // POS-OPERATIONS-SYNC-001 carry no snapshot at all and are the cashier's
    // real day's work. A key that is PRESENT but unreadable is corruption, and
    // the containing record is refused so the existing quarantine seam keeps it
    // instead of re-pricing the order from stale local data.
    final PosOrderSnapshot? snapshotEarly;
    if (!json.containsKey('snapshot')) {
      snapshotEarly = null;
    } else {
      final parsed = PosOrderSnapshot.fromJson(json['snapshot']);
      if (parsed == null) {
        throw const FormatException(
          'recent order: snapshot is present but unreadable',
        );
      }
      snapshotEarly = parsed;
    }

    // A record must be ONE of the two things it can be: something this device
    // submitted (an `order` view) or something the server told us about (a
    // `snapshot`). Neither is not an order.
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
      // A3: a permanently-rejected submit shell (absent key = false, so older
      // records are unaffected). A snapshot cannot coexist with it — a stored
      // snapshot means the order exists — so ignore the flag if one is present.
      neverCreated: json['never_created'] == true && snapshot == null,
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
  if (o.customerPhone != null) 'customer_phone': o.customerPhone,
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
  // MONEY-LOCAL-DECODE-INTEGRITY-002B: `lines` is written unconditionally. A
  // non-list previously became an EMPTY order — every item silently gone while
  // the totals stayed — and a non-object element was SKIPPED, yielding a
  // shorter itemisation than the bill it accompanies. Both are refused, so the
  // caller quarantines the raw record instead of showing a mismatched order.
  final linesRaw = j['lines'];
  if (linesRaw is! List) {
    throw FormatException(
      'recent order: lines is not a list '
      '(${linesRaw == null ? 'absent/null' : linesRaw.runtimeType})',
    );
  }
  final lines = <SubmittedLineView>[];
  for (var i = 0; i < linesRaw.length; i++) {
    final l = linesRaw[i];
    if (l is! Map) {
      throw FormatException(
        'recent order: line $i is not an object '
        '(${l == null ? 'absent/null' : l.runtimeType})',
      );
    }
    lines.add(_lineFromJson(l.cast<String, Object?>()));
  }
  return SubmittedOrderView(
    orderNumber: orderNumber,
    orderType: _requireOrderType(j, 'order_type'),
    currencyCode: currencyCode,
    // MONEY-LOCAL-DECODE-INTEGRITY-002B: all four are written unconditionally,
    // so absence is corruption, and a coerced 0 would understate the bill.
    subtotalMinor: _requireMoney(j, 'subtotal_minor', 'order'),
    discountTotalMinor: _requireMoney(j, 'discount_total_minor', 'order'),
    taxTotalMinor: _requireMoney(j, 'tax_total_minor', 'order'),
    taxRateBp: _requireMoney(j, 'tax_rate_bp', 'order'),
    tableLabel: _strOrNull(j['table_label']),
    customerName: _strOrNull(j['customer_name']),
    customerPhone: _strOrNull(j['customer_phone']),
    orderId: _strOrNull(j['order_id']),
    outboxEntryId: _strOrNull(j['outbox_entry_id']),
    localOperationId: _strOrNull(j['local_operation_id']),
    lines: lines,
  );
}

Map<String, Object?> _lineToJson(SubmittedLineView l) => <String, Object?>{
  'name': l.name,
  'quantity': l.quantity,
  'line_total_minor': l.lineTotalMinor,
  'currency_code': l.currencyCode,
  'modifiers': l.modifiers,
  if (l.note != null) 'note': l.note,
  // MENU-ORDER-001: persist the menu-order snapshots (ADDITIVE — only when set)
  // so the CLIENT-fallback reprint keeps Dashboard order across a relaunch. Older
  // records simply lack the keys and load as 0 (keep their stored order).
  if (l.categoryDisplayOrder != 0)
    'category_display_order_snapshot': l.categoryDisplayOrder,
  if (l.itemDisplayOrder != 0)
    'item_display_order_snapshot': l.itemDisplayOrder,
  if (l.linePosition != 0) 'line_position': l.linePosition,
  // PRINT-STARTUP-REPRINT-001: persist the ORDER-TIME kitchen count snapshots
  // (ADDITIVE — only when set) so a MANUAL kitchen reprint after a relaunch
  // still aggregates the same whole-order counts the automatic ticket printed.
  // Older records simply lack the keys and decode to empty (see _lineFromJson).
  if (l.kitchenMeats.isNotEmpty)
    'kitchen_meat_snapshots': [for (final m in l.kitchenMeats) m.toJson()],
  if (l.prepComponents.isNotEmpty)
    'prep_snapshot': [for (final c in l.prepComponents) c.toJson()],
};

SubmittedLineView _lineFromJson(Map<String, Object?> j) {
  final name = j['name'];
  final currencyCode = j['currency_code'];
  if (name is! String || currencyCode is! String) {
    throw const FormatException('recent order: bad line');
  }
  // MONEY-LOCAL-DECODE-INTEGRITY-002B: `modifiers` is written unconditionally,
  // so a non-list is corruption; reinterpreting it as empty would hide the
  // paid options this line was actually charged for.
  final modsRaw = j['modifiers'];
  if (modsRaw is! List) {
    throw FormatException(
      'recent order: line modifiers is not a list '
      '(${modsRaw == null ? 'absent/null' : modsRaw.runtimeType})',
    );
  }
  final quantity = _requireInt(j, 'quantity', 'line');
  if (quantity < 1) {
    throw FormatException(
      'recent order: line quantity must be >= 1, got '
      '$quantity',
    );
  }
  return SubmittedLineView(
    name: name,
    quantity: quantity,
    lineTotalMinor: _requireMoney(j, 'line_total_minor', 'line'),
    currencyCode: currencyCode,
    modifiers: <String>[
      for (final m in modsRaw)
        if (m is String)
          m
        else
          throw FormatException(
            'recent order: line modifier is not a string (${m.runtimeType})',
          ),
    ],
    note: _strOrNull(j['note']),
    // MENU-ORDER-001: the menu-order snapshots are ADDITIVE — older records
    // lack them and keep their stored order (0). Present but unreadable is
    // corruption, so the tolerance is now absence only.
    categoryDisplayOrder: _optionalInt(
      j,
      'category_display_order_snapshot',
      'line',
    ),
    itemDisplayOrder: _optionalInt(j, 'item_display_order_snapshot', 'line'),
    linePosition: _optionalInt(j, 'line_position', 'line'),
    // PRINT-STARTUP-REPRINT-001: tolerant read of the kitchen count snapshots.
    // A record written before this change lacks the keys and decodes to EMPTY —
    // the reprint then honestly omits the count section instead of guessing
    // quantities out of the stored `name ×N` display strings, and nothing is
    // ever re-read from the current menu.
    kitchenMeats: _kitchenMeats(j['kitchen_meat_snapshots']),
    prepComponents: parseKitchenPrepComponents(j['prep_snapshot']),
  );
}

List<KitchenMeat> _kitchenMeats(Object? raw) {
  if (raw is! List) return const <KitchenMeat>[];
  final out = <KitchenMeat>[];
  for (final element in raw) {
    final meat = KitchenMeat.tryFromJson(element);
    if (meat != null) out.add(meat);
  }
  return out;
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
  // MONEY-LOCAL-ATOMICITY-003A — `paid_at` must be an EXACT String.
  //
  // This used to read `DateTime.tryParse('${j['paid_at']}')`. Interpolation
  // turned the integer 20260805 into "20260805", which is a valid compact-ISO
  // date — so a corrupt numeric field became a real settlement timestamp. The
  // timestamp is never invented here either: an absent or unreadable value
  // refuses the record.
  final rawPaidAt = j['paid_at'];
  if (rawPaidAt is! String) {
    throw FormatException(
      'recent order: payment paid_at is not a string '
      '(${rawPaidAt == null ? 'absent/null' : rawPaidAt.runtimeType})',
    );
  }
  final paidAt = DateTime.tryParse(rawPaidAt);
  if (paidAt == null) {
    throw const FormatException('recent order: bad payment paid_at');
  }
  // MONEY-LOCAL-DECODE-INTEGRITY-002B (Codex Blocker 3). An UNKNOWN method
  // used to fall back to cash and an UNKNOWN status to `completed`, so a
  // record we could not read presented itself as a settled cash payment —
  // with a reprintable receipt — for an order that may never have been paid.
  // Both are written unconditionally, so neither fallback was ever legacy
  // tolerance; it was a fabricated settlement.
  final method = PaymentMethod.fromWire(j['method']);
  if (method == null) {
    throw FormatException(
      'recent order: payment method is not a known method (${j['method']})',
    );
  }
  final status = _statusFromWire(j['status']);
  if (status == null) {
    throw FormatException(
      'recent order: payment status is not a known status (${j['status']})',
    );
  }
  // MONEY-LOCAL-ATOMICITY-003A — a PERSISTED local payment records a
  // SETTLEMENT, and only `completed` is one.
  //
  // 002B stopped an UNKNOWN status becoming `completed`, but a KNOWN
  // non-terminal one still decoded into a payment object — and every receipt
  // gate downstream asked only whether a payment existed. So a `pending`,
  // `tendered`, `voided` or `failed` marker presented itself as settled and
  // offered a reprintable receipt for money that was never taken.
  //
  // Refusing the record is the right outcome rather than "keep it unpaid":
  // this device only ever writes a payment here on a CONFIRMED settlement, so a
  // non-completed value is corruption. The quarantine seam keeps the raw record
  // and the order stays visible and payable from its own (valid) order money —
  // a later real payment attaches normally.
  if (!status.isPaid) {
    throw FormatException(
      'recent order: a persisted payment must be a settlement, got '
      '"${status.wire}"',
    );
  }
  return CashPayment(
    paymentId: _requireString(j, 'payment_id', 'payment'),
    orderId: _strOrNull(j['order_id']),
    orderNumber: _requireString(j, 'order_number', 'payment'),
    // The D-022 idempotency key halves. Written unconditionally; a coerced
    // '7' or 'null' would silently re-key the operation.
    deviceId: _requireString(j, 'device_id', 'payment', allowBlank: true),
    localOperationId: _requireString(
      j,
      'local_operation_id',
      'payment',
      allowBlank: true,
    ),
    method: method,
    status: status,
    amountMinor: _requireMoney(j, 'amount_minor', 'payment'),
    tenderedMinor: _requireMoney(j, 'tendered_minor', 'payment'),
    changeMinor: _requireMoney(j, 'change_minor', 'payment'),
    currencyCode: _requireString(j, 'currency_code', 'payment'),
    // A payment may legitimately hold no receipt number yet (offline, before
    // the branch sequence assigns one), so blank is allowed — but a non-string
    // is still corruption.
    receiptNumber: _requireString(
      j,
      'receipt_number',
      'payment',
      allowBlank: true,
    ),
    paidAt: paidAt,
    orderStatus: _strOrNull(j['order_status']),
  );
}

/// MONEY-LOCAL-ATOMICITY-003A — fail closed on an UNKNOWN order type.
///
/// This used to map anything unrecognised to takeaway, so a corrupt or foreign
/// token silently changed a dine-in order's operational meaning. Absence keeps
/// its documented legacy default (records written before the key existed); a
/// PRESENT value must be an exact known token, and anything else refuses the
/// record like the money fields around it.
OrderType _requireOrderType(Map<String, Object?> j, String key) {
  // Absence is history. An explicit null is a PRESENT wrong type, and is
  // corruption — the same containsKey distinction the money decoders use.
  if (!j.containsKey(key)) return OrderType.takeaway;
  final raw = j[key];
  for (final t in OrderType.values) {
    if (t.name == raw) return t;
  }
  throw FormatException(
    'recent order: order_type is not a known type ('
    '${raw is String ? '"$raw"' : raw.runtimeType})',
  );
}

/// MONEY-LOCAL-DECODE-INTEGRITY-002B: null on an unknown wire value. The
/// caller refuses the record rather than assuming it was `completed`.
PaymentStatus? _statusFromWire(Object? wire) {
  for (final s in PaymentStatus.values) {
    if (s.wire == wire) return s;
  }
  return null;
}

/// MONEY-LOCAL-DECODE-INTEGRITY-002B (Codex Blocker 3) — money is read
/// EXACTLY. The old `_int` coerced through `int.tryParse('$v') ?? 0`, so a
/// corrupt or foreign total read as 0: an order that had been paid in full
/// could re-present itself as free, and the cashier would have no way to tell.
/// A value we cannot read is not a zero — it is a record we must refuse.
int _requireInt(Map<String, Object?> j, String key, String what) {
  final raw = j[key];
  if (raw is int) return raw;
  throw FormatException(
    'recent order: $what $key is not an integer '
    '(${raw == null ? 'absent/null' : raw.runtimeType})',
  );
}

/// A money field that must be exact AND non-negative.
int _requireMoney(Map<String, Object?> j, String key, String what) {
  final v = _requireInt(j, key, what);
  if (v < 0) {
    throw FormatException('recent order: $what $key must be >= 0, got $v');
  }
  return v;
}

/// An ADDITIVE snapshot written only when non-zero: absent is legitimate
/// history, present-but-unreadable is corruption.
int _optionalInt(Map<String, Object?> j, String key, String what) {
  if (!j.containsKey(key) || j[key] == null) return 0;
  return _requireInt(j, key, what);
}

String _requireString(
  Map<String, Object?> j,
  String key,
  String what, {
  bool allowBlank = false,
}) {
  final raw = j[key];
  if (raw is String && (allowBlank || raw.trim().isNotEmpty)) return raw;
  throw FormatException(
    'recent order: $what $key is not a '
    '${allowBlank ? '' : 'non-blank '}string '
    '(${raw == null ? 'absent/null' : raw.runtimeType})',
  );
}

String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}
