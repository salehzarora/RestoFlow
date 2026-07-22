import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenTicketPrintLabels, buildKdsTicketPrintDocument;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'print_document.dart';

/// Builds the kitchen-ticket print document for a REAL synced ticket
/// (device settings sprint, Part D) — the auto-print payload behind the
/// acknowledge trigger.
///
/// KITCHEN-PRINT-DUAL-001B: the layout itself now lives in the shared
/// [buildKdsTicketPrintDocument] (package `restoflow_feature_kitchen`), so the
/// POS direct kitchen print produces the SAME ticket from the SAME
/// [KdsTicketView]. This wrapper only adapts the KDS `AppLocalizations` into the
/// plain [KitchenTicketPrintLabels] the shared builder consumes — the emitted
/// document is byte-for-byte what this file built before. MONEY-FREE by
/// construction: a [KdsTicketView] carries no money fields at all (T-003).
PrintDocument buildKdsTicketDocument(
  AppLocalizations l10n,
  KdsTicketView ticket,
) => buildKdsTicketPrintDocument(
  ticket: ticket,
  labels: kitchenTicketPrintLabelsFromL10n(l10n),
);

/// Adapts the shared kitchen-ticket CHROME labels from `AppLocalizations`. The
/// POS builds the SAME struct from the SAME l10n keys, so the printed chrome is
/// identical on both surfaces.
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
);
