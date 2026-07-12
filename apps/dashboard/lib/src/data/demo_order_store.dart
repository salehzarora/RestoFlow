/// The ONE mutable demo order dataset (ORDER-COMPLETION-001).
///
/// Before this ticket the demo active-orders repository and the demo
/// order-history repository each built their OWN copy of [demoOrderHistory], so a
/// demo mutation in one could never be observed by the other. Completion has to
/// move an order OUT of Active Orders and INTO History, so both demo repositories
/// now read this single shared, mutable store.
///
/// It is deterministic and honest: [complete] applies exactly the rules the server
/// enforces (the order must be `served`, and — per DECISION D-025 — it must carry
/// a completed payment), and it FABRICATES NOTHING: no payment is created, no
/// total is touched, and an ineligible order is refused with the same domain
/// error the RPC returns.
library;

import 'order_history_models.dart';
import 'order_history_repository.dart';

/// Why a demo completion was refused — the SAME domain errors the RPC returns.
enum DemoCompleteRefusal {
  /// No such order in the demo dataset.
  notFound,

  /// The order is not in the one eligible source state (`served`).
  invalidTransition,

  /// D-025: the order carries no completed payment.
  notPaid,
}

/// The shared, mutable demo order dataset.
class DemoOrderStore {
  DemoOrderStore([List<DemoOrder>? orders])
    : _orders = [...(orders ?? demoOrderHistory())];

  final List<DemoOrder> _orders;

  /// The current dataset (read-only view).
  List<DemoOrder> get orders => List<DemoOrder>.unmodifiable(_orders);

  /// Marks [orderId] completed, applying the canonical rules.
  ///
  /// Returns null on success; otherwise the reason it was refused. On success the
  /// order's status becomes `completed` (terminal), so it leaves the active board
  /// and appears in history — WITHOUT inventing a payment or changing any money.
  DemoCompleteRefusal? complete(String orderId) {
    final index = _orders.indexWhere((o) => o.detail.orderId == orderId);
    if (index < 0) return DemoCompleteRefusal.notFound;

    final existing = _orders[index];
    final detail = existing.detail;
    if (detail.status != 'served') return DemoCompleteRefusal.invalidTransition;
    // D-025: fulfillment may only close once payment is completed.
    if (detail.completedPayment == null) return DemoCompleteRefusal.notPaid;

    _orders[index] = DemoOrder(
      daysAgo: existing.daysAgo,
      minutesAgo: existing.minutesAgo,
      branchId: existing.branchId,
      detail: _completedCopy(detail),
    );
    return null;
  }

  /// The SAME order with `status: 'completed'`. Every other field — money,
  /// payments, items, customer, table — is carried over untouched.
  OrderDetail _completedCopy(OrderDetail d) => OrderDetail(
    orderId: d.orderId,
    orderCode: d.orderCode,
    status: 'completed',
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
    payments: d.payments,
  );
}
