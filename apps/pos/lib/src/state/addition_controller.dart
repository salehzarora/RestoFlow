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
/// HONESTY RULES (locked + Finding-2 correction):
///  * the FIRST submit FREEZES one immutable [AdditionAttempt] — parent order
///    id, the canonical serialized item payload, the local_operation_id and
///    the client timestamp. Every retry reuses that exact snapshot: the
///    idempotency key can never be re-associated with a different target or a
///    mutated cart payload;
///  * while an attempt is pending or failed-retryable, the TARGET is
///    immutable — entry to a different order is refused; changing items or
///    target requires the explicit cancel (exit), and the NEXT submission
///    gets a NEW operation id;
///  * the cart clears ONLY after the server applied the addition;
///  * success triggers the targeted authoritative snapshot refresh AND a
///    fresh [PosOrderDetail] load, and only then is the attempt cleared.
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

class AdditionState {
  const AdditionState({
    this.target,
    this.attempt,
    this.sending = false,
    this.failed = false,
    this.lastError,
  });

  /// The order being extended (null = the cart is an ordinary new-order draft).
  final PosOrderDetail? target;

  /// The FROZEN in-progress attempt (pending or failed-retryable), if any.
  final AdditionAttempt? attempt;

  final bool sending;

  /// The last attempt failed (typed rejection or transport) — the frozen
  /// addition is intact and retryable.
  final bool failed;
  final String? lastError;

  bool get active => target != null;

  /// An attempt exists that has not been applied or explicitly cancelled.
  bool get hasOpenAttempt => attempt != null;

  AdditionState copyWith({
    PosOrderDetail? target,
    bool clearTarget = false,
    AdditionAttempt? attempt,
    bool clearAttempt = false,
    bool? sending,
    bool? failed,
    String? lastError,
    bool clearError = false,
  }) => AdditionState(
    target: clearTarget ? null : (target ?? this.target),
    attempt: clearAttempt ? null : (attempt ?? this.attempt),
    sending: sending ?? this.sending,
    failed: failed ?? this.failed,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

/// The applied result of one addition (for the confirmation toast).
class AdditionResult {
  const AdditionResult({required this.applied, this.roundNumber, this.error});
  final bool applied;
  final int? roundNumber;
  final String? error;
}

/// Why an [AdditionController.enter] call was or was not honoured.
enum AdditionEntryResult {
  /// Addition mode is active for the requested order.
  entered,

  /// A frozen attempt is pending/retryable — the target is immutable until
  /// it is applied or explicitly cancelled.
  blockedPendingAttempt,

  /// A DIFFERENT order is already targeted — cancel it first.
  blockedDifferentTarget,
}

class AdditionController extends Notifier<AdditionState> {
  Future<AdditionResult>? _inFlight;

  @override
  AdditionState build() => const AdditionState();

  /// Enters addition mode for [detail] (the authoritative existing order).
  ///
  /// Finding-2 rules: entering the SAME target again is a harmless no-op
  /// (refreshing the shown detail when no attempt is frozen); entering while
  /// an attempt is open, or while a DIFFERENT order is targeted, is REFUSED —
  /// a non-empty cart / pending attempt is never silently retargeted. The
  /// cart-emptiness gate for a NORMAL (non-addition) cart lives at the call
  /// site, which owns the cart.
  AdditionEntryResult enter(PosOrderDetail detail) {
    final current = state.target;
    if (current != null && current.orderId == detail.orderId) {
      if (state.attempt == null) {
        // Same target, nothing frozen: refresh the authoritative view.
        state = state.copyWith(target: detail);
      }
      return AdditionEntryResult.entered;
    }
    if (state.attempt != null) {
      return AdditionEntryResult.blockedPendingAttempt;
    }
    if (current != null) {
      return AdditionEntryResult.blockedDifferentTarget;
    }
    state = AdditionState(target: detail);
    return AdditionEntryResult.entered;
  }

  /// Leaves addition mode, EXPLICITLY discarding any frozen attempt — the
  /// next submission gets a NEW operation id and a fresh payload. The cart's
  /// pending lines are the caller's to keep or clear — cancelling an addition
  /// must never silently discard work.
  void exit() {
    state = const AdditionState();
  }

  /// Submits the pending addition. On the FIRST call the cart's [lines] are
  /// frozen into the immutable attempt; retries IGNORE [lines] and resend the
  /// frozen snapshot verbatim. Single-flight; duplicate taps await the same
  /// attempt.
  Future<AdditionResult> submit(List<CartLineView> lines) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final attempt = _submit(lines);
    _inFlight = attempt;
    return attempt.whenComplete(() => _inFlight = null);
  }

  Future<AdditionResult> _submit(List<CartLineView> lines) async {
    final target = state.target;
    if (target == null) {
      return const AdditionResult(applied: false, error: 'nothing_to_add');
    }
    final cfg = ref.read(runtimeConfigProvider);
    final transport = ref.read(posAuthTransportProvider);
    final session = ref.read(posSyncSessionProvider);
    if (cfg.isDemoMode || transport == null || session == null) {
      state = state.copyWith(failed: true, lastError: 'no_session');
      return const AdditionResult(applied: false, error: 'no_session');
    }

    // FREEZE ONCE (Finding 2): the first submit captures the canonical
    // payload + operation id + client timestamp; every retry reuses the
    // frozen snapshot and never re-reads the mutable cart.
    var attempt = state.attempt;
    if (attempt == null) {
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

    state = state.copyWith(
      attempt: attempt,
      sending: true,
      failed: false,
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
      state = state.copyWith(
        sending: false,
        failed: true,
        lastError: 'transport',
      );
      return const AdditionResult(applied: false, error: 'transport');
    }

    final result = _appliedResult(raw, attempt.localOperationId);
    if (result == null) {
      // Typed rejection / malformed envelope: the FROZEN attempt stays local
      // and retryable — nothing merged, nothing cleared, no fake success.
      final error = _errorOf(raw, attempt.localOperationId) ?? 'rejected';
      state = state.copyWith(sending: false, failed: true, lastError: error);
      return AdditionResult(applied: false, error: error);
    }

    // APPLIED. The addition is server truth now: clear the pending lines and
    // reload the AUTHORITATIVE state (targeted snapshot for every till + the
    // combined detail for this one); only then is the frozen attempt cleared.
    // Refresh failures are tolerated — the regular poll converges; the local
    // cart is still cleared because the server HAS the addition (keeping the
    // lines would double it).
    ref.read(cartControllerProvider.notifier).clear();
    final roundNumber = result['round_number'];
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
    } catch (_) {}
    state = AdditionState(target: fresh ?? state.target);
    return AdditionResult(
      applied: true,
      roundNumber: roundNumber is int ? roundNumber : null,
    );
  }

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

/// Finding 2 — the PURE entry-guard decision (testable, one place): may the
/// cashier begin adding to [orderId] right now? Re-entering the CURRENT
/// target is always harmless; otherwise entry needs no open attempt, no other
/// active target, and an EMPTY normal cart (a non-empty cart is never
/// silently retargeted into an addition).
bool canBeginAddition({
  required AdditionState addition,
  required bool cartIsEmpty,
  required String orderId,
}) {
  if (addition.target?.orderId == orderId) return true;
  if (addition.hasOpenAttempt || addition.active) return false;
  return cartIsEmpty;
}
