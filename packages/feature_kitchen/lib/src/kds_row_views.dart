import 'package:restoflow_domain/restoflow_domain.dart';

import 'kds_ticket_view.dart';

// ORDER-EDIT-001C: the money-free row -> view building blocks of the KDS
// mapper, extracted VERBATIM from `kds_ticket_mapper.dart` so the base mapper
// and the sent-order edit overlay render a retired "was" line exactly like a
// live line. Internal to the package (not exported). Every helper is an
// EXPLICIT scalar pluck — never a raw-row passthrough (SECURITY T-003).

/// Station bucket for an item with no `station_id` (routing not yet assigned).
const String kKdsUnassignedStation = 'unassigned';

/// The station bucket of one `order_items` row.
String kdsStationOf(Map<String, dynamic> item) {
  final stationRaw = item['station_id'];
  return stationRaw is String && stationRaw.isNotEmpty
      ? stationRaw
      : kKdsUnassignedStation;
}

/// The explicit money-free pluck of one order's display fields.
class KdsOrderHeader {
  const KdsOrderHeader({
    required this.status,
    required this.orderType,
    required this.tableLabel,
    required this.notes,
    required this.customerName,
    required this.customerPhone,
    required this.submittedAt,
    this.voidedAt,
    this.voidedFromStatus,
    this.roundContextOnly = false,
  });

  /// Plucks the header of the order row [o] (whose status is [status]).
  /// [tableLabels] resolves `table_id`; the PSC-001D void provenance is read
  /// only for a pending-ack void ([isPendingAckVoid]).
  factory KdsOrderHeader.pluck(
    Map<String, dynamic> o, {
    required String status,
    required Map<String, String> tableLabels,
    bool isPendingAckVoid = false,
    bool roundContextOnly = false,
  }) {
    final tableId = o['table_id'];
    final orderType = o['order_type'];
    final notes = o['notes'];
    // ORDER-CUSTOMER-001: the OPTIONAL customer display name (money-free pluck,
    // trimmed + empty->null). Present on the kitchen wire row because
    // app.redact_money only strips *_minor/receipt keys, not this display text.
    final customerName = o['customer_name'];
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL phone (money-free scalar
    // pluck, trimmed + empty->null). Present on the kitchen wire row because
    // app.redact_money only strips *_minor/receipt keys, not this display text.
    final customerPhone = o['customer_phone'];
    // PSC-001D: the cancellation card's honest void time + source state —
    // money-free scalar plucks, present only on a pending-ack void.
    final voidedAtRaw = o['voided_at'];
    final voidedFromRaw = o['voided_from_status'];
    return KdsOrderHeader(
      status: status,
      orderType: orderType is String ? orderType : null,
      tableLabel: tableId is String ? tableLabels[tableId] : null,
      notes: notes is String && notes.isNotEmpty ? notes : null,
      customerName: customerName is String && customerName.trim().isNotEmpty
          ? customerName.trim()
          : null,
      customerPhone: customerPhone is String && customerPhone.trim().isNotEmpty
          ? customerPhone.trim()
          : null,
      // DESIGN-001 display-only pluck: when the order was submitted, for the
      // elapsed/urgency pill. `created_at` is the stable server insert time
      // (`updated_at` bumps on every status push and would under-report
      // age); `client_created_at` is the offline-client fallback. Still a
      // money-free pluck — timestamps only.
      submittedAt: parseKdsTimestamp(o['created_at'], o['client_created_at']),
      voidedAt: isPendingAckVoid && voidedAtRaw is String
          ? DateTime.tryParse(voidedAtRaw)
          : null,
      voidedFromStatus: isPendingAckVoid && voidedFromRaw is String
          ? voidedFromRaw
          : null,
      roundContextOnly: roundContextOnly,
    );
  }

  final String status;
  final String? orderType;
  final String? tableLabel;
  final String? notes;
  final String? customerName;
  final String? customerPhone;
  final DateTime? submittedAt;

  /// PSC-001D: set ONLY for a pending-acknowledgement void (the red card).
  final DateTime? voidedAt;
  final String? voidedFromStatus;

  /// PSC-001C: TRUE for a SERVED parent admitted only so its still-active
  /// rounds can render — its original (already bumped) items never re-appear.
  final bool roundContextOnly;
}

/// Modifier option names (and meat contributions) per `order_item_id`, built
/// once from the pulled `order_item_modifiers` rows.
class KdsItemModifiers {
  KdsItemModifiers._(this.textsByItem, this.meatByItem);

  /// Indexes [modifiers] (tombstoned modifiers skipped).
  factory KdsItemModifiers.fromRows(List<Map<String, dynamic>> modifiers) {
    // Modifier option names per order_item_id (skip tombstoned modifiers).
    // A modifier row carries an integer `quantity` (>=1, default 1); when it is
    // above 1 the display string gets a '×N' suffix (name first, U+00D7 — the
    // same convention as the KDS item line). Never money.
    // MENU-ORDER-001: collect each item's modifier lines WITH their menu-
    // configured print-order keys, snapshotted at submit (modifier GROUP display
    // order + OPTION display order) + the line_position tie-breaker, so the KDS
    // prints them in the SAME order as the cashier receipt. The wire delivers
    // modifiers `ORDER BY (updated_at, id)` — random within an item for a fresh
    // order — so the snapshot keys (not wire order) drive the sequence.
    final modLinesByItem = <String, List<_ModLine>>{};
    // KITCHEN-MEAT-001: each order item's meat contributions from its selected
    // options, PRE-MULTIPLIED by the modifier units (× the item quantity is
    // applied per item below). Money-free; only options carrying meat_snapshot
    // contribute (nothing is inferred from a name/price).
    final meatByItem = <String, List<KitchenMeat>>{};
    for (final m in modifiers) {
      if (m['deleted_at'] != null) continue;
      final itemId = m['order_item_id'];
      final option = m['option_name_snapshot'];
      if (itemId is! String || option is! String) continue;
      final qtyRaw = m['quantity'];
      final qty = qtyRaw is int ? qtyRaw : int.tryParse('$qtyRaw') ?? 1;
      // Tolerant int-or-0 plucks — an order/server predating the columns yields
      // 0 (legacy sentinel), so those modifiers keep their wire (input) order.
      (modLinesByItem[itemId] ??= <_ModLine>[]).add(
        _ModLine(
          groupDisplayOrder: menuPrintOrderInt(
            m['modifier_group_display_order_snapshot'],
          ),
          optionDisplayOrder: menuPrintOrderInt(
            m['modifier_option_display_order_snapshot'],
          ),
          linePosition: menuPrintOrderInt(m['line_position']),
          text: qty > 1 ? '$option ×$qty' : option,
        ),
      );
      final meat = KitchenMeat.tryFromJson(m['meat_snapshot']);
      if (meat != null && qty > 0) {
        // 020 (Codex HIGH #2): scale through the domain API so the WHOLE
        // decoded contribution survives. Rebuilding it as
        // `KitchenMeat(quantity: …, unit: …)` silently dropped
        // classifierOptionId / classifierOptionName / classifierSelected, so a
        // classified size option arrived at the KDS as an unsplit total even
        // though the wire carried the answer.
        //
        // `scaledBy` multiplies the QUANTITY only, by the modifier's own units;
        // the order-item quantity is applied exactly once downstream by
        // [aggregateOrderKitchenCounts]. Nothing is multiplied twice.
        (meatByItem[itemId] ??= <KitchenMeat>[]).add(meat.scaledBy(qty));
      }
    }
    // MENU-ORDER-001: order each item's modifiers by the shared canonical key
    // (group -> option -> line_position -> input index), so the KDS prints them
    // in the SAME Dashboard order as the cashier receipt. Legacy 0 keys fall back
    // to input (wire) order — a partially-migrated order never scrambles.
    final modsByItem = <String, List<String>>{};
    for (final entry in modLinesByItem.entries) {
      final lines = sortByMenuPrintOrder(
        entry.value,
        (l) => [l.groupDisplayOrder, l.optionDisplayOrder, l.linePosition],
      );
      modsByItem[entry.key] = [for (final l in lines) l.text];
    }
    return KdsItemModifiers._(modsByItem, meatByItem);
  }

  /// order_item_id -> modifier display lines, in menu print order.
  final Map<String, List<String>> textsByItem;

  /// order_item_id -> meat contributions (× modifier units). Money-free.
  final Map<String, List<KitchenMeat>> meatByItem;

  /// The modifier display lines of [itemId] (empty when none).
  List<String> textsFor(String itemId) =>
      textsByItem[itemId] ?? const <String>[];
}

/// Builds the money-free [KdsItemView] of one `order_items` row [it] whose id
/// is [itemId]. Used for live lines AND for the retired "was" lines of the
/// edit overlay, so both render identically.
KdsItemView kdsItemViewFromRow(
  Map<String, dynamic> it, {
  required String itemId,
  required KdsItemModifiers modifiers,
}) {
  final nameRaw = it['menu_item_name_snapshot'];
  final name = nameRaw is String ? nameRaw : '';
  final qty = it['quantity'];
  final quantity = qty is int ? qty : int.tryParse('$qty') ?? 0;
  final noteRaw = it['notes'];
  final note = noteRaw is String && noteRaw.isNotEmpty ? noteRaw : null;
  // KITCHEN-PREP-001: the item's PER-UNIT prep components (money-free
  // {name,quantity,unit}) plucked from the order_items snapshot. Tolerant
  // parse — a missing/bad value yields an empty list (no prep row).
  final prepComponents = parseKitchenPrepComponents(it['prep_snapshot']);
  // MENU-ORDER-001: the item's menu-configured print-order keys — the
  // category rank + within-category rank snapshotted at submit (order_items
  // .category_display_order_snapshot / .item_display_order_snapshot) + the
  // 001D line_position tie-breaker. Tolerant int-or-0 plucks (an order/server
  // predating the columns yields 0 -> keep wire order). Non-money.
  final categoryDisplayOrder = menuPrintOrderInt(
    it['category_display_order_snapshot'],
  );
  final itemDisplayOrder = menuPrintOrderInt(it['item_display_order_snapshot']);
  final linePosition = menuPrintOrderInt(it['line_position']);
  return KdsItemView(
    name: name,
    quantity: quantity,
    // Structured modifier lines (was: flattened into the name).
    modifiers: modifiers.textsFor(itemId),
    note: note,
    prepComponents: prepComponents,
    categoryDisplayOrder: categoryDisplayOrder,
    itemDisplayOrder: itemDisplayOrder,
    linePosition: linePosition,
    // ORDER-EDIT-001C: the non-money source id (T-003) the overlay keys on.
    orderItemId: itemId,
  );
}

/// Parses the submit timestamp from the wire row: `created_at` first (the
/// stable server anchor), then `client_created_at`. Non-string / unparseable
/// values yield null — the card then shows no elapsed pill rather than a
/// fabricated age (DESIGN-001).
DateTime? parseKdsTimestamp(Object? createdAt, Object? clientCreatedAt) {
  if (createdAt is String) {
    final parsed = DateTime.tryParse(createdAt);
    if (parsed != null) return parsed;
  }
  if (clientCreatedAt is String) return DateTime.tryParse(clientCreatedAt);
  return null;
}

/// Minimal order-status -> kitchen-ticket-status projection.
KitchenTicketStatus kdsTicketStatusFor(String orderStatus) {
  return switch (orderStatus) {
    'submitted' => KitchenTicketStatus.newTicket,
    'accepted' => KitchenTicketStatus.acknowledged,
    'preparing' => KitchenTicketStatus.inPreparation,
    'ready' => KitchenTicketStatus.ready,
    _ => KitchenTicketStatus.newTicket,
  };
}

/// MENU-ORDER-001: one modifier line with its menu-configured print-order keys
/// (group display order, option display order) + the line_position tie-breaker,
/// used to sort an item's modifiers into cashier-receipt (Dashboard) order
/// before they are flattened to display strings. Money-free.
class _ModLine {
  _ModLine({
    required this.groupDisplayOrder,
    required this.optionDisplayOrder,
    required this.linePosition,
    required this.text,
  });

  final int groupDisplayOrder;
  final int optionDisplayOrder;
  final int linePosition;
  final String text;
}
