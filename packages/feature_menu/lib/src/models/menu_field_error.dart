/// A client-side field validation error code (RF-111).
///
/// Validators return one of these (never a hardcoded message) so the UI can
/// render a localized string (ar/he/en). The client rules MIRROR the RF-109
/// server rules so the operator gets fast feedback; the server remains the
/// source of truth and re-validates every write.
enum MenuFieldError {
  /// A required text field (e.g. `name`) is blank.
  blank,

  /// A price could not be parsed as an integer minor-unit amount.
  notAnInteger,

  /// An item base price is negative (`base_price_minor` must be `>= 0`).
  negativePrice,

  /// A currency code does not match `^[A-Z]{3}$`.
  invalidCurrency,

  /// `selection_type` is neither `single` nor `multiple`.
  invalidSelectionType,

  /// `min_select` is negative.
  negativeMinSelect,

  /// `max_select` is below `min_select`.
  maxLessThanMin,
}
