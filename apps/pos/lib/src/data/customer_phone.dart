/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 — the OPTIONAL order-time customer phone.
///
/// ONE central validator/normalizer for the whole POS, mirroring the server
/// contract (`app.is_valid_customer_phone` + the `orders_customer_phone_valid_chk`
/// CHECK): a display string of digits / space / `+` / `-` / `(` / `)`, 1..32
/// characters, carrying at least 5 digits. The phone is OPTIONAL and never gates
/// submit; an empty/whitespace input is acceptable (stored as null). A non-empty
/// input that is not a storable phone is rejected so the UI can show a localized
/// inline error and block THAT submit — the server re-validates as defence in
/// depth (an invalid value can never reach an order). Non-money display text; it
/// is deliberately kept out of any log/toString.
library;

/// The max stored/display length — mirrors the server's 32-char cap. The POS
/// input field also caps typing at this length.
const int kCustomerPhoneMaxLength = 32;

/// The minimum number of DIGITS a non-empty phone must carry (mirrors the
/// server's `>= 5` digit rule). Punctuation and spaces do not count.
const int kCustomerPhoneMinDigits = 5;

/// Allowed characters (anchored): digits, space, `+`, `-`, `(`, `)`. No letters,
/// control characters, tabs or newlines. Mirrors the server regex `^[0-9 ()+-]+$`.
final RegExp _kCustomerPhoneAllowed = RegExp(r'^[0-9 ()+-]+$');
final RegExp _kNonDigit = RegExp(r'[^0-9]');

/// Why a non-empty phone is not storable — drives the localized inline error.
enum CustomerPhoneError { unsupportedCharacters, tooFewDigits, tooLong }

/// The result of validating a raw phone input. Used by the cart field (for the
/// inline error) and the submit guard (to block an invalid non-empty phone).
class CustomerPhoneValidation {
  const CustomerPhoneValidation(this.value, this.error);

  /// The trimmed display value, or null when the input is empty/whitespace.
  final String? value;

  /// The reason the input is rejected, or null when it is valid OR empty.
  final CustomerPhoneError? error;

  /// True when the input is a storable phone OR empty — i.e. it does NOT block
  /// submit. Only a non-empty, malformed input is unacceptable.
  bool get isAcceptable => error == null;
}

/// Validates [raw] against the phone contract. An empty/whitespace input is
/// acceptable (value null, error null) — the phone is optional. A non-empty input
/// is either valid (value = trimmed, error null) or rejected (value = trimmed,
/// error set) so the field can echo what was typed alongside the error.
CustomerPhoneValidation validateCustomerPhone(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return const CustomerPhoneValidation(null, null);
  }
  if (trimmed.length > kCustomerPhoneMaxLength) {
    return CustomerPhoneValidation(trimmed, CustomerPhoneError.tooLong);
  }
  if (!_kCustomerPhoneAllowed.hasMatch(trimmed)) {
    return CustomerPhoneValidation(
      trimmed,
      CustomerPhoneError.unsupportedCharacters,
    );
  }
  if (trimmed.replaceAll(_kNonDigit, '').length < kCustomerPhoneMinDigits) {
    return CustomerPhoneValidation(trimmed, CustomerPhoneError.tooFewDigits);
  }
  return CustomerPhoneValidation(trimmed, null);
}

/// The value to STORE/SEND for [raw]: the trimmed display form when valid, else
/// null (empty OR invalid). The POS UI blocks submit on an invalid non-empty
/// phone and the server re-validates, so an invalid value never reaches an order.
String? normalizeCustomerPhone(String? raw) {
  final v = validateCustomerPhone(raw);
  return v.error == null ? v.value : null;
}
