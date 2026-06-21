/// Table-driven transition validators for the order and order-item state
/// machines (RF-032). The allowed-edge tables are the single source of
/// legality (STATE_MACHINES.md §1/§2: "the allowed table is exhaustive — any
/// transition not listed is FORBIDDEN"). Pure Dart.
library;

import 'order_exceptions.dart';
import 'order_item_status.dart';
import 'order_status.dart';
import 'order_type.dart';

/// Validates ORDER transitions (STATE_MACHINES.md §1). The `ready` fork is
/// parameterized by [OrderType]: takeaway goes `ready -> completed` (skipping
/// `served`); dine-in goes `ready -> served -> completed`.
abstract final class OrderStateMachine {
  /// Order edges that do NOT depend on order type. The two type-conditional
  /// `ready` edges are handled explicitly in [isLegal].
  static const Set<(OrderStatus, OrderStatus)> _typeIndependentEdges = {
    (OrderStatus.draft, OrderStatus.submitted),
    (OrderStatus.submitted, OrderStatus.accepted),
    (OrderStatus.submitted, OrderStatus.cancelled),
    (OrderStatus.accepted, OrderStatus.preparing),
    (OrderStatus.accepted, OrderStatus.cancelled),
    (OrderStatus.preparing, OrderStatus.ready),
    (OrderStatus.served, OrderStatus.completed),
    (OrderStatus.submitted, OrderStatus.voided),
    (OrderStatus.accepted, OrderStatus.voided),
    (OrderStatus.preparing, OrderStatus.voided),
    (OrderStatus.ready, OrderStatus.voided),
    (OrderStatus.served, OrderStatus.voided),
  };

  /// Whether `from -> to` is a legal order transition for [orderType].
  static bool isLegal(OrderStatus from, OrderStatus to, OrderType orderType) {
    if (from == OrderStatus.ready && to == OrderStatus.served) {
      return orderType == OrderType.dineIn; // takeaway skips `served`
    }
    if (from == OrderStatus.ready && to == OrderStatus.completed) {
      return orderType == OrderType.takeaway; // dine-in must go via `served`
    }
    return _typeIndependentEdges.contains((from, to));
  }

  /// Returns [to] if the transition is legal, else throws
  /// [IllegalOrderTransitionException]. Does not apply higher-level guards
  /// (reason/authorization/payment) — those live on the aggregate.
  static OrderStatus transition(
    OrderStatus from,
    OrderStatus to,
    OrderType orderType,
  ) {
    if (!isLegal(from, to, orderType)) {
      throw IllegalOrderTransitionException(from, to);
    }
    return to;
  }
}

/// Validates ORDER-ITEM transitions (STATE_MACHINES.md §2). No order-type fork.
abstract final class OrderItemStateMachine {
  static const Set<(OrderItemStatus, OrderItemStatus)> _edges = {
    (OrderItemStatus.pending, OrderItemStatus.queued),
    (OrderItemStatus.queued, OrderItemStatus.preparing),
    (OrderItemStatus.preparing, OrderItemStatus.ready),
    (OrderItemStatus.ready, OrderItemStatus.served),
    (OrderItemStatus.pending, OrderItemStatus.cancelled),
    (OrderItemStatus.queued, OrderItemStatus.cancelled),
    (OrderItemStatus.pending, OrderItemStatus.voided),
    (OrderItemStatus.queued, OrderItemStatus.voided),
    (OrderItemStatus.preparing, OrderItemStatus.voided),
    (OrderItemStatus.ready, OrderItemStatus.voided),
    (OrderItemStatus.served, OrderItemStatus.voided),
  };

  /// Whether `from -> to` is a legal order-item transition.
  static bool isLegal(OrderItemStatus from, OrderItemStatus to) =>
      _edges.contains((from, to));

  /// Returns [to] if legal, else throws [IllegalOrderItemTransitionException].
  static OrderItemStatus transition(OrderItemStatus from, OrderItemStatus to) {
    if (!isLegal(from, to)) {
      throw IllegalOrderItemTransitionException(from, to);
    }
    return to;
  }
}
