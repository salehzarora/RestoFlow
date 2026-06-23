/// Integer-only money formatting for customer receipts (RF-073, D-007/D-008).
///
/// The print/receipt layer NEVER computes money and NEVER uses floating point.
/// This formatter turns an authoritative integer minor-unit value (already
/// computed upstream by RF-054) into a deterministic display string using only
/// integer arithmetic — no `double`, no `num`, no `toStringAsFixed`, no money
/// engine. It does NOT add, discount, or tax anything; it only renders a value
/// the caller supplies.
class ReceiptMoneyFormat {
  const ReceiptMoneyFormat._();

  /// Minor-unit exponent (digits after the decimal point) per ISO-4217 code.
  /// Only a small, receipt-relevant set is hard-coded; unknown codes fall back
  /// to [defaultExponent]. The real jurisdiction/currency table is out of scope
  /// (OPEN QUESTION Q-007) — this is presentation only, not tax/rounding.
  static const Map<String, int> _exponents = <String, int>{
    'ILS': 2,
    'USD': 2,
    'EUR': 2,
    'GBP': 2,
    'JOD': 3,
    'KWD': 3,
    'BHD': 3,
    'JPY': 0,
  };

  /// Exponent assumed when a currency code is not in [_exponents].
  static const int defaultExponent = 2;

  /// The minor-unit exponent for [currencyCode], or [exponentOverride] if given.
  static int exponentFor(String currencyCode, {int? exponentOverride}) =>
      exponentOverride ??
      _exponents[currencyCode.toUpperCase()] ??
      defaultExponent;

  /// Format [minor] (integer minor units) as a bare numeric string, e.g.
  /// `4242` with exponent 2 -> `42.42`, `-500` -> `-5.00`, `1000` with
  /// exponent 0 -> `1000`. Deterministic; integer arithmetic only.
  static String format(
    int minor, {
    required String currencyCode,
    int? exponentOverride,
  }) {
    final exponent = exponentFor(
      currencyCode,
      exponentOverride: exponentOverride,
    );
    final negative = minor < 0;
    final magnitude = negative ? -minor : minor;
    final scale = _pow10(exponent);
    final whole = magnitude ~/ scale;
    final fraction = magnitude % scale;
    final sign = negative ? '-' : '';
    if (exponent == 0) {
      return '$sign$whole';
    }
    final fractionText = fraction.toString().padLeft(exponent, '0');
    return '$sign$whole.$fractionText';
  }

  /// Like [format] but appends the upper-cased currency code, e.g. `42.42 ILS`.
  static String formatWithCurrency(
    int minor, {
    required String currencyCode,
    int? exponentOverride,
  }) =>
      '${format(minor, currencyCode: currencyCode, exponentOverride: exponentOverride)} '
      '${currencyCode.toUpperCase()}';

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
