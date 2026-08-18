/// The ONE display formatter and major->minor parser for RestoFlow money.
///
/// Every existing site (POS `MoneyFormatter`, the dashboard's copy of it,
/// `ReceiptMoneyFormat`, `feature_menu`'s `minor_money`, `parseCashToMinor`)
/// is expressible through this module WITHOUT changing a single character of
/// its current output — that is the whole point of building it before Phase 2
/// replaces them. The parity is pinned by golden tests.
///
/// Nothing here rounds. Money is integer minor units (DECISION D-007); a value
/// that does not fit the currency's exponent is REJECTED by the parser, never
/// silently rounded.
library;

import 'currency_catalog.dart';

/// How the currency identifies itself in formatted output.
enum CurrencySymbolStyle {
  /// The unambiguous glyph as a prefix with no space (`₪1234.56`), falling
  /// back to the CODE as a prefix with a space (`CHF 25.00`) when the catalog
  /// has no unambiguous glyph. D2: never invent a glyph.
  symbolOrCode,

  /// The code as a suffix (`42.42 ILS`) — the receipt style, which is
  /// deliberately symbol-free so a thermal printer's code page can never turn
  /// a glyph into a question mark.
  codeSuffix,

  /// Digits only (`42.42`).
  bare,
}

/// Formats [amountMinor] of [currencyCode].
///
/// [grouped] is OFF by default: no formatter in this repo groups thousands
/// today, and Phase 2 must be able to swap this module in with byte-identical
/// output. Turn it on deliberately at a call site that wants `1,500 KWD`.
String formatCurrencyMinor(
  int amountMinor,
  String? currencyCode, {
  CurrencySymbolStyle style = CurrencySymbolStyle.symbolOrCode,
  bool grouped = false,
  int? exponentOverride,
}) {
  final info = lookupCurrency(currencyCode);
  final exponent =
      exponentOverride ?? info?.exponent ?? kDefaultCurrencyExponent;
  final number = _digits(amountMinor, exponent, grouped: grouped);
  // A zero amount is never signed, so -0 minor units cannot print "-0.00".
  final sign = amountMinor < 0 ? '-' : '';
  final code = normalizeCurrencyCode(currencyCode);

  switch (style) {
    case CurrencySymbolStyle.bare:
      return '$sign$number';
    case CurrencySymbolStyle.codeSuffix:
      return code == null ? '$sign$number' : '$sign$number $code';
    case CurrencySymbolStyle.symbolOrCode:
      final symbol = info?.symbol;
      if (symbol != null) return '$sign$symbol$number';
      // Unknown or ambiguous: the CODE carries the identity, never a guess.
      return code == null ? '$sign$number' : '$code $sign$number';
  }
}

/// A signed delta (modifier price, adjustment): `+₪2.50` / `−₪2.50`.
///
/// The negative uses the typographic minus U+2212, matching what the POS
/// already prints for deltas; zero renders as `+`, so a caller that wants
/// "free" must branch before calling.
String formatSignedCurrencyMinor(
  int deltaMinor,
  String? currencyCode, {
  CurrencySymbolStyle style = CurrencySymbolStyle.symbolOrCode,
  bool grouped = false,
}) =>
    (deltaMinor < 0 ? '−' : '+') +
    formatCurrencyMinor(
      deltaMinor.abs(),
      currencyCode,
      style: style,
      grouped: grouped,
    );

String _digits(int amountMinor, int exponent, {required bool grouped}) {
  final absolute = amountMinor.abs();
  if (exponent <= 0) {
    return _group(absolute.toString(), grouped);
  }
  final scale = _pow10(exponent);
  final whole = absolute ~/ scale;
  final fraction = (absolute % scale).toString().padLeft(exponent, '0');
  return '${_group(whole.toString(), grouped)}.$fraction';
}

String _group(String whole, bool grouped) {
  if (!grouped || whole.length <= 3) return whole;
  final buffer = StringBuffer();
  final firstGroup = whole.length % 3 == 0 ? 3 : whole.length % 3;
  buffer.write(whole.substring(0, firstGroup));
  for (var i = firstGroup; i < whole.length; i += 3) {
    buffer
      ..write(',')
      ..write(whole.substring(i, i + 3));
  }
  return buffer.toString();
}

int _pow10(int exponent) {
  var value = 1;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}

/// Parses a MAJOR-unit string into integer minor units for [currencyCode].
///
/// Returns null — never a rounded or partial value — for anything it cannot
/// represent exactly:
///   * more fractional digits than the currency has (`1.234` in USD),
///   * a fraction at all for a 0-decimal currency (`100.5` in JPY),
///   * a negative when [allowNegative] is false,
///   * a bare `.50` when [allowLeadingDot] is false, or a trailing `50.`,
///   * a whole part longer than [maxWholeDigits] (JS integer safety),
///   * grouping separators, currency glyphs, spaces or any other character.
///
/// The defaults are the STRICT cash-entry contract. `feature_menu`'s editor
/// parser additionally accepts negatives and a leading dot, so it passes those
/// flags explicitly.
int? parseMajorToMinor(
  String input,
  String? currencyCode, {
  bool allowNegative = false,
  bool allowLeadingDot = false,
  int maxWholeDigits = 12,
  int? exponentOverride,
}) {
  final exponent = exponentOverride ?? currencyExponent(currencyCode);
  var text = input.trim();
  if (text.isEmpty) return null;

  var negative = false;
  if (text.startsWith('-')) {
    if (!allowNegative) return null;
    negative = true;
    text = text.substring(1);
  }
  if (allowLeadingDot && text.startsWith('.')) {
    text = '0$text';
  }

  final match = _numberPattern.firstMatch(text);
  if (match == null) return null;

  final wholeText = match.group(1)!;
  if (wholeText.length > maxWholeDigits) return null;
  final fractionText = match.group(2);
  if (fractionText != null && fractionText.length > exponent) return null;

  final whole = int.tryParse(wholeText);
  if (whole == null) return null;
  final fraction = exponent == 0
      ? 0
      : int.parse((fractionText ?? '').padRight(exponent, '0'));

  final minor = whole * _pow10(exponent) + fraction;
  return negative ? -minor : minor;
}

final RegExp _numberPattern = RegExp(r'^(\d+)(?:\.(\d+))?$');

/// Cash tender / counted-drawer entry: the strict parser, no negatives and no
/// leading dot. Named so the intent is legible at the till call sites.
int? parseCashToMinor(
  String input,
  String? currencyCode, {
  int? exponentOverride,
}) =>
    parseMajorToMinor(input, currencyCode, exponentOverride: exponentOverride);

/// Quick-tender buttons, expressed in MINOR units of [currencyCode].
///
/// The steps are chosen per exponent so a till never offers a meaningless
/// amount: 20 major units is a sane note in a 2-decimal currency and in JPY it
/// is not — hence the per-class ladders rather than one hardcoded list scaled
/// by 100 (which is exactly the bug Phase 2 has to remove from the POS).
List<int> quickAmountStepsMinor(String? currencyCode) {
  final exponent = currencyExponent(currencyCode);
  final scale = _pow10(exponent);
  final majors = switch (exponent) {
    0 => const <int>[500, 1000, 5000, 10000],
    3 => const <int>[1, 5, 10, 20],
    _ => const <int>[10, 20, 50, 100],
  };
  return majors.map((major) => major * scale).toList(growable: false);
}
