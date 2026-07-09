import 'package:restoflow_domain/restoflow_domain.dart';

import 'kds_ticket_view.dart';

/// Maps raw `app.sync_pull` rows (orders / order_items / order_item_modifiers)
/// to KDS ticket view models (RF-063, approved decision A4 — minimal mapping).
///
/// Deliberately MINIMAL: it groups active order items by `(order_id,
/// station_id)`, derives the ticket status from the parent order's status, and
/// attaches modifier option names to the item label. It does NOT run the full
/// `KitchenRouter`/menu/station-routing fidelity (A4) and — critically — it
/// reads NO money field (`*_minor`, totals, prices). The kitchen redaction
/// (SECURITY T-003) is therefore not relied upon for correctness here: the KDS
/// simply never needs money.
class KdsTicketMapper {
  const KdsTicketMapper._();

  /// Order statuses whose items are shown on the KDS (active kitchen work).
  /// `served`/`completed`/`cancelled`/`voided`/`draft` are excluded.
  static const Set<String> _activeOrderStatuses = {
    'submitted',
    'accepted',
    'preparing',
    'ready',
  };

  /// Item statuses excluded from a ticket (already gone / dropped).
  static const Set<String> _excludedItemStatuses = {
    'voided',
    'cancelled',
    'served',
  };

  /// Station bucket for an item with no `station_id` (routing not yet assigned).
  static const String unassignedStation = 'unassigned';

  static List<KdsTicketView> map({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> orderItems,
    required List<Map<String, dynamic>> modifiers,
    List<Map<String, dynamic>> tables = const [],
  }) {
    // Dining-table labels (tables entity, money-free): id -> label.
    final tableLabels = <String, String>{};
    for (final t in tables) {
      if (t['deleted_at'] != null) continue;
      final id = t['id'];
      final label = t['label'];
      if (id is! String || label is! String) continue;
      tableLabels[id] = label;
    }

    // Active orders: not tombstoned, kitchen-relevant status. An EXPLICIT
    // money-free pluck per order (status, type, table, notes) — never the raw
    // row (T-003: money keys exist on the wire for non-kitchen roles).
    final orderInfo = <String, _OrderInfo>{};
    for (final o in orders) {
      if (o['deleted_at'] != null) continue;
      final id = o['id'];
      final status = o['status'];
      if (id is! String || status is! String) continue;
      if (!_activeOrderStatuses.contains(status)) continue;
      final tableId = o['table_id'];
      final orderType = o['order_type'];
      final notes = o['notes'];
      // ORDER-CUSTOMER-001: the OPTIONAL customer display name (money-free pluck,
      // trimmed + empty->null). Present on the kitchen wire row because
      // app.redact_money only strips *_minor/receipt keys, not this display text.
      final customerName = o['customer_name'];
      orderInfo[id] = _OrderInfo(
        status: status,
        orderType: orderType is String ? orderType : null,
        tableLabel: tableId is String ? tableLabels[tableId] : null,
        notes: notes is String && notes.isNotEmpty ? notes : null,
        customerName: customerName is String && customerName.trim().isNotEmpty
            ? customerName.trim()
            : null,
        // DESIGN-001 display-only pluck: when the order was submitted, for the
        // elapsed/urgency pill. `created_at` is the stable server insert time
        // (`updated_at` bumps on every status push and would under-report
        // age); `client_created_at` is the offline-client fallback. Still a
        // money-free pluck — timestamps only.
        submittedAt: _parseTimestamp(o['created_at'], o['client_created_at']),
      );
    }

    // Modifier option names per order_item_id (skip tombstoned modifiers).
    // A modifier row carries an integer `quantity` (>=1, default 1); when it is
    // above 1 the display string gets a '×N' suffix (name first, U+00D7 — the
    // same convention as the KDS item line). Never money.
    final modsByItem = <String, List<String>>{};
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
      (modsByItem[itemId] ??= <String>[]).add(
        qty > 1 ? '$option ×$qty' : option,
      );
      final meat = KitchenMeat.tryFromJson(m['meat_snapshot']);
      if (meat != null && qty > 0) {
        (meatByItem[itemId] ??= <KitchenMeat>[]).add(
          KitchenMeat(quantity: meat.quantity * qty, unit: meat.unit),
        );
      }
    }

    // Group active items into (order, station) tickets.
    final grouped = <String, _TicketBuilder>{};
    // KDS-ALERTS-AND-KITCHEN-COUNTS-002: WHOLE-ORDER count contributions keyed by
    // order id, unified across BOTH the modifier-option counts (patties, …) AND
    // the item-base counts (buns, …). Aggregated across ALL of an order's items
    // (not per station) so the top-of-ticket summary is the total the kitchen
    // needs for the whole order. Money-free; only explicit owner config feeds it.
    final countContribsByOrder = <String, List<KitchenCountContribution>>{};
    for (final it in orderItems) {
      if (it['deleted_at'] != null) continue;
      final itemId = it['id'];
      final orderId = it['order_id'];
      if (itemId is! String || orderId is! String) continue;
      final info = orderInfo[orderId];
      if (info == null) continue; // parent not active
      final itemStatus = it['status'];
      if (itemStatus is String && _excludedItemStatuses.contains(itemStatus)) {
        continue;
      }
      final stationRaw = it['station_id'];
      final station = stationRaw is String && stationRaw.isNotEmpty
          ? stationRaw
          : unassignedStation;
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

      final key = '$orderId:$station';
      final builder = grouped.putIfAbsent(
        key,
        () => _TicketBuilder(
          kitchenTicketId: key,
          stationId: station,
          orderId: orderId,
          status: _ticketStatusFor(info.status),
          info: info,
        ),
      );
      builder.items.add(
        KdsItemView(
          name: name,
          quantity: quantity,
          // Structured modifier lines (was: flattened into the name).
          modifiers: modsByItem[itemId] ?? const <String>[],
          note: note,
          prepComponents: prepComponents,
        ),
      );
      // KDS-ALERTS-AND-KITCHEN-COUNTS-002: accumulate this item's counted-resource
      // contributions for the whole order — factor = the ordered item quantity.
      if (quantity > 0) {
        final contribs = countContribsByOrder[orderId] ??=
            <KitchenCountContribution>[];
        // Per-OPTION counts (already × modifier units): label = the resource the
        // owner typed as the option's count unit (e.g. "قطع لحم").
        final itemMeat = meatByItem[itemId];
        if (itemMeat != null) {
          for (final meat in itemMeat) {
            contribs.add(
              KitchenCountContribution(
                quantity: meat.quantity,
                label: meat.unit,
                factor: quantity,
              ),
            );
          }
        }
        // Per-ITEM base counts (buns, wraps, trays, …): label = the prep
        // component's resource name (+ unit when the owner set one).
        for (final prep in prepComponents) {
          contribs.add(
            KitchenCountContribution(
              quantity: prep.quantity,
              label: _countLabel(prep),
              factor: quantity,
            ),
          );
        }
      }
    }

    // KDS-ALERTS-AND-KITCHEN-COUNTS-002: the whole-order count totals per order
    // (grouped by resource label), attached to every ticket of that order below.
    final kitchenCountsByOrder = <String, List<KitchenCount>>{
      for (final entry in countContribsByOrder.entries)
        entry.key: aggregateKitchenCounts(entry.value),
    };

    final tickets =
        grouped.values
            .map(
              (b) => KdsTicketView(
                kitchenTicketId: b.kitchenTicketId,
                stationId: b.stationId,
                items: b.items,
                status: b.status,
                orderId: b.orderId,
                // The SAME display code the POS shows (shared derivation).
                orderNumber: displayOrderCode(b.orderId),
                orderType: b.info.orderType,
                tableLabel: b.info.tableLabel,
                customerName: b.info.customerName,
                notes: b.info.notes,
                submittedAt: b.info.submittedAt,
                // KDS-ALERTS-AND-KITCHEN-COUNTS-002: the unified whole-order
                // count totals (patties + buns + …) shown at the top. Money-free.
                kitchenCounts:
                    kitchenCountsByOrder[b.orderId] ?? const <KitchenCount>[],
              ),
            )
            .toList()
          ..sort((a, b) => a.kitchenTicketId.compareTo(b.kitchenTicketId));
    return tickets;
  }

  /// Parses the submit timestamp from the wire row: `created_at` first (the
  /// stable server anchor), then `client_created_at`. Non-string / unparseable
  /// values yield null — the card then shows no elapsed pill rather than a
  /// fabricated age (DESIGN-001).
  static DateTime? _parseTimestamp(Object? createdAt, Object? clientCreatedAt) {
    if (createdAt is String) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) return parsed;
    }
    if (clientCreatedAt is String) return DateTime.tryParse(clientCreatedAt);
    return null;
  }

  /// The resource label for an item-base prep component: its [name], plus the
  /// [unit] when the owner set one (e.g. "خبز" / "Fish pcs"). This is the key the
  /// whole-order counts group by, so item-base counts and modifier-option counts
  /// with the same label merge into one total.
  static String _countLabel(KitchenPrepComponent component) {
    final unit = component.unit.trim();
    return unit.isEmpty ? component.name : '${component.name} $unit';
  }

  /// Minimal order-status -> kitchen-ticket-status projection.
  static KitchenTicketStatus _ticketStatusFor(String orderStatus) {
    return switch (orderStatus) {
      'submitted' => KitchenTicketStatus.newTicket,
      'accepted' => KitchenTicketStatus.acknowledged,
      'preparing' => KitchenTicketStatus.inPreparation,
      'ready' => KitchenTicketStatus.ready,
      _ => KitchenTicketStatus.newTicket,
    };
  }
}

class _TicketBuilder {
  _TicketBuilder({
    required this.kitchenTicketId,
    required this.stationId,
    required this.orderId,
    required this.status,
    required this.info,
  });

  final String kitchenTicketId;
  final String stationId;
  final String orderId;
  final KitchenTicketStatus status;
  final _OrderInfo info;
  final List<KdsItemView> items = [];
}

/// The explicit money-free pluck of one active order's display fields.
class _OrderInfo {
  const _OrderInfo({
    required this.status,
    required this.orderType,
    required this.tableLabel,
    required this.notes,
    required this.customerName,
    required this.submittedAt,
  });

  final String status;
  final String? orderType;
  final String? tableLabel;
  final String? notes;
  final String? customerName;
  final DateTime? submittedAt;
}
