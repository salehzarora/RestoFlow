import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ids.dart' show clientIdGeneratorProvider;
import '../data/kitchen_finish_repository.dart';
import 'kitchen_finish_controller.dart' show kitchenFinishRepositoryProvider;
import 'order_sync_controller.dart';

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B) — the printer-only SINGLE-order
/// COMPLETE safety net. The state is the set of order ids with an in-flight
/// completion, so the UI can disable the button while running and a double-click
/// enqueues EXACTLY ONE `order.status` op (never two). On completion it refreshes
/// the authoritative order state so the now-`completed` order leaves the active
/// board and its table frees through derived occupancy — never a local status
/// guess. It records no payment, resubmits nothing, and prints nothing.
class PosOrderCompleteController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  /// Whether a completion is currently in flight for [orderId].
  bool isCompleting(String? orderId) =>
      orderId != null && state.contains(orderId);

  /// Completes [orderId]. A concurrent call for the SAME order (a double-click) is
  /// a no-op — exactly one op is dispatched. Returns the finish result, or null if
  /// the call was suppressed (empty id / already in flight).
  Future<KitchenFinishResult?> complete(String orderId) async {
    if (orderId.trim().isEmpty || state.contains(orderId)) return null;
    state = <String>{...state, orderId};
    try {
      final localOp = ref.read(clientIdGeneratorProvider).newId();
      final result = await ref
          .read(kitchenFinishRepositoryProvider)
          .completeServedOrder(orderId: orderId, localOperationId: localOp);
      // Pull the authoritative order state so a completed order drops off the
      // active board and its table frees. Best-effort — the op already applied, so
      // a refresh hiccup must never surface as a completion failure.
      try {
        await ref.read(posOrderSyncControllerProvider.notifier).syncNow();
      } on Object {
        // ignore: the authoritative state refreshes on the next pull anyway.
      }
      return result;
    } finally {
      state = <String>{
        for (final id in state)
          if (id != orderId) id,
      };
    }
  }
}

final posOrderCompleteControllerProvider =
    NotifierProvider<PosOrderCompleteController, Set<String>>(
      PosOrderCompleteController.new,
    );
