/// POS-OPERATIONS-SYNC-001 (Commit 3) — THE action-eligibility policy.
///
/// One place decides what a cashier may do to an order. Before this, the answer was
/// spread across a row widget, three sheets and a couple of getters, each asking a
/// slightly different question — which is exactly how a completed order kept its
/// Take-payment button and a comped one kept asking to be paid.
///
/// PURE. No widgets, no providers, no I/O — so every rule below is directly testable
/// and there is exactly one of each.
///
/// The server remains the sole authority. Nothing here GRANTS anything; it only
/// declines to offer a control that we already know cannot work. A button that
/// always fails is a lie, and a cashier under rush deserves better than a lie.
library;

import 'order_snapshot.dart';
import 'recent_order.dart';
import 'staff_capabilities.dart';

/// What may be done to one order, right now, given the latest authoritative state.
class PosOrderActions {
  const PosOrderActions({
    required this.canPay,
    required this.canDiscount,
    required this.canFullComp,
    required this.canVoid,
    required this.canOpenReceipt,
    required this.pendingKind,
  });

  final bool canPay;
  final bool canDiscount;

  /// May bring the total to exactly zero. Requires [canDiscount] TOO — a comp is a
  /// discount, and a cashier who may not discount at all certainly may not comp.
  final bool canFullComp;

  final bool canVoid;

  /// A receipt can be rebuilt: this device holds the order-time lines AND a payment
  /// exists. A discovered order has no lines — printing one would be a forgery.
  final bool canOpenReceipt;

  /// The local operation this device has in flight for the order, if any. It is
  /// reported SEPARATELY from the lifecycle status, because "my payment is syncing"
  /// is a fact about this till, not about the order.
  final PosPendingKind? pendingKind;

  bool get hasPending => pendingKind != null;

  /// True when nothing at all can be offered — the row shows no trailing actions.
  bool get isEmpty => !canPay && !canDiscount && !canVoid && !canOpenReceipt;
}

/// The local mutation this device currently has queued/in flight for an order.
enum PosPendingKind { submit, payment, discount, cancellation }

/// Decides what may be offered for [order].
///
/// [capabilities] are the operator's EFFECTIVE rights, or NULL when unknown.
/// UNKNOWN IS NOT DENIED: a failed capability probe must not silently strip a
/// manager of the ability to discount — we let the SERVER refuse, which it does
/// correctly. Nothing unsafe follows, because the server gate is authoritative.
PosOrderActions resolveOrderActions(
  PosRecentOrder order, {
  PosStaffCapabilities? capabilities,
  PosPendingKind? pending,
}) {
  // A LOCAL DRAFT has no server order. Nothing can be done to it here; it is not a
  // server order at all and must never be presented as one.
  if (order.origin == PosOrderOrigin.localDraft || order.orderId == null) {
    return const PosOrderActions(
      canPay: false,
      canDiscount: false,
      canFullComp: false,
      canVoid: false,
      canOpenReceipt: false,
      pendingKind: null,
    );
  }

  // TERMINAL IS ABSOLUTE. completed / cancelled / voided accept NO mutation —
  // whichever device closed it, and whether or not this one ever heard about it.
  //
  // It is read from the AUTHORITATIVE status only. It is never inferred from a zero
  // total, a missing payment marker, a SQLSTATE, a generic rejection or raw error
  // text — every one of those has, at some point, told this POS something false.
  final terminal = order.isTerminal;

  final settlement = order.settlement;
  final total = order.grandTotalMinor;

  // The server REFUSED a payment for this exact order and said why. No tender, no
  // amount and no retry can change that; the flag survives until the row is
  // reconciled away from it.
  final refusedAsNonChargeable = order.lastSyncError == 'order_not_chargeable';

  // The PAYMENT MARKER — "has money been taken?" — as distinct from settlement,
  // which asks "does it still owe?". Both questions are real, and they can disagree.
  final alreadyCharged = order.isPaid;

  // PAYMENT. Offered only when there is genuinely money to collect AND the server
  // could actually accept it.
  //
  // `!alreadyCharged` is NOT redundant with the settlement test. An UNDER-COVERED
  // order (a payment exists but does not cover the total) reads `unpaid` — it truly
  // does still owe money — and yet a SECOND payment is impossible:
  // `payments_one_completed_per_order_uidx` permits at most ONE completed payment per
  // order, so the server would refuse it. Offering the button anyway would be
  // offering a control that cannot work. Collecting a shortfall needs split payment,
  // which is explicitly out of scope; the order stays visibly Unpaid, which is the
  // honest state, rather than being hidden behind a button that fails.
  final canPay =
      !terminal &&
      settlement == PosSettlement.unpaid && // excludes paid AND notChargeable
      total >
          0 && //                          a non-positive total is never payable
      !alreadyCharged &&
      !refusedAsNonChargeable &&
      pending != PosPendingKind.payment && // no second concurrent payment
      pending != PosPendingKind.cancellation;

  // DISCOUNT. Frozen once a live completed payment exists (the financial snapshot
  // freezes at payment — a post-payment price change is a refund, and there is no
  // refund flow). The MARKER is the right test here: the question is "has this order
  // been CHARGED?", not "does it still owe?".
  final frozenByPayment = alreadyCharged;
  final mayDiscount = capabilities?.applyDiscount ?? true; // unknown != denied
  final canDiscount =
      !terminal &&
      !frozenByPayment &&
      mayDiscount &&
      pending != PosPendingKind.discount &&
      pending != PosPendingKind.cancellation;

  // FULL COMP additionally needs the explicit right — and it needs the ordinary
  // discount right too. FULL-COMP-PERMISSION-001 does not let a comp grant smuggle
  // a cashier past the general discount gate; the server refuses that, and so do we.
  final mayComp = capabilities?.applyFullComp ?? true;
  final canFullComp = canDiscount && mayComp;

  // VOID. A live completed payment blocks it server-side (paid void/refund is
  // deferred), and a terminal order cannot be voided at all.
  final canVoid =
      !terminal &&
      !frozenByPayment &&
      pending != PosPendingKind.cancellation &&
      pending != PosPendingKind.payment;

  return PosOrderActions(
    canPay: canPay,
    canDiscount: canDiscount,
    canFullComp: canFullComp,
    canVoid: canVoid,
    // Reprint stays available for a real receipt even on a terminal order — reading
    // a receipt is not a mutation, and a closed order is exactly when someone asks
    // for one again.
    canOpenReceipt: order.canReprintReceipt,
    pendingKind: pending,
  );
}
