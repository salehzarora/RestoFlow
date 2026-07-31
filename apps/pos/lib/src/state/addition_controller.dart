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
}

class AdditionController extends Notifier<AdditionState> {
  Future<AdditionResult>? _inFlight;

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
    _restoreJournal();
    return const AdditionState();
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
    _pending = List.unmodifiable(
      _pending.where((r) => r.localOperationId != localOperationId),
    );
    final journal = _journal;
    if (journal == null) return;
    final scope = _journalScope;
    if (scope.isEmpty) return;
    try {
      final existing = await journal.load(scope);
      if (!existing.containsKey(localOperationId)) return;
      await journal.persist(scope, <String, PosAdditionJournalRecord>{
        for (final e in existing.entries)
          if (e.key != localOperationId) e.key: e.value,
      });
    } catch (_) {
      // The record survives; reconciliation is idempotent and will close it.
    }
  }

  /// Rehydrates the oldest unresolved amendment, RE-OWNS ITS CART, and
  /// re-installs its target.
  ///
  /// MONEY-CODEX-FINAL-CORRECTIONS-004 (F1). The previous build deliberately did
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
  /// The lock is therefore re-acquired here, synchronously, under the SAME
  /// `CartLockOwner` the attempt was frozen with — which is exactly why the
  /// record persists its `generation`.
  Future<void> _restoreJournal() async {
    final journal = _journal;
    if (journal == null) return;
    final scope = _journalScope;
    if (scope.isEmpty) return;
    Map<String, PosAdditionJournalRecord> records;
    try {
      records = await journal.load(scope);
    } catch (_) {
      return;
    }
    // MONEY-CODEX-FINAL-CORRECTIONS-004 (F4): EVERY record that still needs
    // attention is retained, not just the one being worked. The previous build
    // took `unresolved.first` and dropped the rest on the floor — a second
    // pending amendment, and every `conflict`, simply vanished on restart while
    // its order silently unblocked.
    //
    // `needsAttention` also covers `conflict`, which `isUnresolved` excludes
    // because the server HAS answered; it is nonetheless the one state that can
    // never resolve itself.
    final actionable =
        records.values
            .where((r) => r.needsAttention && r.wasDispatched)
            .toList()
          ..sort((a, b) => a.clientCreatedAt.compareTo(b.clientCreatedAt));
    if (actionable.isEmpty) return;
    _pending = List.unmodifiable(actionable);
    final record = actionable.first;
    // Never clobber work started in this session.
    if (state.attempt != null || state.entryOrderId != null) return;

    final attempt = AdditionAttempt(
      orderId: record.orderId,
      localOperationId: record.localOperationId,
      itemsJson: record.itemsJson,
      clientCreatedAt: record.clientCreatedAt,
      lines: record.lines,
      prepByItemId: record.prepByItemId,
    );
    // The record only survives in a dispatched phase, so the restored identity
    // is by definition one the server may already own.
    state = AdditionState(
      dispatched: true,
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

    // RE-OWN THE CART (F1), synchronously and before any await, so there is no
    // window in which the restored attempt exists but its cart is editable.
    // Idempotent: `lockForAddition` re-asserts a matching token and only refuses
    // a FOREIGN one, in which case the attempt stays visible and unresolved
    // rather than silently taking someone else's cart.
    ref
        .read(cartControllerProvider.notifier)
        .lockForAddition(_ownerOf(record.generation, attempt));

    // Re-install the authoritative parent so the resumed submit/refresh has the
    // same target it had before. A failure here leaves the attempt visible and
    // unresolved rather than silently dropping it.
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

  List<PosAdditionJournalRecord> get pendingAmendments => _pending;

  /// Orders currently blocked by an amendment awaiting resolution.
  Set<String> get blockedOrderIds => <String>{
    if (state.attempt?.orderId case final id?) id,
    for (final r in _pending) r.orderId,
  };

  /// How many blocked records are CONFLICTS — the ones a person must settle.
  int get conflictCount => _pending.where((r) => r.isConflict).length;

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
    if (attempt != null) unawaited(_journalClose(attempt.localOperationId));
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

    final result = _appliedResult(raw, attempt.localOperationId);
    if (result == null) {
      // MONEY-CODEX-FINAL-CORRECTIONS-004 (F2). Only a response that names a
      // REJECTING STATUS for OUR operation, with a real error code, is a
      // verdict. Everything else — a malformed envelope, a non-list `results`,
      // a response that never mentions this operation, an `applied` row whose
      // `ok` is not true, an unknown status — leaves the outcome UNKNOWN on an
      // operation that already reached the wire.
      final refusal = _definitiveRefusal(raw, attempt.localOperationId);
      if (refusal == null) {
        // AMBIGUOUS. Treated exactly like a dead transport, because that is
        // what it is: we do not know whether the server built the round. The
        // identity and the frozen payload are retained, the cart stays owned,
        // `exit()` cannot release it, and the next attempt REPLAYS this
        // operation rather than minting a second one.
        await _journalPhase(
          attempt.localOperationId,
          PosAdditionJournalPhase.transportUncertain,
          errorCode: 'unknown_response',
        );
        if (_isCurrentAttempt(gen, attempt)) {
          state = state.copyWith(
            phase: AdditionPhase.failed,
            lastError: 'unknown_response',
            dispatched: true,
          );
        }
        return const AdditionResult(applied: false, error: 'unknown_response');
      }
      // A `conflict` means this identity already exists server-side under a
      // DIFFERENT payload fingerprint. It can never be resolved by retrying and
      // it can never produce a second round — it needs a person. Everything
      // else is a permanent business rejection: terminal, no retry, no print.
      await _journalPhase(
        attempt.localOperationId,
        refusal == 'conflict'
            ? PosAdditionJournalPhase.conflict
            : PosAdditionJournalPhase.rejected,
        errorCode: refusal,
      );
      // A definitive business rejection RESOLVES the uncertainty: the server
      // refused, so no round exists under this identity and the cashier may
      // abandon it. A `conflict` is NOT definitive — the identity is already in
      // use server-side and only a person can untangle it — so it stays locked.
      state = state.copyWith(
        phase: AdditionPhase.failed,
        lastError: refusal,
        dispatched: refusal == 'conflict',
      );
      return AdditionResult(applied: false, error: refusal);
    }

    // APPLIED (Finding 4). The server owns the addition from this moment:
    // the operation may never be dispatched again, and the frozen identity
    // stays known until the authoritative refresh PROVES the new state.
    final roundNumberRaw = result['round_number'];
    final roundNumber = roundNumberRaw is int ? roundNumberRaw : null;
    final roundIdRaw = result['round_id'];
    final roundId = roundIdRaw is String ? roundIdRaw : null;
    // DEFERRED-ORDER-AMENDMENTS-001: assemble the kitchen ADDITION ticket payload
    // NOW — the frozen delta, the parent's own identity/type/table from the
    // installed authoritative target, and the round the server just named. Built
    // BEFORE the reconciliation below, which clears the cart on success. Requires
    // BOTH round fields: without them there is no round-scoped exactly-once
    // identity, so nothing is printed rather than printing on a guess.
    final printPayload = (roundId != null && roundNumber != null)
        ? AdditionPrintPayload(
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
          )
        : null;
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
        OrderSubmissionItem(
          menuItemId: l.menuItemId,
          nameSnapshot: l.name,
          quantity: l.quantity,
          unitPriceMinorSnapshot: l.unitPriceMinor,
          lineTotalMinor: l.lineTotalMinor,
          notes: l.note,
          prepComponents:
              prepByItemId[l.menuItemId] ?? const <KitchenPrepComponent>[],
          modifiers: [
            for (final m in l.modifiers)
              OrderSubmissionModifier(
                modifierOptionId: m.optionId,
                optionNameSnapshot: m.optionName,
                modifierNameSnapshot: m.groupName,
                priceMinorSnapshot: m.priceDeltaMinor,
                quantity: m.quantity,
                meatSnapshot: m.kitchenMeat,
              ),
          ],
        ).toJson(),
    ];
  }

  /// STRICT fail-closed per-op success parse (the PSC-001D F4 rule): success
  /// requires the MATCHING op with `status == 'applied'` AND `ok == true`.
  static Map<String, dynamic>? _appliedResult(Object? raw, String localOp) {
    if (raw is! Map) return null;
    final results = raw['results'];
    if (results is! List) return null;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOp) {
        if (r['status'] == 'applied' && r['ok'] == true) {
          return r.cast<String, dynamic>();
        }
        return null;
      }
    }
    return null;
  }

  /// MONEY-CODEX-FINAL-CORRECTIONS-004 (F2): the server's DEFINITIVE refusal of
  /// THIS operation, or null when the response proves nothing about it.
  ///
  /// This is the discriminator the previous build lacked. `_appliedResult`
  /// returns null for four structurally different reasons and only one of them
  /// is a verdict: a malformed envelope, a `results` value that is not a list, a
  /// response that never mentions our `local_operation_id`, and a matched op
  /// whose `ok` is not `true` all landed on `?? 'rejected'` — terminal, identity
  /// released, and the next send minting a NEW id for an operation the server
  /// may already have applied. That is the duplicate round this whole program
  /// exists to prevent.
  ///
  /// A refusal counts only when the server named a REJECTING STATUS for OUR
  /// operation AND gave a non-blank error code. Anything else is unknown.
  static String? _definitiveRefusal(Object? raw, String localOp) {
    if (raw is! Map) return null;
    final results = raw['results'];
    if (results is! List) return null;
    for (final r in results) {
      if (r is! Map || r['local_operation_id'] != localOp) continue;
      final status = r['status'];
      if (status != 'rejected' && status != 'conflict' && status != 'dead') {
        // `applied` with a non-true `ok`, a pending/in-flight status, or an
        // unknown token: the operation's fate is not settled by this response.
        return null;
      }
      final error = r['error'];
      if (error is! String || error.trim().isEmpty) {
        // A rejecting status with no code names no reason we can act on.
        return null;
      }
      return error;
    }
    return null; // our operation is not in this response at all
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
