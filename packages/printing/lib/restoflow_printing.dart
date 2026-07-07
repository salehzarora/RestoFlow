/// RestoFlow printing package - the replaceable printing adapter (RF-070) + the
/// durable local print-job spool (RF-071).
///
/// RF-070: a pure-Dart, hardware-free printing port (DECISION D-009, PRINTERS
/// spec §13) — a render-neutral [PrintDocument], a [PrintAdapter] port with the
/// ESC/POS implementation, [PrinterProfile], a [PrintTransport] port + in-memory
/// transport, and a substitutable [Printer] facade.
///
/// RF-071: a durable local print SPOOL on top — a [PrintJob] model, the
/// [PrintJobState] machine (incl. crash-recovery `possiblyPrinted`), a
/// [PrintSpoolStore] port (+ in-memory) with the Drift impl in `data_local`, the
/// [PrintSpool] engine (idempotent enqueue, retry/backoff, abandon), a
/// [PrintDocumentCodec] for durable persistence (A4), and a [ReprintAuditSink]
/// port (the literal server audit_events write is a deferred follow-up, A1).
///
/// The print layer may FORMAT already-supplied integer minor-unit values for
/// display (RF-073 receipts), but it never CALCULATES, recomputes, or derives
/// money/tax totals — authoritative amounts are provided by the caller
/// (D-007/D-008). The ESC/POS layer performs no Arabic/Hebrew shaping/RTL; that
/// rasterization lives in packages/l10n (RF-073). Routing (RF-072), receipt
/// templates (RF-073), the drawer-kick trigger (RF-074), and the server
/// reprint-audit RPC live elsewhere.
library;

// RF-115: the LOCAL print-bridge transport — a loopback HTTP client with honest
// outcomes (accepted / sentToPrinter / failed), a local-only URL guard, a
// package:http seam impl, a PrintTransport adapter, and an encode+submit
// dispatcher. No app CANNOT open raw TCP/USB from web; a bridge is the honest
// path to a physical printer, and "sent to printer" is never claimed unless the
// bridge confirms the transport write.
export 'src/bridge/http_bridge_client.dart';
export 'src/bridge/print_bridge_client.dart';
export 'src/bridge/print_bridge_dispatcher.dart';
export 'src/bridge/print_bridge_transport.dart';
export 'src/codec/print_document_codec.dart';
// ANDROID-002: the on-device ESC/POS "Test print" diagnostic document builder
// (ASCII/English-only, money-free) for the printer-setup Test print button.
export 'src/diagnostics/escpos_test_document.dart';
// RF-074: cash-drawer kick trigger — a narrow input contract + a dispatcher
// that enqueues a one-shot, no-retry `cashDrawer` job (consumes RF-070's
// PrintDrawerKickLine + RF-071 spool + the RF-58 job type/reprint guard).
export 'src/drawer/cash_drawer_kick_dispatcher.dart';
export 'src/drawer/cash_drawer_kick_input.dart';
export 'src/escpos/escpos_command_builder.dart';
export 'src/escpos/escpos_print_adapter.dart';
export 'src/print_adapter.dart';
export 'src/print_document.dart';
export 'src/print_result.dart';
export 'src/printer.dart';
export 'src/printer_profile.dart';
// RF-073: customer receipt printing (ar/he/en, 58/80mm, raster fallback). The
// builder/input/money-formatter/dispatcher are pure-Dart; the real Flutter
// rasterizer implementing ReceiptRasterizer lives in packages/l10n.
export 'src/receipt/customer_receipt_print_builder.dart';
export 'src/receipt/receipt_input.dart';
export 'src/receipt/receipt_money_format.dart';
export 'src/receipt/receipt_print_dispatcher.dart';
export 'src/receipt/receipt_rasterizer.dart';
export 'src/spool/print_job.dart';
export 'src/spool/print_job_state.dart';
export 'src/spool/print_spool.dart';
export 'src/spool/print_spool_store.dart';
export 'src/spool/reprint_audit_sink.dart';
export 'src/transport/in_memory_print_transport.dart';
// ANDROID-002: the real on-device network (Wi-Fi/Ethernet) RAW ESC/POS TCP
// transport (port 9100). Web-safe — direct sockets link only on native.
export 'src/transport/network_tcp_print_transport.dart';
export 'src/transport/print_transport.dart';
