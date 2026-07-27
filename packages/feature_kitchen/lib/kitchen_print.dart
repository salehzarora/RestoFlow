/// KITCHEN-PRINT-DUAL-001B — the shared kitchen-ticket document model + the ONE
/// layout builder, exposed as a DEDICATED library (deliberately NOT re-exported
/// from the package barrel) so its `PrintDocument` never collides with
/// `restoflow_printing`'s `PrintDocument` for the many callers that import both.
///
/// The KDS (`buildKdsTicketDocument`) and the POS direct kitchen print both build
/// the same [KdsTicketView] and render it through [buildKdsTicketPrintDocument]
/// + [kitchenTicketToEscPosDocument], so a ticket printed straight from the POS
/// carries the SAME operational detail as one printed from the KDS. Money-free
/// (SECURITY T-003).
library;

export 'src/print/kds_ticket_print_builder.dart';
export 'src/print/kitchen_print_document.dart';
