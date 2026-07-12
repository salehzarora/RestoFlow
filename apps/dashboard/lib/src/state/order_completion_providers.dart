/// Order-completion state seam (ORDER-COMPLETION-001).
///
/// The ONE write the Dashboard performs on an order. The mutation is modelled
/// EXPLICITLY (idle -> submitting -> success | failure) so the UI can:
///   * disable the action while a request is in flight (no duplicate writes);
///   * keep the order and its detail on screen while submitting;
///   * remove the order from the board ONLY after an authoritative success;
///   * offer retry ONLY for a transport failure (never blind-retry a refusal).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/order_completion_repository.dart';
import 'active_orders_providers.dart';
import 'dashboard_providers.dart';
import 'order_history_providers.dart';

/// The completion seam. Demo mode mutates the shared demo store; real mode calls
/// `owner_complete_order` over the authenticated transport (fails closed with no
/// transport/scope — never a demo fallback).
final orderCompletionRepositoryProvider = Provider<OrderCompletionRepository>((
  ref,
) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return DemoOrderCompletionRepository(ref.watch(demoOrderStoreProvider));
  }
  return RealOrderCompletionRepository(
    config.supabase,
    scope: ref.watch(dashboardMembershipProvider),
    transport: ref.watch(dashboardAuthTransportProvider),
  );
}, dependencies: [dashboardMembershipProvider, dashboardAuthTransportProvider]);

/// The mutation state for ONE order's completion.
class OrderCompletionState {
  const OrderCompletionState({
    this.submitting = false,
    this.completed = false,
    this.error,
  });

  /// A completion request is in flight — the action must be disabled.
  final bool submitting;

  /// The server authoritatively confirmed the order is completed.
  final bool completed;

  /// The refusal/failure, if the last attempt failed.
  final OrderCompletionError? error;

  bool get isRetryable =>
      error != null && OrderCompletionFailed(error!).isRetryable;
}

/// Drives ONE order's completion. Held per order id so two orders never share a
/// submitting flag.
class OrderCompletionController extends StateNotifier<OrderCompletionState> {
  OrderCompletionController(this._repo, this._orderId, this._onCompleted)
    : super(const OrderCompletionState());

  final OrderCompletionRepository _repo;
  final String _orderId;

  /// Called ONCE, after an authoritative success, to refresh the surfaces.
  final void Function() _onCompleted;

  /// Completes the order. A second call while a request is in flight is IGNORED,
  /// so a double-tap can never produce two writes.
  Future<void> complete({int? expectedRevision}) async {
    if (state.submitting || state.completed) return;
    state = const OrderCompletionState(submitting: true);

    final OrderCompletionResult result;
    try {
      result = await _repo.complete(
        _orderId,
        expectedRevision: expectedRevision,
      );
    } catch (_) {
      // Includes RealRepoNotWiredError: fail closed, never a fabricated success.
      if (!mounted) return;
      state = const OrderCompletionState(error: OrderCompletionError.transient);
      return;
    }
    if (!mounted) return;

    switch (result) {
      case OrderCompleted():
        state = const OrderCompletionState(completed: true);
        _onCompleted();
      case OrderCompletionFailed(:final error):
        state = OrderCompletionState(error: error);
    }
  }
}

/// The completion controller for one order id.
final orderCompletionControllerProvider =
    StateNotifierProvider.family<
      OrderCompletionController,
      OrderCompletionState,
      String
    >(
      (ref, orderId) => OrderCompletionController(
        ref.watch(orderCompletionRepositoryProvider),
        orderId,
        () {
          // Authoritative success: re-read the board (the now-terminal order drops
          // out of the ACTIVE set) and drop the cached history + detail so the
          // completed order shows up there. NOTHING is fabricated client-side.
          ref.read(activeOrdersControllerProvider.notifier).refresh();
          ref.invalidate(orderHistoryControllerProvider);
          ref.invalidate(orderDetailProvider);
        },
      ),
      dependencies: [
        orderCompletionRepositoryProvider,
        activeOrdersControllerProvider,
        orderHistoryControllerProvider,
        orderDetailProvider,
      ],
    );
