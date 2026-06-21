/// The integer minor-unit money value object (RF-036, DECISION D-007).
///
/// Money is ALWAYS an integer count of minor currency units (e.g. agorot,
/// cents, fils) plus an ISO 4217 currency code. There is no fractional money
/// type anywhere in this engine. Arithmetic is only valid within a single
/// currency; mixing currencies throws [CurrencyMismatchException].
library;

import 'money_exceptions.dart';

class Money {
  /// Creates money of [amountMinor] integer minor units in [currency]
  /// (normalized to a non-empty uppercase ISO 4217 code).
  Money(this.amountMinor, String currency)
    : currencyCode = normalizeCurrencyCode(currency);

  /// Zero in the given [currency].
  factory Money.zero(String currency) => Money(0, currency);

  /// Integer minor units (may be negative for intermediate values).
  final int amountMinor;

  /// Normalized, non-empty ISO 4217 currency code (uppercase).
  final String currencyCode;

  /// Trims + uppercases [code]; rejects an empty result.
  static String normalizeCurrencyCode(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const InvalidMoneyException('currencyCode must not be empty');
    }
    return normalized;
  }

  bool get isNegative => amountMinor < 0;
  bool get isZero => amountMinor == 0;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(amountMinor + other.amountMinor, currencyCode);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(amountMinor - other.amountMinor, currencyCode);
  }

  /// Multiplies the amount by an integer [factor] (e.g. a line quantity).
  Money scale(int factor) => Money(amountMinor * factor, currencyCode);

  /// Returns this if non-negative, else zero in the same currency.
  Money clampToZero() => amountMinor < 0 ? Money(0, currencyCode) : this;

  int compareTo(Money other) {
    _requireSameCurrency(other);
    return amountMinor.compareTo(other.amountMinor);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  void _requireSameCurrency(Money other) {
    if (other.currencyCode != currencyCode) {
      throw CurrencyMismatchException.between(currencyCode, other.currencyCode);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(amountMinor, currencyCode);

  @override
  String toString() => 'Money($amountMinor, $currencyCode)';
}
