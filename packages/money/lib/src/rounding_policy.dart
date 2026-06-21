/// Integer rounding policies for the money engine (RF-036, MONEY_AND_TAX_SPEC
/// §5). Integer-only: the result of a division `numerator / denominator` is
/// rounded to an integer using purely integer arithmetic (no fractional type).
///
/// NOTE: the default strategy is the MONEY_AND_TAX_SPEC §5 PROPOSED candidate
/// (round half away from zero), NOT a frozen decision; it is a swappable policy
/// so it can be replaced when Q-001/Q-002 freeze the jurisdiction rounding rule.
library;

abstract interface class RoundingPolicy {
  /// Rounds `numerator / denominator` to an integer. [denominator] must be
  /// positive. The result is sign-correct for a negative [numerator].
  int roundDiv(int numerator, int denominator);
}

/// Round half away from zero (commercial rounding): ties round to the larger
/// magnitude. E.g. 1234.5 -> 1235, -1234.5 -> -1235, 1234.4 -> 1234.
class RoundHalfAwayFromZero implements RoundingPolicy {
  const RoundHalfAwayFromZero();

  @override
  int roundDiv(int numerator, int denominator) {
    if (denominator <= 0) {
      throw ArgumentError.value(denominator, 'denominator', 'must be positive');
    }
    final sign = numerator < 0 ? -1 : 1;
    final magnitude = numerator.abs();
    final quotient = magnitude ~/ denominator;
    final remainder = magnitude % denominator;
    // Round half away from zero on the magnitude: bump up when the remainder is
    // at or past half. This doubles only the remainder (always < denominator),
    // so it never overflows for any in-range numerator; the sign re-applies the
    // direction (away from zero).
    final rounded = (remainder * 2 >= denominator) ? quotient + 1 : quotient;
    return sign * rounded;
  }
}
