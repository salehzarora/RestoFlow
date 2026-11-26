import 'dart:typed_data' show Uint8List;

import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../kds_ticket_view.dart' show KdsTicketView;
import 'kds_ticket_print_builder.dart'
    show
        KitchenTicketPrintLabels,
        buildKdsTicketPrintDocument,
        buildOrderChangeSlipPrintDocument,
        kitchenTicketToEscPosDocument;
import 'order_change_slip_view.dart'
    show KitchenChangeSlipLabels, OrderChangeSlipView;

/// Legacy byte entry point for callers that do not select a print mode.
Future<Uint8List> renderKitchenTicketBytes({
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  pp.ReceiptRasterizer? rasterizer,
  pp.EscPosPrintAdapter adapter = const pp.EscPosPrintAdapter(),
  pp.PrinterProfile profile = pp.PrinterProfile.escPos80mm,
  pp.MediaProfile? mediaProfile,
  String? restaurantName,
  pp.PageLineLabel? pageLabel,
  pp.PageLineLabel? continuationHeader,
}) async => (await renderKitchenTicketJob(
  compact: false,
  ticket: ticket,
  labels: labels,
  rasterizer: rasterizer,
  adapter: adapter,
  profile: profile,
  mediaProfile: mediaProfile,
  restaurantName: restaurantName,
  pageLabel: pageLabel,
  continuationHeader: continuationHeader,
)).bytes;

/// Builds the same money-free ticket for every transport. The job also
/// carries the send policy for the bytes the encoder actually produced.
Future<pp.EncodedPrintJob> renderKitchenTicketJob({
  required bool compact,
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  pp.ReceiptRasterizer? rasterizer,
  pp.EscPosPrintAdapter adapter = const pp.EscPosPrintAdapter(),
  pp.PrinterProfile profile = pp.PrinterProfile.escPos80mm,
  pp.MediaProfile? mediaProfile,
  String? restaurantName,
  pp.PageLineLabel? pageLabel,
  pp.PageLineLabel? continuationHeader,
}) async {
  final document = buildKdsTicketPrintDocument(
    ticket: ticket,
    labels: labels,
    restaurantName: restaurantName,
  );
  final media = mediaProfile ?? pp.MediaProfile.continuous80;
  return pp.encodePrintJob(
    kitchenTicketToEscPosDocument(document, columns: media.columns),
    compact: compact,
    mediaProfile: media,
    rasterizer: rasterizer,
    adapter: adapter,
    profile: profile,
    pageLabel: pageLabel,
    continuationHeader: continuationHeader,
  );
}

/// Legacy byte entry point for callers that do not select a print mode.
Future<Uint8List> renderOrderChangeSlipBytes({
  required OrderChangeSlipView slip,
  required KitchenChangeSlipLabels changeLabels,
  required KitchenTicketPrintLabels labels,
  pp.ReceiptRasterizer? rasterizer,
  pp.EscPosPrintAdapter adapter = const pp.EscPosPrintAdapter(),
  pp.PrinterProfile profile = pp.PrinterProfile.escPos80mm,
  pp.MediaProfile? mediaProfile,
  String? restaurantName,
  pp.PageLineLabel? pageLabel,
  pp.PageLineLabel? continuationHeader,
}) async => (await renderOrderChangeSlipJob(
  compact: false,
  slip: slip,
  changeLabels: changeLabels,
  labels: labels,
  rasterizer: rasterizer,
  adapter: adapter,
  profile: profile,
  mediaProfile: mediaProfile,
  restaurantName: restaurantName,
  pageLabel: pageLabel,
  continuationHeader: continuationHeader,
)).bytes;

/// Builds the same money-free change slip for every transport. The job also
/// carries the send policy for the bytes the encoder actually produced.
Future<pp.EncodedPrintJob> renderOrderChangeSlipJob({
  required bool compact,
  required OrderChangeSlipView slip,
  required KitchenChangeSlipLabels changeLabels,
  required KitchenTicketPrintLabels labels,
  pp.ReceiptRasterizer? rasterizer,
  pp.EscPosPrintAdapter adapter = const pp.EscPosPrintAdapter(),
  pp.PrinterProfile profile = pp.PrinterProfile.escPos80mm,
  pp.MediaProfile? mediaProfile,
  String? restaurantName,
  pp.PageLineLabel? pageLabel,
  pp.PageLineLabel? continuationHeader,
}) async {
  final document = buildOrderChangeSlipPrintDocument(
    slip: slip,
    changeLabels: changeLabels,
    labels: labels,
    restaurantName: restaurantName,
  );
  final media = mediaProfile ?? pp.MediaProfile.continuous80;
  return pp.encodePrintJob(
    kitchenTicketToEscPosDocument(document, columns: media.columns),
    compact: compact,
    mediaProfile: media,
    rasterizer: rasterizer,
    adapter: adapter,
    profile: profile,
    pageLabel: pageLabel,
    continuationHeader: continuationHeader,
  );
}
