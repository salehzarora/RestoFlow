/// KIOSK-PRINT-114B.5A: the POS kitchen-ticket BYTES builder MOVED VERBATIM to
/// `restoflow_feature_kitchen` (`kitchen_print.dart`) so the POS direct print,
/// the POS manual reprint, the POS printer-only drain and the kiosk claimed
/// print all encode the ONE canonical ticket through the same seam. This shim
/// keeps the established import path; behavior is unchanged.
///
/// ORDER-EDIT-001F: it also re-exports the CHANGE-SLIP bytes builder, so the
/// POS direct slip and the spool's decoded slip share one encoder.
///
/// Web-safe as before: `restoflow_feature_kitchen/kitchen_print.dart` reaches
/// only the dedicated, drift-free dispatch document library of data_local.
library;

export 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show renderKitchenTicketBytes, renderOrderChangeSlipBytes;
