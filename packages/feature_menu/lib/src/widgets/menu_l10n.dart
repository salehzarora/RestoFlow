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
}
