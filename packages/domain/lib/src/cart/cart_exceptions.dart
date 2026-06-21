/// Domain exceptions for the local POS cart (RF-031).
///
/// Messages carry only domain values (quantities, currency codes, ids/names
/// that are already in the caller's hands) — never secrets or unrelated
/// internal data.
library;

/// Base type for all cart domain failures.
abstract class CartException implements Exception {
  const CartException(this.message);

  /// A short, safe description of what went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A quantity (line or modifier-option) was not a positive integer.
class InvalidQuantityException extends CartException {
  InvalidQuantityException(this.quantity)
    : super('quantity must be a positive integer, got $quantity');

  final int quantity;
}

/// A line's currency does not match the cart's single currency.
class CurrencyMismatchException extends CartException {
  const CurrencyMismatchException(super.message);

  /// Builds the standard cart/line currency-mismatch message.
  factory CurrencyMismatchException.between(
    String cartCurrency,
    String lineCurrency,
  ) => CurrencyMismatchException(
    'line currency "$lineCurrency" does not match cart currency '
    '"$cartCurrency"',
  );
}

/// A modifier selection violated its group's min/max/required rule.
class InvalidModifierSelectionException extends CartException {
  const InvalidModifierSelectionException(super.message);
}

/// A line with the same `lineId` already exists in the cart.
class DuplicateLineException extends CartException {
  DuplicateLineException(this.lineId)
    : super('a cart line with id "$lineId" already exists');

  final String lineId;
}

/// No cart line with the given `lineId` was found.
class LineNotFoundException extends CartException {
  LineNotFoundException(this.lineId)
    : super('no cart line with id "$lineId" was found');

  final String lineId;
}
