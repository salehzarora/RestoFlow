import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

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
  });

  /// The parent order this attempt is bound to — never retargetable.
  final String orderId;

  /// The idempotency identity (D-022) — one per attempt, reused on retries.
  final String localOperationId;

  /// The CANONICAL serialized `order_items` payload, frozen at first submit.
  /// Retries send exactly this — never a rebuild from the mutable cart.
  final List<Map<String, Object?>> itemsJson;

  final DateTime clientCreatedAt;
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
  bool get canCancel =>
      phase == AdditionPhase.entering ||
      phase == AdditionPhase.active ||
      phase == AdditionPhase.failed;

  AdditionState copyWith({
    PosOrderDetail? target,
    AdditionAttempt? attempt,
    String? appliedRoundId,
    AdditionPhase? phase,
    String? lastError,
    bool clearError = false,
  }) => AdditionState(
    generation: generation,
    entryOrderId: entryOrderId,
    target: target ?? this.target,
    attempt: attempt ?? this.attempt,
    appliedRoundId: appliedRoundId ?? this.appliedRoundId,
    phase: phase ?? this.phase,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

/// The applied result of one addition (for the confirmation toast).
class AdditionResult {
  const AdditionResult({
    required this.applied,
    this.roundNumber,
    this.error,
    this.refreshRequired = false,
  });
  final bool applied;
  final int? roundNumber;
  final String? error;

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
  AdditionState build() => const AdditionState();

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
    if (attempt != null &&
        !ref
            .read(cartControllerProvider.notifier)
            .unlockForAddition(_ownerOf(s.generation, attempt))) {
      return false;
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
      attempt = AdditionAttempt(
        orderId: target.orderId,
        localOperationId: ref.read(clientIdGeneratorProvider).newId(),
        itemsJson: _serializeLines(lines),
        clientCreatedAt: DateTime.now(),
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
      // Typed rejection / malformed envelope: the FROZEN attempt stays local
      // and retryable — nothing merged, nothing cleared, no fake success.
      final error = _errorOf(raw, attempt.localOperationId) ?? 'rejected';
      state = state.copyWith(phase: AdditionPhase.failed, lastError: error);
      return AdditionResult(applied: false, error: error);
    }

    // APPLIED (Finding 4). The server owns the addition from this moment:
    // the operation may never be dispatched again, and the frozen identity
    // stays known until the authoritative refresh PROVES the new state.
    final roundNumber = result['round_number'];
    final roundIdRaw = result['round_id'];
    final roundId = roundIdRaw is String ? roundIdRaw : null;
    state = state.copyWith(
      phase: AdditionPhase.appliedAwaitingRefresh,
      appliedRoundId: roundId,
      clearError: true,
    );
    final reconciled = await _reconcileApplied(gen, attempt, roundId);
    return AdditionResult(
      applied: true,
      roundNumber: roundNumber is int ? roundNumber : null,
      refreshRequired: !reconciled,
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
    // Install the VERIFIED fresh detail first, then the privileged
    // owner-token clear+unlock. Fail closed: a refused clear (token owned by
    // someone else — the cannot-happen double-fence disagreement) leaves the
    // cart, the lock and the attempt for the true owner.
    state = state.copyWith(target: fresh);
    if (!ref
        .read(cartControllerProvider.notifier)
        .clearForAddition(_ownerOf(gen, attempt))) {
      state = state.copyWith(lastError: 'refresh_required');
      return false;
    }
    state = AdditionState(generation: gen + 1);
    return true;
  }

  bool _isCurrentAttempt(int gen, AdditionAttempt attempt) =>
      state.generation == gen &&
      state.attempt?.localOperationId == attempt.localOperationId &&
      state.attempt?.orderId == attempt.orderId;

  /// The SAME order-time item snapshots the submit path sends (D-008), built
  /// with the SAME mapping — including the menu's per-unit prep components —
  /// serialized ONCE into the frozen attempt.
  List<Map<String, Object?>> _serializeLines(List<CartLineView> lines) {
    final menuData = ref.read(posMenuProvider).valueOrNull;
    final prepByItemId = <String, List<KitchenPrepComponent>>{
      if (menuData != null)
        for (final item in menuData.items)
          if (item.prepComponents.isNotEmpty) item.id: item.prepComponents,
    };
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

  static String? _errorOf(Object? raw, String localOp) {
    if (raw is! Map) return null;
    final results = raw['results'];
    if (results is! List) return null;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOp) {
        final error = r['error'];
        return error is String ? error : null;
      }
    }
    return null;
  }
}

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
