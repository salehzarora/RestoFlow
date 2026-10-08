import '../kds_ticket_view.dart' show KdsItemView;

/// ORDER-EDIT-001C (D-044, design §7.3) — the money-free VIEW of one
/// printer-only CHANGE SLIP: what a sent-order edit changed, plus every live
/// line of the order after it ("ORDER NOW").
///
/// Built from the server's `order_edit` dispatch payload
/// (`orderChangeSlipViewFromKitchenDispatch`, API_CONTRACT §4.45.9) or by hand
/// (a POS-built slip, a KDS change chit), and printed ONLY through
/// `buildOrderChangeSlipPrintDocument`. Every line reuses [KdsItemView], so
/// item names, "name ×N" modifier strings and notes read exactly as on the
/// kitchen ticket.
///
/// MONEY-FREE by construction (SECURITY T-003): no price, total or currency
/// field exists here. It deliberately has NO phone field (the payload carries
/// none and the slip never prints one) and NO remake field (the paper never
/// prints REMAKE; a modified line is a CHANGE).
final class OrderChangeSlipView {
  const OrderChangeSlipView({
    required this.orderCode,
    required this.editNumber,
    this.orderType,
    this.tableLabel,
    this.customerName,
    this.orderNote,
    this.editedAt,
    this.reasonCode,
    this.reasonText,
    this.staffFirstName,
    this.changes = const <OrderChangeSlipEntry>[],
    this.orderNow = const <KdsItemView>[],
  });

  /// The ORIGINAL order's display code, ALREADY prefixed with '#'
  /// (`#A1B2C3`, the server's `order_code`); printed as-is.
  final String orderCode;

  /// The per-order edit number (1, 2, …) — "Change N".
  final int editNumber;

  /// Order type wire value ('dine_in' | 'takeaway'), when known.
  final String? orderType;

  /// The dining table's human label, if the order is at a table.
  final String? tableLabel;

  /// The optional customer display name (display text only).
  final String? customerName;

  /// The order-level kitchen note, if any.
  final String? orderNote;

  /// When the EDIT was made (the dispatch's `created_at`) — never the order's
  /// creation time and never the print time. Null prints no time line.
  final DateTime? editedAt;

  /// The edit's reason code as the server sent it (`customer_changed_mind`,
  /// `entry_mistake`, `item_unavailable`, `kitchen_issue`, `other`). An
  /// unknown value is never printed (see [KitchenChangeSlipLabels
  /// .reasonCodeLabel]).
  final String? reasonCode;

  /// The edit's optional free-text reason.
  final String? reasonText;

  /// The acting employee's FIRST name (display text, never an identifier).
  final String? staffFirstName;

  /// One entry per requested change, in request order.
  final List<OrderChangeSlipEntry> changes;

  /// EVERY live line of the order after the edit, in the order given (the
  /// server's canonical menu order) — printed as-is, never re-sorted. Empty
  /// omits the ORDER NOW block and the "Replaces earlier tickets" footer.
  final List<KdsItemView> orderNow;
}

/// One requested change of a sent-order edit (the `edit_lines[]` ops).
sealed class OrderChangeSlipEntry {
  const OrderChangeSlipEntry();
}

/// `remove` — the line [was] left the order (REMOVED).
final class OrderChangeRemoved extends OrderChangeSlipEntry {
  const OrderChangeRemoved(this.was);

  final KdsItemView was;
}

/// `set_quantity` — the line [was] now has [nowQuantity] units. An increase
/// prints under ADD as "+[delta] × name"; a reduction prints under CHANGE.
final class OrderChangeQuantity extends OrderChangeSlipEntry {
  const OrderChangeQuantity({required this.was, required this.nowQuantity});

  final KdsItemView was;

  /// The line's NEW absolute quantity (integer units, never money).
  final int nowQuantity;

  /// The signed quantity difference (`nowQuantity - was.quantity`).
  int get delta => nowQuantity - was.quantity;

  bool get isIncrease => delta > 0;
}

/// `modify` — the line [was] was replaced by the [now] lines (the
/// continuation and/or the replacements), printed under CHANGE.
final class OrderChangeModified extends OrderChangeSlipEntry {
  const OrderChangeModified({required this.was, required this.now});

  final KdsItemView was;
  final List<KdsItemView> now;
}

/// `add` — the [now] lines joined the order (ADD).
final class OrderChangeAdded extends OrderChangeSlipEntry {
  const OrderChangeAdded(this.now);

  final List<KdsItemView> now;
}

/// ORDER-EDIT-001C — the localized CHROME strings of the change slip, on top
/// of the ticket's [KitchenTicketPrintLabels] (order type, table, customer and
/// note words come from there). Built from `AppLocalizations` by
/// `kitchenChangeSlipLabelsFromL10n`.
///
/// Every field is REQUIRED with no English default, so a slip built for ar/he
/// can never leak an English word onto the paper. "CHANGE" here means an
/// order change — never the money-change word (`posReceiptChange`).
final class KitchenChangeSlipLabels {
  const KitchenChangeSlipLabels({
    required this.orderChanged,
    required this.changeNumber,
    required this.removedSection,
    required this.changeSection,
    required this.addSection,
    required this.orderNowSection,
    required this.wasLabel,
    required this.nowLabel,
    required this.staffLabel,
    required this.reasonLabel,
    required this.replacesFooter,
    required this.reasonCustomerChangedMind,
    required this.reasonEntryMistake,
    required this.reasonItemUnavailable,
    required this.reasonKitchenIssue,
    required this.reasonOther,
  });

  /// `kitchenChangeSlipTitle` — "ORDER CHANGED".
  final String orderChanged;

  /// `kitchenEditChangeNumber(number)` — "Change N".
  final String Function(int number) changeNumber;

  /// `kitchenEditRemovedLabel` — the REMOVED section heading.
  final String removedSection;

  /// `kitchenChangeSlipChangeLabel` — the CHANGE section heading.
  final String changeSection;

  /// `kitchenChangeSlipAddLabel` — the ADD section heading.
  final String addSection;

  /// `kitchenChangeSlipOrderNow` — the ORDER NOW section heading.
  final String orderNowSection;

  /// `kitchenChangeSlipWasLabel` — prefixes the old line ("Was: 3 × Cola").
  final String wasLabel;

  /// `kitchenChangeSlipNowLabel` — prefixes the new line ("Now: 1 × Cola").
  final String nowLabel;

  /// `kitchenChangeSlipStaffLabel` — prefixes the staff first name.
  final String staffLabel;

  /// `kitchenChangeSlipReasonLabel` — prefixes the reason.
  final String reasonLabel;

  /// `kitchenChangeSlipFooter(orderCode)` — "Replaces earlier tickets for
  /// #A1B2C3"; the code already carries its '#'.
  final String Function(String orderCode) replacesFooter;

  /// `orderEditReason*` — the five reason-code labels.
  final String reasonCustomerChangedMind;
  final String reasonEntryMistake;
  final String reasonItemUnavailable;
  final String reasonKitchenIssue;
  final String reasonOther;

  /// The label of the reason-code [wire] value, or null for an absent or
  /// UNKNOWN code — the raw wire value is never printed.
  String? reasonCodeLabel(String? wire) => switch (wire) {
    'customer_changed_mind' => reasonCustomerChangedMind,
    'entry_mistake' => reasonEntryMistake,
    'item_unavailable' => reasonItemUnavailable,
    'kitchen_issue' => reasonKitchenIssue,
    'other' => reasonOther,
    _ => null,
  };
}
