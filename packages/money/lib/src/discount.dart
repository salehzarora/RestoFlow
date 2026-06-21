/// Discount models for the money engine (RF-036, MONEY_AND_TAX_SPEC §4).
///
/// Two forms: percentage (integer basis points, 1000 = 10.00%) and fixed
/// (integer minor units). Within a level a percentage applies before a fixed
/// amount, and each step clamps the target at zero (§4.3/§4.4 — PROPOSED
/// candidates, modeled here behind swappable policies). Pure Dart.
library;

import 'money.dart';
import 'money_exceptions.dart';
import 'rounding_policy.dart';

abstract class Discount {
  const Discount();

  /// The (un-clamped) amount this discount removes from [base].
  Money computeAmount(Money base, RoundingPolicy rounding);
}

/// A percentage discount expressed in integer basis points (1000 = 10.00%,
/// 10000 = 100.00%). Basis points must be in `[0, 10000]`.
class PercentageDiscount extends Discount {
  PercentageDiscount(this.basisPoints) {
    if (basisPoints < 0) {
      throw const InvalidDiscountException('basisPoints must not be negative');
    }
    if (basisPoints > 10000) {
      throw const InvalidDiscountException(
        'basisPoints must not exceed 10000 (100%)',
      );
    }
  }

  final int basisPoints;

  @override
  Money computeAmount(Money base, RoundingPolicy rounding) => Money(
    rounding.roundDiv(base.amountMinor * basisPoints, 10000),
    base.currencyCode,
  );
}

/// A fixed discount in integer minor units. Must be non-negative; capping so a
/// target never goes below zero is handled by [DiscountSet.applyTo].
class FixedDiscount extends Discount {
  FixedDiscount(this.amountMinor) {
    if (amountMinor < 0) {
      throw const InvalidDiscountException(
        'a fixed discount must not be negative',
      );
    }
  }

  final int amountMinor;

  @override
  Money computeAmount(Money base, RoundingPolicy rounding) =>
      Money(amountMinor, base.currencyCode);
}

/// At most one percentage and one fixed discount applied to a single target
/// (an order line, or the order subtotal). Percentage applies first, then
/// fixed; each step clamps the result at zero (§4.3/§4.4). Multiple percentage
/// or fixed discounts on the same target are out of scope (DEFERRED).
class DiscountSet {
  const DiscountSet({this.percentage, this.fixed});

  final PercentageDiscount? percentage;
  final FixedDiscount? fixed;

  bool get isEmpty => percentage == null && fixed == null;

  /// Applies percentage-then-fixed to [base], clamping at zero each step, and
  /// returns the resulting (non-negative) total.
  Money applyTo(Money base, RoundingPolicy rounding) {
    var current = base;
    final p = percentage;
    if (p != null) {
      current = (current - p.computeAmount(current, rounding)).clampToZero();
    }
    final f = fixed;
    if (f != null) {
      current = (current - f.computeAmount(current, rounding)).clampToZero();
    }
    return current;
  }
}
