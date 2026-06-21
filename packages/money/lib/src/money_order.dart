/// An order input for the money engine (RF-036). Pure Dart, integer minor units.
///
/// Single currency per order (MONEY_AND_TAX_SPEC §2): every line must share the
/// order currency. Tax defaults to the disabled hook and rounding to the §5
/// candidate; both are swappable.
library;

import 'discount.dart';
import 'money.dart';
import 'money_exceptions.dart';
import 'money_line.dart';
import 'rounding_policy.dart';
import 'tax_policy.dart';

class MoneyOrder {
  MoneyOrder({
    required String currency,
    required List<MoneyLine> lines,
    this.orderDiscount,
    this.taxPolicy = const DisabledTaxPolicy(),
    this.roundingPolicy = const RoundHalfAwayFromZero(),
  }) : currencyCode = Money.normalizeCurrencyCode(currency),
       lines = List.unmodifiable(lines) {
    if (this.lines.isEmpty) {
      throw const InvalidMoneyException('an order must have at least one line');
    }
    for (final line in this.lines) {
      if (line.currencyCode != currencyCode) {
        throw CurrencyMismatchException.between(
          currencyCode,
          line.currencyCode,
        );
      }
    }
  }

  /// The order's single normalized currency code (MONEY_AND_TAX_SPEC §2).
  final String currencyCode;

  /// Read-only item-level lines (at least one).
  final List<MoneyLine> lines;

  /// Optional order-level discount applied after item-level discounts.
  final DiscountSet? orderDiscount;

  /// Tax hook (default disabled → zero).
  final TaxPolicy taxPolicy;

  /// Integer rounding policy (default round half away from zero).
  final RoundingPolicy roundingPolicy;
}
