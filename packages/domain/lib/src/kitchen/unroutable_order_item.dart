/// An active order item that could not be routed to any station (RF-033): no
/// explicit item rule and no default station. It is FLAGGED here, never dropped
/// and never silently routed. Pure-Dart value object.
///
/// Cancelled/voided order items are NOT unroutable — they are skipped entirely.
library;

class UnroutableOrderItem {
  const UnroutableOrderItem({
    required this.orderId,
    required this.orderItemId,
    required this.menuItemId,
    required this.itemNameSnapshot,
    required this.branchId,
    this.reason = 'no station rule and no default station',
  });

  final String orderId;
  final String orderItemId;
  final String menuItemId;
  final String itemNameSnapshot;

  /// Inherited from the order (mirrors `LocalOrder`); may be null.
  final String? branchId;

  /// A short, safe explanation of why the item is unroutable.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is UnroutableOrderItem &&
      other.orderId == orderId &&
      other.orderItemId == orderItemId &&
      other.menuItemId == menuItemId &&
      other.itemNameSnapshot == itemNameSnapshot &&
      other.branchId == branchId &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(
    orderId,
    orderItemId,
    menuItemId,
    itemNameSnapshot,
    branchId,
    reason,
  );
}
