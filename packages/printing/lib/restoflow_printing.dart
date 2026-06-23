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
/// The print layer never computes/formats money (D-007/D-008) and performs no
/// Arabic/Hebrew shaping/RTL (RF-073). Routing (RF-072), receipt templates
/// (RF-073), the drawer-kick trigger (RF-074), and the server reprint-audit RPC
/// live elsewhere.
library;

export 'src/codec/print_document_codec.dart';
export 'src/escpos/escpos_command_builder.dart';
export 'src/escpos/escpos_print_adapter.dart';
export 'src/print_adapter.dart';
export 'src/print_document.dart';
export 'src/print_result.dart';
export 'src/printer.dart';
export 'src/printer_profile.dart';
export 'src/spool/print_job.dart';
export 'src/spool/print_job_state.dart';
export 'src/spool/print_spool.dart';
export 'src/spool/print_spool_store.dart';
export 'src/spool/reprint_audit_sink.dart';
export 'src/transport/in_memory_print_transport.dart';
export 'src/transport/print_transport.dart';
