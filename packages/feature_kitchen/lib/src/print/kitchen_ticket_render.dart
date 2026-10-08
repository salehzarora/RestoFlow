import 'dart:typed_data' show Uint8List;

import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../kds_ticket_view.dart' show KdsTicketView;
import 'kds_ticket_print_builder.dart'
    show
        KitchenTicketPrintLabels,
        buildKdsTicketPrintDocument,
        buildOrderChangeSlipPrintDocument,
        kitchenTicketToEscPosDocument;
import 'kitchen_print_document.dart' show PrintDocument;
import 'order_change_slip_view.dart'
    show KitchenChangeSlipLabels, OrderChangeSlipView;

/// KIOSK-PRINT-114B.5A: MOVED VERBATIM from `apps/pos/lib/src/print/` (the POS
/// keeps a re-export shim at the old path) so the POS direct print, the POS
/// manual reprint, the POS printer-only drain and the kiosk claimed print all
/// encode the ONE canonical kitchen ticket through this single seam.
///
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
  // PRINT-LAYOUT-001B: the paired station's restaurant name for the brand
  // header (offline-safe DATA). Null => the shared builder uses the localized
  // fallback carried on [labels].
  String? restaurantName,
  pp.PageLineLabel? pageLabel,
  pp.PageLineLabel? continuationHeader,
}) async {
  final document = buildKdsTicketPrintDocument(
    ticket: ticket,
    labels: labels,
    restaurantName: restaurantName,
  );
  return _encodeKitchenDocument(
    document,
    rasterizer: rasterizer,
    adapter: adapter,
    profile: profile,
    media: mediaProfile ?? pp.MediaProfile.continuous80,
    pageLabel: pageLabel,
    continuationHeader: continuationHeader,
  );
}

/// ORDER-EDIT-001C (D-044) — the money-free CHANGE SLIP bytes builder.
///
/// Renders [buildOrderChangeSlipPrintDocument] through the SAME converter +
/// rasterization + encode seam as [renderKitchenTicketBytes] (ar/he and every
/// slip carrying '·' / '×' rasterize when a rasterizer is injected — OPEN
/// QUESTION Q-015; a FIXED label rasterizes + paginates with [pageLabel] /
/// [continuationHeader]; a rasterizer failure falls back to the text slip).
/// The entry point the POS change-slip print and the spool drain share, so a
/// slip is the same paper whichever path prints it. Money-free by
/// construction (T-003): an [OrderChangeSlipView] carries no money field.
Future<Uint8List> renderOrderChangeSlipBytes({
  required OrderChangeSlipView slip,
  required KitchenTicketPrintLabels labels,
  required KitchenChangeSlipLabels changeLabels,
  pp.ReceiptRasterizer? rasterizer,
  pp.EscPosPrintAdapter adapter = const pp.EscPosPrintAdapter(),
  pp.PrinterProfile profile = pp.PrinterProfile.escPos80mm,
  pp.MediaProfile? mediaProfile,
  String? restaurantName,
  pp.PageLineLabel? pageLabel,
  pp.PageLineLabel? continuationHeader,
}) async {
  // async: a builder error surfaces as a failed Future, exactly like the
  // ticket path (never a synchronous throw at the call site).
  final document = buildOrderChangeSlipPrintDocument(
    slip: slip,
    labels: labels,
    changeLabels: changeLabels,
    restaurantName: restaurantName,
  );
  return _encodeKitchenDocument(
    document,
    rasterizer: rasterizer,
    adapter: adapter,
    profile: profile,
    media: mediaProfile ?? pp.MediaProfile.continuous80,
    pageLabel: pageLabel,
    continuationHeader: continuationHeader,
  );
}

/// The ONE kitchen encode tail (moved verbatim out of
/// [renderKitchenTicketBytes]): kitchen document -> ESC/POS document at the
/// media's columns -> raster for the media profile -> encode.
Future<Uint8List> _encodeKitchenDocument(
  PrintDocument document, {
  required pp.ReceiptRasterizer? rasterizer,
  required pp.EscPosPrintAdapter adapter,
  required pp.PrinterProfile profile,
  required pp.MediaProfile media,
  required pp.PageLineLabel? pageLabel,
  required pp.PageLineLabel? continuationHeader,
}) async {
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
