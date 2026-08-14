import 'package:restoflow_domain/restoflow_domain.dart'
    show formatPrepQuantity, kitchenCountDisplayLabel;
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

/// DEFERRED-ORDER-AMENDMENTS-001 — WHICH kitchen work unit a ticket represents.
///
/// The kitchen must be able to tell, at a glance, whether the paper in its hand
/// is a NEW order to cook from scratch or a DELTA added to something already on
/// the line. Getting that wrong means either cooking the whole order twice or
/// missing the addition entirely, so the distinction is a typed value rather
/// than an inferred formatting difference.
enum KitchenTicketDocumentKind {
  /// The order's FIRST kitchen work unit (PSC-001C work unit 1).
  initialOrder,

  /// A later service round: items ADDED to an order that already exists.
  orderAddition;

  /// The kind [ticket] is, derived from the ONE authoritative signal — the
  /// server-assigned service-round number, which is null on work unit 1 and
  /// 2+ on every addition. Deriving it (instead of accepting a separate flag)
  /// means the marker can never disagree with the round it names.
  static KitchenTicketDocumentKind forTicket(KdsTicketView ticket) =>
      ticket.roundNumber != null ? orderAddition : initialOrder;
}

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
    required this.customerPhoneLabel,
    required this.stationLabel,
    required this.noteLabel,
    required this.kitchenTotal,
    required this.additionLabel,
    required this.roundLabel,
    this.restaurantNameFallback,
    this.prepWithOption = _defaultPrepWithOption,
    this.prepWithoutOption = _defaultPrepWithoutOption,
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

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: `customerPhoneKitchenLabel` — prefixes
  /// the optional customer phone (printed directly below the name).
  final String customerPhoneLabel;

  /// `kdsStationLabel` — prefixes the station id.
  final String stationLabel;

  /// `kdsNoteLabel` — labels an item/order note.
  final String noteLabel;

  /// `kdsMeatTotalLabel(count, unit)` — the whole-order "Kitchen total: N unit".
  final String Function(String count, String unit) kitchenTotal;

  /// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016:
  /// `kitchenPrepResourceWithOption(resource, option)` — the preparation-summary
  /// wording for the portion prepared WITH the classifying option, and
  /// [prepWithoutOption] for the portion prepared without it.
  ///
  /// Both default to the English patterns so a label built without them still
  /// distinguishes the two buckets (never two identically-labelled rows); the
  /// POS and KDS ticket documents override them from the active locale.
  final String Function(String resource, String option) prepWithOption;
  final String Function(String resource, String option) prepWithoutOption;

  /// DEFERRED-ORDER-AMENDMENTS-001: `kdsAdditionLabel` — the word that marks a
  /// ticket as a DELTA rather than a new order. The SAME key the KDS board's
  /// round pill uses, so screen and paper cannot disagree.
  final String additionLabel;

  /// DEFERRED-ORDER-AMENDMENTS-001: `kdsRoundLabel(number)` — "Round N" for the
  /// server-assigned service-round number.
  final String Function(int number) roundLabel;

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
/// DEFERRED-ORDER-AMENDMENTS-001 — an ADDITION ticket (a PSC-001C service round)
/// carries a prominent marker band directly under the order code: the localized
/// "Addition · Round N", in the same large heading style as the order code
/// itself. The order code above it IS the original order's identity, so the
/// kitchen can tie the delta to the food already on the line. [kind] defaults to
/// [KitchenTicketDocumentKind.forTicket] — derived from the ticket's own round
/// number — so an addition can never print without its marker. An INITIAL order
/// prints byte-identically to before: the band is a conditional line and no
/// other line moves.
///
/// MONEY-FREE by construction (SECURITY T-003): a [KdsTicketView] carries no
/// money field and nothing here (item right column stays empty) invents one.
PrintDocument buildKdsTicketPrintDocument({
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  String? restaurantName,
  KitchenTicketDocumentKind? kind,
}) {
  final documentKind = kind ?? KitchenTicketDocumentKind.forTicket(ticket);
  // The marker text: the SAME "Addition · Round N" composition the KDS board's
  // round pill renders. A round number is always present on a real addition
  // (that is what derives the kind); with an explicit [kind] override and no
  // number, the honest bare marker prints rather than a fabricated "Round".
  final round = ticket.roundNumber;
  final String? additionMarker;
  if (documentKind != KitchenTicketDocumentKind.orderAddition) {
    additionMarker = null;
  } else if (round != null) {
    additionMarker = '${labels.additionLabel} · ${labels.roundLabel(round)}';
  } else {
    additionMarker = labels.additionLabel;
  }
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
      // TABLE-FLOOR-LAYOUT-021 (owner decision 4): a DINE-IN ticket opens AND
      // closes with a full-width ASCII star band, so the kitchen separates
      // dine-in from takeaway at arm's length. Takeaway/unknown order types
      // print byte-identically to before.
      if (dineIn) PrintLine.banner(),
      if (brand != null && brand.isNotEmpty) PrintLine.subtitle(brand),
      PrintLine.title(header),
      // DEFERRED-ORDER-AMENDMENTS-001: the addition marker band, immediately
      // under the ORIGINAL order code so the two read as one identity ("this
      // delta belongs to that order"). Large heading style — the kitchen must
      // not have to hunt for it. Absent on an initial order.
      if (additionMarker != null) PrintLine.title(additionMarker),
      PrintLine.rule(),
      if (dineIn || takeaway)
        PrintLine.center(dineIn ? labels.dineIn : labels.takeaway),
      if (ticket.tableLabel case final table?)
        PrintLine.center('${labels.tableLabel} $table'),
      if (ticket.customerName case final customer?)
        PrintLine.center('${labels.customerLabel}: $customer'),
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL phone, directly BELOW the
      // name. Absent => nothing printed (byte-identical ticket). Money-free header
      // text (T-003 holds); rasterized for ar/he downstream so `+`/digits render.
      if (ticket.customerPhone case final phone?)
        PrintLine.center('${labels.customerPhoneLabel}: $phone'),
      if (showStation)
        PrintLine.center('${labels.stationLabel}: ${ticket.stationId}'),
      PrintLine.rule(),
      if (ticket.kitchenCounts.isNotEmpty) ...[
        for (final count in ticket.kitchenCounts)
          PrintLine.title(
            labels.kitchenTotal(
              formatPrepQuantity(count.quantity),
              // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: a classified resource
              // prints as "{resource} with/without {option}" through the shared
              // composer, so the printed ticket and the KDS card word the split
              // identically. An unsplit total is the bare label, exactly as before.
              kitchenCountDisplayLabel(
                count,
                withOption: labels.prepWithOption,
                withoutOption: labels.prepWithoutOption,
              ),
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
      // TABLE-FLOOR-LAYOUT-021: the closing dine-in star band — always the
      // LAST content line, whatever optional blocks printed above it.
      if (dineIn) PrintLine.banner(),
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
            // PRINT-LAYOUT-001C: the DEDICATED larger kitchen item role (the
            // receipt keeps the smaller shared `item`, untouched).
            style: pp.PrintLineStyle.kitchenItem,
          ),
        );
      case PrintLineKind.sub:
        lines.add(
          pp.PrintTextLine(
            '  ${line.left ?? ''}',
            // PRINT-LAYOUT-001C: the DEDICATED larger kitchen modifier / prep
            // role (the receipt keeps the smaller shared `sub`).
            style: pp.PrintLineStyle.kitchenModifier,
          ),
        );
      case PrintLineKind.note:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            // PRINT-LAYOUT-001C: the DEDICATED larger + bold kitchen note role.
            style: pp.PrintLineStyle.kitchenNote,
          ),
        );
      case PrintLineKind.rule:
        lines.add(
          pp.PrintTextLine('-' * columns, style: pp.PrintLineStyle.separator),
        );
      case PrintLineKind.spacer:
        // A blank, ink-free vertical gap between item blocks.
        lines.add(const pp.PrintTextLine('', style: pp.PrintLineStyle.spacer));
      case PrintLineKind.banner:
        // TABLE-FLOOR-LAYOUT-021: the dine-in marker — a FULL-WIDTH star row.
        // Deliberately NOT the separator style: the raster path draws a rule
        // for separators and IGNORES their text; this row must keep its stars
        // in both text and raster modes. Pure ASCII, so the text ESC/POS path
        // stays byte-safe and the band never forces raster by itself.
        lines.add(
          pp.PrintTextLine(
            '*' * columns,
            alignment: pp.PrintAlignment.center,
            emphasis: pp.TextEmphasis.bold,
            style: pp.PrintLineStyle.normal,
          ),
        );
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

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 fallback wording for a classified
/// preparation resource, used only when a [KitchenTicketPrintLabels] is built
/// without the localized patterns. English, so the two buckets always read
/// differently; every production ticket overrides them from the active locale.
String _defaultPrepWithOption(String resource, String option) =>
    '$resource with $option';

String _defaultPrepWithoutOption(String resource, String option) =>
    '$resource without $option';
