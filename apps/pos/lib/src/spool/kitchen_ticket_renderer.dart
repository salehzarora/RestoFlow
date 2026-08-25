/// KIOSK-PRINT-114B.2: the printer_only kitchen ticket renderer was
/// EXTRACTED VERBATIM to the shared restoflow_data_local package (next to
/// its KitchenDispatchDocument payload) so the kiosk claimed-dispatch
/// print uses the exact same renderer. This shim keeps every existing POS
/// import and test byte-untouched (the repo's established re-export
/// pattern, like apps/pos bluetooth_printer.dart).
export 'package:restoflow_data_local/restoflow_data_local.dart'
    show KitchenTicketLabels, KitchenTicketRenderer;
