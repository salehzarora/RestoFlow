/// Integer, floating-point-FREE tax math for the POS (RF-117).
///
/// Tax is computed in integer minor units from an integer BASIS-POINT rate
/// (1 bp = 0.01%; 1700 bp = 17.00%). There is NO `double`/`num` anywhere here —
/// money and rates are integers only (DECISION D-007). This build wires the
/// `exclusive` mode: the tax is ADDED on top of the (post-discount) base.
///
/// Rounding is HALF-AWAY-FROM-ZERO, matching the server's `round()` on a numeric
/// transient in `app.apply_discount` / the money engine (MONEY_AND_TAX_SPEC).
library;

/// [bp] basis points of [baseMinor] as integer minor units, rounded
/// HALF-AWAY-FROM-ZERO. The shared primitive behind both the exclusive tax and
/// the demo percentage discount (which the server computes with the identical
/// `round(base * bp / 10000)` on a numeric transient).
///
/// Formula (positive base): `(base * bp + 5000) ~/ 10000` — the `+ 5000` (half
/// of the 10000 divisor) turns truncating integer division into round-half-up,
/// which for a non-negative base is round-half-away-from-zero. A negative base
/// (never produced by this flow, but handled for correctness) rounds
/// symmetrically. Example: `percentMinor(10000, 1700) == 1700`;
/// `percentMinor(9999, 1700) == 1700` (1699.83 → 1700). No float is ever
/// constructed.
int percentMinor(int baseMinor, int bp) {
  if (bp <= 0 || baseMinor == 0) return 0;
  final product = baseMinor * bp;
  if (product >= 0) {
    return (product + 5000) ~/ 10000;
  }
  // Symmetric rounding for a (theoretical) negative base.
  return -((-product + 5000) ~/ 10000);
}

/// The tax (integer minor units) on [baseMinor] at [rateBp] basis points,
/// rounded HALF-AWAY-FROM-ZERO. Exclusive mode: this is the amount ADDED on top.
int taxMinorExclusive(int baseMinor, int rateBp) =>
    percentMinor(baseMinor, rateBp);

/// The exclusive-mode grand total (integer minor units): the post-discount
/// [baseMinor] plus the tax at [rateBp]. Kept alongside [taxMinorExclusive] so
/// callers never re-derive the addition.
int grandWithExclusiveTax(int baseMinor, int rateBp) =>
    baseMinor + taxMinorExclusive(baseMinor, rateBp);

/// Formats an integer basis-point rate as a percent string for the tax line,
/// e.g. `1700 -> "17%"`, `1750 -> "17.5%"`, `1733 -> "17.33%"`, `1705 ->
/// "17.05%"`. A number + '%' symbol (not translatable copy); callers build it
/// into a local string so the no-hardcoded-strings guard is not tripped. Integer
/// math only — no float.
String formatRateBpPercent(int rateBp) {
  final whole = rateBp ~/ 100;
  final frac = rateBp % 100;
  if (frac == 0) return '$whole%';
  var fracStr = frac.toString().padLeft(2, '0');
  while (fracStr.endsWith('0')) {
    fracStr = fracStr.substring(0, fracStr.length - 1);
  }
  return '$whole.$fracStr%';
}
