/// The ONE mutable demo order dataset (ORDER-COMPLETION-001 /
/// ORDER-AUTO-COMPLETION-001).
///
/// The demo active-orders repository and the demo order-history repository both
/// read this single shared, mutable store, so a completion is observed by both:
/// the order leaves Active Orders and appears in History.
///
/// It is deterministic and honest — it models exactly the rules the server
/// enforces, and it FABRICATES NOTHING:
///
///   * THE RULE (ORDER-AUTO-COMPLETION-001): a `served` order that is FULLY PAID
///     completes ITSELF, from either direction — [markServed] (it was already paid
///     when it was served) and [recordPayment] (it was already served when it was
///     paid). Both funnel through the ONE decision, [_tryAutoComplete], exactly as
///     the server funnels both through `app.try_auto_complete_order`.
///   * "Fully paid" is a SETTLEMENT test, not a marker test: a completed payment
///     whose amount covers the order's CURRENT total, in integer minor units
///     (D-007). `OrderDetail.isFullySettled` mirrors `app.order_is_fully_settled`,
///     and both the automatic rule and the manual path go through it.
///   * [complete] is the MANUAL RECOVERY path, not the normal way an order closes.
///     It still refuses an order that is not `served` or not fully settled, with
///     the same domain errors the RPC returns.
///   * Auto-completion NEVER creates or touches a payment and never changes a
///     total. Only [recordPayment] — the demo model of the POS taking the money —
///     writes a payment, and that is the TRIGGER, never a consequence.
library;

import 'order_history_models.dart';
import 'order_history_repository.dart';

/// Why a demo completion was refused — the SAME domain errors the RPC returns.
enum DemoCompleteRefusal {
  /// No such order in the demo dataset.
  notFound,

  /// The order is not in the one eligible source state (`served`).
  invalidTransition,

  /// D-025: the order is not fully settled (no completed payment, or one that no
  /// longer covers the current total).
  notPaid,
}

/// What a demo trigger did: it applied, and it may also have auto-completed the
/// order as a consequence.
class DemoTransitionOutcome {
  const DemoTransitionOutcome({
    required this.applied,
    required this.autoCompleted,
  });

  /// The triggering operation itself (the serve, or the payment) succeeded.
  final bool applied;

  /// ...and the served + fully-paid rule then closed the order.
  final bool autoCompleted;
}

/// The shared, mutable demo order dataset.
class DemoOrderStore {
  DemoOrderStore([List<DemoOrder>? orders])
    : _orders = [...(orders ?? demoOrderHistory())];

  final List<DemoOrder> _orders;

  /// The current dataset (read-only view).
  List<DemoOrder> get orders => List<DemoOrder>.unmodifiable(_orders);

  /// TRIGGER DIRECTION A — the kitchen serves the order (the KDS bump).
  ///
  /// The serve stands on its own: an UNPAID order simply becomes `served` and
  /// stays active in Awaiting close. A PAID one closes itself immediately.
  DemoTransitionOutcome markServed(String orderId) {
    final index = _indexOf(orderId);
    if (index < 0) {
      return const DemoTransitionOutcome(applied: false, autoCompleted: false);
    }
    final detail = _orders[index].detail;
    // Only a `ready` order can be served (the canonical single-step machine).
    if (detail.status != 'ready') {
      return const DemoTransitionOutcome(applied: false, autoCompleted: false);
    }
    _replace(index, _copyWith(detail, status: 'served'));
    return DemoTransitionOutcome(
      applied: true,
      autoCompleted: _tryAutoComplete(orderId),
    );
  }

  /// TRIGGER DIRECTION B — the POS records the payment.
  ///
  /// The payment is the trigger, and it always succeeds on its own. If the order
  /// was ALREADY served, it is now fully paid and closes itself; if it is still in
  /// the kitchen, it stays exactly where it is (payment is not fulfillment —
  /// D-025).
  DemoTransitionOutcome recordPayment(String orderId) {
    final index = _indexOf(orderId);
    if (index < 0) {
      return const DemoTransitionOutcome(applied: false, autoCompleted: false);
    }
    final detail = _orders[index].detail;
    // A terminal order is never paid again, and at most one completed payment per
    // order exists (D-024/D-025).
    if (_isTerminal(detail.status) || detail.completedPayment != null) {
      return const DemoTransitionOutcome(applied: false, autoCompleted: false);
    }
    // MONEY-SETTLEMENT-CONSISTENCY-001: a NON-CHARGEABLE (zero-total) order takes NO
    // payment — the server now refuses it before it can mint a 0-amount payment row or
    // burn a receipt number. The demo must refuse it too, or it would model a state the
    // real system cannot reach.
    if (detail.grandTotalMinor <= 0) {
      return const DemoTransitionOutcome(applied: false, autoCompleted: false);
    }
    // The payment covers the order total exactly — the server takes no amount
    // parameter and forces amount = the order's own total.
    _replace(
      index,
      _copyWith(
        detail,
        payments: [
          ...detail.payments,
          OrderPayment(
            method: 'cash',
            status: 'completed',
            amountMinor: detail.grandTotalMinor,
            tenderedMinor: detail.grandTotalMinor,
            changeMinor: 0,
            receiptNumber: detail.receiptNumber,
          ),
        ],
      ),
    );
    return DemoTransitionOutcome(
      applied: true,
      autoCompleted: _tryAutoComplete(orderId),
    );
  }

  /// The MANUAL RECOVERY completion (ORDER-COMPLETION-001), reachable from the
  /// order detail sheet. Since ORDER-AUTO-COMPLETION-001 this is the exception
  /// path, not the normal way an order closes — it exists for an order the rule
  /// did not close (e.g. one served and paid before the rule existed).
  ///
  /// Returns null on success; otherwise the reason it was refused.
  DemoCompleteRefusal? complete(String orderId) {
    final index = _indexOf(orderId);
    if (index < 0) return DemoCompleteRefusal.notFound;

    final detail = _orders[index].detail;
    if (detail.status != 'served') return DemoCompleteRefusal.invalidTransition;
    // D-025, and the SAME settlement test the automatic rule uses.
    if (!detail.isFullySettled) return DemoCompleteRefusal.notPaid;

    _replace(index, _copyWith(detail, status: 'completed'));
    return null;
  }

  /// THE ONE automatic decision, shared by both trigger directions — the demo
  /// counterpart of `app.try_auto_complete_order`.
  ///
  /// Fires only on a `served` order that is fully settled. It is idempotent (an
  /// already-completed order is not `served`, so it is left alone) and it never
  /// revives a terminal order. It creates NO payment and moves NO money.
  bool _tryAutoComplete(String orderId) {
    final index = _indexOf(orderId);
    if (index < 0) return false;
    final detail = _orders[index].detail;
    if (detail.status != 'served') return false;
    if (!detail.isFullySettled) return false;
    _replace(index, _copyWith(detail, status: 'completed'));
    return true;
  }

  int _indexOf(String orderId) =>
      _orders.indexWhere((o) => o.detail.orderId == orderId);

  void _replace(int index, OrderDetail detail) {
    final existing = _orders[index];
    _orders[index] = DemoOrder(
      daysAgo: existing.daysAgo,
      minutesAgo: existing.minutesAgo,
      branchId: existing.branchId,
      detail: detail,
    );
  }

  static bool _isTerminal(String status) =>
      status == 'completed' || status == 'cancelled' || status == 'voided';

  /// The SAME order with only the named fields changed. Money, items, customer and
  /// table are always carried over untouched.
  static OrderDetail _copyWith(
    OrderDetail d, {
    String? status,
    List<OrderPayment>? payments,
  }) => OrderDetail(
    orderId: d.orderId,
    orderCode: d.orderCode,
    status: status ?? d.status,
    orderType: d.orderType,
    currencyCode: d.currencyCode,
    subtotalMinor: d.subtotalMinor,
    discountTotalMinor: d.discountTotalMinor,
    taxTotalMinor: d.taxTotalMinor,
    grandTotalMinor: d.grandTotalMinor,
    createdAtLabel: d.createdAtLabel,
    customerName: d.customerName,
    tableLabel: d.tableLabel,
    branchName: d.branchName,
    staffName: d.staffName,
    receiptNumber: d.receiptNumber,
    notes: d.notes,
    items: d.items,
    payments: payments ?? d.payments,
  );
}
