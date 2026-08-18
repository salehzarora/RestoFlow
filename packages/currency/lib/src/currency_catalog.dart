/// The ISO-4217 catalog: code -> minor-unit exponent + a display symbol ONLY
/// where that symbol is unambiguous.
///
/// D2 (OPS-043): the target is FULL ISO-4217, never a permanent allowlist, and
/// a glyph is NEVER invented. A currency the catalog has no unambiguous symbol
/// for renders as its code ("CHF 25.00", "1500 KWD") — which is what every
/// real-world receipt does for those currencies anyway.
library;

/// One ISO-4217 currency.
///
/// [exponent] is the number of minor-unit digits (0, 2, 3, and 4 all occur in
/// the standard). [symbol] is null whenever no glyph is unambiguous for this
/// code — the formatter then falls back to the code itself.
class CurrencyInfo {
  const CurrencyInfo(
    this.code,
    this.exponent, {
    this.symbol,
    this.hasMinorUnit = true,
  });

  /// Uppercase ISO-4217 alphabetic code.
  final String code;

  /// Minor-unit digits. Codes the standard marks "N.A." (metals, funds, test
  /// codes) carry 0 together with [hasMinorUnit] false.
  final int exponent;

  /// An unambiguous display glyph, or null when the code must be shown instead.
  final String? symbol;

  /// False for the codes ISO-4217 marks as having no minor unit at all. A
  /// formatter must never print a fraction for these, which is already implied
  /// by [exponent] 0 — the flag exists so callers can tell "0 decimals like
  /// JPY" apart from "not really a spendable currency".
  final bool hasMinorUnit;

  @override
  String toString() => 'CurrencyInfo($code, exponent: $exponent)';
}

/// The exponent used for a code the catalog does not know.
///
/// 2 matches every pre-existing table in this repo (POS, dashboard, printing,
/// feature_menu all defaulted to 2), so absorbing them in Phase 2 changes no
/// output for an unknown code. A RETIRED code stored on a historical row
/// (HRK, SLL, MRO, STD, VEF, ZWL, BYR...) therefore still renders rather than
/// throwing — D3 forbids relabelling old money, so old money must stay
/// printable.
const int kDefaultCurrencyExponent = 2;

/// Ambiguous glyphs are deliberately absent.
///
/// `$` belongs to a dozen currencies, `¥` to two, `£` to several, `kr` to four.
/// Only codes whose symbol is unambiguous IN PRACTICE for a restaurant receipt
/// carry one. `USD -> $` and `EUR -> €` and `ILS -> ₪` are kept because they
/// are already what this product prints today and Phase 2 must stay
/// pixel-identical for them.
const Map<String, String> _symbols = <String, String>{
  'ILS': '₪',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
};

/// Codes with no minor unit in circulation (ISO exponent 0).
const List<String> _exponent0 = <String>[
  'BIF',
  'CLP',
  'DJF',
  'GNF',
  'ISK',
  'JPY',
  'KMF',
  'KRW',
  'PYG',
  'RWF',
  'UGX',
  'UYI',
  'VND',
  'VUV',
  'XAF',
  'XOF',
  'XPF',
];

/// Codes with three minor-unit digits (ISO exponent 3).
const List<String> _exponent3 = <String>[
  'BHD',
  'IQD',
  'JOD',
  'KWD',
  'LYD',
  'OMR',
  'TND',
];

/// Fund/index units with four minor-unit digits (ISO exponent 4).
const List<String> _exponent4 = <String>['CLF', 'UYW'];

/// Codes ISO-4217 marks "N.A." — precious metals, supranational units and the
/// reserved test/no-transaction codes. They are catalogued so a stored value
/// can still be rendered honestly, never so they can be sold in.
const List<String> _noMinorUnit = <String>[
  'XAU',
  'XAG',
  'XPT',
  'XPD',
  'XDR',
  'XSU',
  'XUA',
  'XBA',
  'XBB',
  'XBC',
  'XBD',
  'XTS',
  'XXX',
];

/// Every other active ISO-4217 code — all exponent 2.
const List<String> _exponent2 = <String>[
  'AED',
  'AFN',
  'ALL',
  'AMD',
  'ANG',
  'AOA',
  'ARS',
  'AUD',
  'AWG',
  'AZN',
  'BAM',
  'BBD',
  'BDT',
  'BGN',
  'BMD',
  'BND',
  'BOB',
  'BOV',
  'BRL',
  'BSD',
  'BTN',
  'BWP',
  'BYN',
  'BZD',
  'CAD',
  'CDF',
  'CHE',
  'CHF',
  'CHW',
  'CNY',
  'COP',
  'COU',
  'CRC',
  'CUP',
  'CVE',
  'CZK',
  'DKK',
  'DOP',
  'DZD',
  'EGP',
  'ERN',
  'ETB',
  'EUR',
  'FJD',
  'FKP',
  'GBP',
  'GEL',
  'GHS',
  'GIP',
  'GMD',
  'GTQ',
  'GYD',
  'HKD',
  'HNL',
  'HTG',
  'HUF',
  'IDR',
  'ILS',
  'INR',
  'IRR',
  'JMD',
  'KES',
  'KGS',
  'KHR',
  'KPW',
  'KYD',
  'KZT',
  'LAK',
  'LBP',
  'LKR',
  'LRD',
  'LSL',
  'MAD',
  'MDL',
  'MGA',
  'MKD',
  'MMK',
  'MNT',
  'MOP',
  'MRU',
  'MUR',
  'MVR',
  'MWK',
  'MXN',
  'MXV',
  'MYR',
  'MZN',
  'NAD',
  'NGN',
  'NIO',
  'NOK',
  'NPR',
  'NZD',
  'PAB',
  'PEN',
  'PGK',
  'PHP',
  'PKR',
  'PLN',
  'QAR',
  'RON',
  'RSD',
  'RUB',
  'SAR',
  'SBD',
  'SCR',
  'SDG',
  'SEK',
  'SGD',
  'SHP',
  'SLE',
  'SOS',
  'SRD',
  'SSP',
  'STN',
  'SVC',
  'SYP',
  'SZL',
  'THB',
  'TJS',
  'TMT',
  'TOP',
  'TRY',
  'TTD',
  'TWD',
  'TZS',
  'UAH',
  'USD',
  'USN',
  'UYU',
  'UZS',
  'VED',
  'VES',
  'WST',
  'XCD',
  'XCG',
  'YER',
  'ZAR',
  'ZMW',
  'ZWG',
];

Map<String, CurrencyInfo> _buildCatalog() {
  final catalog = <String, CurrencyInfo>{};
  void add(String code, int exponent, {bool hasMinorUnit = true}) {
    catalog[code] = CurrencyInfo(
      code,
      exponent,
      symbol: _symbols[code],
      hasMinorUnit: hasMinorUnit,
    );
  }

  for (final code in _exponent0) {
    add(code, 0);
  }
  for (final code in _exponent2) {
    add(code, 2);
  }
  for (final code in _exponent3) {
    add(code, 3);
  }
  for (final code in _exponent4) {
    add(code, 4);
  }
  for (final code in _noMinorUnit) {
    add(code, 0, hasMinorUnit: false);
  }
  return Map<String, CurrencyInfo>.unmodifiable(catalog);
}

/// The whole catalog, keyed by uppercase code.
final Map<String, CurrencyInfo> isoCurrencies = _buildCatalog();

/// Normalizes user/wire input to an uppercase 3-letter code, or null.
String? normalizeCurrencyCode(String? raw) {
  if (raw == null) return null;
  final code = raw.trim().toUpperCase();
  return _codePattern.hasMatch(code) ? code : null;
}

final RegExp _codePattern = RegExp(r'^[A-Z]{3}$');

/// True when [raw] is a syntactically valid ISO-4217 alphabetic code. Shape
/// only — this deliberately does NOT require catalog membership, because the
/// server contract is the same regex and a historical row may carry a retired
/// code.
bool isValidCurrencyCodeShape(String? raw) =>
    normalizeCurrencyCode(raw) != null;

/// The catalog entry for [code], or null when unknown/malformed.
CurrencyInfo? lookupCurrency(String? code) {
  final normalized = normalizeCurrencyCode(code);
  return normalized == null ? null : isoCurrencies[normalized];
}

/// Minor-unit digits for [code], falling back to [kDefaultCurrencyExponent]
/// for anything unknown or malformed. Never throws: a formatter that throws on
/// a stored historical code would take a whole screen down.
int currencyExponent(String? code) =>
    lookupCurrency(code)?.exponent ?? kDefaultCurrencyExponent;
