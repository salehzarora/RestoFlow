/// Pure, client-side menu field validators (RF-111). They MIRROR the RF-109
/// server rules for fast inline feedback; the server re-validates every write
/// and remains the source of truth. Each returns a [MenuFieldError] code (never
/// a hardcoded message) so the UI renders a localized string.
library;

import '../models/menu_field_error.dart';

final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');

/// `name` must be non-blank.
MenuFieldError? validateName(String name) =>
    name.trim().isEmpty ? MenuFieldError.blank : null;

/// Item base price: an integer minor-unit amount `>= 0`. A `null` [minor] means
/// the operator's input did not parse to an integer.
MenuFieldError? validateBasePriceMinor(int? minor) {
  if (minor == null) return MenuFieldError.notAnInteger;
  if (minor < 0) return MenuFieldError.negativePrice;
  return null;
}

/// Size/variant/option price delta: a SIGNED integer (any int is valid). A
/// `null` [minor] means the input did not parse to an integer.
MenuFieldError? validatePriceDeltaMinor(int? minor) =>
    minor == null ? MenuFieldError.notAnInteger : null;

/// Currency code must match `^[A-Z]{3}$`.
MenuFieldError? validateCurrencyCode(String code) =>
    _currencyPattern.hasMatch(code) ? null : MenuFieldError.invalidCurrency;

/// `selection_type` is `single` or `multiple`.
MenuFieldError? validateSelectionType(String type) =>
    (type == 'single' || type == 'multiple')
    ? null
    : MenuFieldError.invalidSelectionType;

/// `min_select` must be `>= 0`.
MenuFieldError? validateMinSelect(int minSelect) =>
    minSelect < 0 ? MenuFieldError.negativeMinSelect : null;

/// `max_select` is either `null` or `>= min_select` (and never negative). The
/// client adds the `>= min_select` rule on top of the server's `>= 0` rule.
MenuFieldError? validateMaxSelect(int? maxSelect, int minSelect) {
  if (maxSelect == null) return null;
  if (maxSelect < 0) return MenuFieldError.negativeMinSelect;
  if (maxSelect < minSelect) return MenuFieldError.maxLessThanMin;
  return null;
}
