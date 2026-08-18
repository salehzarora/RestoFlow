/// Integer-only minor-unit money parse/format helpers (RF-111, DECISION D-007).
///
/// OPS-043 Phase 2: the EXPONENT TABLE and the formatter moved to
/// `packages/currency`, the one shared ISO-4217 catalog. This file held the
/// third of three hand-maintained exponent maps in the repo — it knew OMR, TND
/// and KRW that the receipt formatter's did not, and neither knew the rest of
/// ISO-4217. Sharing the table is the whole point: two maps that disagree about
/// how many decimals a currency has will eventually disagree in production.
///
/// What stays local is the PARSER'S INPUT GRAMMAR. This one is deliberately
/// more forgiving than cash entry — it accepts a leading `+`, a bare `.50`, a
/// trailing `12.` and negatives, because it backs a menu price field an owner
/// types into, not a till. The strict grammar lives in
/// `packages/currency`'s `parseCashToMinor`. Only the exponent is shared.
library;

import 'package:restoflow_currency/restoflow_currency.dart' as currency;

/// The number of minor-unit decimal places for [currencyCode] (e.g. 2 for USD,
/// 3 for JOD, 0 for JPY). Defaults to 2 for unknown codes.
int currencyExponent(String currencyCode) =>
    currency.currencyExponent(currencyCode);

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

final RegExp _digits = RegExp(r'^[0-9]*$');

/// Formats integer minor units to a major-unit display string using ONLY
/// integer arithmetic, e.g. `(4242, 'USD') -> "42.42"`, `(-50, 'USD') -> "-0.50"`,
/// `(500, 'JPY') -> "500"`.
String formatMinorUnits(int minorUnits, String currencyCode) =>
    currency.formatCurrencyMinor(
      minorUnits,
      currencyCode,
      style: currency.CurrencySymbolStyle.bare,
    );

/// Parses a major-unit string (e.g. `"12.50"`) into integer minor units for
/// [currencyCode], or `null` when the input is not a valid amount. Integer-only:
/// it splits on a single decimal separator and scales by the currency exponent.
/// Rejects more fractional digits than the currency allows (no silent rounding).
int? parseMajorToMinor(String input, String currencyCode) {
  final exponent = currencyExponent(currencyCode);
  var text = input.trim();
  if (text.isEmpty) return null;

  var isNegative = false;
  if (text.startsWith('-')) {
    isNegative = true;
    text = text.substring(1);
  } else if (text.startsWith('+')) {
    text = text.substring(1);
  }

  final parts = text.split('.');
  if (parts.length > 2) return null;
  final wholePart = parts[0];
  final fractionPart = parts.length == 2 ? parts[1] : '';
  if (wholePart.isEmpty && fractionPart.isEmpty) return null;
  if (!_digits.hasMatch(wholePart) || !_digits.hasMatch(fractionPart)) {
    return null;
  }
  if (fractionPart.length > exponent) return null;

  final wholeValue = wholePart.isEmpty ? 0 : int.parse(wholePart);
  final paddedFraction = fractionPart.padRight(exponent, '0');
  final fractionValue = paddedFraction.isEmpty ? 0 : int.parse(paddedFraction);
  final minorUnits = wholeValue * _pow10(exponent) + fractionValue;
  return isNegative ? -minorUnits : minorUnits;
}
