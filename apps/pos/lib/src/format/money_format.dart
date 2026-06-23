import 'package:restoflow_money/restoflow_money.dart';

/// Formats integer minor-unit money for display in the POS demo UI.
///
/// Money is integer minor units everywhere (DECISION D-007); the money package
/// ships no formatter, so the presentation layer owns rendering. Every input is
/// an integer minor-unit amount — there is no floating-point money.
class MoneyFormatter {
  const MoneyFormatter._();

  static const Map<String, String> _symbols = <String, String>{
    'ILS': '₪',
    'USD': r'$',
    'EUR': '€',
  };

  static const Map<String, int> _fractionDigits = <String, int>{
    'ILS': 2,
    'USD': 2,
    'EUR': 2,
  };

  /// Renders a [Money] value, e.g. `Money(4200, 'ILS')` -> `"₪42.00"`.
  static String format(Money money) =>
      formatMinor(money.amountMinor, money.currencyCode);

  /// Renders an integer minor-unit amount for [currencyCode],
  /// e.g. `formatMinor(4200, 'ILS')` -> `"₪42.00"`.
  static String formatMinor(int amountMinor, String currencyCode) {
    final digits = _fractionDigits[currencyCode] ?? 2;
    final symbol = _symbols[currencyCode] ?? '';
    final divisor = _pow10(digits);
    final negative = amountMinor < 0;
    final abs = amountMinor.abs();
    final whole = abs ~/ divisor;
    final number = digits == 0
        ? '$whole'
        : '$whole.${(abs % divisor).toString().padLeft(digits, '0')}';
    final sign = negative ? '-' : '';
    return '$sign$symbol$number';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
