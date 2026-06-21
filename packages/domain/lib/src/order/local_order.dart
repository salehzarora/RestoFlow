/// In-memory draft-order aggregate (RF-032): the order-level entity produced by
/// "submitting" an RF-031 [Cart]. It holds the tenant/currency/order-type
/// context, an [OrderStatus], and the list of [LocalOrderItem]s, and enforces
/// the order state machine (STATE_MACHINES.md §1).
///
/// This is IN-MEMORY only — it is NOT persisted, NOT enqueued to an outbox,
/// NOT synced, and does NOT call any backend or generate receipt numbers. The
/// server submit RPC (RF-052), outbox/sync (RF-056/RF-057), real void auth +
/// audit (RF-053), and money totals (RF-036) are all owned downstream. Money is
/// carried only as the non-authoritative integer [subtotalMinorPreview].
library;

import '../cart/cart.dart';
import 'local_order_item.dart';
import 'order_action_authorization.dart';
import 'order_exceptions.dart';
import 'order_item_status.dart';
import 'order_state_machine.dart';
import 'order_status.dart';
import 'order_type.dart';

class LocalOrder {
  LocalOrder._({
    required this.orderId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.currencyCode,
    required this.orderType,
    required this.subtotalMinorPreview,
    required List<LocalOrderItem> items,
    required OrderStatus status,
  }) : _items = items,
       _status = status;

  /// Local "submission": materialize an RF-031 [cart] into a `submitted`
  /// in-memory order aggregate, copying lines into [LocalOrderItem]s and the
  /// non-authoritative subtotal preview. Requires a non-empty cart.
  ///
  /// Persists nothing, enqueues no outbox op, calls no backend, and generates
  /// no receipt number — those belong to RF-052/RF-056.
  factory LocalOrder.submitFromCart(Cart cart, {required OrderType orderType}) {
    if (cart.isEmpty) {
      throw const EmptyOrderException();
    }
    return LocalOrder._(
      orderId: cart.orderId,
      organizationId: cart.organizationId,
      restaurantId: cart.restaurantId,
      branchId: cart.branchId,
      currencyCode: cart.currencyCode,
      orderType: orderType,
      subtotalMinorPreview: cart.subtotalMinor,
      items: cart.lines.map(LocalOrderItem.fromCartLine).toList(),
      status: OrderStatus.submitted,
    );
  }

  /// Injected client order id (DECISION D-010); carried from the cart.
  final String orderId;

  // Tenant scope (DECISION D-001/D-002); branchId may be null.
  final String organizationId;
  final String restaurantId;
  final String? branchId;

  final String currencyCode;
  final OrderType orderType;

  /// Non-authoritative integer subtotal preview (RF-031). RF-032 computes no
  /// discounts/tax/service charge/rounding/totals (that is RF-036).
  final int subtotalMinorPreview;

  final List<LocalOrderItem> _items;
  OrderStatus _status;

  OrderStatus get status => _status;
  List<LocalOrderItem> get items => List.unmodifiable(_items);
  bool get isTerminal => _status.isTerminal;

  void accept() => _to(OrderStatus.accepted);
  void startPreparing() => _to(OrderStatus.preparing);
  void markReady() => _to(OrderStatus.ready);

  /// Serve the order. Legal only `ready -> served` for dine-in; a takeaway
  /// order is rejected here (it skips `served`).
  void serve() => _to(OrderStatus.served);

  /// Complete the order: `served -> completed` (dine-in) or `ready -> completed`
  /// (takeaway). Requires the injected [paymentSettled] precondition — RF-032
  /// has no payment model; the authoritative gate is server-side (D-025).
  void complete({required bool paymentSettled}) {
    OrderStateMachine.transition(_status, OrderStatus.completed, orderType);
    if (!paymentSettled) {
      throw const PaymentNotSettledException();
    }
    _status = OrderStatus.completed;
  }

  /// Cancel the order (pre-production only). Requires a non-empty [reason];
  /// legal only from `submitted`/`accepted` AND while no item has reached
  /// `preparing`; rejected if [hasCompletedPayment] (D-024). Cascades the
  /// order's own still-cancellable (`pending`/`queued`) items to `cancelled`.
  void cancel({required String reason, bool hasCompletedPayment = false}) {
    if (!OrderStateMachine.isLegal(_status, OrderStatus.cancelled, orderType)) {
      throw IllegalOrderTransitionException(_status, OrderStatus.cancelled);
    }
    if (reason.trim().isEmpty) {
      throw const MissingReasonException();
    }
    if (_anyItemInProduction()) {
      throw const CancelNotAllowedException(
        'cannot cancel once an item has started production',
      );
    }
    if (hasCompletedPayment) {
      throw const CompletedPaymentBlockException();
    }
    _status = OrderStatus.cancelled;
    for (final item in _items) {
      if (item.status == OrderItemStatus.pending ||
          item.status == OrderItemStatus.queued) {
        item.cascadeCancel();
      }
    }
  }

  /// Void the order (post-submission only). Requires a non-empty [reason] and a
  /// placeholder [authorization] that permits voiding; rejected if
  /// [hasCompletedPayment] (D-024). Cascades the order's own non-terminal items
  /// to `voided`. RF-032 writes NO audit event (that is RF-053).
  void voidOrder({
    required String reason,
    required OrderActionAuthorization? authorization,
    bool hasCompletedPayment = false,
  }) {
    if (!OrderStateMachine.isLegal(_status, OrderStatus.voided, orderType)) {
      throw IllegalOrderTransitionException(_status, OrderStatus.voided);
    }
    if (reason.trim().isEmpty) {
      throw const MissingReasonException();
    }
    if (authorization == null || !authorization.canVoid) {
      throw const UnauthorizedVoidException();
    }
    if (hasCompletedPayment) {
      throw const CompletedPaymentBlockException();
    }
    _status = OrderStatus.voided;
    for (final item in _items) {
      if (!item.status.isTerminal) {
        item.cascadeVoid();
      }
    }
  }

  bool _anyItemInProduction() => _items.any(
    (i) =>
        i.status == OrderItemStatus.preparing ||
        i.status == OrderItemStatus.ready ||
        i.status == OrderItemStatus.served,
  );

  void _to(OrderStatus to) {
    _status = OrderStateMachine.transition(_status, to, orderType);
  }
}
