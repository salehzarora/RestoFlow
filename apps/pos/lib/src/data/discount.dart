/// Order-level discount types + result for the POS (RF-117 part C).
///
/// A discount is SERVER-AUTHORITATIVE and AUTHORIZED (`app.apply_discount`,
/// RF-053): the server recomputes totals from snapshots, clamps the discount to
/// the subtotal, rounds half-away as integer minor units (D-007), and authorizes
/// the actor (manager/owner OR a cashier whose membership carries the
/// `apply_discount` permission). The client never invents the discounted total —
/// it reads it back from the result.
library;

/// How the discount [value] is interpreted (matches `app.apply_discount`).
enum DiscountType {
  /// [value] is an amount in integer minor units (D-007).
  fixed('fixed'),

  /// [value] is a rate in integer BASIS POINTS (0..10000; 1000 = 10.00%).
  percentage('percentage');

  const DiscountType(this.wire);

  /// The `discount_type` wire string the RPC expects.
  final String wire;
}

/// The recomputed order totals after an order-level discount (RF-117). Integer
/// minor units only. In real mode these are the SERVER's authoritative values;
/// in demo mode they are computed locally with the same clamp.
class OrderDiscount {
  const OrderDiscount({
    required this.discountTotalMinor,
    required this.grandTotalMinor,
  });

  /// The applied discount (integer minor units), clamped to <= subtotal.
  final int discountTotalMinor;

  /// The new order grand total (`subtotal − discount + tax`), never negative.
  final int grandTotalMinor;
}

/// Thrown when an order-level discount cannot be applied (RF-117). Messages carry
/// only domain values — never secrets or raw backend JSON.
///
/// The flags are TYPED, and each maps to exactly ONE stable server contract. The
/// UI dispatches on the flag and NEVER on the message text or on a guess: a
/// refusal is only rendered as "you may not make an order free" when the server
/// actually said `full_comp_permission_required`. Inferring it from a zero total,
/// from a generic rejection, or from a SQLSTATE would let an unrelated failure
/// masquerade as a permission problem.
class DiscountException implements Exception {
  const DiscountException(
    this.message, {
    this.permissionDenied = false,
    this.fullCompRequired = false,
    this.exceedsOrderTotal = false,
  });

  final String message;

  /// The actor may not apply discounts at all
  /// (`permission_denied`, no detail).
  final bool permissionDenied;

  /// FULL-COMP-PERMISSION-001: the actor MAY discount, but this particular
  /// discount would leave the order total at exactly zero, and making an order
  /// free is a SEPARATE permission they do not hold
  /// (`permission_denied` + `full_comp_permission_required`).
  final bool fullCompRequired;

  /// FULL-COMP-PERMISSION-001: the discount would drive the total BELOW zero, which
  /// the server refuses rather than silently flooring
  /// (`invalid_discount` + `discount_exceeds_order_total`).
  final bool exceedsOrderTotal;

  @override
  String toString() => 'DiscountException: $message';
}
