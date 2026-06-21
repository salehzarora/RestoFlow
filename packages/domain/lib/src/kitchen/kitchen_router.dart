/// Pure, deterministic kitchen routing (RF-033): routes a submitted
/// `LocalOrder`'s active items to stations per the injected
/// [KitchenRoutingRules], producing an in-memory [KitchenRoutingResult].
///
/// It is a PURE FUNCTION — it does not mutate the order or its items, performs
/// no persistence/backend/outbox, and uses no `DateTime.now`, randomness, or
/// UUID generation. Ids are deterministic composite keys, so re-routing the
/// same order with the same rules returns a value-equal result.
library;

import '../order/local_order.dart';
import '../order/order_item_status.dart';
import 'kitchen_routing_result.dart';
import 'kitchen_routing_rules.dart';
import 'kitchen_station_item.dart';
import 'kitchen_ticket.dart';
import 'unroutable_order_item.dart';

abstract final class KitchenRouter {
  /// Routes [order]'s ACTIVE items (not `cancelled`/`voided`) to stations.
  /// Active items with no matching rule and no default station are flagged in
  /// [KitchenRoutingResult.unroutableItems] (never dropped, never thrown).
  static KitchenRoutingResult route(
    LocalOrder order,
    KitchenRoutingRules rules,
  ) {
    final byStation = <String, List<KitchenStationItem>>{};
    final unroutable = <UnroutableOrderItem>[];

    for (final item in order.items) {
      // Active = not cancelled, not voided. Skipped items are NOT unroutable.
      final isActive =
          item.status != OrderItemStatus.cancelled &&
          item.status != OrderItemStatus.voided;
      if (!isActive) continue;

      final stationId = rules.stationFor(item.menuItemId);
      if (stationId == null) {
        unroutable.add(
          UnroutableOrderItem(
            orderId: order.orderId,
            orderItemId: item.orderItemId,
            menuItemId: item.menuItemId,
            itemNameSnapshot: item.itemNameSnapshot,
            branchId: order.branchId,
          ),
        );
        continue;
      }

      final ticketId = '${order.orderId}:$stationId';
      (byStation[stationId] ??= <KitchenStationItem>[]).add(
        KitchenStationItem(
          kitchenStationItemId: '$ticketId:${item.orderItemId}',
          kitchenTicketId: ticketId,
          orderId: order.orderId,
          orderItemId: item.orderItemId,
          menuItemId: item.menuItemId,
          itemNameSnapshot: item.itemNameSnapshot,
          quantity: item.quantity,
          organizationId: order.organizationId,
          restaurantId: order.restaurantId,
          branchId: order.branchId,
          stationId: stationId,
        ),
      );
    }

    // Deterministic ordering: tickets by stationId, items by orderItemId.
    final stationIds = byStation.keys.toList()..sort();
    final tickets = <KitchenTicket>[];
    for (final stationId in stationIds) {
      final items = byStation[stationId]!
        ..sort((a, b) => a.orderItemId.compareTo(b.orderItemId));
      tickets.add(
        KitchenTicket(
          kitchenTicketId: '${order.orderId}:$stationId',
          orderId: order.orderId,
          organizationId: order.organizationId,
          restaurantId: order.restaurantId,
          branchId: order.branchId,
          stationId: stationId,
          stationItems: items,
        ),
      );
    }

    unroutable.sort((a, b) => a.orderItemId.compareTo(b.orderItemId));

    return KitchenRoutingResult(tickets: tickets, unroutableItems: unroutable);
  }
}
