import 'package:restoflow_currency/restoflow_currency.dart' as currency;

/// Parses a typed cash amount (e.g. `"50"`, `"50.00"`, `"50.5"`) into integer
/// minor units (e.g. `5000`, `5050`) — RF-116.
///
/// Money is integer minor units everywhere (DECISION D-007); there is NO
/// floating-point parsing. Returns null for empty / negative / malformed input
/// or for more fractional digits than the currency allows — it REJECTS rather
/// than rounds, because a rounded tender is a wrong drawer.
///
/// OPS-043 Phase 2: the number of fractional digits now comes from the
/// CURRENCY, not from a hardcoded 2. This is the path that could corrupt real
/// money rather than merely mis-display it: at a JPY till, `"1000"` parsed with
/// two decimals books 100,000 yen for a 1,000 yen note, and at a KWD till it is
/// wrong by 10x in the other direction. The parsing itself lives in
/// `packages/currency`; this wrapper exists so the POS call sites keep reading
/// as cash entry.
///
/// [currencyCode] is required for money. The one caller that is NOT money —
/// the discount sheet parsing a PERCENTAGE into basis points — passes
/// [fractionDigits] explicitly instead, and must keep doing so: a percentage
/// has two decimals in every currency on earth.
int? parseCashToMinor(
  String raw, {
  String? currencyCode,
  int? fractionDigits,
}) => currency.parseCashToMinor(
  raw,
  currencyCode,
  exponentOverride: fractionDigits,
);
