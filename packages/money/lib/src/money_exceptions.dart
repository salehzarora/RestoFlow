/// Domain exceptions for the integer money engine (RF-036).
///
/// Messages carry only domain values (short fixed text) — never secrets. Pure
/// Dart; all money is integer minor units (DECISION D-007).
library;

/// Base type for all money-engine failures.
abstract class MoneyException implements Exception {
  const MoneyException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Invalid money construction (e.g. an empty currency code).
class InvalidMoneyException extends MoneyException {
  const InvalidMoneyException(super.message);
}

/// Arithmetic/comparison attempted across two different currencies.
class CurrencyMismatchException extends MoneyException {
  const CurrencyMismatchException(super.message);

  /// Standard message for two mismatched currency codes.
  factory CurrencyMismatchException.between(String a, String b) =>
      CurrencyMismatchException('currencies differ: "$a" vs "$b"');
}

/// Invalid discount construction (negative/over-range basis points, negative
/// fixed amount).
class InvalidDiscountException extends MoneyException {
  const InvalidDiscountException(super.message);
}

/// A quantity (line count) was not a positive integer.
class InvalidQuantityException extends MoneyException {
  const InvalidQuantityException(super.message);
}
