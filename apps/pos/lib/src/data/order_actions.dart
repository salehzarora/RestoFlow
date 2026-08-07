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

import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;

import 'order_identity.dart';
import 'order_snapshot.dart';
import 'order_submission.dart' show OutboxEntry, PosOrderOutcome;
import 'recent_order.dart';
import 'staff_capabilities.dart';

/// What may be done to one order, right now, given the latest authoritative state.
class PosOrderActions {
  const PosOrderActions({
    required this.canPay,
    required this.canDiscount,
    required this.canFullComp,
    required this.canVoid,
    required this.canMoveTable,
    required this.canOpenReceipt,
    required this.pendingKind,
    this.canAddItems = false,
    this.canComplete = false,
    this.canPrintBill = false,
    this.submitUnacknowledged = false,
  });

  final bool canPay;

  /// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass C] The customer-facing
  /// UNPAID PRE-BILL may be printed for this order.
  ///
  /// SEPARATE FROM [canPay] ON PURPOSE, and the separation is the fix. The bill
  /// action used to render inside `if (actions.canPay)`, so Pass B's
  /// acknowledgement rule — which correctly withdraws PAYMENT from an order the
  /// server has never seen — also removed the pre-bill from exactly the order
  /// that needs one most: the one taken during an outage. Printing is a READ-ONLY
  /// local render of data this device already holds; it takes no money, needs no
  /// server acceptance, and cannot be refused by a backend it never calls.
  ///
  /// It keeps every OTHER money interlock (see `resolveOrderActions`), because a
  /// bill is still a customer-facing money document: a paid, comped-to-zero,
  /// server-refused, terminal or mid-payment order must not be handed to a
  /// customer as an amount still due.
  final bool canPrintBill;

  final bool canDiscount;

  /// May bring the total to exactly zero. Requires [canDiscount] TOO — a comp is a
  /// discount, and a cashier who may not discount at all certainly may not comp.
  final bool canFullComp;

  final bool canVoid;

  /// RESTAURANT-OPERATIONS-V1-001: the order may be moved to another table —
  /// an ACTIVE DINE-IN order the server already knows about. Takeaway never
  /// sits at a table; a terminal order keeps its historical one. The server
  /// enforces both again (table_not_allowed / order_not_movable).
  final bool canMoveTable;

  /// A receipt can be rebuilt: this device holds the order-time lines AND a payment
  /// exists. A discovered order has no lines — printing one would be a forgery.
  final bool canOpenReceipt;

  /// PSC-001C: new items may be added to this order as an authoritative
  /// SERVICE ROUND — an ACTIVE (non-terminal) DINE-IN server order that has
  /// not been charged yet. The server enforces every rule again
  /// (order_not_dine_in / order_not_eligible / order_already_settled).
  final bool canAddItems;

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B): the explicit printer-only
  /// COMPLETE safety net may be offered — a served, fully-settled order on a
  /// VERIFIED printer_only branch, not terminal, no transition in flight, the
  /// actor authorized. Decided ONLY by the central [posOrderCloseEligibility]
  /// policy (passed in as `completeEligible`); the server re-enforces the
  /// served->completed transition + settlement.
  final bool canComplete;

  /// The local operation this device has in flight for the order, if any. It is
  /// reported SEPARATELY from the lifecycle status, because "my payment is syncing"
  /// is a fact about this till, not about the order.
  final PosPendingKind? pendingKind;

  /// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass B] WHY payment was withdrawn
  /// when it was withdrawn for this reason: the server has not acknowledged this
  /// order's `order.submit` yet (see [posSubmitUnacknowledged]).
  ///
  /// Carried on the result so the ONE payment entry point can say so in the
  /// cashier's words instead of showing the generic connectivity failure — and so
  /// the row, the detail preview and the confirmation all speak from the same
  /// decision. It NEVER grants anything; [canPay] is already false whenever it is
  /// true.
  final bool submitUnacknowledged;

  bool get hasPending => pendingKind != null;

  /// True when nothing at all can be offered — the row shows no trailing actions.
  ///
  /// Pass C: [canPrintBill] counts. It can be true while [canPay] is false (a
  /// queued offline order), and an "empty" verdict makes the caller skip the
  /// whole [OrderActionRow] — which would hide the pre-bill button again by a
  /// different route.
  bool get isEmpty =>
      !canPay &&
      !canPrintBill &&
      !canDiscount &&
      !canVoid &&
      !canMoveTable &&
      !canOpenReceipt &&
      !canAddItems &&
      !canComplete;
}

/// The local mutation this device currently has queued/in flight for an order.
enum PosPendingKind { submit, payment, discount, cancellation, itemsAdd }

/// The IDENTITY of the order an outbox entry targets.
///
/// `targetId` is the CLIENT-generated order id the server adopts, so a queued
/// submit resolves to the SAME identity as the recent-order row it created — and
/// never to a different order that merely shares its printed code.
PosOrderIdentity posOutboxEntryIdentity(OutboxEntry entry) =>
    PosOrderIdentity.of(
      orderId: entry.targetId,
      localOperationId: entry.localOperationId,
      orderNumber: entry.summary.orderNumber,
    );

/// This device's `order.submit` entry for [identity], or null when it holds none.
///
/// RESTRICTED TO `order.submit` deliberately. Later operations (a payment, a
/// discount) target the same order id and therefore resolve to the same identity,
/// and their state says nothing about whether the ORDER itself was accepted —
/// which is the only question [posSubmitUnacknowledged] asks.
OutboxEntry? posSubmitEntryFor(
  List<OutboxEntry> entries,
  PosOrderIdentity identity,
) {
  for (final e in entries) {
    if (e.operationType != 'order.submit') continue;
    if (posOutboxEntryIdentity(e) == identity) return e;
  }
  return null;
}

/// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass B] — HAS THE SERVER
/// ACKNOWLEDGED THIS ORDER'S SUBMIT?
///
/// THE DEFECT this answers: `resolveOrderActions` decided `canPay` without ever
/// asking, and [PosPendingKind.submit] did not withdraw it. So while a queued
/// submit was still pending / in flight / transiently failed, the Pay button was
/// live — and tapping it sent `record_payment` for an order the server had never
/// seen. `app.record_payment` then raised `order not found` (42501), `sync_push`
/// classified that as a PERMANENT rejection, and the sheet showed the generic
/// "check the connection" banner: order-specific, unrecoverable by retrying, and
/// indistinguishable from a network fault.
///
/// IT FAILS OPEN, and that is the whole safety argument. It answers true ONLY on
/// POSITIVE evidence that the submit is still unacknowledged:
///
///   * NOT demo mode — in demo the entry is never pushed, so it stays pending
///     forever and would strip payment from every demo order;
///   * the row holds NO server snapshot — a snapshot IS the server speaking about
///     this order, so its existence is settled whatever the entry still says;
///   * this device HOLDS an `order.submit` entry for the identity — no entry means
///     UNKNOWN (a device-owned row from before this build, a discovered order),
///     and unknown is never denied; and
///   * that entry's [OutboxEntry.outcome] is not [PosOrderOutcome.accepted] —
///     the same typed vocabulary `hasDefinitiveVerdict` and
///     `isDefinitiveNoServerOrder` speak. PENDING IS NOT ACCEPTED (024), and an
///     UNCONFIRMED delivery is not acceptance either: nobody has told us the order
///     exists, and `payments_one_completed_per_order_uidx` gives us exactly one
///     attempt to get the payment right.
///
/// Nothing here is a permanent verdict: the outbox re-pushes the SAME identity
/// (D-022), the server replays it idempotently, and the entry flips to `applied` —
/// at which point this reads false again and payment reopens with no restart.
bool posSubmitUnacknowledged({
  required bool isDemo,
  required bool hasServerSnapshot,
  required OutboxEntry? submitEntry,
}) {
  if (isDemo) return false;
  if (hasServerSnapshot) return false;
  final entry = submitEntry;
  if (entry == null) return false; // unknown is NOT denied
  return entry.outcome != PosOrderOutcome.accepted;
}

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
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B): whether the central
  // posOrderCloseEligibility policy returned `allowed` for this order (computed by
  // the caller from the VERIFIED kitchen mode + settlement + status + authorization
  // + in-flight). Gated below by the same terminal/draft guards as every action.
  bool completeEligible = false,
  // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass B] Whether the server has NOT
  // acknowledged this order's `order.submit` yet, computed by the caller with
  // [posSubmitUnacknowledged] (which owns the fail-open rule). It withdraws
  // PAYMENT and nothing else: void, discount, move, add-items, receipt and print
  // are unchanged, because none of them is the operation that fails with
  // `order not found` against an order the server has never seen.
  bool submitUnacknowledged = false,
  // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass C] Whether a
  // [PosPendingKind.itemsAdd] on this row is the STARTUP BLANKET rather than a
  // real amendment for THIS order.
  //
  // The Orders sheet stamps `itemsAdd` on EVERY row while the durable amendment
  // journal is still being read (or could not be read) — a deliberate
  // fail-closed for MONEY actions, because until that read lands we do not know
  // which orders have a round in flight. It is not evidence about any particular
  // order, and `hydrationFailed` makes it non-transient.
  //
  // It relaxes [PosOrderActions.canPrintBill] and NOTHING else: with no money
  // taken, the worst case of a read-only pre-bill is a provisional total (which
  // a pre-bill is by definition — the customer can order another round the
  // moment it is printed), while the alternative is a till that cannot hand
  // anyone a bill because a local disk read failed. A REAL amendment for this
  // order still withdraws the bill, because THAT total is knowably moving.
  bool amendmentsHydrating = false,
}) {
  // A LOCAL DRAFT has no server order. Nothing can be done to it here; it is not a
  // server order at all and must never be presented as one.
  //
  // PILOT-OPERATIONS-CORRECTIONS-001 (A3): a PERMANENTLY-REJECTED submit
  // ([PosRecentOrder.isNeverCreated]) is the same situation dressed as a real order:
  // it carries a NON-NULL locally-generated order id, but the authoritative submit
  // result was a permanent rejection (item_unavailable), so no server order exists.
  // Deciding eligibility from `orderId != null` alone is exactly the bug — a local id
  // is not proof of acceptance — so this fails closed here, in the ONE policy, rather
  // than in scattered per-button checks.
  if (order.origin == PosOrderOrigin.localDraft ||
      order.isNeverCreated ||
      order.orderId == null) {
    return const PosOrderActions(
      canPay: false,
      canDiscount: false,
      canFullComp: false,
      canVoid: false,
      canMoveTable: false,
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
  // MONEY-DURABLE-ADDITIONS-003C: an UNRESOLVED items-add withdraws every money
  // action on that order. The total on screen predates the amendment — the
  // server has either already applied it or may still be about to — so acting
  // on that number charges, discounts or voids the wrong amount. This is not a
  // race we can win by being quick: for payment it is unrecoverable, because
  // `payments_one_completed_per_order_uidx` permits exactly ONE completed
  // payment per order, so a payment taken against the pre-addition total cannot
  // be topped up afterwards. It withdraws actions on THIS order only.
  final amending = pending == PosPendingKind.itemsAdd;

  final canPay =
      !terminal &&
      settlement == PosSettlement.unpaid && // excludes paid AND notChargeable
      total >
          0 && //                          a non-positive total is never payable
      !alreadyCharged &&
      !refusedAsNonChargeable &&
      !amending && //                      the total predates the amendment
      // Pass B: the server has never acknowledged this order, so `record_payment`
      // can only answer `order not found`. Withdrawn until the submit is applied
      // — which the outbox achieves on its own, without a restart.
      !submitUnacknowledged &&
      pending != PosPendingKind.payment && // no second concurrent payment
      pending != PosPendingKind.cancellation;

  // PRE-BILL (Pass C). The customer-facing UNPAID bill — a READ-ONLY local
  // render, never a server call, so it asks for no server acceptance.
  //
  // It is EXACTLY the pre-Pass-B payment eligibility MINUS the acknowledgement
  // requirement: same terminal / settlement / positive-total / already-charged /
  // server-refused / in-flight-payment / in-flight-cancellation interlocks,
  // because a bill is still a money document handed to a customer and must never
  // state an amount due on an order that is paid, comped to zero, refused as
  // non-chargeable, cancelled, or being paid right now.
  //
  // What it deliberately does NOT require is [submitUnacknowledged] being false.
  // A queued offline order is precisely the case this exists for: the kitchen has
  // the food, the customer wants the bill, and the only thing missing is a
  // network the customer did not break. `record_payment` would answer
  // `order not found`; a printer does not answer anything at all.
  //
  // The `itemsAdd` interlock stays for a REAL amendment (the printed total would
  // predate the round) and is relaxed only for the startup blanket — see
  // [amendmentsHydrating].
  final canPrintBill =
      !terminal &&
      settlement == PosSettlement.unpaid &&
      total > 0 &&
      !alreadyCharged &&
      !refusedAsNonChargeable &&
      (!amending || amendmentsHydrating) &&
      pending != PosPendingKind.payment &&
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
      !amending && // the base the discount applies to is still moving (003C)
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
      !amending && // voiding an order mid-amendment races the round (003C)
      pending != PosPendingKind.cancellation &&
      pending != PosPendingKind.payment;

  // MOVE TABLE (RESTAURANT-OPERATIONS-V1-001). A floor action, not a money
  // action: any order-taking session may move an ACTIVE DINE-IN order the
  // server already holds. Withheld while THIS device has any operation in
  // flight for the order — a move races nothing from here, and its
  // expected_revision would be stale the moment the queued work lands.
  final canMoveTable =
      !terminal && order.orderType == OrderType.dineIn && pending == null;

  // ADD ITEMS (PSC-001C). New work joins the SAME bill as a service round —
  // never on a terminal order, FROZEN once the order has been charged (the same
  // freeze that guards discounts: a charged bill's total must keep matching its
  // numbered receipt), and withheld while THIS device has any operation in
  // flight for the order (a stale expected state helps nobody). A comped-to-zero
  // UNPAID order stays eligible — the addition simply makes it chargeable again.
  //
  // DEFERRED-ORDER-AMENDMENTS-001: TAKEAWAY is now eligible too, matching the
  // widened server gate (`app.add_order_items` accepts dine_in AND takeaway). A
  // takeaway customer who orders more while still waiting is the same operation
  // as a dine-in table asking for another round; refusing it forced a second,
  // separately-paid order for one visit. NO table is required — a takeaway order
  // has none, and the server does not ask for one.
  //
  // "Charged" here spans BOTH channels: this device's own payment MARKER and
  // the SERVER's settlement verdict — a branch-DISCOVERED paid order has no
  // local payment row, and its snapshot saying `paid` is exactly the server
  // telling us the freeze applies (offering the button would offer a control
  // the server refuses with order_already_settled).
  final chargedPerServer = alreadyCharged || settlement == PosSettlement.paid;
  final canAddItems =
      !terminal &&
      (order.orderType == OrderType.dineIn ||
          order.orderType == OrderType.takeaway) &&
      !chargedPerServer &&
      pending == null;

  return PosOrderActions(
    canPay: canPay,
    // Pass C: the read-only pre-bill, decided independently of payment.
    canPrintBill: canPrintBill,
    canDiscount: canDiscount,
    canFullComp: canFullComp,
    canVoid: canVoid,
    canMoveTable: canMoveTable,
    // Reprint stays available for a real receipt even on a terminal order — reading
    // a receipt is not a mutation, and a closed order is exactly when someone asks
    // for one again.
    // PSC-001C: the AUTHORITATIVE server detail (pos_order_detail) can rebuild
    // the COMBINED receipt for any PAID server order — original + added items
    // as one list — so a different POS device is no longer blind. The local
    // order-time-lines path stays first-class; the detail read is the honest
    // cross-device upgrade (no more forgery risk: the lines come from the
    // server, not a guess). "Paid" spans the local marker AND the server's
    // settlement verdict (a discovered paid order has no local payment row).
    canOpenReceipt:
        order.canReprintReceipt || (chargedPerServer && order.orderId != null),
    pendingKind: pending,
    canAddItems: canAddItems,
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B): the printer-only Complete safety
    // net — the central policy's `allowed`, re-guarded by terminal here (a terminal
    // order accepts no mutation, whichever device closed it).
    canComplete: completeEligible && !terminal,
    // Pass B: reported so the ONE payment entry point can explain the refusal in
    // sync terms rather than connectivity terms.
    submitUnacknowledged: submitUnacknowledged,
  );
}
