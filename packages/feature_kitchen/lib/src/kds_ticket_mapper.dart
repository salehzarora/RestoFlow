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
      orderInfo[id] = _OrderInfo(
        status: status,
        orderType: orderType is String ? orderType : null,
        tableLabel: tableId is String ? tableLabels[tableId] : null,
        notes: notes is String && notes.isNotEmpty ? notes : null,
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
    }

    // Group active items into (order, station) tickets.
    final grouped = <String, _TicketBuilder>{};
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
        ),
      );
    }

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
                notes: b.info.notes,
                submittedAt: b.info.submittedAt,
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
    required this.submittedAt,
  });

  final String status;
  final String? orderType;
  final String? tableLabel;
  final String? notes;
  final DateTime? submittedAt;
}
