import 'package:restoflow_currency/restoflow_currency.dart';
import 'package:restoflow_money/restoflow_money.dart';

/// Formats integer minor-unit money for display in the Dashboard.
///
/// OPS-043 Phase 2: this is now a THIN ADAPTER over `packages/currency`, the
/// one shared ISO-4217 catalog/formatter. It used to carry its own 3-entry
/// symbol table and its own 3-entry fraction-digit table — both defaulting to
/// two decimals, which for JPY/KRW (0) and JOD/KWD/BHD/OMR/TND (3) rendered a
/// figure that was wrong by 100x or 10x rather than merely unfamiliar.
///
/// The class survives (rather than 32 call sites being rewritten) because the
/// call sites are correct as they stand: each already passes the currency of
/// the thing it is rendering — the ROW's code for stored money, the cart's for
/// live money. Only the table underneath them was wrong.
///
/// ILS/USD/EUR output is unchanged to the character; the difference is that a
/// currency outside those three now renders with its CODE ("CHF 25.00") instead
/// of a bare, unlabelled number, and 0-/3-decimal currencies get their real
/// exponent.
class MoneyFormatter {
  const MoneyFormatter._();

  /// Renders a [Money] value, e.g. `Money(4200, 'ILS')` -> `"₪42.00"`.
  static String format(Money money) =>
      formatMinor(money.amountMinor, money.currencyCode);

  /// Renders an integer minor-unit amount for [currencyCode],
  /// e.g. `formatMinor(4200, 'ILS')` -> `"₪42.00"`.
  static String formatMinor(int amountMinor, String currencyCode) =>
      formatCurrencyMinor(amountMinor, currencyCode);
}
