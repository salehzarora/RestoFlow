/// WHICH currencies a human may actually pick, as opposed to which ones the
/// catalog can render.
///
/// D2 (OPS-043) sets a hard ordering rule: a currency may NOT appear in the
/// selector until display + input + cash/payment parsing are proven safe for
/// its exponent class. Phase 1 ships the shared module but the POS still
/// carries hardcoded 2-decimal assumptions (`parseCashToMinor(fractionDigits:
/// 2)`, the `% 100` / `~/ 100` cash sheet, the 100-minor dashboard axis), so
/// only exponent-2 currencies are offerable. Phase 2 replaces those sites and
/// flips [kCurrencySelectorScope] to [CurrencySelectorScope.fullIso] — one
/// constant, in code, exactly as D2 demands.
library;

import 'currency_catalog.dart';

/// How wide the operating-currency selector is allowed to be.
enum CurrencySelectorScope {
  /// Phase 1: only currencies with two minor-unit digits, the single class
  /// every existing display/entry site already handles correctly.
  exponent2Only,

  /// Phase 2 onward: the full spendable ISO-4217 catalog.
  fullIso,
}

/// THE GATE. Flip this to [CurrencySelectorScope.fullIso] in the same change
/// that lands Phase 2's replacement of every hardcoded exponent site — not
/// before, and never as a config value a deployment could get wrong.
const CurrencySelectorScope kCurrencySelectorScope =
    CurrencySelectorScope.exponent2Only;

/// Fund, metal, supranational and reserved codes: real ISO-4217 entries that a
/// restaurant cannot be paid in. They stay in the catalog so a stored value
/// still renders, but they are never offered for selection.
const Set<String> kNonTradableCurrencyCodes = <String>{
  // Fund / index units
  'BOV', 'CHE', 'CHW', 'CLF', 'COU', 'MXV', 'USN', 'UYI', 'UYW',
  // Precious metals
  'XAU', 'XAG', 'XPT', 'XPD',
  // Supranational / bond-market / reserved
  'XDR', 'XSU', 'XUA', 'XBA', 'XBB', 'XBC', 'XBD', 'XTS', 'XXX',
};

/// True when [code] may appear in a currency selector under [scope].
bool isSelectableCurrency(
  String? code, {
  CurrencySelectorScope scope = kCurrencySelectorScope,
}) {
  final info = lookupCurrency(code);
  if (info == null) return false;
  if (!info.hasMinorUnit) return false;
  if (kNonTradableCurrencyCodes.contains(info.code)) return false;
  return switch (scope) {
    CurrencySelectorScope.exponent2Only => info.exponent == 2,
    CurrencySelectorScope.fullIso => true,
  };
}

/// The selectable currencies under [scope], sorted by code.
List<CurrencyInfo> selectableCurrencies({
  CurrencySelectorScope scope = kCurrencySelectorScope,
}) {
  final codes =
      isoCurrencies.keys
          .where((code) => isSelectableCurrency(code, scope: scope))
          .toList(growable: false)
        ..sort();
  return codes.map((code) => isoCurrencies[code]!).toList(growable: false);
}

/// A selector label: the code, plus its glyph when there is an unambiguous
/// one — `ILS (₪)`, `CHF`. Deliberately NOT a translated currency NAME: the
/// ARB files would then need ~180 entries per language, and a code plus its
/// own glyph is what a restaurant owner recognizes anyway.
String currencySelectorLabel(String? code) {
  final info = lookupCurrency(code);
  if (info == null) return normalizeCurrencyCode(code) ?? '';
  final symbol = info.symbol;
  return symbol == null ? info.code : '${info.code} ($symbol)';
}

/// [currencySelectorLabel] wrapped in a Unicode LTR isolate.
///
/// A currency label is Latin text with a glyph in brackets. Dropped raw into an
/// Arabic or Hebrew sentence, the bidi algorithm reorders the brackets and the
/// two labels of a "from → to" line visually swap their parentheses — the owner
/// then reads a money change they cannot parse. The isolate pins each label to
/// its own direction without changing the surrounding sentence.
String currencySelectorLabelIsolated(String? code) =>
    '\u2066${currencySelectorLabel(code)}\u2069';
