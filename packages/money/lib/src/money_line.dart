/// An order line and its calculation (RF-036, MONEY_AND_TAX_SPEC §9 step 1-2).
/// Pure Dart, integer minor units only.
library;

import 'discount.dart';
import 'money.dart';
import 'money_exceptions.dart';
import 'rounding_policy.dart';

/// Input line: a per-unit gross price (item snapshot + its modifier snapshots),
/// an integer quantity, and an optional item-level discount.
class MoneyLine {
  MoneyLine({
    required this.unitPrice,
    required this.quantity,
    this.itemDiscount,
  }) {
    if (quantity < 1) {
      throw InvalidQuantityException(
        'quantity must be a positive integer, got $quantity',
      );
    }
  }

  final Money unitPrice;
  final int quantity;
  final DiscountSet? itemDiscount;

  String get currencyCode => unitPrice.currencyCode;

  /// Computes the line: subtotal = unitPrice * quantity, then the item-level
  /// discount (clamped at zero), and the effective discount (subtotal - total).
  LineCalculation calculate(RoundingPolicy rounding) {
    final subtotal = unitPrice.scale(quantity);
    final discounts = itemDiscount;
    final total = discounts == null
        ? subtotal
        : discounts.applyTo(subtotal, rounding);
    final discount = subtotal - total;
    return LineCalculation(
      subtotal: subtotal,
      discount: discount,
      total: total,
    );
  }
}

/// Output of a single line calculation. All values are integer minor [Money].
class LineCalculation {
  const LineCalculation({
    required this.subtotal,
    required this.discount,
    required this.total,
  });

  /// Pre-discount line amount (unit price * quantity).
  final Money subtotal;

  /// The effective item-level discount removed (`subtotal - total`).
  final Money discount;

  /// Discounted line total (clamped at zero).
  final Money total;
}
