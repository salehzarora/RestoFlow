import 'dart:typed_data';

import 'print_document.dart';
import 'printer_profile.dart';

/// The replaceable printing port (RF-070, DECISION D-009, PRINTERS spec §13.2).
///
/// An adapter turns a render-neutral [PrintDocument] + a target [PrinterProfile]
/// into device-ready bytes. It is STATELESS with respect to job identity —
/// idempotency/retry/dedup are the RF-071 spool's concern, not the adapter's.
/// ESC/POS is the first implementation; the domain never depends on it.
abstract class PrintAdapter {
  /// Encode [document] for [profile] into device bytes. Pure + deterministic.
  Uint8List encode(PrintDocument document, PrinterProfile profile);
}
