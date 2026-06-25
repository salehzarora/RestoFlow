/// Integer-only minor-unit money parse/format helpers (RF-111, DECISION D-007).
///
/// There is NO shared display/input formatter in `packages/money` (it has the
/// `Money` value type but no formatter), so RF-111 provides this small one. It
/// is strictly integer arithmetic — no `double`, no `toStringAsFixed` — so it
/// can never introduce floating-point money. Per-currency minor-unit exponents
/// mirror the receipt formatter's approach.
library;

/// The number of minor-unit decimal places for [currencyCode] (e.g. 2 for USD,
/// 3 for JOD, 0 for JPY). Defaults to 2 for unknown codes.
int currencyExponent(String currencyCode) {
  switch (currencyCode.trim().toUpperCase()) {
    case 'JOD':
    case 'KWD':
    case 'BHD':
    case 'OMR':
    case 'TND':
      return 3;
    case 'JPY':
    case 'KRW':
      return 0;
    default:
      return 2;
  }
}

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
String formatMinorUnits(int minorUnits, String currencyCode) {
  final exponent = currencyExponent(currencyCode);
  final isNegative = minorUnits < 0;
  final absolute = isNegative ? -minorUnits : minorUnits;
  final scale = _pow10(exponent);
  final whole = absolute ~/ scale;
  final fraction = absolute % scale;
  final sign = isNegative ? '-' : '';
  if (exponent == 0) return '$sign$whole';
  final fractionText = fraction.toString().padLeft(exponent, '0');
  return '$sign$whole.$fractionText';
}

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
