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
/// only domain values — never secrets or raw backend JSON. [permissionDenied] is
/// true for the honest cashier-without-permission case, so the UI can show the
/// "ask a manager" message rather than a generic failure.
class DiscountException implements Exception {
  const DiscountException(this.message, {this.permissionDenied = false});

  final String message;
  final bool permissionDenied;

  @override
  String toString() => 'DiscountException: $message';
}
