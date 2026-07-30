/// ORDER-DETAIL-PREVIEW-001 — loading the read-only order preview.
///
/// STRICTLY READ-ONLY. This controller performs exactly ONE kind of I/O: a
/// `pos_order_detail` read. It never submits, pays, prints, cancels, voids,
/// completes, adds items, touches a table or enqueues an outbox operation —
/// opening a window is not an instruction.
///
/// Every asynchronous continuation is FENCED on a monotonic request token, the
/// same discipline the addition controller uses: a response that belongs to a
/// CLOSED or SUPERSEDED preview is discarded rather than published into the
/// wrong one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/order_detail_repository.dart';
import '../data/order_preview_model.dart';
import '../data/recent_order.dart';

/// What the preview surface should be showing right now.
enum OrderPreviewPhase {
  /// The authoritative read is in flight — the UI shows a bounded, STATIC
  /// skeleton (never a perpetual spinner).
  loading,

  /// A model is available. It may be authoritative or an honest local copy —
  /// [OrderDetailPreviewModel.source] says which.
  ready,

  /// The read failed and there was no usable local copy to fall back on.
  failed,
}

class OrderPreviewState {
  const OrderPreviewState({
    required this.phase,
    this.model,
    this.staleLocalCopy = false,
  });

  final OrderPreviewPhase phase;
  final OrderDetailPreviewModel? model;

  /// The authoritative read FAILED and this is the local copy shown in its
  /// place. The UI says so, and offers Retry.
  final bool staleLocalCopy;

  bool get isLoading => phase == OrderPreviewPhase.loading;
  bool get isFailed => phase == OrderPreviewPhase.failed;
  bool get isReady => phase == OrderPreviewPhase.ready;
}

/// Loads the preview for ONE order.
///
/// A family provider keyed by the order's identity, so two previews can never
/// publish into each other and closing one disposes exactly its own work.
class OrderPreviewController
    extends AutoDisposeFamilyNotifier<OrderPreviewState, PosRecentOrder> {
  /// The generation fence. Every load increments it; a continuation only
  /// publishes while it still owns the current token.
  int _generation = 0;
  bool _disposed = false;

  int fetchCount = 0;

  @override
  OrderPreviewState build(PosRecentOrder arg) {
    ref.onDispose(() => _disposed = true);
    // A locally-known order can always be shown immediately; the authoritative
    // read then upgrades it. That is why opening never blanks the screen.
    final local = OrderDetailPreviewModel.fromLocal(arg);
    final orderId = arg.orderId;
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    if (isDemo || orderId == null || orderId.trim().isEmpty) {
      // No authoritative identity to read: the local record IS the answer, and
      // it is labelled as a local copy rather than dressed up as server truth.
      return OrderPreviewState(phase: OrderPreviewPhase.ready, model: local);
    }
    Future<void>.microtask(load);
    return const OrderPreviewState(phase: OrderPreviewPhase.loading);
  }

  /// Fetches the authoritative detail. Safe to call from Retry.
  ///
  /// This is the ONLY network call the preview ever makes.
  Future<void> load() async {
    final orderId = arg.orderId;
    if (orderId == null || orderId.trim().isEmpty) return;
    final generation = ++_generation;
    if (!_disposed && !state.isReady) {
      state = const OrderPreviewState(phase: OrderPreviewPhase.loading);
    }
    PosOrderDetail? detail;
    try {
      fetchCount++;
      detail = await ref.read(orderDetailRepositoryProvider).fetch(orderId);
    } catch (_) {
      detail = null;
    }
    // THE FENCE: a response from a closed or superseded preview is dropped. It
    // must never publish into a different order's surface, and it must never
    // touch a disposed notifier.
    if (_disposed || generation != _generation) return;

    if (detail != null) {
      state = OrderPreviewState(
        phase: OrderPreviewPhase.ready,
        model: OrderDetailPreviewModel.fromDetail(
          detail,
          // Precedence is inside the mapper: the server's payment wins, and the
          // local one is consulted only when the server named none.
          localPayment: arg.payment,
          // The pending pill is rendered from the SAME PosOrderActions object
          // the Orders sheet already resolved and hands to the preview, so the
          // model deliberately does not compute a second one here.
          createdAt: arg.snapshot?.createdAt,
          updatedAt: arg.snapshot?.updatedAt,
          voidedAt: arg.voidedAt,
          settlement: arg.settlement,
        ),
      );
      return;
    }

    // The read failed. If this device has usable local lines, show THEM and say
    // plainly that they are a local copy — a partial view honestly labelled
    // beats an empty error the cashier cannot act on.
    final local = OrderDetailPreviewModel.fromLocal(arg);
    if (local.lines.isNotEmpty) {
      state = OrderPreviewState(
        phase: OrderPreviewPhase.ready,
        model: local,
        staleLocalCopy: true,
      );
    } else {
      state = const OrderPreviewState(phase: OrderPreviewPhase.failed);
    }
  }
}

/// The preview for one order. AutoDispose: closing the sheet ends its work.
///
/// KEYED ON THE ORDER OBJECT, which is stable for a preview's whole life: the
/// sheet route captures ONE [PosRecentOrder] when it opens and hands that same
/// instance to every rebuild. `PosRecentOrder` has no value equality, so a
/// caller that rebuilt the order would key a different controller and refetch —
/// hold the instance rather than reconstructing it.
final orderPreviewControllerProvider = NotifierProvider.autoDispose
    .family<OrderPreviewController, OrderPreviewState, PosRecentOrder>(
      OrderPreviewController.new,
    );
