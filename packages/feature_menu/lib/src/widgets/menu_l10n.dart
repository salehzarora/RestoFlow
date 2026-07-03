import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/menu_field_error.dart';
import '../models/menu_write_failure.dart';

/// Maps domain error codes to localized strings (RF-111) so widgets never hold
/// hardcoded messages.
extension MenuL10n on AppLocalizations {
  /// A localized message for a client-side field validation error.
  String menuFieldErrorText(MenuFieldError error) => switch (error) {
    MenuFieldError.blank => menuErrorRequired,
    MenuFieldError.notAnInteger => menuErrorAmount,
    MenuFieldError.negativePrice => menuErrorNegativePrice,
    MenuFieldError.invalidCurrency => menuErrorCurrency,
    MenuFieldError.invalidSelectionType => menuErrorSelectionType,
    MenuFieldError.negativeMinSelect => menuErrorNegativePrice,
    MenuFieldError.maxLessThanMin => menuErrorMaxLessThanMin,
  };

  /// A localized message for a write failure. Role-denied and generic failures
  /// have dedicated messages; a server-raised validation/scope rejection carries
  /// its own descriptive message (surfaced verbatim, falling back to a generic).
  String menuWriteFailureText(MenuWriteFailure failure) => switch (failure) {
    MenuPermissionDenied() => menuWritePermissionDenied,
    MenuValidationRejected(:final message) =>
      message.isEmpty ? menuWriteProblem : message,
    MenuTransientFailure() => menuWriteProblem,
    MenuServerFailure() => menuWriteProblem,
    MenuInvalidResponseFailure() => menuWriteProblem,
  };

  /// The localized DISPLAY label for a fixed-vocabulary tag wire string
  /// (menu/media sprint). Data stays the stable wire string ('spicy', ...);
  /// only presentation is localized. Unknown values fall back verbatim so a
  /// newer backend never crashes an older client.
  String menuTagText(String tag) => switch (tag) {
    'spicy' => menuTagSpicy,
    'vegetarian' => menuTagVegetarian,
    'popular' => menuTagPopular,
    'new' => menuTagNew,
    _ => tag,
  };

  /// The localized DISPLAY label for an `item_type` wire value; null renders
  /// the "not specified" entry. Unknown values fall back verbatim. (Named
  /// `...Text` — `menuItemTypeLabel` is the generated ARB field-label getter.)
  String menuItemTypeText(String? itemType) => switch (itemType) {
    null => menuItemTypeUnspecified,
    'food' => menuItemTypeFood,
    'drink' => menuItemTypeDrink,
    'side' => menuItemTypeSide,
    'combo' => menuItemTypeCombo,
    'other' => menuItemTypeOther,
    _ => itemType,
  };
}
