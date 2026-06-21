/// Tax hook for the money engine (RF-036, MONEY_AND_TAX_SPEC §6).
///
/// Tax mode, rate(s), and jurisdiction are intentionally UNRESOLVED
/// (OPEN QUESTION Q-002 / Q-001); production code ships NO rate. The engine
/// exposes a swappable [TaxPolicy] whose default ([DisabledTaxPolicy]) returns
/// zero, so tax stays disabled until Q-002 resolves. Pure Dart.
library;

import 'money.dart';
import 'rounding_policy.dart';

abstract interface class TaxPolicy {
  /// The tax for a post-discount [discountedBase], in integer minor units,
  /// rounded per [rounding] where applicable.
  Money computeTax(Money discountedBase, RoundingPolicy rounding);
}

/// The default policy: tax is OFF (returns zero) until Q-002 resolves. There is
/// no rate, no inclusive/exclusive mode, and no jurisdiction logic here.
class DisabledTaxPolicy implements TaxPolicy {
  const DisabledTaxPolicy();

  @override
  Money computeTax(Money discountedBase, RoundingPolicy rounding) =>
      Money.zero(discountedBase.currencyCode);
}
