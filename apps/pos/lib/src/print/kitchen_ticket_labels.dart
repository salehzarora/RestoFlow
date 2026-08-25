/// KIOSK-PRINT-114B.5A: the kitchen-ticket chrome label mapper MOVED VERBATIM to
/// `restoflow_feature_kitchen` (`kitchen_print.dart`) so the kiosk claimed print
/// and the POS printer-only drain map the SAME l10n keys the POS direct print
/// uses. This shim keeps the established import path; wording is unchanged.
library;

export 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show kitchenTicketPrintLabelsFromL10n;
