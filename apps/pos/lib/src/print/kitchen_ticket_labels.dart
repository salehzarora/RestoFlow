import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenTicketPrintLabels;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KITCHEN-PRINT-DUAL-001B — adapts the shared kitchen-ticket CHROME labels from
/// the POS `AppLocalizations`.
///
/// Uses the SAME l10n keys the KDS adapter uses (`kds_ticket_document.dart`), so
/// a ticket printed straight from the POS carries the SAME chrome as the KDS
/// ticket. Only the label mapping is duplicated here (both apps read the same
/// shared ARB); the LAYOUT is the one shared `buildKdsTicketPrintDocument`.
KitchenTicketPrintLabels kitchenTicketPrintLabelsFromL10n(
  AppLocalizations l10n,
) => KitchenTicketPrintLabels(
  ticketLabel: l10n.kdsTicketLabel,
  previewTitle: l10n.kdsTicketPreviewTitle,
  dineIn: l10n.posOrderTypeDineIn,
  takeaway: l10n.posOrderTypeTakeaway,
  tableLabel: l10n.posTableLabel,
  customerLabel: l10n.customerNameKitchenLabel,
  stationLabel: l10n.kdsStationLabel,
  noteLabel: l10n.kdsNoteLabel,
  kitchenTotal: l10n.kdsMeatTotalLabel,
  restaurantNameFallback: l10n.printRestaurantNameFallback,
);
