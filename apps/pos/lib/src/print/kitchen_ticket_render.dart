import 'dart:typed_data' show Uint8List;

import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        KitchenTicketPrintLabels,
        buildKdsTicketPrintDocument,
        kitchenTicketToEscPosDocument;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketView;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-PRINT-DUAL-001B — the POS money-free kitchen-ticket BYTES builder.
///
/// Renders the SHARED kitchen document ([buildKdsTicketPrintDocument] — the SAME
/// layout the KDS live print emits) to 80mm ESC/POS bytes through the SAME
/// converter + rasterization + encode seam the KDS native path uses, so a ticket
/// printed straight from the POS is byte-for-byte the KDS ticket for the same
/// [KdsTicketView]:
///
///   KdsTicketView -> buildKdsTicketPrintDocument -> kitchenTicketToEscPosDocument
///   -> maybeRasterizeForRtl (ar/he -> one GS v 0 bitmap; ASCII keeps the text
///   path) -> EscPosPrintAdapter.encode(escPos80mm).
///
/// Web-safe: it depends only on `restoflow_feature_kitchen` (domain + printing)
/// — NEVER drift/`dart:ffi` — so the POS web build never drags a native database
/// onto the graph (this REPLACES the old drift-backed spool bytes builder on the
/// active print path; the spool renderer stays dormant, confined to lib/src/
/// spool). MONEY-FREE by construction (T-003): a [KdsTicketView] carries no money
/// fields at all, and nothing here invents any.
Future<Uint8List> renderKitchenTicketBytes({
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  pp.ReceiptRasterizer? rasterizer,
  pp.EscPosPrintAdapter adapter = const pp.EscPosPrintAdapter(),
  pp.PrinterProfile profile = pp.PrinterProfile.escPos80mm,
  // PRINT-LAYOUT-001A: text columns + raster width + margins + pagination all
  // come from the selected KITCHEN media profile. Null/absent => the
  // backward-compatible 80mm continuous default (byte-identical).
  pp.MediaProfile? mediaProfile,
  pp.PageLineLabel? pageLabel,
  pp.PageLineLabel? continuationHeader,
}) async {
  final media = mediaProfile ?? pp.MediaProfile.continuous80;
  final document = buildKdsTicketPrintDocument(ticket: ticket, labels: labels);
  final escPos = kitchenTicketToEscPosDocument(
    document,
    columns: media.columns,
  );
  // Raster Arabic/Hebrew (+ ×) tickets; ASCII-only stays text on a continuous
  // roll. A FIXED label always rasterizes + paginates at its real width. A
  // rasterizer failure falls back to the text ticket (parity with the KDS
  // native bridge). Money-free: a KdsTicketView carries no money fields.
  pp.PrintDocument out = escPos;
  try {
    out = await pp.rasterizeForMediaProfile(
      escPos,
      rasterizer: rasterizer,
      profile: media,
      pageLabel: pageLabel,
      continuationHeader: continuationHeader,
    );
  } catch (_) {
    out = escPos;
  }
  return adapter.encode(out, profile);
}
