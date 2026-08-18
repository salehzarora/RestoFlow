import 'package:restoflow_currency/restoflow_currency.dart';

/// Integer-only money formatting for customer receipts (RF-073, D-007/D-008).
///
/// The print/receipt layer NEVER computes money and NEVER uses floating point.
/// This formatter turns an authoritative integer minor-unit value (already
/// computed upstream by RF-054) into a deterministic display string using only
/// integer arithmetic — no `double`, no `num`, no `toStringAsFixed`, no money
/// engine. It does NOT add, discount, or tax anything; it only renders a value
/// the caller supplies.
///
/// OPS-043 Phase 2: the exponent table moved to `packages/currency`, the one
/// shared ISO-4217 catalog. This copy held eight codes and was already missing
/// OMR, TND and KRW that `feature_menu`'s table had — two hand-maintained maps
/// that could (and did) disagree about how many decimals a currency has. The
/// receipt STYLE is unchanged: bare digits, and `formatWithCurrency` appends
/// the code, because a thermal printer's code page can turn a glyph into a
/// question mark.
class ReceiptMoneyFormat {
  const ReceiptMoneyFormat._();

  /// Exponent assumed when a currency code is not in the shared catalog.
  static const int defaultExponent = kDefaultCurrencyExponent;

  /// The minor-unit exponent for [currencyCode], or [exponentOverride] if given.
  static int exponentFor(String currencyCode, {int? exponentOverride}) =>
      exponentOverride ?? currencyExponent(currencyCode);

  /// Format [minor] (integer minor units) as a bare numeric string, e.g.
  /// `4242` with exponent 2 -> `42.42`, `-500` -> `-5.00`, `1000` with
  /// exponent 0 -> `1000`. Deterministic; integer arithmetic only.
  static String format(
    int minor, {
    required String currencyCode,
    int? exponentOverride,
  }) => formatCurrencyMinor(
    minor,
    currencyCode,
    style: CurrencySymbolStyle.bare,
    exponentOverride: exponentOverride,
  );

  /// Like [format] but appends the upper-cased currency code, e.g. `42.42 ILS`.
  static String formatWithCurrency(
    int minor, {
    required String currencyCode,
    int? exponentOverride,
  }) => formatCurrencyMinor(
    minor,
    currencyCode,
    style: CurrencySymbolStyle.codeSuffix,
    exponentOverride: exponentOverride,
  );
}
