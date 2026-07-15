/// Table-driven transition validators for the order and order-item state
/// machines (RF-032). The allowed-edge tables are the single source of
/// legality (STATE_MACHINES.md §1/§2: "the allowed table is exhaustive — any
/// transition not listed is FORBIDDEN"). Pure Dart.
library;

import 'order_exceptions.dart';
import 'order_item_status.dart';
import 'order_status.dart';
import 'order_type.dart';

/// Validates ORDER transitions (STATE_MACHINES.md §1).
///
/// RESTAURANT-OPERATIONS-V1-001 (review B3): BOTH order types share the ONE
/// canonical chain `submitted -> accepted -> preparing -> ready -> served ->
/// completed`. `served` is a real lifecycle state for takeaway too — the POS
/// and KDS merely DISPLAY it as "Picked up" (a wording concern, not a state);
/// there is NO persisted `picked_up` state. `ready -> completed` is NOT a
/// legal direct transition for either type: the server's auto-completion of a
/// served+settled order is a SIDE EFFECT of settlement, never a manual
/// transition, so it does not appear in this legality table.
abstract final class OrderStateMachine {
  /// The exhaustive legal order edges — identical for both order types.
  static const Set<(OrderStatus, OrderStatus)> _edges = {
    (OrderStatus.draft, OrderStatus.submitted),
    (OrderStatus.submitted, OrderStatus.accepted),
    (OrderStatus.submitted, OrderStatus.cancelled),
    (OrderStatus.accepted, OrderStatus.preparing),
    (OrderStatus.accepted, OrderStatus.cancelled),
    (OrderStatus.preparing, OrderStatus.ready),
    (OrderStatus.ready, OrderStatus.served),
    (OrderStatus.served, OrderStatus.completed),
    (OrderStatus.submitted, OrderStatus.voided),
    (OrderStatus.accepted, OrderStatus.voided),
    (OrderStatus.preparing, OrderStatus.voided),
    (OrderStatus.ready, OrderStatus.voided),
    (OrderStatus.served, OrderStatus.voided),
  };

  /// Whether `from -> to` is a legal order transition. [orderType] is retained
  /// on the signature (callers legitimately carry it; the aggregate passes it
  /// through) but no edge depends on it — the lifecycle is shared (review B3).
  static bool isLegal(OrderStatus from, OrderStatus to, OrderType orderType) =>
      _edges.contains((from, to));

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
