/// POS-OPERATIONS-SYNC-001 — the AUTHORITATIVE server view of a persisted order,
/// and the two enums the POS reasons about it with.
///
/// The POS used to hold only what it SUBMITTED and never hear from the server
/// again, so a discount, a payment, a KDS bump, an auto-completion or a void were
/// all invisible to it. Everything in this file exists to end that: it is the
/// typed, validated mirror of `app.pos_order_snapshots`.
///
/// Money is integer minor units (D-007) — always, everywhere, no exceptions.
library;

/// THE ONE client settlement model (POS-OPERATIONS-SYNC-001).
///
/// "Does this order still owe money?" has exactly ONE answer, and it is the
/// SERVER's. Before this, the POS re-derived settlement in three places from the
/// stale submit-time total, which is how a comped order stayed "unpaid" forever.
///
/// This mirrors `app.order_is_fully_settled` (D-025):
///   * a ZERO-total order is [notChargeable] — it owes nothing and carries no
///     payment row. It is NOT "unpaid", and it is NOT "paid" either; saying "paid"
///     of an order nobody paid for is a lie the audit trail already refuses to tell.
///   * a positive total is [paid] only when a live completed payment COVERS it.
///   * anything else is [unpaid].
enum PosSettlement {
  paid,
  unpaid,
  notChargeable;

  /// Parses the server's `payment_status` token. FAIL CLOSED: an unknown, missing
  /// or malformed value reads as [unpaid], never as settled — an order we cannot
  /// classify must keep asking to be dealt with, not quietly disappear.
  static PosSettlement fromWire(Object? wire) => switch (wire) {
    'paid' => PosSettlement.paid,
    'not_chargeable' => PosSettlement.notChargeable,
    _ => PosSettlement.unpaid,
  };

  String get wire => switch (this) {
    PosSettlement.paid => 'paid',
    PosSettlement.unpaid => 'unpaid',
    PosSettlement.notChargeable => 'not_chargeable',
  };

  /// True when the order owes nothing further — paid OR non-chargeable.
  bool get isSettled => this != PosSettlement.unpaid;

  /// True only when this order should be counted in the cashier's UNPAID badge.
  /// Terminality is a SEPARATE axis and is applied by the caller (D-025).
  bool get owesMoney => this == PosSettlement.unpaid;
}

/// The CANONICAL order lifecycle statuses (D-018). Kept as a closed set so the
/// client can recognise a terminal order without inventing states: an UNKNOWN
/// server status is preserved verbatim and treated as NON-terminal, because
/// fabricating "terminal" from a token we do not understand would silently strip
/// a cashier's payment and cancel controls.
const Set<String> kPosTerminalStatuses = <String>{
  'completed',
  'cancelled',
  'voided',
};

/// The statuses an order passes through while it is still operationally OPEN.
const Set<String> kPosOpenStatuses = <String>{
  'submitted',
  'accepted',
  'preparing',
  'ready',
  'served',
};

/// WHERE A ROW CAME FROM — its ownership, which is a different question from both
/// its lifecycle status and its sync state (POS-OPERATIONS-SYNC-001, Commit 3).
///
/// The operational centre shows the BRANCH's orders, not just this till's. That
/// only works if "this device made it" and "the server told us about it" stay
/// distinct: a row we merely discovered must never inherit another till's queue, and
/// a receipt can only be reprinted for lines this device actually captured.
enum PosOrderOrigin {
  /// Never submitted. Exists only here. The server has no such order, so a snapshot
  /// can neither create nor overwrite one.
  localDraft,

  /// THIS device submitted it (or holds durable local operations for it). It may
  /// carry queued work, and it has the order-time line snapshot a receipt needs.
  deviceOwned,

  /// Discovered from the server's branch feed — another till took it. We hold the
  /// authoritative server fields and NOTHING local: no lines, no receipt, and above
  /// all no other device's pending operations.
  ///
  /// It can BECOME device-interacted (this till pays it, discounts it, cancels it),
  /// but it stays ONE row: origin describes where it came from, not who may act.
  branchDiscovered;

  /// True when this device holds the order-time snapshot (lines + prices) that a
  /// receipt is built from. A discovered order has none — and inventing empty lines
  /// to print would be a forged receipt.
  bool get hasLocalOrderSnapshot => this == PosOrderOrigin.deviceOwned;
}

/// The LOCAL synchronization state of a POS order — deliberately NOT the order's
/// lifecycle status.
///
/// These two were conflated before, and that is a category error: `served` is
/// where the ORDER is; `pendingOperation` is where THIS DEVICE is with respect to
/// the server. An order can be `served` (lifecycle) while its discount is still
/// queued (sync). Keeping them apart is what lets a snapshot refresh authoritative
/// money WITHOUT touching a queued operation.
enum PosOrderSyncState {
  /// Never submitted. The server has no such order. A snapshot must NEVER
  /// overwrite this — there is nothing to overwrite it WITH.
  localDraft,

  /// Queued locally, not yet acknowledged by the server.
  pendingSubmit,

  /// Acknowledged; local state matches the last authoritative snapshot.
  synchronized,

  /// Persisted server-side, but this device has a mutation (payment / discount /
  /// void) queued or in flight. A snapshot may refresh the AUTHORITATIVE fields;
  /// it must never mark the pending operation successful.
  pendingOperation,

  /// The server REFUSED this device's operation, or the revision conflicted. The
  /// refusal is kept so the UI can explain it honestly; it is never auto-retried.
  rejected,

  /// The server says the order is terminal (completed / cancelled / voided). No
  /// mutation can succeed against it.
  terminal;

  /// True while this device still owes the server work, or is waiting on it.
  bool get hasPendingWork =>
      this == PosOrderSyncState.pendingSubmit ||
      this == PosOrderSyncState.pendingOperation;
}

/// A keyset cursor into the server's change feed: `(sync_at, id)`.
///
/// `sync_at` is `greatest(order.updated_at, completed_payment.updated_at)` — NOT
/// `orders.updated_at`. A payment does not touch the order row, so a cursor over
/// the order alone would never deliver a paid-but-not-yet-completed order. Both
/// halves are required; a half cursor is refused by the server.
class PosSyncCursor {
  const PosSyncCursor({required this.at, required this.id});

  final DateTime at;
  final String id;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.toIso8601String(),
    'id': id,
  };

  /// Returns null for anything malformed — a bad cursor must never be coerced
  /// into "start from the beginning", which would silently re-deliver the whole
  /// window and look like success.
  static PosSyncCursor? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawAt = json['at'];
    final rawId = json['id'];
    if (rawAt is! String || rawId is! String || rawId.isEmpty) return null;
    final at = DateTime.tryParse(rawAt);
    if (at == null) return null;
    return PosSyncCursor(at: at, id: rawId);
  }

  @override
  bool operator ==(Object other) =>
      other is PosSyncCursor && other.at == at && other.id == id;

  @override
  int get hashCode => Object.hash(at, id);
}

/// The AUTHORITATIVE server snapshot of one order, as returned by
/// `app.pos_order_snapshots`. Strictly validated: a snapshot is either fully
/// valid or REJECTED — never partially applied.
class PosOrderSnapshot {
  const PosOrderSnapshot({
    required this.orderId,
    required this.orderCode,
    required this.revision,
    required this.status,
    required this.settlement,
    required this.subtotalMinor,
    required this.discountTotalMinor,
    required this.taxTotalMinor,
    required this.grandTotalMinor,
    required this.createdAt,
    required this.updatedAt,
    required this.syncAt,
    this.orderType,
    this.tableLabel,
    this.currencyCode,
  });

  final String orderId;

  /// The SAFE `#XXXXXX` reference. Never the raw UUID.
  final String orderCode;

  /// The server's optimistic-concurrency revision. The POS stored NONE before
  /// this ticket, which is why `expected_revision` was dead code and the server's
  /// conflict branch was unreachable from the POS.
  final int revision;

  /// The canonical lifecycle status, verbatim from the server. An unrecognised
  /// value is preserved and treated as NON-terminal (see [isTerminal]).
  final String status;

  /// SERVER-COMPUTED settlement. The client never re-derives this.
  final PosSettlement settlement;

  final int subtotalMinor;
  final int discountTotalMinor;
  final int taxTotalMinor;
  final int grandTotalMinor;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// `greatest(order.updated_at, completed_payment.updated_at)` — the cursor axis.
  final DateTime syncAt;

  final String? orderType;
  final String? tableLabel;
  final String? currencyCode;

  /// Terminal per the CANONICAL set only. An unknown status is NOT terminal: we
  /// will not invent a lifecycle state, and wrongly calling an order terminal
  /// would strip the cashier's payment and cancel controls on a live order.
  bool get isTerminal => kPosTerminalStatuses.contains(status);

  bool get isNonChargeable => settlement == PosSettlement.notChargeable;

  /// Strict parse. Returns null (REJECT, atomically) when ANY required field is
  /// missing or malformed, or when money is negative — the DB forbids a negative
  /// total, so seeing one means the payload is not what it claims to be, and a
  /// half-applied snapshot is worse than none.
  static PosOrderSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final orderId = _str(raw['order_id']);
    final orderCode = _str(raw['order_code']);
    final status = _str(raw['status']);
    if (orderId == null || orderCode == null || status == null) return null;

    final revision = _int(raw['revision']);
    if (revision == null || revision < 0) return null;

    final subtotal = _int(raw['subtotal_minor']);
    final discount = _int(raw['discount_total_minor']);
    final tax = _int(raw['tax_total_minor']);
    final grand = _int(raw['grand_total_minor']);
    if (subtotal == null || discount == null || tax == null || grand == null) {
      return null;
    }
    // FAIL CLOSED on negative money. `grand_total_minor >= 0` is a DB CHECK, so a
    // negative here is a corrupt/foreign payload, not a business case.
    if (subtotal < 0 || discount < 0 || tax < 0 || grand < 0) return null;

    final createdAt = _time(raw['created_at']);
    final updatedAt = _time(raw['updated_at']);
    final syncAt = _time(raw['sync_at']);
    if (createdAt == null || updatedAt == null || syncAt == null) return null;

    return PosOrderSnapshot(
      orderId: orderId,
      orderCode: orderCode,
      revision: revision,
      status: status,
      // An unknown/missing payment_status fails closed to `unpaid`.
      settlement: PosSettlement.fromWire(raw['payment_status']),
      subtotalMinor: subtotal,
      discountTotalMinor: discount,
      taxTotalMinor: tax,
      grandTotalMinor: grand,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncAt: syncAt,
      orderType: _str(raw['order_type']),
      tableLabel: _str(raw['table_label']),
      currencyCode: _str(raw['currency_code']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'order_id': orderId,
    'order_code': orderCode,
    'revision': revision,
    'status': status,
    'payment_status': settlement.wire,
    'subtotal_minor': subtotalMinor,
    'discount_total_minor': discountTotalMinor,
    'tax_total_minor': taxTotalMinor,
    'grand_total_minor': grandTotalMinor,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'sync_at': syncAt.toIso8601String(),
    if (orderType != null) 'order_type': orderType,
    if (tableLabel != null) 'table_label': tableLabel,
    if (currencyCode != null) 'currency_code': currencyCode,
  };

  /// The cursor position of this snapshot.
  PosSyncCursor get cursor => PosSyncCursor(at: syncAt, id: orderId);

  /// Is [other] STRICTLY NEWER authority than this?
  ///
  /// REVISION FIRST. A higher revision always wins. At EQUAL revision a newer
  /// `sync_at` may still carry news — a payment bumps `sync_at` WITHOUT bumping
  /// the order's revision, so settlement can change while the revision stands
  /// still. That single case is the reason equal-revision comparison exists at
  /// all; without it a paid order would never become "paid" on this device.
  ///
  /// An OLDER revision NEVER wins, whatever its timestamp says.
  bool isNewerThan(PosOrderSnapshot other) {
    if (revision != other.revision) return revision > other.revision;
    return syncAt.isAfter(other.syncAt);
  }
}

String? _str(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

/// Integers ONLY. A money value arriving as a double/string is a contract
/// violation (D-007), not something to coerce — coercion is exactly how float
/// money creeps in.
int? _int(Object? v) => v is int ? v : null;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
