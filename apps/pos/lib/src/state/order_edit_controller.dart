import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ids.dart';
import '../data/order_detail_repository.dart';
import '../data/order_edit_baseline.dart';
import '../data/order_edit_diff.dart';
import '../data/order_edit_journal_store.dart';
import '../data/order_edit_read_model.dart' show PosKitchenChannel;
import '../data/order_edit_response.dart';
import '../data/order_edit_slip.dart'
    show OrderEditSlipItem, orderEditSlipWasLines;
import 'addition_controller.dart';
import 'cart_controller.dart';
import 'discount_controller.dart' show staffCapabilitiesProvider;
import 'order_sync_controller.dart';
import 'pos_branch_tax.dart';
import 'pos_menu_provider.dart';
import 'pos_offline_state.dart';
import 'pos_session.dart';

/// ORDER-EDIT-001E — THE SENT-ORDER EDIT FLOW (design §7.1, API_CONTRACT
/// §4.45), the Add-items flow's pattern ([AdditionController]) for
/// `order.edit`.
///
/// While an edit is open the cart is in EDIT MODE ([CartController.loadForEdit]):
/// its lines are bound to the order's sent lines, and "Send changes" plans the
/// difference ([planOrderEdit]) and sends ONE `order.edit` operation through
/// `public.sync_push`. Editing is ONLINE ONLY (§4.45.1): nothing is queued.
///
/// HONESTY RULES (the Add-items rules, carried over):
///  * ENTRY IS CONTROLLER-OWNED: [enterForOrder] validates synchronously,
///    RESERVES the order under a fresh generation BEFORE any await, and
///    re-checks the generation, the still-empty cart and the idle addition
///    flow before the edit cart is loaded;
///  * THE FIRST SEND FREEZES ONE ATTEMPT: plan, payload, `local_operation_id`
///    and the cart lock are taken in ONE synchronous block, and the attempt is
///    JOURNALED (and the write confirmed) BEFORE a single byte reaches the
///    transport. A journal that cannot be written sends nothing;
///  * THE IDENTITY IS FROZEN: a retry re-sends the SAME id and the VERBATIM
///    payload — `sync_push` fingerprints the payload, so a rebuilt one would be
///    a conflict, never a replay;
///  * ONLY A VERDICT RELEASES IT: an applied answer is kept until the
///    authoritative detail PROVES it; a typed refusal (or a ledgered RAISE)
///    proves nothing was written; EVERYTHING else is outcome-unknown, and an
///    unknown outcome keeps the identity, the payload and the cart lock;
///  * DISCARD IS REFUSED once the attempt reached the wire;
///  * every asynchronous continuation is FENCED on the generation and the
///    attempt identity — a stale answer has no state side effect.
///
/// No change slip is printed here: the paper `order_edit` dispatch the server
/// returns is carried in the journal for ORDER-EDIT-001F, untouched.
class OrderEditAttempt {
  const OrderEditAttempt({
    required this.localOperationId,
    required this.orderId,
    required this.orderCode,
    required this.generation,
    required this.payload,
    required this.summary,
    required this.clientCreatedAt,
    this.employeeProfileId,
    this.slipWas,
  });

  /// A restored journal record as an attempt (cart-free: no edit cart is ever
  /// rebuilt from a record).
  factory OrderEditAttempt.fromRecord(OrderEditJournalRecord r) =>
      OrderEditAttempt(
        localOperationId: r.localOperationId,
        orderId: r.orderId,
        orderCode: r.orderCode,
        generation: r.generation,
        payload: r.payload,
        summary: r.summary,
        clientCreatedAt: r.clientCreatedAt,
        employeeProfileId: r.employeeProfileId,
        slipWas: r.slipWas,
      );

  /// The D-022 idempotency identity — one per attempt, reused by every retry.
  final String localOperationId;

  /// The order being edited; equals `payload['order_id']`, which `sync_push`
  /// requires to equal the op's `target_id`.
  final String orderId;
  final String orderCode;

  /// The cart-lock generation the attempt was frozen under.
  final int generation;

  /// THE FROZEN `order.edit` PAYLOAD — sent verbatim, never rebuilt.
  final Map<String, Object?> payload;

  /// Money-free counts, including the remake dishes the toast reports (D8).
  final OrderEditAttemptSummary summary;

  /// UTC — the op's `client_created_at`.
  final DateTime clientCreatedAt;

  /// The worker who froze it — diagnostic only (decision D12).
  final String? employeeProfileId;

  /// ORDER-EDIT-001F (D2): the money-free "was" projections of the lines the
  /// payload names, frozen from the baseline on a PAPER edit (null on KDS), so
  /// a cart-free replay can still hand-build the full change slip.
  final Map<String, OrderEditSlipItem>? slipWas;

  /// Whether the payload told the server a pre-bill had been presented
  /// (decision D7) — the result then offers "Bill changed: print new bill?".
  bool get billPresented => payload.containsKey('bill_presented_at');

  OrderEditJournalRecord toRecord({
    OrderEditJournalPhase phase = OrderEditJournalPhase.dispatching,
    int attemptCount = 1,
  }) => OrderEditJournalRecord(
    localOperationId: localOperationId,
    orderId: orderId,
    orderCode: orderCode,
    clientCreatedAt: clientCreatedAt,
    generation: generation,
    payload: payload,
    summary: summary,
    phase: phase,
    attemptCount: attemptCount,
    employeeProfileId: employeeProfileId,
    slipWas: slipWas,
  );
}

/// The lifecycle phase of the edit flow (one open edit at a time).
enum OrderEditPhase {
  /// No edit is open. Unresolved journal records may still block their orders.
  idle,

  /// The durable journal is being read — nothing is yet known about which
  /// orders carry an unresolved edit. Published SYNCHRONOUSLY by `build()`.
  hydrating,

  /// The journal could not be read. Never treated as an empty journal: no edit
  /// may start and every order stays held (fail closed).
  hydrationFailed,

  /// The order is RESERVED and its authoritative detail is loading.
  entering,

  /// The edit cart is loaded and the cashier is editing.
  active,

  /// The frozen attempt is on the wire. Discard is refused.
  sending,

  /// The attempt reached the transport and its outcome is UNKNOWN (or it is
  /// in conflict). The identity, payload and cart lock are kept; only a retry
  /// of the same identity can resolve it.
  failed,

  /// A `line_changed` / `totals_mismatch` (or a stale line flag) is being
  /// rebased onto the fresh detail.
  rebasing,

  /// The server APPLIED the edit; the authoritative refresh has not yet proven
  /// it. Never dispatched again — only the refresh may be retried.
  appliedAwaitingRefresh,
}

class OrderEditState {
  const OrderEditState({
    this.generation = 0,
    this.phase = OrderEditPhase.idle,
    this.entryOrderId,
    this.baseline,
    this.attempt,
    this.dispatched = false,
    this.applied,
    this.lastError,
    this.consecutiveTotalsMismatches = 0,
    this.records = const <String, OrderEditJournalRecord>{},
  });

  /// The entry/attempt token: every reservation, exit and completed reconcile
  /// bumps it, and every asynchronous continuation re-checks it.
  final int generation;
  final OrderEditPhase phase;

  /// The order RESERVED by entry — set before any await and held through every
  /// later phase of the open edit.
  final String? entryOrderId;

  /// The authoritative starting point of the open edit (null until loaded).
  final OrderEditBaseline? baseline;

  /// The FROZEN attempt of this session (sending / failed / applied-awaiting-
  /// refresh), or null.
  final OrderEditAttempt? attempt;

  /// Whether [attempt] reached the transport without a definitive verdict
  /// coming back — the server may own the edit. Discard is refused.
  final bool dispatched;

  /// The server's applied facts, while awaiting the authoritative refresh.
  final OrderEditApplied? applied;

  /// A SAFE classification code — never raw backend text.
  final String? lastError;

  /// How many `totals_mismatch` refusals came back IN A ROW. The first one is
  /// rebased automatically; a second one stops (decision D9 — the server's
  /// figures are never adopted).
  final int consecutiveTotalsMismatches;

  /// Every unresolved durable edit record of this device, by
  /// `local_operation_id` — including the ones of earlier sessions, which no
  /// cart is rebuilt for.
  final Map<String, OrderEditJournalRecord> records;

  bool get isHydrating => phase == OrderEditPhase.hydrating;
  bool get hydrationFailed => phase == OrderEditPhase.hydrationFailed;

  /// The startup gate: the journal is unread, or unreadable.
  bool get startupBlocked => isHydrating || hydrationFailed;

  /// An edit is open (reserved, editing, sending, unresolved or applied).
  bool get isEditing => entryOrderId != null;
  bool get sending => phase == OrderEditPhase.sending;
  bool get awaitingRefresh => phase == OrderEditPhase.appliedAwaitingRefresh;

  /// Discard is honest: offered only while nothing reached the server.
  bool get canDiscard =>
      !dispatched &&
      (phase == OrderEditPhase.entering || phase == OrderEditPhase.active);

  /// Orders with two or more live records, plus every server-declared
  /// conflict — frozen until a person settles them.
  Set<String> get conflictingOrderIds {
    final byOrder = <String, int>{};
    for (final r in records.values) {
      byOrder[r.orderId] = (byOrder[r.orderId] ?? 0) + 1;
    }
    return <String>{
      for (final e in byOrder.entries)
        if (e.value > 1) e.key,
      for (final r in records.values)
        if (r.isConflict) r.orderId,
    };
  }

  /// Orders whose money actions are withdrawn: this session's frozen attempt
  /// and every unresolved record (design §7.1 point 7).
  Set<String> get blockedOrderIds => <String>{
    if (attempt?.orderId case final id?) id,
    for (final r in records.values) r.orderId,
  };

  /// Whether an unresolved edit is carried for [orderId].
  bool hasUnresolvedEditFor(String orderId) =>
      attempt?.orderId == orderId ||
      records.values.any((r) => r.orderId == orderId);

  /// The record a retry of [orderId] replays — one whose outcome is unknown
  /// (or not yet proven applied) and that is not in conflict — or null.
  OrderEditJournalRecord? retryableRecordFor(String orderId) {
    if (conflictingOrderIds.contains(orderId)) return null;
    for (final r in records.values) {
      if (r.orderId != orderId || r.isConflict) continue;
      // This session's attempt is not retryable while it is on the wire.
      if (r.localOperationId == attempt?.localOperationId &&
          (phase == OrderEditPhase.sending ||
              phase == OrderEditPhase.rebasing)) {
        continue;
      }
      return r;
    }
    return null;
  }

  OrderEditState copyWith({
    OrderEditPhase? phase,
    OrderEditBaseline? baseline,
    OrderEditAttempt? attempt,
    bool? dispatched,
    OrderEditApplied? applied,
    String? lastError,
    bool clearError = false,
    int? consecutiveTotalsMismatches,
    Map<String, OrderEditJournalRecord>? records,
  }) => OrderEditState(
    generation: generation,
    phase: phase ?? this.phase,
    entryOrderId: entryOrderId,
    baseline: baseline ?? this.baseline,
    attempt: attempt ?? this.attempt,
    dispatched: dispatched ?? this.dispatched,
    applied: applied ?? this.applied,
    lastError: clearError ? null : (lastError ?? this.lastError),
    consecutiveTotalsMismatches:
        consecutiveTotalsMismatches ?? this.consecutiveTotalsMismatches,
    records: records ?? this.records,
  );
}

/// Why an [OrderEditController.enterForOrder] call was or was not honoured.
enum OrderEditEntryResult {
  /// Edit mode is active (or already entering) for the order.
  entered,

  /// The edit journal — or the Add-items journal — has not been read yet (or
  /// could not be read).
  hydrating,

  /// Another edit is open on this till.
  busy,

  /// An Add-items flow is open, or this order carries an unresolved addition.
  additionActive,

  /// The cart holds other work — park or clear it first.
  cartNotEmpty,

  /// The till is offline: editing needs a connection so the kitchen is told.
  offline,

  /// An earlier edit of this order is still unresolved.
  pendingAttempt,

  /// The server does not know the order (its submit never landed, or it is
  /// not this tenant's) — "Waiting for the order to reach the server".
  orderNotFound,

  /// The branch switch is off (or unknown).
  featureDisabled,

  /// Not dine-in / takeaway, or not `submitted..served`.
  notEditable,

  /// A completed payment exists.
  alreadyPaid,

  /// The kitchen channel is unresolvable.
  kitchenModeChanged,

  /// The authoritative detail could not be loaded or used.
  detailUnavailable,

  /// The entry was superseded while its detail loaded — no side effects.
  superseded,
}

/// What a send (or a retry) came to.
enum OrderEditSubmitStatus {
  /// Nothing reached the server: blocked before dispatch.
  notSent,

  /// The server applied the edit.
  applied,

  /// The server refused (a typed refusal or a ledgered RAISE): nothing was
  /// written and the identity is spent.
  refused,

  /// The outcome is unknown: the identity and the frozen payload are kept, and
  /// a retry replays them.
  uncertain,

  /// The identity is in conflict server-side; a person must settle it.
  conflict,
}

/// The cashier-facing meaning of an outcome — ONE value per message, mapped
/// to its l10n string by the widget layer (ORDER-EDIT-001E plan §8b).
enum OrderEditNotice {
  /// `posOrderEditRebased` (plus `posOrderEditRebaseDropped`).
  rebased,

  /// `posOrderEditReasonRequired`.
  reasonRequired,

  /// `posOrderEditAllRemovedUseCancel`.
  allRemovedUseCancel,

  /// `posDiscountExceedsOrderTotal`.
  discountExceedsOrderTotal,

  /// `posDiscountFullCompDenied`.
  fullCompDenied,

  /// `posOrderEditErrorRemovalNotPermitted`.
  removalNotPermitted,

  /// `posOrderEditErrorFinishedFoodNeedsManager`.
  finishedFoodNeedsManager,

  /// `posOrderEditErrorNotAllowed`.
  notAllowed,

  /// `posOrderEditErrorFeatureDisabled`.
  featureDisabled,

  /// `posOrderEditErrorNotEditable`.
  notEditable,

  /// `posOrderEditErrorAlreadyPaid`.
  alreadyPaid,

  /// `posOrderEditErrorKitchenModeChanged`.
  kitchenModeChanged,

  /// `posOrderEditErrorTaxModeUnsupported`.
  taxModeUnsupported,

  /// `posOrderEditErrorLineHasDiscount`.
  lineHasDiscount,

  /// `posOrderEditErrorLegacyLine`.
  legacyLine,

  /// `posOrderEditErrorItemUnavailable` (with the refused item names).
  itemUnavailable,

  /// `posOrderEditErrorOptionNotInScope`.
  optionNotInScope,

  /// `posPrepSnapshotStale`.
  prepSnapshotStale,

  /// `posOrderEditErrorInvalid`.
  invalid,

  /// `posOrderEditErrorTooManyChanges`.
  tooManyChanges,

  /// `posOrderEditBlockedUnacknowledged` — the 42501 anti-oracle.
  blockedUnacknowledged,

  /// `posOrderEditErrorSlipTooLarge` (23514).
  slipTooLarge,

  /// `posOrderEditRetry` — storage, transport or an unknown outcome.
  retry,

  /// `posAdditionConflictBlocked`.
  conflictBlocked,

  /// `posAdditionLoadingPending` — a journal is still being read.
  hydrating,

  /// `posOrderEditNeedsConnection`.
  needsConnection,

  /// `posAdditionFailedRetry` — the authoritative detail could not be loaded.
  detailUnavailable,
}

/// What a refusal does to the open edit (ORDER-EDIT-001E plan §8b).
enum OrderEditRefusalEffect {
  /// The edit stays open, unchanged, for the cashier to correct.
  stay,

  /// The edit ends: the cart leaves edit mode and the order is refreshed.
  exit,

  /// Another till changed the order: re-fetch, re-apply the cashier's intents
  /// to the fresh lines, and let the cashier send again (a NEW identity).
  rebase,

  /// A line's flags were stale: the same re-fetch and re-apply, under the
  /// refusal's own message.
  rebaseline,
}

/// The message and the effect of one outcome, plus the caches it stales.
class OrderEditRefusalPolicy {
  const OrderEditRefusalPolicy(
    this.notice,
    this.effect, {
    this.invalidateCapabilities = false,
    this.invalidateMenu = false,
  });

  final OrderEditNotice notice;
  final OrderEditRefusalEffect effect;

  /// The session's capability probe is stale (a right or the switch changed).
  final bool invalidateCapabilities;

  /// The menu this till sells from is stale.
  final bool invalidateMenu;
}

/// THE ONE mapping of an `order.edit` outcome to its message and effect
/// (API_CONTRACT §4.45.6; ORDER-EDIT-001E plan §8b). Null for an applied
/// outcome, which is not a refusal.
OrderEditRefusalPolicy? orderEditRefusalPolicy(OrderEditOutcome outcome) {
  const stay = OrderEditRefusalEffect.stay;
  const exit = OrderEditRefusalEffect.exit;
  switch (outcome.kind) {
    case OrderEditOutcomeKind.applied:
      return null;
    case OrderEditOutcomeKind.unknown:
      return const OrderEditRefusalPolicy(OrderEditNotice.retry, stay);
    case OrderEditOutcomeKind.conflict:
      return const OrderEditRefusalPolicy(
        OrderEditNotice.conflictBlocked,
        stay,
      );
    case OrderEditOutcomeKind.rejected:
      return switch (outcome.rejection!) {
        OrderEditRejection.orderNotFound => const OrderEditRefusalPolicy(
          OrderEditNotice.blockedUnacknowledged,
          exit,
        ),
        OrderEditRejection.notAllowed => const OrderEditRefusalPolicy(
          OrderEditNotice.notAllowed,
          exit,
        ),
        OrderEditRejection.slipTooLarge => const OrderEditRefusalPolicy(
          OrderEditNotice.slipTooLarge,
          stay,
        ),
        OrderEditRejection.invalid => const OrderEditRefusalPolicy(
          OrderEditNotice.invalid,
          stay,
        ),
      };
    case OrderEditOutcomeKind.refused:
      final refusal = outcome.refusal!;
      return switch (refusal.code) {
        'line_changed' || 'totals_mismatch' => const OrderEditRefusalPolicy(
          OrderEditNotice.rebased,
          OrderEditRefusalEffect.rebase,
        ),
        'reason_required' => const OrderEditRefusalPolicy(
          OrderEditNotice.reasonRequired,
          stay,
        ),
        'edit_would_empty_order' => const OrderEditRefusalPolicy(
          OrderEditNotice.allRemovedUseCancel,
          stay,
        ),
        'invalid_discount' => const OrderEditRefusalPolicy(
          OrderEditNotice.discountExceedsOrderTotal,
          stay,
        ),
        'permission_denied' => switch (refusal.detail) {
          'full_comp_permission_required' => const OrderEditRefusalPolicy(
            OrderEditNotice.fullCompDenied,
            stay,
          ),
          'removal_not_permitted' => const OrderEditRefusalPolicy(
            OrderEditNotice.removalNotPermitted,
            stay,
            invalidateCapabilities: true,
          ),
          'finished_food_needs_manager' => const OrderEditRefusalPolicy(
            OrderEditNotice.finishedFoodNeedsManager,
            stay,
            invalidateCapabilities: true,
          ),
          // No detail (the role check) or one this build does not know:
          // the edit cannot go through from here.
          _ => const OrderEditRefusalPolicy(OrderEditNotice.notAllowed, exit),
        },
        'invalid_device_type' => const OrderEditRefusalPolicy(
          OrderEditNotice.notAllowed,
          exit,
        ),
        'feature_disabled' => const OrderEditRefusalPolicy(
          OrderEditNotice.featureDisabled,
          exit,
          invalidateCapabilities: true,
        ),
        'order_not_editable' => const OrderEditRefusalPolicy(
          OrderEditNotice.notEditable,
          exit,
        ),
        'order_already_settled' => const OrderEditRefusalPolicy(
          OrderEditNotice.alreadyPaid,
          exit,
        ),
        'kitchen_mode_changed' => const OrderEditRefusalPolicy(
          OrderEditNotice.kitchenModeChanged,
          exit,
        ),
        'tax_mode_unsupported' => const OrderEditRefusalPolicy(
          OrderEditNotice.taxModeUnsupported,
          exit,
        ),
        'line_has_discount' => const OrderEditRefusalPolicy(
          OrderEditNotice.lineHasDiscount,
          OrderEditRefusalEffect.rebaseline,
        ),
        'legacy_line_not_editable' => const OrderEditRefusalPolicy(
          OrderEditNotice.legacyLine,
          OrderEditRefusalEffect.rebaseline,
        ),
        'item_unavailable' => const OrderEditRefusalPolicy(
          OrderEditNotice.itemUnavailable,
          stay,
          invalidateMenu: true,
        ),
        'modifier_option_not_in_scope' => const OrderEditRefusalPolicy(
          OrderEditNotice.optionNotInScope,
          stay,
          invalidateMenu: true,
        ),
        'modifier_prep_snapshot_stale' => const OrderEditRefusalPolicy(
          OrderEditNotice.prepSnapshotStale,
          stay,
          invalidateMenu: true,
        ),
        'too_many_changes' => const OrderEditRefusalPolicy(
          OrderEditNotice.tooManyChanges,
          stay,
        ),
        // invalid_payload, no_changes, duplicate_line_reference,
        // expected_totals_required, invalid_item_payload.
        _ => const OrderEditRefusalPolicy(OrderEditNotice.invalid, stay),
      };
  }
}

/// What one send, retry or refresh came to — everything the widget layer
/// needs for the toast or the refusal message, and nothing it must re-derive.
class OrderEditResult {
  const OrderEditResult({
    required this.status,
    this.notice,
    this.effect,
    this.outcome,
    this.applied,
    this.refreshRequired = false,
    this.remakeCount = 0,
    this.billPresented = false,
    this.droppedItems = const <String>[],
    this.sendBlock,
    this.error,
  });

  final OrderEditSubmitStatus status;

  /// The message to show, or null when there is nothing to say (the footer
  /// already explains a [sendBlock]).
  final OrderEditNotice? notice;

  /// What a refusal did to the open edit.
  final OrderEditRefusalEffect? effect;

  /// The classified server answer, when one came back.
  final OrderEditOutcome? outcome;

  /// The server's applied facts (`edit_number`, `kitchen_ack_required`, the
  /// channel and the new round) — the toast is built from these.
  final OrderEditApplied? applied;

  /// The edit is applied but the authoritative refresh did not prove it yet:
  /// the honest "saved, refresh required" state.
  final bool refreshRequired;

  /// Dishes the kitchen will make again — the frozen plan's allotment (D8).
  final int remakeCount;

  /// The payload carried `bill_presented_at` (D7): offer a new bill.
  final bool billPresented;

  /// After a rebase: the cashier's intents that no longer apply.
  final List<String> droppedItems;

  /// Why the send was blocked before dispatch, when the plan was the reason.
  final OrderEditSendBlock? sendBlock;

  /// A SAFE diagnostic code — never raw backend text.
  final String? error;

  /// `item_unavailable`: the names the server refused.
  List<String> get unavailableItems => [
    for (final i in outcome?.refusal?.items ?? const <OrderEditRefusedItem>[])
      if (i.name case final name?) name,
  ];
}

/// The cashier's intents re-applied to a fresh baseline (rebase, D9).
class OrderEditReplay {
  const OrderEditReplay({required this.lines, required this.droppedItems});

  /// The edit cart for the fresh baseline, in its print order, then the added
  /// lines in their old order.
  final List<OrderEditCartLine> lines;

  /// Names of the intents that no longer apply — left out, and said so.
  final List<String> droppedItems;
}

/// ORDER-EDIT-001E — THE REBASE REPLAY (design §7.1 point 9). PURE.
///
/// The cashier's intents are read as the changes [previousLines] plan against
/// [previous], keyed by `order_item_id`, and re-applied to [fresh]:
///
///  * an intent on a line that is STILL LIVE is kept when the fresh line still
///    allows it (a removal always; a quantity or option change only on a line
///    that is neither remove-only nor keep-or-remove-only, and an increase only
///    while the item is sellable) — its cart lines are carried over as they
///    were;
///  * an intent on a line that is gone (another till retired it), or that the
///    fresh flags no longer allow, is DROPPED and named. `pos_order_detail`
///    carries no replacement provenance, so following a line through another
///    till's edit would be a guess — and a guess here is money;
///  * every other fresh line is loaded untouched, including lines another till
///    added;
///  * added lines are always kept.
OrderEditReplay replayOrderEditIntents({
  required OrderEditBaseline previous,
  required List<OrderEditCartLine> previousLines,
  required OrderEditBaseline fresh,
}) {
  final plan = planOrderEdit(previous, previousLines, tax: BranchTax.disabled);
  final intents = <String, OrderEditPlannedChange>{
    for (final c in plan.plannedChanges)
      if (c.source case final s?) s.orderItemId.toLowerCase(): c,
  };
  final boundBy = <String, List<OrderEditCartLine>>{};
  final adds = <OrderEditCartLine>[];
  for (final l in previousLines) {
    final bound = l.sourceOrderItemId;
    if (bound == null) {
      if (!l.removed) adds.add(l);
      continue;
    }
    boundBy.putIfAbsent(bound.toLowerCase(), () => []).add(l);
  }

  final lines = <OrderEditCartLine>[];
  final dropped = <String>[];
  final live = <String>{};
  for (final f in fresh.lines) {
    final key = f.orderItemId.toLowerCase();
    live.add(key);
    final intent = intents[key];
    final carried = boundBy[key];
    if (intent != null && carried != null && _intentAllowed(intent, f)) {
      for (final l in carried) {
        lines.add(
          OrderEditCartLine(
            line: l.line,
            sourceOrderItemId: f.orderItemId,
            removed: l.removed,
          ),
        );
      }
      continue;
    }
    if (intent != null) dropped.add(intent.name);
    lines.add(orderEditSentLine(f, currencyCode: fresh.currencyCode));
  }
  for (final c in plan.plannedChanges) {
    final s = c.source;
    if (s != null && !live.contains(s.orderItemId.toLowerCase())) {
      dropped.add(c.name);
    }
  }
  lines.addAll(adds);
  return OrderEditReplay(
    lines: List<OrderEditCartLine>.unmodifiable(lines),
    droppedItems: List<String>.unmodifiable(dropped),
  );
}

bool _intentAllowed(OrderEditPlannedChange c, OrderEditSourceLine f) {
  final editable = !f.removeOnly && !f.keepOrRemoveOnly;
  return switch (c.kind) {
    OrderEditChangeKind.remove || OrderEditChangeKind.add => true,
    OrderEditChangeKind.increase => editable && !f.increaseBlocked,
    OrderEditChangeKind.reduce => editable,
    OrderEditChangeKind.modify =>
      editable && (c.quantityAfter <= f.quantity || !f.increaseBlocked),
  };
}

class OrderEditController extends Notifier<OrderEditState> {
  Future<OrderEditResult>? _inFlight;
  int? _inFlightGeneration;

  /// Single-flight replays / reconciles of cart-free records, by identity.
  final Map<String, Future<OrderEditResult>> _replays = {};

  bool _disposed = false;

  /// The in-memory index of every unresolved record — written through to the
  /// journal when one is wired, and the source of [OrderEditState.records].
  Map<String, OrderEditJournalRecord> _records =
      const <String, OrderEditJournalRecord>{};

  /// Journal I/O is serialized: two interleaved load-modify-persist cycles
  /// would otherwise lose one record's write.
  Future<void> _journalTail = Future<void>.value();

  @override
  OrderEditState build() {
    _disposed = false;
    _records = const <String, OrderEditJournalRecord>{};
    ref.onDispose(() => _disposed = true);
    // Decision D12: an UNSENT edit belongs to the worker who opened it. A PIN
    // handover (or a sign-out) discards it; a dispatched one is kept, because
    // the server may already own it and any operator may resolve it.
    ref.listen<String?>(posSignedInEmployeeProfileIdProvider, (prev, next) {
      if (prev != next) _onWorkerChanged();
    });
    // THE HYDRATION GATE IS SYNCHRONOUS (the Add-items rule): until the
    // journal is read nothing may claim "no edit is pending". Only when
    // something durable is wired; with no store there is nothing to read.
    final journal = ref.read(orderEditJournalStoreProvider);
    if (journal == null || _scope.isEmpty) return const OrderEditState();
    Future.microtask(_restore);
    return const OrderEditState(phase: OrderEditPhase.hydrating);
  }

  OrderEditJournalStore? get _journal =>
      ref.read(orderEditJournalStoreProvider);

  /// The journal is keyed by THIS device: one device never replays another's.
  String get _scope => ref.read(posSyncSessionProvider)?.deviceId ?? '';

  bool get _online =>
      ref.read(posOfflineModeProvider).phase == PosOfflinePhase.online;

  /// Publishes [next] carrying the CURRENT record index — the one way state
  /// is written, so no transition can resurrect a stale index.
  void _publish(OrderEditState next) {
    if (_disposed) return;
    state = next.copyWith(records: _records);
  }

  void _index(Map<String, OrderEditJournalRecord> records) {
    _records = Map<String, OrderEditJournalRecord>.unmodifiable(records);
    if (!_disposed) state = state.copyWith(records: _records);
  }

  // -------------------------------------------------------------------------
  // Read-side API (the action gates, the orders sheet, the Add-items flow).
  // -------------------------------------------------------------------------

  /// The journal is unread or unreadable — no edit may start, every order is
  /// held.
  bool get isStartupBlocked => state.startupBlocked;

  /// Orders whose money actions are withdrawn by an edit.
  Set<String> get blockedOrderIds => state.blockedOrderIds;

  bool hasUnresolvedEditFor(String orderId) =>
      state.hasUnresolvedEditFor(orderId);

  OrderEditJournalRecord? retryableRecordFor(String orderId) =>
      state.retryableRecordFor(orderId);

  // -------------------------------------------------------------------------
  // Entry and discard.
  // -------------------------------------------------------------------------

  /// CONTROLLER-OWNED SAFE ENTRY into edit mode for [orderId].
  ///
  /// The synchronous part refuses (startup gate, another open edit, an
  /// Add-items flow or an unresolved addition, an unresolved edit of this
  /// order, a non-empty cart, offline) and RESERVES the order under a fresh
  /// generation. The branch tax is re-read and the authoritative detail
  /// fetched; the commit FENCE then re-checks the generation, the still-empty
  /// cart and the idle addition flow, the baseline is judged (its switch is
  /// fresher than the session probe), and only then is the edit cart loaded.
  Future<OrderEditEntryResult> enterForOrder(String orderId) async {
    final s = state;
    if (s.startupBlocked) return OrderEditEntryResult.hydrating;
    final additionNotifier = ref.read(additionControllerProvider.notifier);
    if (additionNotifier.isStartupBlocked) {
      return OrderEditEntryResult.hydrating;
    }
    if (s.entryOrderId == orderId &&
        (s.phase == OrderEditPhase.entering ||
            s.phase == OrderEditPhase.active)) {
      return OrderEditEntryResult.entered; // idempotent re-entry
    }
    if (s.phase != OrderEditPhase.idle) return OrderEditEntryResult.busy;
    if (_additionBusy() ||
        additionNotifier.hasUnresolvedAmendmentFor(orderId)) {
      return OrderEditEntryResult.additionActive;
    }
    if (s.hasUnresolvedEditFor(orderId)) {
      return OrderEditEntryResult.pendingAttempt;
    }
    final cart = ref.read(cartControllerProvider);
    if (cart.isEditing || cart.lockedByAddition) {
      return OrderEditEntryResult.busy;
    }
    if (cart.isNotEmpty) return OrderEditEntryResult.cartNotEmpty;
    if (!_online) return OrderEditEntryResult.offline;

    final gen = s.generation + 1;
    _publish(
      OrderEditState(
        generation: gen,
        entryOrderId: orderId,
        phase: OrderEditPhase.entering,
      ),
    );

    // The footer recomputes tax with the branch's CURRENT setting, exactly as
    // the server will; a stale read is the commonest `totals_mismatch`.
    await _freshTax();
    if (_disposed) return OrderEditEntryResult.superseded;

    final PosOrderDetail detail;
    try {
      detail = await ref.read(orderDetailRepositoryProvider).fetch(orderId);
    } on PosOrderDetailException catch (e) {
      if (!_isCurrentEntry(gen, orderId)) {
        return OrderEditEntryResult.superseded;
      }
      _publish(OrderEditState(generation: gen + 1));
      return e.failure == PosOrderDetailFailure.notFound
          ? OrderEditEntryResult.orderNotFound
          : OrderEditEntryResult.detailUnavailable;
    } catch (_) {
      if (!_isCurrentEntry(gen, orderId)) {
        return OrderEditEntryResult.superseded;
      }
      _publish(OrderEditState(generation: gen + 1));
      return OrderEditEntryResult.detailUnavailable;
    }
    PosMenuData? menu;
    try {
      menu = await ref.read(posMenuProvider.future);
    } catch (_) {
      menu = null; // nothing provably on the menu: keep-or-remove-only
    }

    // COMMIT FENCE.
    if (!_isCurrentEntry(gen, orderId)) return OrderEditEntryResult.superseded;
    OrderEditEntryResult release(OrderEditEntryResult why) {
      _publish(OrderEditState(generation: gen + 1));
      return why;
    }

    if (detail.orderId != orderId) {
      return release(OrderEditEntryResult.detailUnavailable);
    }
    final cartNow = ref.read(cartControllerProvider);
    if (cartNow.isNotEmpty || cartNow.isEditing || cartNow.lockedByAddition) {
      // A line added while loading stays a NORMAL cart line.
      return release(OrderEditEntryResult.cartNotEmpty);
    }
    if (_additionBusy()) return release(OrderEditEntryResult.additionActive);
    final verdict = OrderEditBaseline.fromDetail(detail, menu: menu);
    final baseline = verdict.baseline;
    if (baseline == null) {
      return release(switch (verdict.ineligibility!) {
        OrderEditIneligibility.featureDisabled =>
          OrderEditEntryResult.featureDisabled,
        OrderEditIneligibility.notEditable => OrderEditEntryResult.notEditable,
        OrderEditIneligibility.alreadyPaid => OrderEditEntryResult.alreadyPaid,
        OrderEditIneligibility.kitchenModeChanged =>
          OrderEditEntryResult.kitchenModeChanged,
        OrderEditIneligibility.unidentifiedLine =>
          OrderEditEntryResult.detailUnavailable,
      });
    }
    final loaded = ref
        .read(cartControllerProvider.notifier)
        .loadForEdit(CartEditContext(baseline: baseline, generation: gen));
    if (loaded != CartEditLoadResult.loaded) {
      return release(
        loaded == CartEditLoadResult.invalid
            ? OrderEditEntryResult.detailUnavailable
            : OrderEditEntryResult.cartNotEmpty,
      );
    }
    _publish(
      OrderEditState(
        generation: gen,
        entryOrderId: orderId,
        baseline: baseline,
        phase: OrderEditPhase.active,
      ),
    );
    return OrderEditEntryResult.entered;
  }

  bool _additionBusy() {
    final a = ref.read(additionControllerProvider);
    return a.active || a.hasOpenAttempt || a.entryOrderId != null;
  }

  bool _isCurrentEntry(int gen, String orderId) =>
      !_disposed &&
      state.generation == gen &&
      state.entryOrderId == orderId &&
      state.phase == OrderEditPhase.entering;

  /// "Discard changes": leaves edit mode and the order exactly as it was sent.
  /// REFUSED (false, nothing changes) once the attempt reached the wire — the
  /// server may own the edit — and while the journal is unread.
  bool discard() {
    final s = state;
    if (s.startupBlocked || !s.canDiscard) return false;
    if (s.phase == OrderEditPhase.active) {
      final cart = ref.read(cartControllerProvider);
      if (cart.editContext?.orderId == s.entryOrderId &&
          !ref.read(cartControllerProvider.notifier).exitEdit()) {
        return false;
      }
    }
    _publish(OrderEditState(generation: s.generation + 1));
    return true;
  }

  void _onWorkerChanged() {
    if (_disposed) return;
    final s = state;
    if (s.attempt != null || s.dispatched) return;
    if (s.phase == OrderEditPhase.entering ||
        s.phase == OrderEditPhase.active) {
      discard();
    }
  }

  // -------------------------------------------------------------------------
  // Send, retry, refresh.
  // -------------------------------------------------------------------------

  /// "Send changes". The FIRST call plans the edit cart, freezes the payload
  /// under a NEW identity and locks the cart in ONE synchronous block, then
  /// journals it BEFORE dispatch. While an attempt's outcome is unknown this
  /// re-sends THAT attempt verbatim (the reason arguments are ignored: the
  /// payload is frozen). Applied-awaiting-refresh retries only the refresh.
  /// Single-flight: a double tap joins the same send.
  Future<OrderEditResult> submit({
    String? reasonCode,
    String? reasonText,
    DateTime? billPresentedAt,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightGeneration == state.generation) {
      return inFlight;
    }
    final run = _submit(
      reasonCode: reasonCode,
      reasonText: reasonText,
      billPresentedAt: billPresentedAt,
    );
    _inFlight = run;
    _inFlightGeneration = state.generation;
    run.whenComplete(() {
      if (identical(_inFlight, run)) {
        _inFlight = null;
        _inFlightGeneration = null;
      }
    });
    return run;
  }

  /// Re-sends this session's frozen attempt (same identity, same payload).
  Future<OrderEditResult> retry() => submit();

  Future<OrderEditResult> _submit({
    String? reasonCode,
    String? reasonText,
    DateTime? billPresentedAt,
  }) async {
    final s0 = state;
    // No identity may be minted, and nothing dispatched, before the journal
    // has been read.
    if (s0.startupBlocked) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        notice: OrderEditNotice.hydrating,
        error: 'hydrating',
      );
    }
    if (s0.phase == OrderEditPhase.appliedAwaitingRefresh) {
      final applied = s0.applied;
      final attempt = s0.attempt;
      final ok = await retryRefresh();
      return OrderEditResult(
        status: OrderEditSubmitStatus.applied,
        applied: applied,
        refreshRequired: !ok,
        remakeCount: attempt?.summary.remakeDishCount ?? 0,
        billPresented: attempt?.billPresented ?? false,
      );
    }
    final frozen = s0.attempt;
    if (frozen != null && s0.phase == OrderEditPhase.failed) {
      if (s0.conflictingOrderIds.contains(frozen.orderId)) {
        return const OrderEditResult(
          status: OrderEditSubmitStatus.conflict,
          notice: OrderEditNotice.conflictBlocked,
          error: 'conflict',
        );
      }
      return _dispatch(s0.generation, frozen, cartBound: true);
    }
    if (s0.phase != OrderEditPhase.active || s0.baseline == null) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        error: 'nothing_to_send',
      );
    }
    if (!_online) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        notice: OrderEditNotice.needsConnection,
        error: 'offline',
      );
    }
    if (ref.read(runtimeConfigProvider).isDemoMode ||
        ref.read(posAuthTransportProvider) == null ||
        ref.read(posSyncSessionProvider) == null) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        error: 'no_session',
      );
    }
    final gen = s0.generation;
    // The branch's CURRENT tax — the server recomputes with its current
    // setting too. Read before the freeze; the freeze itself never awaits.
    BranchTax tax;
    try {
      tax = await ref.read(posBranchTaxProvider.future);
    } catch (_) {
      tax = BranchTax.disabled;
    }
    if (_disposed ||
        state.generation != gen ||
        state.phase != OrderEditPhase.active) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        error: 'stale_attempt',
      );
    }

    // ---- ONE SYNCHRONOUS BLOCK: plan, payload, identity, lock --------------
    final cart = ref.read(cartControllerProvider);
    final context = cart.editContext;
    if (context == null || context.orderId != s0.entryOrderId) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        error: 'cart_mismatch',
      );
    }
    final plan = planOrderEdit(
      context.baseline,
      cart.editLines,
      tax: tax,
      capabilities: ref.read(staffCapabilitiesProvider).valueOrNull,
      prepByItemId: _prepSnapshot(),
    );
    final block = orderEditSendBlock(
      plan,
      online: true,
      reasonCode: reasonCode,
      reasonText: reasonText,
    );
    if (block != null) {
      return OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        sendBlock: block,
        error: 'blocked',
      );
    }
    final payload = buildOrderEditPayload(
      plan,
      reasonCode: reasonCode,
      reasonText: reasonText,
      billPresentedAt: billPresentedAt,
    );
    final attempt = OrderEditAttempt(
      localOperationId: ref.read(clientIdGeneratorProvider).newId(),
      orderId: context.orderId,
      orderCode: context.orderCode,
      generation: gen,
      payload: payload,
      summary: plan.summary,
      clientCreatedAt: DateTime.now().toUtc(),
      employeeProfileId: ref.read(posSignedInEmployeeProfileIdProvider),
      // ORDER-EDIT-001F (D2): the paper slip's "was" lines, frozen with the
      // payload from the same baseline.
      slipWas: context.baseline.channel == PosKitchenChannel.paper
          ? orderEditSlipWasLines(context.baseline, payload)
          : null,
    );
    final cartController = ref.read(cartControllerProvider.notifier);
    final owner = _ownerOf(attempt);
    if (!cartController.lockForAddition(owner)) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        error: 'cart_locked',
      );
    }
    _publish(
      state.copyWith(
        phase: OrderEditPhase.sending,
        attempt: attempt,
        clearError: true,
      ),
    );

    // ---- JOURNAL BEFORE DISPATCH -------------------------------------------
    // Confirmed before a single byte reaches the transport: without the record
    // there is nothing to replay under, and a later retry would mint a second
    // identity for an edit the server may already have applied.
    if (!await _journalPut(attempt.toRecord(), required: true)) {
      cartController.unlockForAddition(owner);
      if (_isCurrentAttempt(gen, attempt)) {
        _publish(
          OrderEditState(
            generation: gen,
            entryOrderId: attempt.orderId,
            baseline: state.baseline,
            phase: OrderEditPhase.active,
            lastError: 'storage',
            consecutiveTotalsMismatches: state.consecutiveTotalsMismatches,
          ),
        );
      }
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        notice: OrderEditNotice.retry,
        error: 'storage',
      );
    }
    return _dispatch(gen, attempt, cartBound: true, firstSend: true);
  }

  /// Sends [attempt] — its first dispatch, or a verbatim retry — and settles
  /// the answer. [cartBound] attempts own the session's edit cart; a restored
  /// record ([cartBound] false) never had one.
  Future<OrderEditResult> _dispatch(
    int gen,
    OrderEditAttempt attempt, {
    required bool cartBound,
    bool firstSend = false,
  }) async {
    // A RETRY is refused up front when it cannot reach the server; nothing
    // changes. A FIRST send was checked before its freeze and is journaled as
    // dispatching now, so it can no longer be "not sent": a session lost in
    // between is settled as outcome-unknown, exactly like a dead transport.
    if (!firstSend && !_online) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        notice: OrderEditNotice.needsConnection,
        error: 'offline',
      );
    }
    final transport = ref.read(posAuthTransportProvider);
    final session = ref.read(posSyncSessionProvider);
    if (transport == null || session == null) {
      if (firstSend) {
        return _settleUncertain(
          gen,
          attempt,
          'no_session',
          cartBound: cartBound,
        );
      }
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        error: 'no_session',
      );
    }
    if (!firstSend) {
      // A retry: count it (best effort — the identity is already durable).
      final current = _records[attempt.localOperationId];
      if (current != null) {
        await _journalPut(
          current.copyWith(attemptCount: current.attemptCount + 1),
        );
      }
    }
    if (cartBound && _isCurrentAttempt(gen, attempt)) {
      _publish(state.copyWith(phase: OrderEditPhase.sending, dispatched: true));
    }

    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[
          <String, dynamic>{
            'local_operation_id': attempt.localOperationId,
            'operation_type': kOrderEditOperationType,
            'target_entity': 'order',
            // `sync_push` refuses an op whose target is not the payload's
            // order (`invalid_payload`), so it is read from the frozen payload.
            'target_id': attempt.payload['order_id'],
            'client_created_at': attempt.clientCreatedAt
                .toUtc()
                .toIso8601String(),
            'payload': attempt.payload,
          },
        ],
      });
    } catch (_) {
      // TRANSPORT UNCERTAIN — NOT "not applied".
      return _settleUncertain(gen, attempt, 'transport', cartBound: cartBound);
    }

    // RESPONSE FENCE: a stale continuation writes nothing — not even the
    // journal, whose record stays open for a replay to resolve.
    if (_disposed) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.uncertain,
        error: 'stale_attempt',
      );
    }
    if (cartBound && !_isCurrentAttempt(gen, attempt)) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.uncertain,
        error: 'stale_attempt',
      );
    }

    final outcome = classifyOrderEditResponse(
      raw,
      localOperationId: attempt.localOperationId,
      orderId: attempt.orderId,
    );
    switch (outcome.kind) {
      case OrderEditOutcomeKind.unknown:
        return _settleUncertain(
          gen,
          attempt,
          outcome.reason ?? 'unknown',
          cartBound: cartBound,
          outcome: outcome,
        );
      case OrderEditOutcomeKind.conflict:
        await _journalPhase(
          attempt,
          OrderEditJournalPhase.conflict,
          errorCode: 'conflict',
        );
        if (cartBound && _isCurrentAttempt(gen, attempt)) {
          _publish(
            state.copyWith(
              phase: OrderEditPhase.failed,
              dispatched: true,
              lastError: 'conflict',
            ),
          );
        }
        return OrderEditResult(
          status: OrderEditSubmitStatus.conflict,
          notice: OrderEditNotice.conflictBlocked,
          outcome: outcome,
          error: 'conflict',
        );
      case OrderEditOutcomeKind.refused:
      case OrderEditOutcomeKind.rejected:
        return cartBound
            ? _settleRefused(gen, attempt, outcome)
            : _settleRecordRefused(attempt, outcome);
      case OrderEditOutcomeKind.applied:
        break;
    }

    // APPLIED, and COMPLETE. The identity is spent: never dispatched again,
    // and kept open until the authoritative detail proves the edit.
    final applied = outcome.applied!;
    await _journalPhase(
      attempt,
      OrderEditJournalPhase.awaitingAuthoritativeRefresh,
      applied: applied,
      clearError: true,
    );
    if (!cartBound) {
      final reconciled = await _reconcileRecord(attempt, applied);
      return _appliedResult(attempt, applied, outcome, reconciled: reconciled);
    }
    if (!_disposed && _isCurrentAttempt(gen, attempt)) {
      _publish(
        state.copyWith(
          phase: OrderEditPhase.appliedAwaitingRefresh,
          applied: applied,
          dispatched: true,
          clearError: true,
          consecutiveTotalsMismatches: 0,
        ),
      );
    }
    final reconciled = await _reconcileApplied(gen, attempt, applied);
    return _appliedResult(attempt, applied, outcome, reconciled: reconciled);
  }

  OrderEditResult _appliedResult(
    OrderEditAttempt attempt,
    OrderEditApplied applied,
    OrderEditOutcome outcome, {
    required bool reconciled,
  }) => OrderEditResult(
    status: OrderEditSubmitStatus.applied,
    outcome: outcome,
    applied: applied,
    refreshRequired: !reconciled,
    remakeCount: attempt.summary.remakeDishCount,
    billPresented: attempt.billPresented,
    error: reconciled ? null : 'refresh_required',
  );

  /// The outcome is unknown: the identity, the payload and (for this
  /// session's attempt) the cart lock are all kept.
  Future<OrderEditResult> _settleUncertain(
    int gen,
    OrderEditAttempt attempt,
    String reason, {
    required bool cartBound,
    OrderEditOutcome? outcome,
  }) async {
    await _journalPhase(
      attempt,
      OrderEditJournalPhase.transportUncertain,
      errorCode: reason,
    );
    if (cartBound && _isCurrentAttempt(gen, attempt)) {
      _publish(
        state.copyWith(
          phase: OrderEditPhase.failed,
          dispatched: true,
          lastError: reason,
        ),
      );
    }
    return OrderEditResult(
      status: OrderEditSubmitStatus.uncertain,
      notice: OrderEditNotice.retry,
      outcome: outcome,
      error: reason,
    );
  }

  /// A definitive NO for this session's attempt: nothing was written, so the
  /// record closes, the identity is released and the cart unlocks. The policy
  /// then decides whether the edit stays open, ends, or is rebased.
  Future<OrderEditResult> _settleRefused(
    int gen,
    OrderEditAttempt attempt,
    OrderEditOutcome outcome,
  ) async {
    await _journalClose(attempt.localOperationId);
    final policy = orderEditRefusalPolicy(outcome)!;
    _invalidateFor(policy);
    if (_disposed || !_isCurrentAttempt(gen, attempt)) {
      return OrderEditResult(
        status: OrderEditSubmitStatus.refused,
        notice: policy.notice,
        effect: policy.effect,
        outcome: outcome,
        error: outcome.reason,
      );
    }
    ref
        .read(cartControllerProvider.notifier)
        .unlockForAddition(_ownerOf(attempt));
    final totalsMismatch = outcome.refusal?.code == 'totals_mismatch';
    final consecutive = totalsMismatch
        ? state.consecutiveTotalsMismatches + 1
        : 0;
    _publish(
      OrderEditState(
        generation: gen,
        entryOrderId: attempt.orderId,
        baseline: state.baseline,
        phase: OrderEditPhase.active,
        lastError: outcome.reason,
        consecutiveTotalsMismatches: consecutive,
      ),
    );
    OrderEditResult refused(
      OrderEditNotice notice,
      OrderEditRefusalEffect effect,
    ) => OrderEditResult(
      status: OrderEditSubmitStatus.refused,
      notice: notice,
      effect: effect,
      outcome: outcome,
      error: outcome.reason,
    );

    switch (policy.effect) {
      case OrderEditRefusalEffect.stay:
        return refused(policy.notice, policy.effect);
      case OrderEditRefusalEffect.exit:
        _leaveEdit(gen, attempt.orderId);
        return refused(policy.notice, policy.effect);
      case OrderEditRefusalEffect.rebase:
        // Decision D9: ONE automatic rebase per tap. A second
        // `totals_mismatch` in a row means the figures will not converge by
        // re-fetching (a tax read that keeps drifting): stop, and never adopt
        // the server's figures.
        if (totalsMismatch && consecutive >= 2) {
          return refused(OrderEditNotice.invalid, OrderEditRefusalEffect.stay);
        }
        return _rebase(gen, outcome, policy);
      case OrderEditRefusalEffect.rebaseline:
        return _rebase(gen, outcome, policy);
    }
  }

  /// A definitive NO for a restored record: nothing was written and there is
  /// no cart to keep — the record closes and the order is refreshed. A rebase
  /// has no intents to re-apply here, so the edit is reported as not sent.
  Future<OrderEditResult> _settleRecordRefused(
    OrderEditAttempt attempt,
    OrderEditOutcome outcome,
  ) async {
    await _journalClose(attempt.localOperationId);
    final policy = orderEditRefusalPolicy(outcome)!;
    _invalidateFor(policy);
    unawaited(_refreshOrder(attempt.orderId));
    final rebase =
        policy.effect == OrderEditRefusalEffect.rebase ||
        policy.effect == OrderEditRefusalEffect.rebaseline;
    return OrderEditResult(
      status: OrderEditSubmitStatus.refused,
      notice: policy.effect == OrderEditRefusalEffect.rebase
          ? OrderEditNotice.invalid
          : policy.notice,
      effect: rebase ? OrderEditRefusalEffect.exit : policy.effect,
      outcome: outcome,
      error: outcome.reason,
    );
  }

  void _invalidateFor(OrderEditRefusalPolicy policy) {
    if (_disposed) return;
    if (policy.invalidateCapabilities) {
      ref.invalidate(staffCapabilitiesProvider);
    }
    if (policy.invalidateMenu) ref.invalidate(posMenuProvider);
  }

  /// Ends the open edit after a refusal that leaves nothing to correct.
  void _leaveEdit(int gen, String orderId) {
    if (_disposed) return;
    final cart = ref.read(cartControllerProvider);
    if (cart.editContext?.orderId == orderId) {
      ref.read(cartControllerProvider.notifier).exitEdit();
    }
    _publish(OrderEditState(generation: gen + 1));
    unawaited(_refreshOrder(orderId));
  }

  Future<void> _refreshOrder(String orderId) async {
    if (_disposed) return;
    try {
      await ref.read(posOrderSyncControllerProvider.notifier).refreshOrders([
        orderId,
      ]);
    } catch (_) {
      // The poll converges regardless.
    }
  }

  /// Decision D10 — re-baselines the OPEN, UNSENT edit in place after a
  /// separate committed change to the same order made from inside the edit
  /// ("Lower discount", or the "Cancel order" link when every line would be
  /// removed): the detail is re-fetched and the cashier's intents are
  /// re-applied to it, exactly like a rebase. The line ids do not change, so
  /// every intent is kept; a cancelled order is no longer editable and the
  /// edit ends ([OrderEditRefusalEffect.exit]).
  ///
  /// Never sends anything. Refused (`notSent`, nothing changes) unless an
  /// edit is open and unsent.
  Future<OrderEditResult> refreshBaseline() async {
    final s = state;
    if (s.startupBlocked ||
        s.phase != OrderEditPhase.active ||
        s.baseline == null ||
        s.entryOrderId == null) {
      return const OrderEditResult(
        status: OrderEditSubmitStatus.notSent,
        error: 'nothing_to_refresh',
      );
    }
    return _rebase(s.generation, null, null);
  }

  /// THE REBASE (design §7.1 point 9, decision D9): re-fetch the detail,
  /// rebuild the baseline, re-apply the cashier's intents to the fresh lines
  /// and reload the edit cart. The resend is MANUAL, under a new identity.
  ///
  /// [outcome] / [policy] are the refusal that asked for it; both are null for
  /// a [refreshBaseline], whose result is `notSent` and says something only
  /// when an intent had to be left out.
  Future<OrderEditResult> _rebase(
    int gen,
    OrderEditOutcome? outcome,
    OrderEditRefusalPolicy? policy,
  ) async {
    final s = state;
    final orderId = s.entryOrderId!;
    final previous = s.baseline;
    final previousLines = ref.read(cartControllerProvider).editLines;
    // THE CART IS HELD FOR THE WHOLE REBASE. The intents are read from the
    // lines above, synchronously, and the cart is then REPLACED by their
    // replay onto the fresh detail — so a tap landing in between (a menu
    // item, a '+', an option sheet closing) would be shown and then silently
    // thrown away. Taken in the same synchronous block as the snapshot, and
    // released on every way out (right before the reload, which refuses a
    // held cart).
    final cart = ref.read(cartControllerProvider.notifier);
    final hold = CartLockOwner(
      generation: gen,
      orderId: orderId,
      localOperationId: 'order-edit-rebase',
    );
    final held = cart.lockForAddition(hold);
    void release() {
      if (held && !_disposed) cart.unlockForAddition(hold);
    }

    _publish(s.copyWith(phase: OrderEditPhase.rebasing));
    OrderEditResult result(
      OrderEditNotice? notice,
      OrderEditRefusalEffect? effect, {
      List<String> dropped = const <String>[],
    }) => OrderEditResult(
      status: outcome == null
          ? OrderEditSubmitStatus.notSent
          : OrderEditSubmitStatus.refused,
      notice: notice,
      effect: effect,
      outcome: outcome,
      droppedItems: dropped,
      error: outcome?.reason,
    );

    if (outcome?.refusal?.code == 'totals_mismatch') await _freshTax();
    PosOrderDetail? fresh;
    try {
      fresh = await ref.read(orderDetailRepositoryProvider).fetch(orderId);
    } catch (_) {
      fresh = null;
    }
    PosMenuData? menu;
    try {
      menu = await ref.read(posMenuProvider.future);
    } catch (_) {
      menu = null;
    }
    // Every way out below releases the hold first.
    release();
    if (_disposed ||
        state.generation != gen ||
        state.phase != OrderEditPhase.rebasing) {
      return result(policy?.notice, policy?.effect);
    }
    void back() => _publish(
      state.copyWith(phase: OrderEditPhase.active, lastError: 'rebase_failed'),
    );
    if (previous == null || fresh == null || fresh.orderId != orderId) {
      back();
      return result(
        OrderEditNotice.detailUnavailable,
        OrderEditRefusalEffect.stay,
      );
    }
    final verdict = OrderEditBaseline.fromDetail(fresh, menu: menu);
    final baseline = verdict.baseline;
    if (baseline == null) {
      _leaveEdit(gen, orderId);
      return result(switch (verdict.ineligibility!) {
        OrderEditIneligibility.featureDisabled =>
          OrderEditNotice.featureDisabled,
        OrderEditIneligibility.notEditable => OrderEditNotice.notEditable,
        OrderEditIneligibility.alreadyPaid => OrderEditNotice.alreadyPaid,
        OrderEditIneligibility.kitchenModeChanged =>
          OrderEditNotice.kitchenModeChanged,
        OrderEditIneligibility.unidentifiedLine =>
          OrderEditNotice.detailUnavailable,
      }, OrderEditRefusalEffect.exit);
    }
    final replay = replayOrderEditIntents(
      previous: previous,
      previousLines: previousLines,
      fresh: baseline,
    );
    final loaded = ref
        .read(cartControllerProvider.notifier)
        .loadForEdit(
          CartEditContext(baseline: baseline, generation: gen),
          replay: replay.lines,
        );
    if (loaded != CartEditLoadResult.loaded) {
      back();
      return result(
        OrderEditNotice.detailUnavailable,
        OrderEditRefusalEffect.stay,
      );
    }
    _publish(
      state.copyWith(
        phase: OrderEditPhase.active,
        baseline: baseline,
        lastError: outcome?.reason,
      ),
    );
    if (policy == null) {
      // A re-baseline: silent unless an intent no longer applies.
      return result(
        replay.droppedItems.isEmpty ? null : OrderEditNotice.rebased,
        OrderEditRefusalEffect.rebaseline,
        dropped: replay.droppedItems,
      );
    }
    return result(policy.notice, policy.effect, dropped: replay.droppedItems);
  }

  /// Retries ONLY the authoritative refresh of this session's applied edit.
  /// Never dispatches `order.edit` again.
  Future<bool> retryRefresh() async {
    final s = state;
    final attempt = s.attempt;
    final applied = s.applied;
    if (s.phase != OrderEditPhase.appliedAwaitingRefresh ||
        attempt == null ||
        applied == null) {
      return false;
    }
    return _reconcileApplied(s.generation, attempt, applied);
  }

  /// The post-apply reconcile of this session's attempt: the targeted
  /// snapshot refresh, then the authoritative detail, which must PROVE the
  /// edit (its `edit_count` reached `edit_number` and `edits[]` names the
  /// `order_edit_id`) before the cart is cleared — with the matching owner
  /// token — and the record closed, exactly once.
  Future<bool> _reconcileApplied(
    int gen,
    OrderEditAttempt attempt,
    OrderEditApplied applied,
  ) async {
    final fresh = await _authoritativeDetail(attempt.orderId);
    if (_disposed ||
        state.generation != gen ||
        state.phase != OrderEditPhase.appliedAwaitingRefresh ||
        state.attempt?.localOperationId != attempt.localOperationId) {
      return false; // stale — zero side effects
    }
    final cart = ref.read(cartControllerProvider.notifier);
    final owner = _ownerOf(attempt);
    if (!_proves(fresh, attempt, applied) || !cart.ownsAdditionLock(owner)) {
      _publish(state.copyWith(lastError: 'refresh_required'));
      return false;
    }
    cart.finishEdit(owner);
    await _journalClose(attempt.localOperationId);
    _publish(OrderEditState(generation: gen + 1));
    return true;
  }

  /// The reconcile of a restored applied record (no cart is involved).
  Future<bool> _reconcileRecord(
    OrderEditAttempt attempt,
    OrderEditApplied applied,
  ) async {
    final fresh = await _authoritativeDetail(attempt.orderId);
    if (_disposed) return false;
    if (!_records.containsKey(attempt.localOperationId)) return true;
    if (!_proves(fresh, attempt, applied)) return false;
    await _journalClose(attempt.localOperationId);
    return true;
  }

  Future<PosOrderDetail?> _authoritativeDetail(String orderId) async {
    await _refreshOrder(orderId);
    if (_disposed) return null;
    try {
      return await ref.read(orderDetailRepositoryProvider).fetch(orderId);
    } catch (_) {
      return null;
    }
  }

  bool _proves(
    PosOrderDetail? fresh,
    OrderEditAttempt attempt,
    OrderEditApplied applied,
  ) {
    if (fresh == null || fresh.orderId != attempt.orderId) return false;
    if (fresh.editCount < applied.editNumber) return false;
    final id = applied.orderEditId.toLowerCase();
    return fresh.edits?.any((e) => e.orderEditId.toLowerCase() == id) ?? false;
  }

  /// The row's retry for [orderId] (an earlier session's record, or this
  /// session's uncertain attempt): replays the frozen payload verbatim, or —
  /// for a record the server already applied — retries only the refresh.
  Future<OrderEditResult> retryOrder(String orderId) {
    final s = state;
    if (s.startupBlocked) {
      return Future.value(
        const OrderEditResult(
          status: OrderEditSubmitStatus.notSent,
          notice: OrderEditNotice.hydrating,
          error: 'hydrating',
        ),
      );
    }
    if (s.attempt?.orderId == orderId) return submit();
    final record = s.retryableRecordFor(orderId);
    if (record == null) {
      return Future.value(
        OrderEditResult(
          status: s.conflictingOrderIds.contains(orderId)
              ? OrderEditSubmitStatus.conflict
              : OrderEditSubmitStatus.notSent,
          notice: s.conflictingOrderIds.contains(orderId)
              ? OrderEditNotice.conflictBlocked
              : null,
          error: 'nothing_to_retry',
        ),
      );
    }
    final key = record.localOperationId;
    final running = _replays[key];
    if (running != null) return running;
    final run = _replayRecord(record);
    _replays[key] = run;
    run.whenComplete(() {
      if (identical(_replays[key], run)) _replays.remove(key);
    });
    return run;
  }

  Future<OrderEditResult> _replayRecord(OrderEditJournalRecord record) async {
    final attempt = OrderEditAttempt.fromRecord(record);
    final applied = record.applied;
    if (record.awaitingRefresh && applied != null) {
      final reconciled = await _reconcileRecord(attempt, applied);
      return OrderEditResult(
        status: OrderEditSubmitStatus.applied,
        applied: applied,
        refreshRequired: !reconciled,
        remakeCount: attempt.summary.remakeDishCount,
        billPresented: attempt.billPresented,
        error: reconciled ? null : 'refresh_required',
      );
    }
    return _dispatch(attempt.generation, attempt, cartBound: false);
  }

  // -------------------------------------------------------------------------
  // Hydration.
  // -------------------------------------------------------------------------

  /// Reads the journal and indexes every unresolved record. No edit cart is
  /// rebuilt: a `dispatching` / `transportUncertain` record blocks its order
  /// until the row's retry replays it; an applied one is reconciled; a
  /// conflict (or two records on one order) needs a person. A journal that
  /// cannot be read keeps the gate SHUT.
  Future<void> _restore() async {
    if (_disposed) return;
    final journal = _journal;
    final scope = _scope;
    if (journal == null || scope.isEmpty) {
      _publish(OrderEditState(generation: state.generation));
      return;
    }
    final Map<String, OrderEditJournalRecord> records;
    try {
      records = await _serialized(() => journal.load(scope));
    } catch (_) {
      if (_disposed) return;
      _publish(
        const OrderEditState(
          phase: OrderEditPhase.hydrationFailed,
          lastError: 'journal_unreadable',
        ),
      );
      return;
    }
    if (_disposed) return;
    _records = Map<String, OrderEditJournalRecord>.unmodifiable(records);
    _publish(
      OrderEditState(
        generation: state.generation,
        lastError: records.isEmpty ? null : 'reconcile_required',
      ),
    );
    final conflicting = state.conflictingOrderIds;
    for (final r in records.values) {
      final applied = r.applied;
      if (r.awaitingRefresh &&
          applied != null &&
          !conflicting.contains(r.orderId)) {
        unawaited(retryOrder(r.orderId));
      }
    }
  }

  // -------------------------------------------------------------------------
  // The durable journal.
  // -------------------------------------------------------------------------

  Future<T> _serialized<T>(Future<T> Function() op) {
    final run = _journalTail.then((_) => op());
    _journalTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Writes [record]. [required] is the pre-dispatch write: its failure is
  /// reported (false) and nothing is indexed. A later phase write is best
  /// effort: by then the outcome is known in memory, and the record on disk
  /// keeps its previous phase, which always errs toward reconciling again.
  Future<bool> _journalPut(
    OrderEditJournalRecord record, {
    bool required = false,
  }) async {
    final journal = _journal;
    final scope = _scope;
    if (journal == null || scope.isEmpty) {
      _index({..._records, record.localOperationId: record});
      return true;
    }
    try {
      final written = await _serialized(() async {
        final existing = await journal.load(scope);
        final next = <String, OrderEditJournalRecord>{
          ...existing,
          record.localOperationId: record,
        };
        await journal.persist(scope, next);
        return next;
      });
      if (!_disposed) _index(written);
      return true;
    } catch (_) {
      // Includes PosPersistenceException from a refused write.
      if (!required && !_disposed) {
        _index({..._records, record.localOperationId: record});
      }
      return false;
    }
  }

  Future<void> _journalPhase(
    OrderEditAttempt attempt,
    OrderEditJournalPhase phase, {
    String? errorCode,
    OrderEditApplied? applied,
    bool clearError = false,
  }) async {
    final current =
        _records[attempt.localOperationId] ??
        attempt.toRecord(phase: phase, attemptCount: 1);
    await _journalPut(
      current.copyWith(
        phase: phase,
        lastErrorCode: errorCode,
        applied: applied,
        clearError: clearError,
      ),
    );
  }

  /// Removes the record — ONLY after authoritative confirmation, or for an
  /// attempt the server provably refused.
  Future<void> _journalClose(String localOperationId) async {
    if (_disposed) return;
    _index({
      for (final e in _records.entries)
        if (e.key != localOperationId) e.key: e.value,
    });
    final journal = _journal;
    final scope = _scope;
    if (journal == null || scope.isEmpty) return;
    try {
      final remaining = await _serialized(() async {
        final existing = await journal.load(scope);
        if (!existing.containsKey(localOperationId)) return existing;
        final next = <String, OrderEditJournalRecord>{
          for (final e in existing.entries)
            if (e.key != localOperationId) e.key: e.value,
        };
        await journal.persist(scope, next);
        return next;
      });
      if (!_disposed) _index(remaining);
    } catch (_) {
      // The record survives on disk; a later replay gets the same verdict.
    }
  }

  // -------------------------------------------------------------------------
  // Helpers.
  // -------------------------------------------------------------------------

  /// Re-reads the branch tax setting. Only a provider that already holds a
  /// value is invalidated — invalidating an unread one would read it twice.
  /// Unread tax reads as disabled everywhere; a wrong guess is a refusal.
  Future<BranchTax> _freshTax() async {
    if (_disposed) return BranchTax.disabled;
    if (ref.exists(posBranchTaxProvider)) ref.invalidate(posBranchTaxProvider);
    try {
      return await ref.read(posBranchTaxProvider.future);
    } catch (_) {
      return BranchTax.disabled;
    }
  }

  CartLockOwner _ownerOf(OrderEditAttempt attempt) => CartLockOwner(
    generation: attempt.generation,
    orderId: attempt.orderId,
    localOperationId: attempt.localOperationId,
  );

  bool _isCurrentAttempt(int gen, OrderEditAttempt attempt) =>
      !_disposed &&
      state.generation == gen &&
      state.attempt?.localOperationId == attempt.localOperationId &&
      state.attempt?.orderId == attempt.orderId;

  /// The live menu's prep snapshot for ADDED lines (D-008), read once per
  /// frozen attempt — what the Add-items path freezes.
  Map<String, List<KitchenPrepComponent>> _prepSnapshot() =>
      orderEditPrepSnapshot(ref.read(posMenuProvider).valueOrNull);
}

/// The live menu's `menuItemId -> prepComponents` (empty when unknown).
Map<String, List<KitchenPrepComponent>> orderEditPrepSnapshot(
  PosMenuData? menu,
) => <String, List<KitchenPrepComponent>>{
  if (menu != null)
    for (final item in menu.items)
      if (item.prepComponents.isNotEmpty) item.id: item.prepComponents,
};

final orderEditControllerProvider =
    NotifierProvider<OrderEditController, OrderEditState>(
      OrderEditController.new,
    );

/// ORDER-EDIT-001E — the LIVE plan of the open edit: what the footer shows
/// ("Was → Now", tax, discount kept), why Send is disabled, and whether the
/// reason chips and the finished-food sheet apply. Null outside edit mode.
///
/// The SAME function with the same inputs as the send's frozen plan — the
/// edit cart's bound baseline, the branch tax (unread reads as disabled, as
/// everywhere in the cart), the advisory capabilities and the menu's prep —
/// so the screen cannot show a figure the payload would not send.
final orderEditPlanProvider = Provider<OrderEditPlan?>((ref) {
  final cart = ref.watch(cartControllerProvider);
  final context = cart.editContext;
  if (context == null) return null;
  return planOrderEdit(
    context.baseline,
    cart.editLines,
    tax: ref.watch(posBranchTaxProvider).valueOrNull ?? BranchTax.disabled,
    capabilities: ref.watch(staffCapabilitiesProvider).valueOrNull,
    prepByItemId: orderEditPrepSnapshot(ref.watch(posMenuProvider).valueOrNull),
  );
});
