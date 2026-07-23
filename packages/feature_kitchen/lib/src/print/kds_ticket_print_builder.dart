import 'package:restoflow_domain/restoflow_domain.dart' show formatPrepQuantity;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../kds_ticket_mapper.dart' show KdsTicketMapper;
import '../kds_ticket_view.dart';
import 'kitchen_print_document.dart';

/// KITCHEN-PRINT-DUAL-001B — the ONE kitchen-ticket layout, shared by the KDS
/// live board and the POS direct kitchen print.
///
/// The layout lived in the KDS app (`buildKdsTicketDocument`); it is extracted
/// here — parameterized by a plain [KitchenTicketPrintLabels] instead of
/// `AppLocalizations` — so a ticket printed straight from the POS carries the
/// SAME operational detail (item name/qty, structured modifiers, whole-order
/// kitchen counts, kitchen notes, table/order type) as one printed from the
/// KDS. There is no second mapping: `buildKdsTicketDocument` now delegates here,
/// and the POS builds the SAME [KdsTicketView] and renders it through this
/// builder. MONEY-FREE by construction (SECURITY T-003): a [KdsTicketView]
/// carries no money fields at all, and nothing here invents any.

/// The localized CHROME strings the kitchen-ticket layout needs. Both apps build
/// one from their `AppLocalizations` (identical keys), so the printed chrome is
/// the same on either surface; only the labels differ, never the layout.
class KitchenTicketPrintLabels {
  const KitchenTicketPrintLabels({
    required this.ticketLabel,
    required this.previewTitle,
    required this.dineIn,
    required this.takeaway,
    required this.tableLabel,
    required this.customerLabel,
    required this.stationLabel,
    required this.noteLabel,
    required this.kitchenTotal,
    this.restaurantNameFallback,
  });

  /// Header fallback prefix when the ticket has no order number (`kdsTicketLabel`).
  final String ticketLabel;

  /// Preview/document title prefix (`kdsTicketPreviewTitle`).
  final String previewTitle;

  /// `posOrderTypeDineIn`.
  final String dineIn;

  /// `posOrderTypeTakeaway`.
  final String takeaway;

  /// `posTableLabel` — prefixes the table value.
  final String tableLabel;

  /// `customerNameKitchenLabel` — prefixes the customer name.
  final String customerLabel;

  /// `kdsStationLabel` — prefixes the station id.
  final String stationLabel;

  /// `kdsNoteLabel` — labels an item/order note.
  final String noteLabel;

  /// `kdsMeatTotalLabel(count, unit)` — the whole-order "Kitchen total: N unit".
  final String Function(String count, String unit) kitchenTotal;

  /// PRINT-LAYOUT-001B: the localized GENERIC brand word printed as the
  /// restaurant-name header when the device carries no real restaurant name
  /// (`printRestaurantNameFallback`). Null on a label built without it — the
  /// brand line is then simply omitted (never a hardcoded placeholder).
  final String? restaurantNameFallback;
}

/// Builds the render-neutral, money-free kitchen-ticket [PrintDocument] for
/// [ticket] using [labels].
///
/// PRINT-LAYOUT-001B — clearer operational hierarchy on the SAME shared layout
/// (POS direct print and the KDS board stay byte-identical):
///  * optional [restaurantName] brand line as a secondary heading ABOVE the
///    big order-number hero (DATA passed in at the print call site — never a
///    server-row pluck, never money; omitted when absent, the call site
///    supplies a localized fallback, never a hardcoded placeholder here);
///  * items lead with the QUANTITY (the kitchen scans the count first), the
///    item name large + bold, modifiers indented under it, and a per-item note
///    in the distinct bold note style (not the plain modifier style);
///  * a blank spacer before each item after the first, so the gap BETWEEN
///    items reads larger than the spacing WITHIN one item.
///
/// MONEY-FREE by construction (SECURITY T-003): a [KdsTicketView] carries no
/// money field and nothing here (item right column stays empty) invents one.
PrintDocument buildKdsTicketPrintDocument({
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  String? restaurantName,
}) {
  final header =
      ticket.orderNumber ?? '${labels.ticketLabel} ${ticket.kitchenTicketId}';
  final dineIn = ticket.orderType == 'dine_in';
  final takeaway = ticket.orderType == 'takeaway';
  final showStation =
      ticket.stationId != KdsTicketMapper.unassignedStation &&
      ticket.stationId.isNotEmpty;
  // The brand line: the real restaurant name when the print path supplies one,
  // else the localized generic fallback from [labels]; omitted only when neither
  // exists (never a hardcoded placeholder).
  final rawBrand = restaurantName?.trim();
  final brand = (rawBrand != null && rawBrand.isNotEmpty)
      ? rawBrand
      : labels.restaurantNameFallback?.trim();
  final items = ticket.items;
  final docTitle = '${labels.previewTitle} $header';
  return PrintDocument(
    title: docTitle,
    lines: <PrintLine>[
      if (brand != null && brand.isNotEmpty) PrintLine.subtitle(brand),
      PrintLine.title(header),
      PrintLine.rule(),
      if (dineIn || takeaway)
        PrintLine.center(dineIn ? labels.dineIn : labels.takeaway),
      if (ticket.tableLabel case final table?)
        PrintLine.center('${labels.tableLabel} $table'),
      if (ticket.customerName case final customer?)
        PrintLine.center('${labels.customerLabel}: $customer'),
      if (showStation)
        PrintLine.center('${labels.stationLabel}: ${ticket.stationId}'),
      PrintLine.rule(),
      if (ticket.kitchenCounts.isNotEmpty) ...[
        for (final count in ticket.kitchenCounts)
          PrintLine.title(
            labels.kitchenTotal(
              formatPrepQuantity(count.quantity),
              count.label,
            ),
          ),
        PrintLine.rule(),
      ],
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) PrintLine.spacer(),
        PrintLine.item(
          '${items[i].quantity} × ${items[i].name}',
          '',
          emphasised: true,
        ),
        for (final modifier in items[i].modifiers) PrintLine.sub('+ $modifier'),
        if (items[i].note case final note?)
          PrintLine.note('» ${labels.noteLabel}: $note'),
      ],
      if (ticket.notes case final orderNote?) ...[
        PrintLine.rule(),
        PrintLine.note('» ${labels.noteLabel}: $orderNote'),
      ],
    ],
  );
}

/// Converts the kitchen-ticket [doc] into a render-neutral ESC/POS
/// [pp.PrintDocument] (moved here from the KDS app, unchanged). [columns]
/// matches the printer profile (48 for 80mm). MONEY-FREE: there is NO `total`
/// style on the kitchen ticket (a money row never exists here — T-003).
pp.PrintDocument kitchenTicketToEscPosDocument(
  PrintDocument doc, {
  int columns = 48,
}) {
  final lines = <pp.PrintLine>[];
  for (final line in doc.lines) {
    // PRINT-RASTER-STYLE-001: tag each ESC/POS line with its raster style. The
    // ESC/POS text + loopback paths ignore it.
    switch (line.kind) {
      case PrintLineKind.title:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            emphasis: pp.TextEmphasis.bold,
            style: pp.PrintLineStyle.headingLarge,
          ),
        );
      case PrintLineKind.subtitle:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            emphasis: pp.TextEmphasis.bold,
            style: pp.PrintLineStyle.subheading,
          ),
        );
      case PrintLineKind.center:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            style: pp.PrintLineStyle.centered,
          ),
        );
      case PrintLineKind.keyValue:
        lines.add(
          pp.PrintTextLine(
            _twoColumn(line.left, line.right, columns),
            emphasis: line.emphasised
                ? pp.TextEmphasis.bold
                : pp.TextEmphasis.normal,
            style: pp.PrintLineStyle.normal,
          ),
        );
      case PrintLineKind.item:
        lines.add(
          pp.PrintTextLine(
            _twoColumn(line.left, line.right, columns),
            emphasis: line.emphasised
                ? pp.TextEmphasis.bold
                : pp.TextEmphasis.normal,
            style: pp.PrintLineStyle.item,
          ),
        );
      case PrintLineKind.sub:
        lines.add(
          pp.PrintTextLine(
            '  ${line.left ?? ''}',
            style: pp.PrintLineStyle.sub,
          ),
        );
      case PrintLineKind.note:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            style: pp.PrintLineStyle.note,
          ),
        );
      case PrintLineKind.rule:
        lines.add(
          pp.PrintTextLine('-' * columns, style: pp.PrintLineStyle.separator),
        );
      case PrintLineKind.spacer:
        // A blank, ink-free vertical gap between item blocks.
        lines.add(const pp.PrintTextLine('', style: pp.PrintLineStyle.spacer));
    }
  }
  lines.add(const pp.PrintFeedLine(3));
  lines.add(const pp.PrintCutLine());
  return pp.PrintDocument(lines);
}

String _twoColumn(String? left, String? right, int columns) {
  final l = left ?? '';
  final r = right ?? '';
  final pad = columns - l.length - r.length;
  return pad < 1 ? '$l $r' : '$l${' ' * pad}$r';
}
