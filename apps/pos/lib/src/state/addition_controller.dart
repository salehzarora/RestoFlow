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
/// HONESTY RULES (locked):
///  * a failed addition stays LOCAL and RETRYABLE — the cart keeps the pending
///    lines and the SAME local_operation_id is reused on retry, so the server's
///    idempotency can never mint a duplicate round;
///  * the cart clears ONLY after the server applied the addition;
///  * success triggers the targeted authoritative snapshot refresh AND a fresh
///    [PosOrderDetail] load, so payment totals and the combined receipt come
///    from the SERVER, not from a local merge.
class AdditionState {
  const AdditionState({
    this.target,
    this.sending = false,
    this.failed = false,
    this.lastError,
  });

  /// The order being extended (null = the cart is an ordinary new-order draft).
  final PosOrderDetail? target;

  final bool sending;

  /// The last attempt failed (typed rejection or transport) — the pending
  /// addition is intact and retryable.
  final bool failed;
  final String? lastError;

  bool get active => target != null;

  AdditionState copyWith({
    PosOrderDetail? target,
    bool clearTarget = false,
    bool? sending,
    bool? failed,
    String? lastError,
    bool clearError = false,
  }) => AdditionState(
    target: clearTarget ? null : (target ?? this.target),
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

class AdditionController extends Notifier<AdditionState> {
  /// The SAME local operation id is reused across retries of one pending
  /// addition (D-022): an exact replay returns the SAME round server-side.
  String? _pendingOperationId;
  Future<AdditionResult>? _inFlight;

  @override
  AdditionState build() => const AdditionState();

  /// Enters addition mode for [detail] (the authoritative existing order).
  void enter(PosOrderDetail detail) {
    _pendingOperationId = null;
    state = AdditionState(target: detail);
  }

  /// Leaves addition mode. The cart's pending lines are the caller's to keep
  /// or clear — cancelling an addition must never silently discard work.
  void exit() {
    _pendingOperationId = null;
    state = const AdditionState();
  }

  /// Submits the cart's [lines] as ONE new service round for the target.
  /// Single-flight; duplicate taps while sending await the same attempt.
  Future<AdditionResult> submit(List<CartLineView> lines) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final attempt = _submit(lines);
    _inFlight = attempt;
    return attempt.whenComplete(() => _inFlight = null);
  }

  Future<AdditionResult> _submit(List<CartLineView> lines) async {
    final target = state.target;
    if (target == null || lines.isEmpty) {
      return const AdditionResult(applied: false, error: 'nothing_to_add');
    }
    final cfg = ref.read(runtimeConfigProvider);
    final transport = ref.read(posAuthTransportProvider);
    final session = ref.read(posSyncSessionProvider);
    if (cfg.isDemoMode || transport == null || session == null) {
      state = state.copyWith(failed: true, lastError: 'no_session');
      return const AdditionResult(applied: false, error: 'no_session');
    }

    // The pending addition's ONE operation id (kept across retries).
    final localOperationId = _pendingOperationId ??= ref
        .read(clientIdGeneratorProvider)
        .newId();

    // The SAME order-time item snapshots the submit path sends (D-008), built
    // with the SAME mapping — including the menu's per-unit prep components.
    final menuData = ref.read(posMenuProvider).valueOrNull;
    final prepByItemId = <String, List<KitchenPrepComponent>>{
      if (menuData != null)
        for (final item in menuData.items)
          if (item.prepComponents.isNotEmpty) item.id: item.prepComponents,
    };
    final items = [
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
        ),
    ];

    state = state.copyWith(sending: true, failed: false, clearError: true);
    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[
          <String, dynamic>{
            'local_operation_id': localOperationId,
            'operation_type': 'order.items_add',
            'target_entity': 'order',
            'target_id': target.orderId,
            'client_created_at': DateTime.now().toIso8601String(),
            'payload': <String, dynamic>{
              'order_id': target.orderId,
              'order_items': [for (final i in items) i.toJson()],
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

    final result = _appliedResult(raw, localOperationId);
    if (result == null) {
      // Typed rejection / malformed envelope: the pending addition stays local
      // and retryable — nothing merged, nothing cleared, no fake success.
      final error = _errorOf(raw, localOperationId) ?? 'rejected';
      state = state.copyWith(sending: false, failed: true, lastError: error);
      return AdditionResult(applied: false, error: error);
    }

    // APPLIED. The addition is server truth now: clear the pending lines, drop
    // the retry id, and reload the AUTHORITATIVE state (targeted snapshot for
    // every till + the combined detail for this one). Refresh failures are
    // tolerated — the regular poll converges; the local cart is still cleared
    // because the server HAS the addition (keeping the lines would double it).
    _pendingOperationId = null;
    ref.read(cartControllerProvider.notifier).clear();
    final roundNumber = result['round_number'];
    try {
      await ref.read(posOrderSyncControllerProvider.notifier).refreshOrders([
        target.orderId,
      ]);
    } catch (_) {}
    PosOrderDetail? fresh;
    try {
      fresh = await ref
          .read(orderDetailRepositoryProvider)
          .fetch(target.orderId);
    } catch (_) {}
    state = AdditionState(target: fresh ?? state.target);
    return AdditionResult(
      applied: true,
      roundNumber: roundNumber is int ? roundNumber : null,
    );
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
