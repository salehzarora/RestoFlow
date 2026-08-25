import 'dart:ui' show Locale;

import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_ticket_print_builder.dart' show KitchenTicketPrintLabels;

/// KIOSK-PRINT-114B.5A: MOVED VERBATIM from `apps/pos/lib/src/print/` (the POS
/// keeps a re-export shim at the old path) so the kiosk claimed print and the
/// POS printer-only drain derive the SAME chrome labels the POS direct print
/// uses, from the ONE shared `AppLocalizations`.
///
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
  customerPhoneLabel: l10n.customerPhoneKitchenLabel,
  stationLabel: l10n.kdsStationLabel,
  noteLabel: l10n.kdsNoteLabel,
  kitchenTotal: l10n.kdsMeatTotalLabel,
  // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the localized with/without wording
  // for a preparation resource split by a classifying modifier option — the SAME
  // two keys the KDS card and the KDS ticket document use.
  prepWithOption: l10n.kitchenPrepResourceWithOption,
  prepWithoutOption: l10n.kitchenPrepResourceWithoutOption,
  // DEFERRED-ORDER-AMENDMENTS-001: the SAME two keys the KDS board's round pill
  // uses, so an addition reads identically on screen and on paper.
  additionLabel: l10n.kdsAdditionLabel,
  roundLabel: l10n.kdsRoundLabel,
  restaurantNameFallback: l10n.printRestaurantNameFallback,
);

/// KIOSK-PRINT-114B.5A: context-free labels for a BCP-47 language code — the
/// kiosk lane and the POS drain worker run outside any widget tree, so they
/// resolve the shared `AppLocalizations` for the device/order language and map
/// it through the ONE [kitchenTicketPrintLabelsFromL10n] above. Fail-safe: an
/// unsupported code resolves to English (the same fallback the legacy spool
/// label bundles used), never a throw on the print path.
KitchenTicketPrintLabels kitchenTicketPrintLabelsForLanguageCode(String code) {
  AppLocalizations l10n;
  try {
    l10n = lookupAppLocalizations(Locale(code));
  } catch (_) {
    l10n = lookupAppLocalizations(const Locale('en'));
  }
  return kitchenTicketPrintLabelsFromL10n(l10n);
}
