/// RestoFlow printing package - the replaceable printing adapter (RF-070).
///
/// A pure-Dart, hardware-free printing port (DECISION D-009, PRINTERS spec §13):
///   * a render-neutral [PrintDocument] (text/feed/cut/drawer-kick/raster lines);
///   * a [PrinterProfile] (58/80mm + capabilities + code page);
///   * a [PrintAdapter] port with the first ESC/POS implementation
///     ([EscPosPrintAdapter] over [EscPosCommandBuilder]) producing deterministic
///     bytes;
///   * a [PrintTransport] port with an [InMemoryPrintTransport] (real
///     network/USB/Bluetooth deferred — `transportFor` throws clearly);
///   * a substitutable [Printer] facade ([AdapterPrinter] / [FakePrinter]).
///
/// The print layer never computes or formats money (D-007/D-008 — text is
/// pre-formatted by the caller) and performs no Arabic/Hebrew shaping/RTL
/// (raster is RF-073). Spool/job lifecycle (RF-071), routing (RF-072), receipt
/// templates (RF-073), and the drawer-kick trigger (RF-074) live elsewhere.
library;

export 'src/escpos/escpos_command_builder.dart';
export 'src/escpos/escpos_print_adapter.dart';
export 'src/print_adapter.dart';
export 'src/print_document.dart';
export 'src/print_result.dart';
export 'src/printer.dart';
export 'src/printer_profile.dart';
export 'src/transport/in_memory_print_transport.dart';
export 'src/transport/print_transport.dart';
