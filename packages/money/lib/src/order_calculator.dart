/// The pure integer order calculation engine (RF-036, MONEY_AND_TAX_SPEC §9).
///
/// Calculation order: line subtotals → item-level discounts → order subtotal →
/// order-level discount → service charge (zero slot, Q-012) → tax (hook,
/// disabled by default) → grand total. All integer minor units; no fractional
/// type anywhere. Pure — no persistence, no I/O.
library;

import 'money.dart';
import 'money_line.dart';
import 'money_order.dart';

abstract final class OrderCalculator {
  /// Computes the [OrderCalculation] for [order] following the canonical
  /// MONEY_AND_TAX_SPEC §9 order, using the order's rounding + tax policies.
  static OrderCalculation calculate(MoneyOrder order) {
    final rounding = order.roundingPolicy;
    final zero = Money.zero(order.currencyCode);

    // Step 1-3: per-line, then the order subtotal (sum of discounted lines).
    final lineCalcs = <LineCalculation>[];
    var subtotal = zero;
    var itemDiscountTotal = zero;
    for (final line in order.lines) {
      final lc = line.calculate(rounding);
      lineCalcs.add(lc);
      subtotal = subtotal + lc.total;
      itemDiscountTotal = itemDiscountTotal + lc.discount;
    }

    // Step 4: order-level discount on the order subtotal (clamped at zero).
    final orderDiscounts = order.orderDiscount;
    final afterOrderDiscount = orderDiscounts == null
        ? subtotal
        : orderDiscounts.applyTo(subtotal, rounding);
    final orderDiscount = subtotal - afterOrderDiscount;

    // Step 5: service charge — DEFERRED (Q-012); a zero slot only.
    final serviceCharge = zero;

    // Step 6: tax via the hook (disabled by default → zero).
    final tax = order.taxPolicy.computeTax(afterOrderDiscount, rounding);

    // Step 7: grand total.
    final grandTotal = afterOrderDiscount + serviceCharge + tax;
    final discountTotal = itemDiscountTotal + orderDiscount;

    return OrderCalculation(
      lines: List.unmodifiable(lineCalcs),
      subtotal: subtotal,
      itemDiscountTotal: itemDiscountTotal,
      orderDiscount: orderDiscount,
      discountTotal: discountTotal,
      serviceCharge: serviceCharge,
      tax: tax,
      grandTotal: grandTotal,
    );
  }
}

/// The reconciled output of an order calculation. All values are integer minor
/// [Money]. `subtotal` is the post-item-discount order subtotal.
class OrderCalculation {
  const OrderCalculation({
    required this.lines,
    required this.subtotal,
    required this.itemDiscountTotal,
    required this.orderDiscount,
    required this.discountTotal,
    required this.serviceCharge,
    required this.tax,
    required this.grandTotal,
  });

  final List<LineCalculation> lines;

  /// Sum of discounted line totals (order subtotal after item discounts).
  final Money subtotal;

  /// Sum of item-level discounts across all lines.
  final Money itemDiscountTotal;

  /// Effective order-level discount.
  final Money orderDiscount;

  /// Total of all discounts (`itemDiscountTotal + orderDiscount`).
  final Money discountTotal;

  /// Service charge — always zero in MVP (Q-012 DEFERRED).
  final Money serviceCharge;

  /// Tax (zero under the default disabled policy).
  final Money tax;

  /// Final payable: `subtotal - orderDiscount + serviceCharge + tax`.
  final Money grandTotal;

  /// The reconciliation invariants that must hold for every calculation.
  bool get reconciles =>
      grandTotal == (subtotal - orderDiscount + serviceCharge + tax) &&
      discountTotal == (itemDiscountTotal + orderDiscount);
}
