import 'dart:typed_data' show Uint8List;

import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        KitchenDispatchDocument,
        KitchenDispatchItem,
        KitchenDispatchModifier,
        KitchenSpoolDispatchType;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'kitchen_ticket_renderer.dart'
    show KitchenTicketLabels, KitchenTicketRenderer;

/// KITCHEN-PRINT-DUAL-001 — the money-free kitchen-ticket BYTES builder.
///
/// This deliberately lives in `lib/src/spool/`: it reuses the EXISTING
/// money-free [KitchenTicketRenderer] and the [KitchenDispatchDocument] value
/// model (from `restoflow_data_local`), both of which the POS source-boundary
/// proof ([kitchen_spool_dormancy_test]) confines to this directory. It is a
/// PURE document → ESC/POS-bytes function — it never touches the encrypted
/// spool database, cipher, key, server dispatch, print transport,
/// SharedPreferences, or logging — so the dormant spool subsystem stays exactly
/// that. The dual-print service (`lib/src/print/pos_kitchen_ticket_printer.dart`)
/// calls this to obtain bytes and performs the actual native send.

/// One money-free kitchen line: quantity, name, an optional kitchen note, and
/// pre-formatted modifier display strings. It structurally cannot carry a
/// price, total, or any money field.
final class KitchenTicketLineInput {
  const KitchenTicketLineInput({
    required this.qty,
    required this.name,
    this.note,
    this.modifiers = const [],
  });

  final int qty;
  final String name;
  final String? note;

  /// Modifier display strings (any "×N" is already baked in by the caller).
  final List<String> modifiers;
}

/// A money-free kitchen-ticket input for one created order.
final class KitchenTicketInput {
  const KitchenTicketInput({
    required this.orderCode,
    required this.orderType,
    this.tableLabel,
    this.customerName,
    this.orderNote,
    this.lines = const [],
    this.createdAtIso,
  });

  /// The human order code (e.g. `#000042`).
  final String orderCode;

  /// The order-type wire token (`dine_in` / `takeaway`) the kitchen labels map.
  final String orderType;
  final String? tableLabel;
  final String? customerName;
  final String? orderNote;
  final List<KitchenTicketLineInput> lines;
  final String? createdAtIso;
}

/// Builds the money-free [KitchenDispatchDocument] for [input] and renders it to
/// 80mm ESC/POS bytes through the EXISTING [KitchenTicketRenderer] — never the
/// cashier-receipt renderer. [rasterizer] (from `nativePrintRasterizerProvider`)
/// enables the ar/he raster path; null keeps the ASCII text path. [languageCode]
/// selects the frame labels (en fail-safe).
Future<Uint8List> renderKitchenTicketBytes({
  required KitchenTicketInput input,
  String? languageCode,
  pp.ReceiptRasterizer? rasterizer,
}) {
  final dispatch = KitchenDispatchDocument(
    serverPayloadVersion: 1,
    kind: KitchenSpoolDispatchType.initialOrder,
    orderCode: input.orderCode,
    orderType: input.orderType,
    tableLabel: input.tableLabel,
    customerDisplayName: input.customerName,
    orderNote: input.orderNote,
    createdAt: input.createdAtIso,
    items: [
      for (final line in input.lines)
        KitchenDispatchItem(
          qty: line.qty,
          name: line.name,
          note: line.note,
          modifiers: [
            for (final modifier in line.modifiers)
              KitchenDispatchModifier(qty: 1, name: modifier),
          ],
        ),
    ],
  );
  final renderer = KitchenTicketRenderer(
    labels: KitchenTicketLabels.forLanguageCode(languageCode),
    rasterizer: rasterizer,
  );
  return renderer.renderToBytes(dispatch);
}
