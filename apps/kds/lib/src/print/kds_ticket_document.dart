import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'print_document.dart';

/// Builds the kitchen-ticket print document for a REAL synced ticket
/// (device settings sprint, Part D) — the auto-print payload behind the
/// acknowledge trigger.
///
/// Mirrors the demo preview builder but consumes the live [KdsTicketView]:
/// order code (ticket-id fallback), order type wire value mapped to chrome,
/// table, station, each item as `name xN` with its `+ modifier` sub-lines
/// (quantities arrive pre-formatted as `name ×N` — modifier-quantity sprint)
/// and its note, plus the order-level note. MONEY-FREE by construction: a
/// [KdsTicketView] carries no money fields at all (T-003), and nothing here
/// invents any.
PrintDocument buildKdsTicketDocument(
  AppLocalizations l10n,
  KdsTicketView ticket,
) {
  final header =
      ticket.orderNumber ?? '${l10n.kdsTicketLabel} ${ticket.kitchenTicketId}';
  final dineIn = ticket.orderType == 'dine_in';
  final takeaway = ticket.orderType == 'takeaway';
  final showStation =
      ticket.stationId != KdsTicketMapper.unassignedStation &&
      ticket.stationId.isNotEmpty;
  // Interpolated into a local so the no-hardcoded-strings guard reads this
  // as data assembly (it is: both parts are l10n/data).
  final docTitle = '${l10n.kdsTicketPreviewTitle} $header';

  return PrintDocument(
    title: docTitle,
    lines: <PrintLine>[
      // PRINT-LAYOUT-001: the big order number is the hero, set off by a rule.
      PrintLine.title(header),
      PrintLine.rule(),
      // Service context grouped + centered so the chef reads it at a glance.
      if (dineIn || takeaway)
        PrintLine.center(
          dineIn ? l10n.posOrderTypeDineIn : l10n.posOrderTypeTakeaway,
        ),
      if (ticket.tableLabel case final table?)
        PrintLine.center('${l10n.posTableLabel} $table'),
      // ORDER-CUSTOMER-001: the OPTIONAL customer name. Absent => no row.
      // Money-free display text (T-003).
      if (ticket.customerName case final customer?)
        PrintLine.center('${l10n.customerNameKitchenLabel}: $customer'),
      if (showStation)
        PrintLine.center('${l10n.kdsStationLabel}: ${ticket.stationId}'),
      PrintLine.rule(),
      // Items — bold, with a prominent quantity; modifiers + the note indented
      // underneath. Notes carry a "»" marker so a chef never misses them.
      for (final item in ticket.items) ...[
        PrintLine.item(item.name, '${item.quantity}×', emphasised: true),
        for (final modifier in item.modifiers) PrintLine.sub('+ $modifier'),
        if (item.note case final note?)
          PrintLine.sub('» ${l10n.kdsNoteLabel}: $note'),
      ],
      if (ticket.notes case final orderNote?) ...[
        PrintLine.rule(),
        PrintLine.sub('» ${l10n.kdsNoteLabel}: $orderNote'),
      ],
    ],
  );
}
