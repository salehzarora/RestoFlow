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
  }) {
    // Active orders: not tombstoned, kitchen-relevant status. orderId -> status.
    final orderStatus = <String, String>{};
    for (final o in orders) {
      if (o['deleted_at'] != null) continue;
      final id = o['id'];
      final status = o['status'];
      if (id is! String || status is! String) continue;
      if (!_activeOrderStatuses.contains(status)) continue;
      orderStatus[id] = status;
    }

    // Modifier option names per order_item_id (skip tombstoned modifiers).
    final modsByItem = <String, List<String>>{};
    for (final m in modifiers) {
      if (m['deleted_at'] != null) continue;
      final itemId = m['order_item_id'];
      final option = m['option_name_snapshot'];
      if (itemId is! String || option is! String) continue;
      (modsByItem[itemId] ??= <String>[]).add(option);
    }

    // Group active items into (order, station) tickets.
    final grouped = <String, _TicketBuilder>{};
    for (final it in orderItems) {
      if (it['deleted_at'] != null) continue;
      final itemId = it['id'];
      final orderId = it['order_id'];
      if (itemId is! String || orderId is! String) continue;
      if (!orderStatus.containsKey(orderId)) continue; // parent not active
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

      final mods = modsByItem[itemId];
      final label = (mods == null || mods.isEmpty)
          ? name
          : '$name (${mods.join(', ')})';

      final key = '$orderId:$station';
      final builder = grouped.putIfAbsent(
        key,
        () => _TicketBuilder(
          kitchenTicketId: key,
          stationId: station,
          orderId: orderId,
          status: _ticketStatusFor(orderStatus[orderId]!),
        ),
      );
      builder.items.add(KdsItemView(name: label, quantity: quantity));
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
              ),
            )
            .toList()
          ..sort((a, b) => a.kitchenTicketId.compareTo(b.kitchenTicketId));
    return tickets;
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
  });

  final String kitchenTicketId;
  final String stationId;
  final String orderId;
  final KitchenTicketStatus status;
  final List<KdsItemView> items = [];
}
