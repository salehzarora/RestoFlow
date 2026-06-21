/// RestoFlow money package — the pure integer money calculation engine (RF-036).
///
/// Integer minor-unit money type, currency, rounding, discounts, and order
/// totals (DECISION D-007; MONEY_AND_TAX_SPEC). There is no fractional money
/// type anywhere — all amounts are integer minor units. Tax is a swappable hook
/// disabled by default (OPEN QUESTION Q-002); the rounding strategy and discount
/// precedence implement the MONEY_AND_TAX_SPEC §5/§4.3 PROPOSED candidates
/// behind named, swappable policies. Pure Dart — no Flutter, no IO, no backend.
library;

export 'src/discount.dart';
export 'src/money.dart';
export 'src/money_exceptions.dart';
export 'src/money_line.dart';
export 'src/money_order.dart';
export 'src/order_calculator.dart';
export 'src/rounding_policy.dart';
export 'src/tax_policy.dart';
