/// In-memory order-item aggregate (RF-032): an item-level line on a submitted
/// [LocalOrder], carrying the immutable RF-031 price/name snapshots and a
/// mutable [OrderItemStatus]. Pure Dart, in-memory only — NOT a persisted
/// `order_items` Drift row, and it carries NO syncable columns (`device_id`,
/// `local_operation_id`, `revision`, `deleted_at` belong to RF-052/RF-056).
library;

import '../cart/cart_line.dart';
import '../cart/cart_snapshots.dart';
import 'order_exceptions.dart';
import 'order_item_status.dart';
import 'order_state_machine.dart';
import 'order_action_authorization.dart';

class LocalOrderItem {
  LocalOrderItem({
    required this.orderItemId,
    required this.menuItemId,
    required this.itemNameSnapshot,
    required this.basePriceMinorSnapshot,
    required this.currencyCodeSnapshot,
    required this.quantity,
    required this.lineTotalMinorPreview,
    this.size,
    this.variant,
    List<ModifierOptionSnapshot> modifiers = const [],
    OrderItemStatus status = OrderItemStatus.pending,
  }) : modifiers = List.unmodifiable(modifiers),
       _status = status;

  /// Materializes an order item from an RF-031 [CartLine], copying its
  /// immutable snapshots and integer line-total preview. Initial status is
  /// `pending` (STATE_MACHINES §2 initial state).
  factory LocalOrderItem.fromCartLine(CartLine line) => LocalOrderItem(
    orderItemId: line.lineId,
    menuItemId: line.menuItemId,
    itemNameSnapshot: line.itemNameSnapshot,
    basePriceMinorSnapshot: line.basePriceMinorSnapshot,
    currencyCodeSnapshot: line.currencyCodeSnapshot,
    quantity: line.quantity,
    lineTotalMinorPreview: line.lineTotalMinor,
    size: line.size,
    variant: line.variant,
    modifiers: line.modifiers,
  );

  /// Local identity (carried from the cart line).
  final String orderItemId;

  // Immutable snapshots captured at order/cart time (DECISION D-008).
  final String menuItemId;
  final String itemNameSnapshot;
  final int basePriceMinorSnapshot;
  final String currencyCodeSnapshot;
  final SizeSnapshot? size;
  final VariantSnapshot? variant;
  final List<ModifierOptionSnapshot> modifiers;
  final int quantity;

  /// Non-authoritative integer line-total preview (RF-031; no money engine).
  final int lineTotalMinorPreview;

  OrderItemStatus _status;
  OrderItemStatus get status => _status;
  bool get isTerminal => _status.isTerminal;

  void queue() => _to(OrderItemStatus.queued);
  void startPreparing() => _to(OrderItemStatus.preparing);
  void markReady() => _to(OrderItemStatus.ready);
  void serve() => _to(OrderItemStatus.served);

  /// Cancel this item (pre-production only, per the machine). Requires a
  /// non-empty reason.
  void cancel(String reason) {
    _requireReason(reason);
    _to(OrderItemStatus.cancelled);
  }

  /// Void this item. Requires a non-empty reason and a placeholder
  /// authorization that permits voiding.
  void voidItem(String reason, OrderActionAuthorization? authorization) {
    _requireReason(reason);
    if (authorization == null || !authorization.canVoid) {
      throw const UnauthorizedVoidException();
    }
    _to(OrderItemStatus.voided);
  }

  /// System-driven cascade from a parent order cancel (no reason/auth at item
  /// level — the parent already validated). Still legality-checked.
  void cascadeCancel() => _to(OrderItemStatus.cancelled);

  /// System-driven cascade from a parent order void. Legality-checked.
  void cascadeVoid() => _to(OrderItemStatus.voided);

  void _requireReason(String reason) {
    if (reason.trim().isEmpty) throw const MissingReasonException();
  }

  void _to(OrderItemStatus to) {
    _status = OrderItemStateMachine.transition(_status, to);
  }
}
