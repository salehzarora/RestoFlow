/// Parses a typed cash amount (e.g. `"50"`, `"50.00"`, `"50.5"`) into integer
/// minor units (e.g. `5000`, `5050`) — RF-116.
///
/// Money is integer minor units everywhere (DECISION D-007); there is NO
/// floating-point parsing. The string is split on the decimal point and the
/// fractional part is padded/validated as digits, so `"50.5"` → `5050` with no
/// `double` ever involved. Returns null for empty / negative / malformed input
/// or for more fractional digits than the currency allows.
int? parseCashToMinor(String raw, {int fractionDigits = 2}) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // Optional whole digits, an optional single decimal point, optional fraction.
  final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(s);
  if (match == null) return null;

  // Bound the whole part so the integer-minor result stays exact on every
  // target (a JS-`double` int on web is only safe to 2^53). 12 digits is far
  // beyond any real cash tender and keeps `whole * 10^digits` well within range.
  if (match.group(1)!.length > 12) return null;

  final whole = int.parse(match.group(1)!);
  final fracRaw = match.group(2);
  if (fracRaw != null && fracRaw.length > fractionDigits) return null;

  final frac = (fracRaw ?? '').padRight(fractionDigits, '0');
  final fracValue = frac.isEmpty ? 0 : int.parse(frac);
  return whole * _pow10(fractionDigits) + fracValue;
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
