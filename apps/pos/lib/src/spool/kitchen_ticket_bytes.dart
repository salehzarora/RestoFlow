import 'dart:typed_data' show Uint8List;

import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        KitchenDispatchDocument,
        KitchenDispatchItem,
        KitchenDispatchModifier,
        KitchenSpoolDispatchType;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../print/kitchen_ticket_contract.dart' show KitchenTicketInput;
import 'kitchen_ticket_renderer.dart'
    show KitchenTicketLabels, KitchenTicketRenderer;

/// KITCHEN-PRINT-DUAL-001 — the NATIVE money-free kitchen-ticket BYTES builder.
///
/// This deliberately lives in `lib/src/spool/`: it reuses the EXISTING
/// money-free [KitchenTicketRenderer] and the [KitchenDispatchDocument] value
/// model (from `restoflow_data_local`), both of which the POS source-boundary
/// proof ([kitchen_spool_dormancy_test]) confines to this directory. It is a
/// PURE document → ESC/POS-bytes function — it never touches the encrypted
/// spool database, cipher, key, server dispatch, print transport,
/// SharedPreferences, or logging — so the dormant spool subsystem stays exactly
/// that. Because it imports `restoflow_data_local` (drift/`dart:ffi`), the
/// dual-print service reaches it ONLY through a `dart.library.io` conditional
/// import ([kitchen_ticket_bytes_web.dart] on web), so `flutter build web`
/// never drags drift onto the web graph. The web-safe [KitchenTicketInput] DTO
/// lives in `lib/src/print/kitchen_ticket_contract.dart`.

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
    customerPhone: input.customerPhone,
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
