/// An in-memory kitchen ticket (RF-033): one station's grouping of the order
/// items routed to it — one ticket per station per order (DOMAIN_MODEL.md §7.1).
/// Pure-Dart value object — NOT persisted, NOT synced; it carries NO status/
/// state machine (kitchen statuses + bump/recall are RF-034).
///
/// `branchId` may be null (mirrors the routed `LocalOrder`).
library;

import 'kitchen_station_item.dart';

class KitchenTicket {
  KitchenTicket({
    required this.kitchenTicketId,
    required this.orderId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.stationId,
    required List<KitchenStationItem> stationItems,
  }) : stationItems = List.unmodifiable(stationItems);

  /// Deterministic local id: `$orderId:$stationId` (RF-033).
  final String kitchenTicketId;

  final String orderId;

  // Tenant/station scope (RF-033 AC#2) — inherited from the order + rule.
  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final String stationId;

  /// Read-only station items routed to this station, sorted by `orderItemId`.
  final List<KitchenStationItem> stationItems;

  @override
  bool operator ==(Object other) =>
      other is KitchenTicket &&
      other.kitchenTicketId == kitchenTicketId &&
      other.orderId == orderId &&
      other.organizationId == organizationId &&
      other.restaurantId == restaurantId &&
      other.branchId == branchId &&
      other.stationId == stationId &&
      _listEquals(other.stationItems, stationItems);

  @override
  int get hashCode => Object.hash(
    kitchenTicketId,
    orderId,
    organizationId,
    restaurantId,
    branchId,
    stationId,
    Object.hashAll(stationItems),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
