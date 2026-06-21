/// An in-memory kitchen station item (RF-033): the per-station unit of work for
/// a single routable order item, grouped under a [KitchenTicket]. Pure-Dart
/// value object — NOT persisted, NOT synced, and it carries NO status/state
/// machine (kitchen statuses + transitions are RF-034) and no syncable columns.
///
/// Tenant/station fields are inherited from the routed `LocalOrder`
/// (DOMAIN_MODEL.md §7.2). `branchId` may be null (mirrors `LocalOrder`).
library;

class KitchenStationItem {
  const KitchenStationItem({
    required this.kitchenStationItemId,
    required this.kitchenTicketId,
    required this.orderId,
    required this.orderItemId,
    required this.menuItemId,
    required this.itemNameSnapshot,
    required this.quantity,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.stationId,
  });

  /// Deterministic local id: `$orderId:$stationId:$orderItemId` (RF-033).
  final String kitchenStationItemId;

  /// Owning ticket's deterministic id: `$orderId:$stationId`.
  final String kitchenTicketId;

  final String orderId;
  final String orderItemId;
  final String menuItemId;

  /// Display name snapshot carried from the order item (KDS convenience).
  final String itemNameSnapshot;

  /// Integer count carried from the order item.
  final int quantity;

  // Tenant/station scope (RF-033 AC#2) — inherited from the order + rule.
  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final String stationId;

  @override
  bool operator ==(Object other) =>
      other is KitchenStationItem &&
      other.kitchenStationItemId == kitchenStationItemId &&
      other.kitchenTicketId == kitchenTicketId &&
      other.orderId == orderId &&
      other.orderItemId == orderItemId &&
      other.menuItemId == menuItemId &&
      other.itemNameSnapshot == itemNameSnapshot &&
      other.quantity == quantity &&
      other.organizationId == organizationId &&
      other.restaurantId == restaurantId &&
      other.branchId == branchId &&
      other.stationId == stationId;

  @override
  int get hashCode => Object.hash(
    kitchenStationItemId,
    kitchenTicketId,
    orderId,
    orderItemId,
    menuItemId,
    itemNameSnapshot,
    quantity,
    organizationId,
    restaurantId,
    branchId,
    stationId,
  );
}
