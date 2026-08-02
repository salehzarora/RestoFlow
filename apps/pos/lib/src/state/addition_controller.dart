import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import 'dart:async' show unawaited;

import '../data/addition_journal_store.dart';
import '../data/ids.dart';
import '../data/order_detail_repository.dart';
import '../data/order_submission.dart';
import 'cart_controller.dart';
import 'order_sync_controller.dart';
import 'pos_menu_provider.dart';
import 'pos_session.dart';

/// PSC-001C — the ADD-ITEMS-TO-EXISTING-ORDER flow state.
///
/// While a target is set, the POS cart is in ADDITION MODE: the cashier's new
/// selections are the PENDING ADDITION (kept strictly local and visually
/// separate from the authoritative existing items shown from
/// [PosOrderDetail]), and submit sends ONE `order.items_add` operation through
/// `public.sync_push` — never a re-send of the original items.
///
/// HONESTY RULES (locked + the correction findings):
///  * ENTRY IS CONTROLLER-OWNED (Finding 1): `enterForOrder` synchronously
///    validates and RESERVES the target (an entry generation token) BEFORE
///    the authoritative detail is awaited, and re-verifies the token, the
///    target and the still-empty cart immediately before committing addition
///    mode — a cart line added during the load can never silently become an
///    addition to the previously selected order;
///  * the FIRST submit ATOMICALLY freezes one immutable [AdditionAttempt] —
///    parent order id, the canonical serialized item payload (snapshotted
///    from the LIVE cart), the local_operation_id and the client timestamp —
///    AND acquires the [CartController] mutation lock under the attempt's
///    owner token in the same synchronous block. While the frozen attempt
///    exists (sending / retryable failure / applied-awaiting-refresh) every
///    normal cart mutation refuses, so the visible cart and the frozen
///    payload can never diverge and no unrelated line can be introduced only
///    to be lost on reconciliation. Every retry reuses the exact snapshot;
///  * CANCEL IS REFUSED WHILE SENDING (Finding 2), and every asynchronous
///    continuation is FENCED on the attempt/entry generation — a stale
///    response has zero state side effects;
///  * an APPLIED operation is never resubmitted (Finding 4): the state moves
///    to [AdditionPhase.appliedAwaitingRefresh] until the authoritative
///    detail refresh PROVES the addition (right parent + the applied round);
///    only the refresh may be retried, and cleanup happens exactly once;
///  * the cart clears ONLY on that verified reconciliation.
class AdditionAttempt {
  const AdditionAttempt({
    required this.orderId,
    required this.localOperationId,
    required this.itemsJson,
    required this.clientCreatedAt,
    this.lines = const <CartLineView>[],
    this.prepByItemId = const <String, List<KitchenPrepComponent>>{},
  });

  /// The parent order this attempt is bound to — never retargetable.
  final String orderId;

  /// The idempotency identity (D-022) — one per attempt, reused on retries.
  final String localOperationId;

  /// The CANONICAL serialized `order_items` payload, frozen at first submit.
  /// Retries send exactly this — never a rebuild from the mutable cart.
  final List<Map<String, Object?>> itemsJson;

  final DateTime clientCreatedAt;

  /// DEFERRED-ORDER-AMENDMENTS-001: the SAME cart lines [itemsJson] was
  /// serialized from, frozen in the SAME synchronous block. The kitchen ADDITION
  /// ticket is rendered from these, so the paper cannot disagree with the wire
  /// payload the server applied — and it survives the reconciliation that clears
  /// the cart. Retries print the same delta, never a rebuild from a mutable cart.
  final List<CartLineView> lines;

  /// The ORDER-TIME (D-008) per-item prep snapshot used for BOTH the wire
  /// payload and the printed ticket — captured once, never re-read from the live
  /// menu afterwards.
  final Map<String, List<KitchenPrepComponent>> prepByItemId;
}

/// DEFERRED-ORDER-AMENDMENTS-001 — everything the kitchen ADDITION ticket needs,
/// assembled at the moment the server confirmed the round and BEFORE the
/// reconciliation clears the cart.
///
/// It carries the DELTA only (the frozen added lines), the parent order's own
/// identity and type, and the server's applied round identity. There is no money
/// field: a kitchen ticket never carries one (T-003).
class AdditionPrintPayload {
  const AdditionPrintPayload({
    required this.orderId,
    required this.orderCode,
    required this.orderTypeWire,
    required this.roundId,
    required this.roundNumber,
    required this.lines,
    required this.prepByItemId,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
  });

  /// The ORIGINAL order — the addition's parent, never a new order.
  final String orderId;
  final String orderCode;

  /// The parent's PRESERVED order type, as the server stores it
  /// (`dine_in` / `takeaway`). Never rewritten by the addition.
  final String orderTypeWire;

  /// The server's applied round identity. Both are required: the id scopes the
  /// exactly-once print guard, the number is what the kitchen reads.
  final String roundId;
  final int roundNumber;

  final List<CartLineView> lines;
  final Map<String, List<KitchenPrepComponent>> prepByItemId;

  /// The parent's table — present for dine-in, null for takeaway (which has no
  /// table at all, and none is invented).
  final String? tableLabel;
  final String? customerName;
  final String? customerPhone;

  /// The parent's type as the POS domain enum, or null when the wire value is
  /// missing/unrecognized. FAIL-CLOSED on purpose: an unknown type is never
  /// coerced to dine-in, because that would print a type (and possibly a table
  /// line) the order does not actually have.
  OrderType? get orderType => switch (orderTypeWire) {
    'dine_in' => OrderType.dineIn,
    'takeaway' => OrderType.takeaway,
    _ => null,
  };
}

/// The lifecycle phase of the addition flow (one attempt at a time).
enum AdditionPhase {
  /// No addition anywhere — the cart is an ordinary new-order draft.
  idle,

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F1): the durable journal is being read and
  /// NOTHING is yet known about which orders carry an unresolved amendment.
  ///
  /// Published SYNCHRONOUSLY by [AdditionController.build], before the first
  /// `await`, precisely so this is never confused with [idle]. Idle is a
  /// positive statement — "there is no pending amendment" — and before the read
  /// completes we are not entitled to make it.
  hydrating,

  /// The journal could not be read. NOT idle, and never treated as an empty
  /// journal: an unreadable store may hold identities the server already owns,
  /// so the gate stays closed and no new attempt may be created.
  hydrationFailed,

  /// The target is RESERVED and its authoritative detail is loading. The
  /// reservation blocks any different target; the cart must stay empty.
  entering,

  /// The authoritative detail is installed; the cart builds the addition.
  active,

  /// The frozen attempt is on the wire. Cancel is REFUSED here.
  sending,

  /// The attempt failed (typed rejection or transport) — the frozen addition
  /// is intact and retryable; explicit cancel is allowed.
  failed,

  /// The server APPLIED the operation but the authoritative refresh has not
  /// yet proven it. The operation may NEVER be dispatched again; only the
  /// refresh may be retried; cancel is refused (the server has the addition).
  appliedAwaitingRefresh,
}

class AdditionState {
  const AdditionState({
    this.generation = 0,
    this.entryOrderId,
    this.target,
    this.attempt,
    this.appliedRoundId,
    this.phase = AdditionPhase.idle,
    this.lastError,
    this.dispatched = false,
  });

  /// The entry/attempt token (Finding 2): every reservation, exit and
  /// completed reconciliation bumps it, and every asynchronous continuation
  /// re-checks it before touching state — a stale response is discarded.
  final int generation;

  /// The order id RESERVED by entry — set synchronously before any await and
  /// held through every later phase, so a second different target is refused
  /// even while the detail is still loading.
  final String? entryOrderId;

  /// The order being extended (null while [AdditionPhase.entering] and when
  /// idle — the cart is an ordinary new-order draft then).
  final PosOrderDetail? target;

  /// The FROZEN in-progress attempt, if any (sending / failed / applied-
  /// awaiting-refresh).
  final AdditionAttempt? attempt;

  /// The round id the server reported for the APPLIED attempt — what the
  /// authoritative refresh must contain before cleanup may run (Finding 4).
  final String? appliedRoundId;

  final AdditionPhase phase;
  final String? lastError;

  /// MONEY-DURABLE-ADDITIONS-003C: whether the frozen attempt reached the
  /// transport WITHOUT a definitive verdict coming back — i.e. the server may
  /// already own the round and we cannot tell.
  ///
  /// The distinction matters. A typed business REJECTION is the server saying
  /// no: there is no round, so abandoning the identity is safe and the cashier
  /// must be able to. A TRANSPORT failure says nothing at all, and treating it
  /// as a no is how a second round gets created. Only the second case locks the
  /// identity down.
  ///
  /// Lives on the state, not just in the controller, because the UI must not
  /// offer a Cancel that cannot work — the same honesty rule the order-action
  /// predicates follow.
  final bool dispatched;

  bool get active => target != null;
  bool get sending => phase == AdditionPhase.sending;
  bool get failed => phase == AdditionPhase.failed;

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F1): the durable journal has not been read
  /// yet. Every mutation gate reads this; it is true from the synchronous part
  /// of `build()` until hydration settles.
  bool get isHydrating => phase == AdditionPhase.hydrating;

  /// The journal read failed. The till must not act as though nothing is
  /// pending, and no new Addition identity may be minted.
  bool get hydrationFailed => phase == AdditionPhase.hydrationFailed;

  /// Whether the startup gate is closed for either reason — the ONE predicate
  /// the entry, submit and cart gates ask.
  bool get startupBlocked => isHydrating || hydrationFailed;

  /// The server applied the addition; the authoritative refresh is still
  /// owed. Never resubmit; offer ONLY the refresh retry (Finding 4).
  bool get awaitingRefresh => phase == AdditionPhase.appliedAwaitingRefresh;

  /// An attempt exists that has not been reconciled or explicitly cancelled.
  bool get hasOpenAttempt => attempt != null;

  /// Finding 2: cancel is honest — it is only offered when it can actually
  /// happen. While SENDING the server may already own the operation; while
  /// APPLIED-AWAITING-REFRESH it definitely does.
  /// 003C: an attempt whose outcome is UNCERTAIN can never be cancelled,
  /// whatever phase it is showing. A transport failure looks retryable, but the
  /// operation was on the wire and its verdict is unknown — releasing the
  /// identity there is how a second server round gets created without any
  /// crash. A definitive rejection is different and stays cancellable.
  bool get canCancel =>
      !dispatched &&
      (phase == AdditionPhase.entering ||
          phase == AdditionPhase.active ||
          phase == AdditionPhase.failed);

  AdditionState copyWith({
    PosOrderDetail? target,
    AdditionAttempt? attempt,
    String? appliedRoundId,
    AdditionPhase? phase,
    String? lastError,
    bool clearError = false,
    bool? dispatched,
  }) => AdditionState(
    generation: generation,
    entryOrderId: entryOrderId,
    target: target ?? this.target,
    attempt: attempt ?? this.attempt,
    appliedRoundId: appliedRoundId ?? this.appliedRoundId,
    phase: phase ?? this.phase,
    lastError: clearError ? null : (lastError ?? this.lastError),
    dispatched: dispatched ?? this.dispatched,
  );
}

/// The applied result of one addition (for the confirmation toast).
class AdditionResult {
  const AdditionResult({
    required this.applied,
    this.roundNumber,
    this.error,
    this.refreshRequired = false,
    this.printPayload,
  });
  final bool applied;
  final int? roundNumber;
  final String? error;

  /// DEFERRED-ORDER-AMENDMENTS-001: non-null ONLY when the server applied the
  /// addition AND named both the round id and the round number — the identity the
  /// kitchen ticket and its exactly-once guard are built from. Absent otherwise:
  /// the addition stays applied, and no ticket is printed on a guess.
  final AdditionPrintPayload? printPayload;

  /// Finding 4: the server applied the addition but the authoritative
  /// refresh did not complete — the honest "saved, refresh required" state.
  final bool refreshRequired;
}

/// Why an [AdditionController.enterForOrder] call was or was not honoured.
enum AdditionEntryResult {
  /// Addition mode is active (or already entering) for the requested order.
  entered,

  /// A frozen attempt is pending/retryable/awaiting-refresh — the target is
  /// immutable until it is reconciled or explicitly cancelled.
  blockedPendingAttempt,

  /// A DIFFERENT order is already reserved or targeted — cancel it first.
  blockedDifferentTarget,

  /// The normal cart has lines (at entry, or gained during the detail load) —
  /// a cart is never silently retargeted into an addition.
  cartNotEmpty,

  /// The authoritative detail could not be loaded/parsed; the reservation was
  /// released and a later clean entry may succeed.
  detailUnavailable,

  /// The entry was superseded while its detail loaded (cancelled or replaced)
  /// — the stale continuation had zero side effects.
  superseded,

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F1): the durable journal has not been read
  /// yet, or could not be read. Entering now could start a SECOND attempt for
  /// an order that already has one, so it is refused until hydration settles.
  blockedHydrating,

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F4): two or more live journal records claim
  /// this order. No automatic winner may be picked and no third identity may be
  /// minted — a person must settle it.
  blockedConflict,
}

/// The wire operation type this controller dispatches. A result row answering
/// under any other type is not this operation's verdict.
const String kAdditionOperationType = 'order.items_add';

/// MONEY-CODEX-FINAL-CLOSURE-005 (F2) — the EXPLICIT allowlist of terminal
/// business refusals for `order.items_add`.
///
/// Every code here is emitted by real server source, not invented:
///
///  * the seven typed refusals `app.add_order_items` returns —
///    `invalid_device_type`, `permission_denied`, `invalid_item_payload`,
///    `order_not_dine_in`, `order_not_eligible`, `order_already_settled`,
///    `item_unavailable`. The LIVE definition is
///    `20260806090000_money_modifier_scope_003d_option_ownership.sql` (the RPC
///    has been re-created by 20260804090000 and 20260805090000 since its
///    20260722090000 introduction; the refusal set is unchanged across all of
///    them, but the live body is the one to read);
///  * `modifier_option_not_in_scope`, the 003D ownership refusal raised inside
///    the shared submit_order-parity pricing loop;
///  * `invalid_payload`, `public.sync_push`'s identity-hardening refusal for
///    `order.items_add` when `target_id` and `payload.order_id` are not a
///    matching uuid pair. TERMINAL and, critically, emitted BEFORE the ledger
///    claim — there is no stored row to replay, so re-sending the same identity
///    gets the identical answer forever. Omitting it left such an operation
///    looping as outcome-unknown, which locks the cart and withdraws Pay / Void
///    / Discount on that order permanently;
///  * `rejected`, `public.sync_push`'s generic permanent collapse of a raised
///    validation/authorization failure, which it ledgers terminally.
///
/// It reuses [kPermanentRejectionCodes] — the established set — and adds only
/// the add-items-specific codes, so the two contracts cannot drift apart. Four
/// members inherited from that spread (`table_required`, `table_not_allowed`,
/// `table_not_available`, `dispatch_mode_not_allowed`) are `order.submit`
/// refusals this RPC never emits; harmless, because a row is matched on the
/// operation identity AND type before its code is consulted.
///
/// WHY AN ALLOWLIST AT ALL. A rejecting status with an unrecognised code used to
/// be treated as a definitive no: the identity was released and the next send
/// minted a fresh `local_operation_id`. But `app.add_order_items` keys its
/// idempotency on (org, device, local_operation_id) — under a new key it builds
/// a SECOND round, and the kitchen cooks the same food twice. An unknown code
/// is not evidence that nothing happened.
///
/// `const`, so nothing can widen the set that decides which server refusals free
/// an idempotency identity.
const Set<String> kAdditionTerminalRefusalCodes = <String>{
  ...kPermanentRejectionCodes,
  'invalid_device_type',
  'permission_denied',
  'invalid_item_payload',
  'invalid_payload',
  'order_not_dine_in',
  'order_not_eligible',
  'order_already_settled',
};

/// What a `sync_push` response proves about one Add-items operation.
enum AdditionOutcomeKind {
  /// A COMPLETE authoritative applied result naming a real round.
  applied,

  /// An allowlisted terminal business refusal. No round exists; the identity is
  /// free and the cashier may correct and re-send as a new operation.
  refused,

  /// The identity exists server-side under a different payload. Never a second
  /// round, never resolvable by retrying — it needs a person.
  conflict,

  /// The response proves NOTHING about this operation. The server may or may not
  /// own the round; only a replay of the same identity can tell us.
  unknown,
}

/// The classified outcome. [reason] is a SAFE local classification code — never
/// raw backend text, never a stack trace — suitable for the journal and for the
/// operator-facing message.
class AdditionOutcome {
  const AdditionOutcome.applied({
    required this.roundId,
    required this.roundNumber,
  }) : kind = AdditionOutcomeKind.applied,
       reason = null;

  const AdditionOutcome.refused(String code)
    : kind = AdditionOutcomeKind.refused,
      reason = code,
      roundId = null,
      roundNumber = null;

  const AdditionOutcome.conflict()
    : kind = AdditionOutcomeKind.conflict,
      reason = 'conflict',
      roundId = null,
      roundNumber = null;

  const AdditionOutcome.unknown(this.reason)
    : kind = AdditionOutcomeKind.unknown,
      roundId = null,
      roundNumber = null;

  final AdditionOutcomeKind kind;
  final String? reason;

  /// Non-null ONLY for [AdditionOutcomeKind.applied], and then guaranteed to be
  /// a non-blank round id and a real integer round number.
  final String? roundId;
  final int? roundNumber;

  // NO `replay` FLAG. `app.sync_push`'s applied merge is
  // `v_dispatch || {..., 'idempotency_replay', false}` and the right operand
  // wins, so an APP-level replay from `app.add_order_items` (which returns
  // true) reaches the client as false. The field would have been unread and
  // wrong; recovery does not need it, because a replay is deliberately handled
  // identically to a first application.
}

class AdditionController extends Notifier<AdditionState> {
  Future<AdditionResult>? _inFlight;

  /// Whether this controller's container has been torn down. Hydration and
  /// queue advancement both run in asynchronous continuations that can outlive
  /// the container (a disposed test container, a POS surface popped mid-restore),
  /// and reading a provider from a disposed container throws.
  bool _disposed = false;

  /// The generation the in-flight submit belongs to — a single-flight join is
  /// only valid for the SAME attempt. A stale still-pending future from a
  /// reconciled/cancelled attempt must never be handed to a NEW attempt's
  /// submit (its result would be the old attempt's, and nothing would
  /// dispatch).
  int? _inFlightGeneration;

  @override
  AdditionState build() {
    // MONEY-DURABLE-ADDITIONS-003C: rehydrate an unresolved amendment. An
    // operation whose outcome is UNKNOWN must not disappear because the process
    // died — nothing else in the system can resolve it, and re-keying it under
    // a fresh identity is exactly how a second server round gets created.
    //
    // MONEY-CODEX-FINAL-CLOSURE-005 (F1) — THE HYDRATION GATE IS SYNCHRONOUS.
    //
    // This used to call `_restoreJournal()` and immediately return
    // `const AdditionState()`, whose phase is `idle`. Everything the journal
    // knows arrives one or more microtasks later, after a real disk read, so
    // for that whole window the till positively asserted "no amendment is
    // pending" — and the cashier could add cart lines the restored attempt
    // would then own and destroy, enter Add-items for the very order with an
    // unresolved operation, or take a payment against a total the server was
    // about to change. A cold start is exactly when a till gets tapped.
    //
    // The gate is therefore closed HERE, in the synchronous part of build(),
    // before `_restoreJournal()` is even called — there is no `await` between
    // the decision and the observable state.
    //
    // Only when something durable is actually wired: with no store (demo mode,
    // most tests) there is nothing to hydrate, nothing could be pending, and
    // paying for a gate that guards an absent store would block a till that has
    // no amendment mechanism at all.
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final journal = ref.read(additionJournalStoreProvider);
    if (journal == null || _journalScope.isEmpty) return const AdditionState();
    // Closing the gate mutates a plain shared object, not another provider's
    // state, which is what makes it legal HERE — inside build, with no await
    // before it. The cart consults the same object on every mutation, so it is
    // barred from this instant on, whether or not it has been built yet.
    ref.read(posAdditionHydrationGateProvider).close();
    // The restore itself is deferred a microtask so that NOTHING it does — not
    // even its early returns — runs during this build.
    Future.microtask(_restoreJournal);
    return const AdditionState(phase: AdditionPhase.hydrating);
  }

  /// The durable journal for this device, or null when nothing durable is wired
  /// (demo mode / tests), in which case the pre-003C session behaviour stands.
  PosAdditionJournalStore? get _journal =>
      ref.read(additionJournalStoreProvider);

  /// RF-114 scope binding: the journal is keyed by THIS session's device, so one
  /// device never replays another's amendment.
  String get _journalScope => ref.read(posSyncSessionProvider)?.deviceId ?? '';

  /// Rebuilds the durable record for [attempt] and CONFIRMS the write. Returns
  /// whether the operation may now be dispatched.
  Future<bool> _journalPrepared(
    AdditionAttempt attempt,
    PosOrderDetail target,
    PosAdditionJournalStore journal,
  ) async {
    final scope = _journalScope;
    if (scope.isEmpty) return true; // no session => no real submit anyway
    try {
      final existing = await journal.load(scope);
      final record = PosAdditionJournalRecord(
        localOperationId: attempt.localOperationId,
        orderId: attempt.orderId,
        orderCode: target.orderCode,
        orderTypeWire: target.orderType ?? '',
        generation: state.generation,
        itemsJson: attempt.itemsJson,
        lines: attempt.lines,
        prepByItemId: attempt.prepByItemId,
        // The 002A formula, computed ONCE here and never recomputed: each line
        // already carries qty x (base + Σ(delta x modifierQty)).
        expectedDeltaMinor: attempt.lines.fold<int>(
          0,
          (sum, l) => sum + l.lineTotalMinor,
        ),
        currencyCode: attempt.lines.isEmpty
            ? 'ILS'
            : attempt.lines.first.currencyCode,
        clientCreatedAt: attempt.clientCreatedAt,
        // DISPATCHING, written BEFORE the wire. A crash between this write and
        // the invoke therefore reads as "outcome unknown", which is the truth —
        // recording `prepared` here would let recovery wrongly conclude the
        // server never saw it and free the identity.
        phase: PosAdditionJournalPhase.dispatching,
        tableLabel: target.tableLabel,
        customerName: target.customerName,
        customerPhone: target.customerPhone,
        attemptCount:
            (existing[attempt.localOperationId]?.attemptCount ?? 0) + 1,
      );
      await journal.persist(scope, <String, PosAdditionJournalRecord>{
        ...existing,
        attempt.localOperationId: record,
      });
      return true;
    } catch (_) {
      // Includes PosPersistenceException from a refused write. Fail CLOSED.
      return false;
    }
  }

  /// Records a phase transition. Best-effort by design: by this point the
  /// operation's real outcome is already known in memory, and refusing to carry
  /// on because a bookkeeping write failed would turn a storage wobble into a
  /// lost order. The record itself stays on disk under its previous phase,
  /// which always errs toward reconciling again rather than toward forgetting.
  Future<void> _journalPhase(
    String localOperationId,
    PosAdditionJournalPhase phase, {
    String? errorCode,
    String? roundId,
    int? roundNumber,
  }) async {
    final journal = _journal;
    if (journal == null) return;
    final scope = _journalScope;
    if (scope.isEmpty) return;
    try {
      final existing = await journal.load(scope);
      final record = existing[localOperationId];
      if (record == null) return;
      await journal.persist(scope, <String, PosAdditionJournalRecord>{
        ...existing,
        localOperationId: record.copyWith(
          phase: phase,
          lastErrorCode: errorCode,
          appliedRoundId: roundId,
          appliedRoundNumber: roundNumber,
        ),
      });
    } catch (_) {
      // Surfaced through the store's own degraded health, never swallowed into
      // a false claim about the operation.
    }
  }

  /// Removes the record — ONLY after authoritative confirmation, or for an
  /// attempt that provably never reached the server.
  Future<void> _journalClose(String localOperationId) async {
    _indexPending(
      _pending.where((r) => r.localOperationId != localOperationId),
    );
    final journal = _journal;
    if (journal == null) return;
    final scope = _journalScope;
    if (scope.isEmpty) return;
    try {
      final existing = await journal.load(scope);
      if (!existing.containsKey(localOperationId)) return;
      final remaining = <String, PosAdditionJournalRecord>{
        for (final e in existing.entries)
          if (e.key != localOperationId) e.key: e.value,
      };
      await journal.persist(scope, remaining);
      // MONEY-CODEX-FINAL-CLOSURE-005 (F4): re-index from what is ACTUALLY on
      // disk, not from the in-memory list — the durable set is the truth, and a
      // record written by a path that did not go through `_pending` (a
      // concurrent phase write, a repaired quarantine) must still be sequenced.
      _indexPending(remaining.values);
    } catch (_) {
      // The record survives; reconciliation is idempotent and will close it.
    }
  }

  /// Hydrates the durable journal, indexes every actionable record, detects
  /// same-order conflicts, and activates the oldest SAFE record — re-owning its
  /// cart under the token it was frozen with.
  ///
  /// MONEY-CODEX-FINAL-CORRECTIONS-004 (F1). The 003C build deliberately did
  /// NOT re-acquire the lock, reasoning that an empty post-restart cart has
  /// nothing to protect. That was wrong twice over:
  ///
  ///  * a restored FAILED attempt left the cart free, so the cashier could type
  ///    new lines that were never part of the frozen payload — and the
  ///    reconciliation's privileged `clearForAddition` then destroyed them;
  ///  * a restored APPLIED-AWAITING-REFRESH attempt could never complete at all.
  ///    `submit()` short-circuits to `retryRefresh()`, which reaches
  ///    `_reconcileApplied` without ever locking, so the `ownsAdditionLock`
  ///    fence was permanently false: the journal never closed and the order
  ///    stayed blocked for ever.
  ///
  /// MONEY-CODEX-FINAL-CLOSURE-005 (F4). Three further corrections:
  ///
  ///  * `prepared` records are actionable. The previous filter required
  ///    `wasDispatched`, but the journal is written BEFORE the first dispatch
  ///    precisely so the identity survives a crash in that window — dropping
  ///    the record is exactly how the retry mints a second identity;
  ///  * a same-order collision is a FAIL-CLOSED conflict, not a queue. Two live
  ///    records claiming one order cannot both be right and nothing here may
  ///    guess which; both are preserved, neither is dispatched;
  ///  * the queue ADVANCES. Closing the active record recomputes ownership and
  ///    activates the next safe one, so a second order's amendment does not stay
  ///    invisible for the rest of the session.
  Future<void> _restoreJournal() async {
    if (_disposed) return;
    // FIRST FRAME HONESTY. The gate is consulted live by every cart mutation, so
    // money is safe from the instant `build()` closes it — but `CartController`
    // is built LAZILY and in production (`cart_panel.dart`) it is watched BEFORE
    // the addition controller, so its published `lockedByAddition` can have been
    // computed while the gate was still open. Republishing here, in the first
    // microtask (never during a build, which Riverpod forbids), makes the flag
    // agree with the gate before anything is painted.
    ref.read(cartControllerProvider.notifier).refreshAdditionLockView();
    final journal = _journal;
    final scope = _journalScope;
    if (journal == null || scope.isEmpty) {
      _releaseHydration(const AdditionState());
      return;
    }
    Map<String, PosAdditionJournalRecord> records;
    try {
      records = await journal.load(scope);
      if (_disposed) return;
    } catch (_) {
      if (_disposed) return;
      // FAIL CLOSED. A journal we could not read is not an empty journal: it may
      // hold identities the server already owns. Staying in `hydrationFailed`
      // keeps the cart gate shut and refuses every new attempt, which is
      // recoverable; declaring idle is not.
      state = const AdditionState(
        phase: AdditionPhase.hydrationFailed,
        lastError: 'journal_unreadable',
      );
      return;
    }
    _indexPending(records.values);
    _activateNextSafeRecord(releaseGateWhenIdle: true);
  }

  /// Rebuilds the pending index from [all], oldest first, and recomputes which
  /// orders are in same-order conflict.
  void _indexPending(Iterable<PosAdditionJournalRecord> all) {
    final actionable = all.where((r) => r.needsAttention).toList()
      ..sort((a, b) {
        final byTime = a.clientCreatedAt.compareTo(b.clientCreatedAt);
        // A stable tiebreak so two records stamped in the same millisecond do
        // not reorder between runs — sequencing must be deterministic.
        return byTime != 0
            ? byTime
            : a.localOperationId.compareTo(b.localOperationId);
      });
    _pending = List.unmodifiable(actionable);

    // SAME-ORDER CONFLICT (F4). Two or more live records claiming one order
    // cannot both be reconciled: whichever we replayed first would leave the
    // other's identity dangling against a changed order. There is no safe
    // automatic winner, so the order is frozen and both records are kept.
    // A record the SERVER already called a conflict marks its order too.
    final byOrder = <String, int>{};
    for (final r in actionable) {
      byOrder[r.orderId] = (byOrder[r.orderId] ?? 0) + 1;
    }
    _conflictingOrderIds = <String>{
      for (final e in byOrder.entries)
        if (e.value > 1) e.key,
      for (final r in actionable)
        if (r.isConflict) r.orderId,
    };
  }

  /// Makes the oldest SAFE pending record the active attempt and re-owns its
  /// cart. A record whose order is in conflict is never activated.
  ///
  /// [releaseGateWhenIdle] opens the startup gate when there is nothing to
  /// activate — used by hydration, which owns the gate.
  void _activateNextSafeRecord({bool releaseGateWhenIdle = false}) {
    if (_disposed) return;
    // Never clobber work started in this session.
    if (state.attempt != null || state.entryOrderId != null) {
      if (releaseGateWhenIdle) _openCartGate();
      return;
    }
    final record = _pending
        .where(
          (r) => !_conflictingOrderIds.contains(r.orderId) && _mayTakeCart(r),
        )
        .firstOrNull;
    if (record == null) {
      // THE GENERATION IS PRESERVED, never reset. It is the single-flight join
      // key (`_inFlightGeneration`) and every asynchronous continuation's fence:
      // rewinding it lets a NEW attempt collide with a still-pending future from
      // an older one, which returns the old attempt's result and dispatches
      // nothing. Records remaining means the flow is blocked on a person, not
      // idle, and it must not claim otherwise.
      _releaseHydration(
        AdditionState(
          generation: state.generation,
          lastError: _pending.isEmpty ? null : 'amendment_conflict',
        ),
      );
      return;
    }
    _activateRecord(record);
  }

  /// Whether [record] may take the cart right now.
  ///
  /// SELF-REVIEW CORRECTION (D1). Activation used to lock unconditionally, and
  /// `lockForAddition` succeeds on ANY unlocked cart regardless of contents. The
  /// queue advances from an async continuation — after `await _journalClose`,
  /// two real SharedPreferences round-trips — and the cart is unlocked for that
  /// whole window. A cashier who starts the next customer's order in it would
  /// find those lines seized under a DIFFERENT order's identity: every mutation
  /// refused, `exit()` refused (the record is dispatched), the cart panel
  /// showing the new lines under the restored attempt's banner while a submit
  /// would dispatch the frozen payload instead. The only escape was a successful
  /// replay — over the network whose absence created the record.
  ///
  /// So a non-empty cart defers activation. The record stays pending, its order
  /// stays blocked in the orders sheet, and `enterForOrder` resumes it once the
  /// cashier has cleared or sent what they were doing.
  bool _mayTakeCart(PosAdditionJournalRecord record) {
    if (ref.read(cartControllerProvider).isEmpty) return true;
    // Already ours (an idempotent re-activation) is fine.
    return ref
        .read(cartControllerProvider.notifier)
        .ownsAdditionLock(
          _ownerOf(
            record.generation,
            AdditionAttempt(
              orderId: record.orderId,
              localOperationId: record.localOperationId,
              itemsJson: record.itemsJson,
              clientCreatedAt: record.clientCreatedAt,
            ),
          ),
        );
  }

  /// Installs [record] as the active attempt and re-owns its cart.
  void _activateRecord(PosAdditionJournalRecord record) {
    final attempt = AdditionAttempt(
      orderId: record.orderId,
      localOperationId: record.localOperationId,
      itemsJson: record.itemsJson,
      clientCreatedAt: record.clientCreatedAt,
      lines: record.lines,
      prepByItemId: record.prepByItemId,
    );
    state = AdditionState(
      // A `prepared` record provably never reached the transport, so its
      // identity may still be abandoned; every other phase may already be owned
      // by the server.
      dispatched: record.wasDispatched,
      // The PERSISTED generation, so `_ownerOf` reproduces the byte-equal
      // CartLockOwner the attempt was frozen under.
      generation: record.generation,
      entryOrderId: record.orderId,
      attempt: attempt,
      appliedRoundId: record.appliedRoundId,
      phase:
          record.phase == PosAdditionJournalPhase.awaitingAuthoritativeRefresh
          ? AdditionPhase.appliedAwaitingRefresh
          : AdditionPhase.failed,
      lastError: record.lastErrorCode ?? 'reconcile_required',
    );

    // RE-OWN THE CART (004 F1), synchronously and before any await, so there is
    // no window in which the restored attempt exists but its cart is editable.
    // Idempotent: `lockForAddition` re-asserts a matching token and only refuses
    // a FOREIGN one, in which case the attempt stays visible and unresolved
    // rather than silently taking someone else's cart.
    ref
        .read(cartControllerProvider.notifier)
        .lockForAddition(_ownerOf(record.generation, attempt));
    // The real owner lock now holds the cart, so the blunt startup gate can go.
    _openCartGate();

    // Re-install the authoritative parent so the resumed submit/refresh has the
    // same target it had before. A failure here leaves the attempt visible and
    // unresolved rather than silently dropping it.
    unawaited(_installTarget(record));
  }

  Future<void> _installTarget(PosAdditionJournalRecord record) async {
    if (_disposed) return;
    try {
      final detail = await ref
          .read(orderDetailRepositoryProvider)
          .fetch(record.orderId);
      if (state.attempt?.localOperationId != record.localOperationId) return;
      if (detail.orderId != record.orderId) return;
      state = state.copyWith(target: detail);
    } catch (_) {
      // Keep the restored attempt; the order stays locked and pending.
    }
  }

  /// Publishes [next] and opens the startup cart gate together.
  void _releaseHydration(AdditionState next) {
    if (_disposed) return;
    state = next;
    _openCartGate();
  }

  void _openCartGate() {
    if (_disposed) return;
    final gate = ref.read(posAdditionHydrationGateProvider);
    if (!gate.isClosed) return;
    gate.open();
    // Republish so the cart's `lockedByAddition` view flag agrees with the gate
    // it just reopened. Safe here: every caller is an async continuation, never
    // a build.
    ref.read(cartControllerProvider.notifier).refreshAdditionLockView();
  }

  /// Whether an unresolved amendment is being carried for [orderId] — the
  /// signal the order-action gates and the operator surface read after a
  /// restart, when nothing else remembers the operation.
  bool hasUnresolvedAmendmentFor(String orderId) =>
      state.attempt?.orderId == orderId ||
      _pending.any((r) => r.orderId == orderId);

  /// MONEY-CODEX-FINAL-CORRECTIONS-004 (F4): every journal record still needing
  /// attention, oldest first — the ACTIVE one plus every other order's blocked
  /// record. The action gates, the operator surface and the cutover all read
  /// this, so "no unresolved amendments" can be stated truthfully instead of
  /// meaning "none that happened to be restored".
  List<PosAdditionJournalRecord> _pending = const <PosAdditionJournalRecord>[];

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F4): orders with two or more live records,
  /// plus every order carrying a server-declared conflict. FROZEN: no automatic
  /// winner, no dispatch, no new identity — a person must settle them.
  Set<String> _conflictingOrderIds = const <String>{};

  List<PosAdditionJournalRecord> get pendingAmendments => _pending;

  /// Orders currently blocked by an amendment awaiting resolution.
  Set<String> get blockedOrderIds => <String>{
    if (state.attempt?.orderId case final id?) id,
    for (final r in _pending) r.orderId,
  };

  /// Orders frozen by a same-order (or server-declared) conflict.
  Set<String> get conflictingOrderIds => _conflictingOrderIds;

  /// How many blocked records are CONFLICTS — the ones a person must settle.
  ///
  /// Counts BOTH server-declared conflicts and records caught in a same-order
  /// collision, because the operator surface and the cutover need one truthful
  /// "needs a human" number, not two partial ones.
  int get conflictCount => _pending
      .where((r) => r.isConflict || _conflictingOrderIds.contains(r.orderId))
      .length;

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F1/F4): whether the startup gate is closed —
  /// the journal is being read, or could not be read. Read by the cart panel and
  /// the orders sheet so no money action is offered on an unknown journal.
  bool get isStartupBlocked => state.startupBlocked;

  /// Finding 1 — CONTROLLER-OWNED SAFE ENTRY into addition mode.
  ///
  /// The complete transition lives here, not in the UI: the synchronous part
  /// validates (no open attempt, no different target, EMPTY cart) and
  /// RESERVES [orderId] under a fresh generation token BEFORE any await; the
  /// awaited authoritative load then commits ONLY if the same token is still
  /// current, the target is unchanged, and the cart REMAINED empty. A cart
  /// line added during the load keeps its normal-cart meaning: the fetched
  /// detail is discarded, the reservation is released, and the caller gets
  /// the honest [AdditionEntryResult.cartNotEmpty].
  Future<AdditionEntryResult> enterForOrder(String orderId) async {
    final s = state;
    // MONEY-CODEX-FINAL-CLOSURE-005 (F1): the durable journal has not been read
    // (or could not be), so we do not know whether THIS order already has an
    // unresolved amendment. Entering would look like a fresh attempt and the
    // next submit would mint a second identity for an operation the server may
    // already own. Refused until hydration settles — it is a disk read.
    if (s.startupBlocked) return AdditionEntryResult.blockedHydrating;
    // MONEY-CODEX-FINAL-CLOSURE-005 (F4): two live records claim this order.
    // Neither may be resumed and no third identity may be created; a person has
    // to decide which operation is real.
    if (_conflictingOrderIds.contains(orderId)) {
      return AdditionEntryResult.blockedConflict;
    }
    // F4: a non-terminal record exists for this order but is not the ACTIVE
    // attempt (it is queued behind another order's). Resume it rather than
    // starting a new one — a new attempt would be a second identity.
    if (s.attempt == null && s.entryOrderId == null) {
      final queued = _pending.where((r) => r.orderId == orderId).firstOrNull;
      if (queued != null) {
        // D1/D2: the same empty-cart guarantee every other entry path enforces.
        // Resuming must never take lines the cashier is holding — this method is
        // documented as the ACTUAL guarantee, not the UI's convenience check.
        if (!_mayTakeCart(queued)) return AdditionEntryResult.cartNotEmpty;
        _activateRecord(queued);
        return AdditionEntryResult.entered;
      }
    }
    // Idempotent same-target re-entry: already reserved/entering/active for
    // this exact order — nothing to change, nothing to refetch.
    //
    // 003C: this is also how a RESTORED unresolved amendment is resumed. The
    // restore installs `entryOrderId`, so coming back to Add-items for that
    // order returns `entered` with the frozen attempt still held, and the next
    // submit replays the SAME identity instead of starting a new operation.
    if (s.entryOrderId == orderId) return AdditionEntryResult.entered;
    if (s.attempt != null) return AdditionEntryResult.blockedPendingAttempt;
    if (s.entryOrderId != null) {
      return AdditionEntryResult.blockedDifferentTarget;
    }
    if (!ref.read(cartControllerProvider).isEmpty) {
      return AdditionEntryResult.cartNotEmpty;
    }
    final gen = s.generation + 1;
    state = AdditionState(
      generation: gen,
      entryOrderId: orderId,
      phase: AdditionPhase.entering,
    );

    final PosOrderDetail detail;
    try {
      detail = await ref.read(orderDetailRepositoryProvider).fetch(orderId);
    } catch (_) {
      if (_isCurrentEntry(gen, orderId)) {
        state = AdditionState(generation: gen + 1);
        return AdditionEntryResult.detailUnavailable;
      }
      return AdditionEntryResult.superseded;
    }

    // COMMIT FENCE: same entry token, same reserved target, still entering.
    if (!_isCurrentEntry(gen, orderId)) return AdditionEntryResult.superseded;
    if (detail.orderId != orderId) {
      // The repository answered for a different order — never install it.
      state = AdditionState(generation: gen + 1);
      return AdditionEntryResult.detailUnavailable;
    }
    if (!ref.read(cartControllerProvider).isEmpty) {
      // The cart changed while loading: the line stays a NORMAL cart line,
      // the fetched detail is discarded, no operation id was allocated.
      state = AdditionState(generation: gen + 1);
      return AdditionEntryResult.cartNotEmpty;
    }
    state = AdditionState(
      generation: gen,
      entryOrderId: orderId,
      target: detail,
      phase: AdditionPhase.active,
    );
    return AdditionEntryResult.entered;
  }

  bool _isCurrentEntry(int gen, String orderId) =>
      state.generation == gen &&
      state.entryOrderId == orderId &&
      state.phase == AdditionPhase.entering;

  /// Leaves addition mode, EXPLICITLY discarding any frozen attempt — the
  /// next submission gets a NEW operation id and a fresh payload.
  ///
  /// Finding 2: REFUSED (returns false, state untouched) while the attempt is
  /// on the wire or applied-awaiting-refresh — the server may/does own the
  /// operation, and pretending it was cancelled would let the same lines be
  /// sent again as something else.
  ///
  /// Cart-safety: cancelling a FAILED frozen attempt releases the cart
  /// mutation lock with the matching owner token — the cart LINES stay intact
  /// (discarding work is the cashier's explicit choice via the cart's own
  /// Clear), and editing + a fresh attempt with a NEW operation id become
  /// possible again. The release fails closed on a token mismatch.
  bool exit() {
    final s = state;
    // F1: nothing may be released while the journal is unread — there may be an
    // identity behind it that this call would silently free.
    if (s.startupBlocked) return false;
    if (!s.canCancel && s.phase != AdditionPhase.idle) return false;
    final attempt = s.attempt;
    // MONEY-DURABLE-ADDITIONS-003C: an attempt that REACHED THE TRANSPORT may
    // never be discarded here.
    //
    // `canCancel` includes `failed`, and a transport timeout lands in `failed` —
    // but a timeout is not a "no". The server may already have applied the
    // round; we simply never heard. Releasing the identity there means the next
    // submission dispatches a DIFFERENT operation, `app.add_order_items` cannot
    // recognise it as a replay, and the kitchen gets a second round of the same
    // food. That needed no crash at all: a timeout, Cancel, and re-send did it.
    //
    // So the UI may dismiss, but the identity stays: the attempt is retained,
    // the order remains reconciliation-pending, and coming back to Add-items
    // for it RESUMES the frozen operation. A fresh identity becomes available
    // only once this one reaches a terminal, safely-released state.
    if (attempt != null && s.dispatched) {
      state = s.copyWith(lastError: 'reconcile_required');
      return false;
    }
    if (attempt != null &&
        !ref
            .read(cartControllerProvider.notifier)
            .unlockForAddition(_ownerOf(s.generation, attempt))) {
      return false;
    }
    // An attempt that provably never left this device is safe to abandon, and
    // its journal record (if any) goes with it — there is nothing to replay.
    if (attempt != null) {
      unawaited(
        _journalClose(attempt.localOperationId).then((_) {
          // F4: cancelling a definitive rejection must advance the queue too,
          // otherwise the NEXT order's pending amendment is stranded behind an
          // attempt the cashier already dismissed.
          if (state.attempt == null && state.entryOrderId == null) {
            _activateNextSafeRecord();
          }
        }),
      );
    }
    state = AdditionState(generation: s.generation + 1);
    return true;
  }

  /// The cart-lock owner token of one frozen attempt — the SAME immutable
  /// identity from freeze to release; never exposed to the widget layer.
  CartLockOwner _ownerOf(int generation, AdditionAttempt attempt) =>
      CartLockOwner(
        generation: generation,
        orderId: attempt.orderId,
        localOperationId: attempt.localOperationId,
      );

  /// Submits the pending addition. The FIRST call ATOMICALLY snapshots the
  /// LIVE cart into the immutable attempt and acquires the cart mutation lock
  /// (one synchronous block — no window where the payload is frozen but the
  /// cart still accepts edits); retries resend the frozen snapshot verbatim.
  /// Single-flight; duplicate taps await the same attempt. In
  /// [AdditionPhase.appliedAwaitingRefresh] this NEVER dispatches again — it
  /// retries only the authoritative refresh (Finding 4).
  Future<AdditionResult> submit() {
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightGeneration == state.generation) {
      return inFlight;
    }
    final attempt = _submit();
    _inFlight = attempt;
    _inFlightGeneration = state.generation;
    attempt.whenComplete(() {
      if (identical(_inFlight, attempt)) {
        _inFlight = null;
        _inFlightGeneration = null;
      }
    });
    return attempt;
  }

  Future<AdditionResult> _submit() async {
    final s0 = state;
    // MONEY-CODEX-FINAL-CLOSURE-005 (F1): no network operation, and no new
    // local_operation_id, may exist before the durable journal has been read.
    // This is the first statement in the submit path deliberately — every later
    // branch either freezes an identity or reaches the transport.
    if (s0.startupBlocked) {
      return const AdditionResult(applied: false, error: 'hydrating');
    }
    // Finding 4: an APPLIED operation is never re-dispatched. The only thing
    // left to retry is the authoritative refresh.
    if (s0.phase == AdditionPhase.appliedAwaitingRefresh) {
      final reconciled = await retryRefresh();
      return AdditionResult(applied: true, refreshRequired: !reconciled);
    }
    final target = s0.target;
    if (target == null || s0.phase == AdditionPhase.entering) {
      return const AdditionResult(applied: false, error: 'nothing_to_add');
    }
    final cfg = ref.read(runtimeConfigProvider);
    final transport = ref.read(posAuthTransportProvider);
    final session = ref.read(posSyncSessionProvider);
    if (cfg.isDemoMode || transport == null || session == null) {
      state = s0.copyWith(phase: AdditionPhase.failed, lastError: 'no_session');
      return const AdditionResult(applied: false, error: 'no_session');
    }

    // ATOMIC FREEZE + LOCK (Finding 2 + cart-safety): one SYNCHRONOUS block —
    // no await between these lines — reads the LIVE cart, finalizes the
    // immutable attempt identity, and acquires the CartController mutation
    // lock for exactly that identity. From here until reconciliation or
    // explicit cancel, the visible cart and the frozen payload cannot
    // diverge, and no unrelated line can slip in only to be cleared later.
    // Retries re-assert the SAME owner token (idempotent).
    final gen = s0.generation;
    final cartController = ref.read(cartControllerProvider.notifier);
    var attempt = s0.attempt;
    if (attempt == null) {
      final lines = ref.read(cartControllerProvider).lines;
      if (lines.isEmpty) {
        return const AdditionResult(applied: false, error: 'nothing_to_add');
      }
      // DEFERRED-ORDER-AMENDMENTS-001: the ONE order-time prep snapshot, read
      // here inside the synchronous freeze and then used for BOTH the wire
      // payload and the printed addition ticket — so a menu edit while the
      // operation is in flight can never make the paper disagree with what the
      // server applied.
      final prepByItemId = _prepSnapshot();
      attempt = AdditionAttempt(
        orderId: target.orderId,
        localOperationId: ref.read(clientIdGeneratorProvider).newId(),
        itemsJson: _serializeLines(lines, prepByItemId),
        clientCreatedAt: DateTime.now(),
        lines: List.unmodifiable(lines),
        prepByItemId: prepByItemId,
      );
    }
    if (!cartController.lockForAddition(_ownerOf(gen, attempt))) {
      // Another attempt owns the cart — refuse WITHOUT dispatching, without
      // storing the new identity, and with the cart untouched.
      return const AdditionResult(applied: false, error: 'cart_locked');
    }

    state = s0.copyWith(
      attempt: attempt,
      phase: AdditionPhase.sending,
      clearError: true,
    );

    // MONEY-DURABLE-ADDITIONS-003C — PERSIST BEFORE DISPATCH.
    //
    // The frozen identity and payload are written to the durable journal and
    // the write is CONFIRMED before a single byte goes to the transport. If it
    // cannot be stored, nothing is sent: without the record there is nothing to
    // replay under, so a later retry would mint a NEW local_operation_id and
    // `app.add_order_items` — whose idempotency is keyed on
    // (org, device, local_operation_id) — would build a SECOND round for food
    // the kitchen is already cooking.
    //
    // The failure is returned as a typed AdditionResult rather than thrown:
    // `cart_panel._handleSend` wraps the call in try/finally with no catch, so a
    // throw here would escape as an unhandled async error instead of the honest
    // "not sent, keep your cart" the cashier needs.
    // The await happens ONLY when there is something durable to write. With no
    // journal wired (demo mode / tests) the path from the synchronous freeze to
    // the invoke stays exactly as it was — an extra microtask here would change
    // observable dispatch timing for every existing caller, which is not this
    // phase's business to alter.
    final journal = _journal;
    if (journal != null && !await _journalPrepared(attempt, target, journal)) {
      if (_isCurrentAttempt(gen, attempt)) {
        state = state.copyWith(
          phase: AdditionPhase.failed,
          lastError: 'storage',
        );
      }
      return const AdditionResult(applied: false, error: 'storage');
    }

    // From here the server may see this operation. Recorded BEFORE the await,
    // so a continuation that lands after a dismissal still knows the identity
    // is owned and must not be released.
    state = state.copyWith(dispatched: true);

    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[
          <String, dynamic>{
            'local_operation_id': attempt.localOperationId,
            'operation_type': 'order.items_add',
            'target_entity': 'order',
            'target_id': attempt.orderId,
            'client_created_at': attempt.clientCreatedAt.toIso8601String(),
            'payload': <String, dynamic>{
              'order_id': attempt.orderId,
              'order_items': attempt.itemsJson,
            },
          },
        ],
      });
    } catch (_) {
      // TRANSPORT UNCERTAIN — NOT "not applied". The server may already own the
      // round; only a replay of this exact identity can tell us. The journal
      // keeps the frozen operation so that replay is possible.
      await _journalPhase(
        attempt.localOperationId,
        PosAdditionJournalPhase.transportUncertain,
        errorCode: 'transport',
      );
      if (_isCurrentAttempt(gen, attempt)) {
        state = state.copyWith(
          phase: AdditionPhase.failed,
          lastError: 'transport',
        );
      }
      return const AdditionResult(applied: false, error: 'transport');
    }

    // RESPONSE FENCE (Finding 2): only THIS attempt's state may be updated —
    // a stale continuation (disposal, delayed callback, future transitions)
    // must not clear a newer cart, install another order's detail, or show
    // success for the wrong attempt.
    if (!_isCurrentAttempt(gen, attempt)) {
      return const AdditionResult(applied: false, error: 'stale_attempt');
    }

    // MONEY-CODEX-FINAL-CLOSURE-005 (F2): ONE strict classification, wrapped
    // against every parser failure. Only a COMPLETE applied result or an
    // ALLOWLISTED refusal is a verdict.
    final outcome = classifyAdditionResponse(
      raw,
      localOperationId: attempt.localOperationId,
      orderId: attempt.orderId,
    );

    switch (outcome.kind) {
      case AdditionOutcomeKind.unknown:
        // AMBIGUOUS. Treated exactly like a dead transport, because that is what
        // it is: we do not know whether the server built the round. The identity
        // and the frozen payload are retained, the cart stays owned, `exit()`
        // cannot release it, and the next attempt REPLAYS this operation rather
        // than minting a second one.
        await _journalPhase(
          attempt.localOperationId,
          PosAdditionJournalPhase.transportUncertain,
          errorCode: outcome.reason,
        );
        if (!_disposed && _isCurrentAttempt(gen, attempt)) {
          state = state.copyWith(
            phase: AdditionPhase.failed,
            lastError: outcome.reason,
            dispatched: true,
          );
        }
        return AdditionResult(applied: false, error: outcome.reason);

      case AdditionOutcomeKind.conflict:
        await _journalPhase(
          attempt.localOperationId,
          PosAdditionJournalPhase.conflict,
          errorCode: 'conflict',
        );
        // NOT definitive: the identity is already in use server-side and only a
        // person can untangle it, so it stays locked and dispatched.
        //
        // FENCED like the unknown branch above. `_journalPhase` is a real disk
        // read AND write, so this resumes after an await; writing state without
        // re-checking the attempt would stamp this verdict onto whatever attempt
        // is current by then.
        if (_disposed) {
          return const AdditionResult(applied: false, error: 'conflict');
        }
        if (_isCurrentAttempt(gen, attempt)) {
          state = state.copyWith(
            phase: AdditionPhase.failed,
            lastError: 'conflict',
            dispatched: true,
          );
        }
        return const AdditionResult(applied: false, error: 'conflict');

      case AdditionOutcomeKind.refused:
        await _journalPhase(
          attempt.localOperationId,
          PosAdditionJournalPhase.rejected,
          errorCode: outcome.reason,
        );
        // A definitive business rejection RESOLVES the uncertainty: the server
        // refused, so no round exists under this identity and the cashier may
        // abandon it.
        //
        // THE MOST DANGEROUS WRITE IN THIS CLASS is `dispatched: false` — it is
        // what re-opens `canCancel` and lets `exit()` release an identity. It is
        // therefore fenced on the attempt AND on disposal, not left to an
        // invariant enforced elsewhere by accident.
        if (_disposed) {
          return AdditionResult(applied: false, error: outcome.reason);
        }
        if (_isCurrentAttempt(gen, attempt)) {
          state = state.copyWith(
            phase: AdditionPhase.failed,
            lastError: outcome.reason,
            dispatched: false,
          );
        }
        return AdditionResult(applied: false, error: outcome.reason);

      case AdditionOutcomeKind.applied:
        break; // handled below
    }

    // APPLIED (Finding 4), and COMPLETE. The server owns the addition from this
    // moment: the operation may never be dispatched again, and the frozen
    // identity stays known until the authoritative refresh PROVES the new state.
    final roundId = outcome.roundId!;
    final roundNumber = outcome.roundNumber!;
    // DEFERRED-ORDER-AMENDMENTS-001: assemble the kitchen ADDITION ticket payload
    // NOW — the frozen delta, the parent's own identity/type/table from the
    // installed authoritative target, and the round the server just named. Built
    // BEFORE the reconciliation below, which clears the cart on success. Both
    // round fields are guaranteed present by the classifier, which is exactly
    // why an incomplete applied result can no longer reach this point.
    final printPayload = AdditionPrintPayload(
      orderId: attempt.orderId,
      orderCode: target.orderCode,
      orderTypeWire: target.orderType ?? '',
      roundId: roundId,
      roundNumber: roundNumber,
      lines: attempt.lines,
      prepByItemId: attempt.prepByItemId,
      tableLabel: target.tableLabel,
      customerName: target.customerName,
      customerPhone: target.customerPhone,
    );
    // APPLIED — but NOT closed. The journal records the round identity and stays
    // open until the authoritative refresh proves the new state; closing here
    // would discard the only evidence that could reconcile a crash in the next
    // few milliseconds. A replayed result (`idempotency_replay: true`) lands
    // here identically and by design: the server is telling us the round it
    // already built, which is exactly what recovery needs.
    await _journalPhase(
      attempt.localOperationId,
      PosAdditionJournalPhase.awaitingAuthoritativeRefresh,
      roundId: roundId,
      roundNumber: roundNumber,
    );
    state = state.copyWith(
      phase: AdditionPhase.appliedAwaitingRefresh,
      appliedRoundId: roundId,
      clearError: true,
    );
    final reconciled = await _reconcileApplied(gen, attempt, roundId);
    return AdditionResult(
      applied: true,
      roundNumber: roundNumber,
      refreshRequired: !reconciled,
      printPayload: printPayload,
    );
  }

  /// Retries ONLY the authoritative refresh of an applied-awaiting-refresh
  /// attempt (Finding 4). Never dispatches `order.items_add`. Returns whether
  /// the reconciliation completed.
  Future<bool> retryRefresh() async {
    final s = state;
    final attempt = s.attempt;
    if (s.phase != AdditionPhase.appliedAwaitingRefresh || attempt == null) {
      return false;
    }
    return _reconcileApplied(s.generation, attempt, s.appliedRoundId);
  }

  /// The post-apply reconciliation: the targeted branch-snapshot refresh
  /// (side channel — the poll converges regardless) and the authoritative
  /// detail reload that must PROVE the addition (right parent order and, when
  /// the server named one, the applied round) before cleanup runs EXACTLY
  /// once: install the fresh authoritative detail, then clear the submitted
  /// cart state + release the mutation lock with the MATCHING owner token
  /// (the privileged [CartController.clearForAddition]), drop the attempt,
  /// leave addition mode. Every path is double-fenced (Finding 2 +
  /// cart-safety): the state fence (generation + attempt identity + phase)
  /// AND the cart's own owner-token check — a stale attempt-A callback can
  /// never clear or unlock a cart owned by attempt B.
  Future<bool> _reconcileApplied(
    int gen,
    AdditionAttempt attempt,
    String? roundId,
  ) async {
    try {
      await ref.read(posOrderSyncControllerProvider.notifier).refreshOrders([
        attempt.orderId,
      ]);
    } catch (_) {}
    PosOrderDetail? fresh;
    try {
      fresh = await ref
          .read(orderDetailRepositoryProvider)
          .fetch(attempt.orderId);
    } catch (_) {
      fresh = null;
    }
    if (state.generation != gen ||
        state.phase != AdditionPhase.appliedAwaitingRefresh ||
        state.attempt?.localOperationId != attempt.localOperationId) {
      return false; // stale — zero side effects
    }
    final verified =
        fresh != null &&
        fresh.orderId == attempt.orderId &&
        (roundId == null || fresh.rounds.any((r) => r.roundId == roundId));
    if (!verified) {
      // The mutation is saved server-side; the view is NOT refreshed. Keep
      // the previous valid detail installed, keep the attempt known, surface
      // the honest "saved, refresh required" state — retry-refresh only.
      state = state.copyWith(lastError: 'refresh_required');
      return false;
    }
    // Final ownership fence (read-only, BEFORE any install): the cart must be
    // locked by EXACTLY this attempt's token. A stale or foreign owner — or
    // no lock at all — gets ZERO side effects: no fresh-detail install, no
    // clear, no unlock, no attempt change; the honest refresh-required state
    // remains. Only then: install the verified fresh detail and IMMEDIATELY
    // run the privileged owner-token clear+unlock — no await exists between
    // the ownership check, the install, and the clear.
    final cartController = ref.read(cartControllerProvider.notifier);
    final owner = _ownerOf(gen, attempt);
    if (!cartController.ownsAdditionLock(owner)) {
      state = state.copyWith(lastError: 'refresh_required');
      return false;
    }
    state = state.copyWith(target: fresh);

    // MONEY-CODEX-FINAL-CORRECTIONS-004 (F1): OWNING THE LOCK IS NOT THE SAME AS
    // OWNING THESE LINES. The token proves this attempt holds the cart; it does
    // not prove the cart still CONTAINS the payload that was frozen. Between a
    // restore and this moment the cashier may have typed lines the server never
    // saw, and `clearForAddition` is privileged — it would delete them.
    //
    // So the frozen lines are compared to the live ones by full per-line
    // identity before anything is destroyed. `lineId` alone is not enough
    // across a restart: `CartController` re-mints `line-0` in a fresh session,
    // so a coincidental id match must not authorise a wipe.
    if (_cartMatchesFrozen(attempt)) {
      if (!cartController.clearForAddition(owner)) {
        // Unreachable after the ownership check above (same synchronous block),
        // but kept fail-closed: the true owner keeps the cart and the attempt.
        state = state.copyWith(lastError: 'refresh_required');
        return false;
      }
    } else {
      // The round IS confirmed applied, so the OPERATION is settled and its
      // journal record must close — leaving it open would block Pay/Void on an
      // order the server has already amended. What must not happen is the
      // destruction of work the cashier entered afterwards, so the lines stay
      // and only the lock is released.
      cartController.unlockForAddition(owner);
    }
    // AUTHORITATIVE CONFIRMATION REACHED, and only now. `verified` above proved
    // the refreshed detail is the right parent AND carries the applied round, so
    // the operation is genuinely settled: the identity can never be needed again
    // and the record may go. The durable print claim is deliberately NOT touched
    // — it is keyed on the round, outlives the journal, and financial closure
    // must not depend on whether paper came out.
    await _journalClose(attempt.localOperationId);
    state = AdditionState(generation: gen + 1);
    // MONEY-CODEX-FINAL-CLOSURE-005 (F4): THE QUEUE ADVANCES. Closing this
    // record recomputed the pending index; the next safe one becomes the active
    // attempt and re-owns its cart. Without this a second order's amendment
    // stayed invisible for the rest of the session — its order silently
    // unblocked, its identity forgotten until the next restart.
    _activateNextSafeRecord();
    return true;
  }

  /// Whether the LIVE cart still holds exactly the lines this attempt froze.
  ///
  /// Compared field by field — id, item, quantity and every money value, the
  /// note, and each modifier's option id / delta / quantity — because a wipe is
  /// irreversible and a near-match is not a match. Any difference at all means
  /// the cashier's cart is not the frozen payload's cart.
  bool _cartMatchesFrozen(AdditionAttempt attempt) {
    final live = ref.read(cartControllerProvider).lines;
    final frozen = attempt.lines;
    if (live.length != frozen.length) return false;
    for (var i = 0; i < frozen.length; i++) {
      final a = frozen[i];
      final b = live[i];
      if (a.lineId != b.lineId ||
          a.menuItemId != b.menuItemId ||
          a.quantity != b.quantity ||
          a.unitPriceMinor != b.unitPriceMinor ||
          a.lineTotalMinor != b.lineTotalMinor ||
          a.currencyCode != b.currencyCode ||
          a.note != b.note ||
          a.modifiers.length != b.modifiers.length) {
        return false;
      }
      for (var m = 0; m < a.modifiers.length; m++) {
        final x = a.modifiers[m];
        final y = b.modifiers[m];
        if (x.optionId != y.optionId ||
            x.priceDeltaMinor != y.priceDeltaMinor ||
            x.quantity != y.quantity) {
          return false;
        }
      }
    }
    return true;
  }

  bool _isCurrentAttempt(int gen, AdditionAttempt attempt) =>
      state.generation == gen &&
      state.attempt?.localOperationId == attempt.localOperationId &&
      state.attempt?.orderId == attempt.orderId;

  /// The live menu's `menuItemId -> prepComponents` snapshot (D-008), read ONCE
  /// per frozen attempt. Empty for unconfigured items.
  Map<String, List<KitchenPrepComponent>> _prepSnapshot() {
    final menuData = ref.read(posMenuProvider).valueOrNull;
    return <String, List<KitchenPrepComponent>>{
      if (menuData != null)
        for (final item in menuData.items)
          if (item.prepComponents.isNotEmpty) item.id: item.prepComponents,
    };
  }

  /// The SAME order-time item snapshots the submit path sends (D-008), built
  /// with the SAME mapping — including the menu's per-unit prep components —
  /// serialized ONCE into the frozen attempt.
  List<Map<String, Object?>> _serializeLines(
    List<CartLineView> lines,
    Map<String, List<KitchenPrepComponent>> prepByItemId,
  ) {
    return [
      for (final l in lines)
        // 020 (Codex BLOCKER #1): the complete, immutable set of option ids
        // selected on THIS Add-items line, computed once and shared by every
        // modifier snapshot below.
        for (final lineSelectedOptionIds in [selectedOptionIdsOf(l.modifiers)])
          OrderSubmissionItem(
            menuItemId: l.menuItemId,
            nameSnapshot: l.name,
            quantity: l.quantity,
            unitPriceMinorSnapshot: l.unitPriceMinor,
            lineTotalMinor: l.lineTotalMinor,
            notes: l.note,
            // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: an Add-items round resolves
            // its classification exactly like the initial submission, so a round
            // ticket splits its own new items correctly.
            prepComponents: classifiedPrepForLine(
              prepByItemId[l.menuItemId] ?? const <KitchenPrepComponent>[],
              l.modifiers,
            ),
            modifiers: [
              for (final m in l.modifiers)
                OrderSubmissionModifier(
                  modifierOptionId: m.optionId,
                  optionNameSnapshot: m.optionName,
                  modifierNameSnapshot: m.groupName,
                  priceMinorSnapshot: m.priceDeltaMinor,
                  quantity: m.quantity,
                  // 020 (Codex BLOCKER #1): the AUTHORITATIVE order-time snapshot
                  // — the per-unit quantity/unit plus classifier_selected derived
                  // from THIS line's complete selection — stored in the actual
                  // Addition operation payload, exactly as the initial submit
                  // does. Never raw menu config, never re-derived from modifier
                  // text, and never re-read from the live menu after the
                  // operation is accepted. The option's own units stay in the
                  // adjacent quantity field and are applied downstream once.
                  meatSnapshot: resolveOrderTimeMeatSnapshot(
                    m.kitchenMeat,
                    lineSelectedOptionIds,
                  ),
                ),
            ],
          ).toJson(),
    ];
  }

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F2) — the ONE response classification.
  ///
  /// Only TWO things are definitive: a COMPLETE authoritative applied result,
  /// and an ALLOWLISTED business refusal for this exact operation. Everything
  /// else is outcome-unknown, and outcome-unknown on an operation that reached
  /// the wire means the identity and its frozen payload are retained.
  ///
  /// WHAT WAS WRONG. `_appliedResult` accepted any row with
  /// `status == 'applied' && ok == true` and the caller then read `round_id` /
  /// `round_number` defensively (`is String ? ... : null`). An applied row with
  /// a missing, null or blank round therefore still moved the flow to
  /// APPLIED-AWAITING-REFRESH with `roundId == null`, and
  /// `_reconcileApplied`'s verification degenerates to
  /// `roundId == null || fresh.rounds.any(...)` — it verified NOTHING, cleared
  /// the cart and closed the journal on a response that never named a round.
  /// And `_definitiveRefusal` accepted ANY non-blank error string, so an error
  /// code this build has never seen became a terminal verdict: the identity is
  /// released and the next send mints a NEW one for an operation the server may
  /// already have applied.
  ///
  /// THE APPLIED CONTRACT is read from the server, not guessed.
  /// `app.add_order_items` returns
  /// `{ok, order_id, round_id, round_number, added_item_count, revision,
  /// server_ts, idempotency_replay}` and `public.sync_push` merges
  /// `{local_operation_id, operation_type, status:'applied',
  /// idempotency_replay}` onto it. Required here: the matching operation
  /// identity, the matching operation TYPE, the exact `applied` status, `ok`
  /// exactly boolean true, `order_id` equal to the attempt's target, a non-blank
  /// String `round_id` and an int `round_number`.
  ///
  /// `added_item_count` and `revision` are deliberately NOT required. Nothing in
  /// the reconciliation path reads them, and demanding a field we do not use
  /// would turn harmless shape drift into a permanently stuck operation.
  static AdditionOutcome classifyAdditionResponse(
    Object? raw, {
    required String localOperationId,
    required String orderId,
  }) {
    // ONE try/catch around the WHOLE boundary. The rows come from a network
    // decode, so a member access can raise TypeError or a cast failure, not just
    // FormatException — and an exception escaping here would propagate out of
    // the submit path, past the journal write, to an uncaught async error.
    try {
      if (raw is! Map)
        return const AdditionOutcome.unknown('malformed_envelope');
      final results = raw['results'];
      if (results is! List)
        return const AdditionOutcome.unknown('missing_results');
      for (final r in results) {
        if (r is! Map) continue;
        if (r['local_operation_id'] != localOperationId) continue;

        // OUR row. From here the response says something about this operation —
        // but only a complete, well-formed statement counts.
        // The row must positively identify itself as OUR operation type. A
        // missing type used to be skipped; today no row can reach here without
        // one (`sync_push` stamps it on every row that carries a
        // local_operation_id), so failing closed costs nothing and removes a
        // guarantee that currently rests on an external invariant.
        if (r['operation_type'] != kAdditionOperationType) {
          return const AdditionOutcome.unknown('operation_type_mismatch');
        }
        final status = r['status'];

        if (status == 'applied') {
          if (r['ok'] != true) {
            return const AdditionOutcome.unknown('applied_not_ok');
          }
          final resultOrderId = r['order_id'];
          if (resultOrderId is! String || resultOrderId != orderId) {
            // An applied row for ANOTHER order proves nothing about ours.
            return const AdditionOutcome.unknown('target_order_mismatch');
          }
          final roundIdRaw = r['round_id'];
          final roundId = roundIdRaw is String ? roundIdRaw.trim() : '';
          if (roundId.isEmpty) {
            // No round identity => nothing to verify against the authoritative
            // detail, nothing to key the exactly-once kitchen print on, and no
            // proof the round exists at all.
            return const AdditionOutcome.unknown('applied_without_round_id');
          }
          final roundNumberRaw = r['round_number'];
          if (roundNumberRaw is! int) {
            return const AdditionOutcome.unknown(
              'applied_without_round_number',
            );
          }
          return AdditionOutcome.applied(
            roundId: roundId,
            roundNumber: roundNumberRaw,
          );
        }

        if (status == 'dead') {
          // SELF-REVIEW CORRECTION: `dead` was routed through the refusal
          // allowlist, which contradicts this repository's own contract for the
          // same ledger column — `order_submission.dart`: "`dead` entries stay
          // retryable: no server verdict was positively recorded". `dead` means
          // retry exhaustion, which is the definition of outcome-unknown, and
          // treating it as a refusal frees the identity so the next send builds
          // a SECOND round. (No migration currently writes it; it exists in the
          // CHECK constraint and the terminal-replay lists. It was wrong in the
          // unsafe direction regardless.)
          return const AdditionOutcome.unknown('dead_no_server_verdict');
        }
        if (status == 'rejected' || status == 'conflict') {
          final error = r['error'];
          if (error is! String) {
            return const AdditionOutcome.unknown('refusal_without_code');
          }
          final code = error.trim();
          if (code.isEmpty) {
            return const AdditionOutcome.unknown('refusal_without_code');
          }
          if (code == 'conflict' || status == 'conflict') {
            // The identity already exists server-side under a DIFFERENT payload
            // fingerprint. Never a second round, never resolvable by retrying.
            return const AdditionOutcome.conflict();
          }
          if (!kAdditionTerminalRefusalCodes.contains(code)) {
            // A code this build has never seen. It may be terminal, it may not;
            // treating it as terminal releases an identity the server may own.
            return const AdditionOutcome.unknown('unknown_refusal_code');
          }
          return AdditionOutcome.refused(code);
        }

        // A pending/in-flight/unknown status token: the operation's fate is not
        // settled by this response.
        return const AdditionOutcome.unknown('unknown_status');
      }
      // Our operation is not in this response at all.
      return const AdditionOutcome.unknown('operation_absent');
    } catch (_) {
      // FormatException, TypeError, StateError, a cast failure, a missing field
      // on a hostile shape — all of it is simply "we could not read the answer".
      return const AdditionOutcome.unknown('unreadable_response');
    }
  }
}

/// MONEY-DURABLE-ADDITIONS-003C: the durable amendment journal. Null by default
/// => in-memory only (demo mode / tests / the pre-003C behaviour); `main.dart`
/// overrides it for the real app.
final additionJournalStoreProvider = Provider<PosAdditionJournalStore?>(
  (_) => null,
);

final additionControllerProvider =
    NotifierProvider<AdditionController, AdditionState>(AdditionController.new);

/// Finding 1/2 — the PURE entry-guard decision (testable, one place): may the
/// cashier begin adding to [orderId] right now? Re-entering the CURRENT
/// reservation/target is always harmless; otherwise entry needs no open
/// attempt, no other reservation, and an EMPTY normal cart (a non-empty cart
/// is never silently retargeted into an addition). The UI uses this as an
/// early convenience check; [AdditionController.enterForOrder] independently
/// re-enforces every rule and is the actual guarantee.
bool canBeginAddition({
  required AdditionState addition,
  required bool cartIsEmpty,
  required String orderId,
}) {
  final current = addition.entryOrderId ?? addition.target?.orderId;
  if (current == orderId) return true;
  if (addition.hasOpenAttempt || current != null) return false;
  return cartIsEmpty;
}
