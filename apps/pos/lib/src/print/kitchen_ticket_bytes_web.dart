import 'dart:typed_data' show Uint8List;

import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'kitchen_ticket_contract.dart' show KitchenTicketInput;

/// KITCHEN-PRINT-DUAL-001 — the WEB stub for the kitchen-ticket bytes builder.
///
/// The real (native) builder lives in `lib/src/spool/kitchen_ticket_bytes.dart`
/// and imports drift (`dart:ffi`). The dual-print service reaches the builder
/// through a `dart.library.io` conditional import, so on the WEB target this
/// stub is compiled instead — keeping drift/sqlite3 entirely off the web graph.
/// It is never actually invoked on web: native printing is unavailable there
/// (`posNativePrintingAvailableProvider` is false), so the kitchen printer
/// resolves to null before any render is attempted.
Future<Uint8List> renderKitchenTicketBytes({
  required KitchenTicketInput input,
  String? languageCode,
  pp.ReceiptRasterizer? rasterizer,
}) async => Uint8List(0);
