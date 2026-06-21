/// In-memory table assignment service (RF-035): assigns a dine-in `LocalOrder`
/// to a `DiningTable`, marks a `LocalOrder` as takeaway, and prevents two
/// concurrent OPEN dine-in orders on the same table unless [TablePolicy] allows
/// it. Pure Dart, in-memory only — NO persistence, NO Drift, NO backend. It does
/// not mutate the order or its state machine (RF-032 is read-only here).
library;

import '../order/local_order.dart';
import '../order/order_type.dart';
import 'dining_table.dart';
import 'order_placement.dart';
import 'table_exceptions.dart';
import 'table_policy.dart';

class TableAssignmentService {
  TableAssignmentService({this.policy = const TablePolicy()});

  final TablePolicy policy;

  final List<_Assignment> _assignments = [];

  /// Read-only view of the placements recorded so far.
  List<OrderPlacement> get placements =>
      List.unmodifiable(_assignments.map((a) => a.placement));

  /// Assigns a dine-in [order] to [table]. Enforces order-type, table activity,
  /// tenant match, and (unless the policy allows sharing) the
  /// one-open-dine-in-per-table rule. Returns the recorded [OrderPlacement].
  OrderPlacement assignDineIn({
    required LocalOrder order,
    required DiningTable table,
  }) {
    if (order.orderType != OrderType.dineIn) {
      throw const OrderTypeMismatchException(
        'assignDineIn requires an order with OrderType.dineIn',
      );
    }
    if (!table.isActive) {
      throw const InactiveTableException();
    }
    if (order.organizationId != table.organizationId ||
        order.restaurantId != table.restaurantId ||
        order.branchId != table.branchId) {
      throw const TableTenantMismatchException();
    }
    if (!policy.allowMultipleOpenDineInPerTable) {
      final occupiedByAnother = _openDineInOrdersForTable(
        table.tableId,
      ).any((o) => o.orderId != order.orderId);
      if (occupiedByAnother) {
        throw const TableOccupiedException();
      }
    }

    final placement = OrderPlacement.dineIn(order.orderId, table.tableId);
    _assignments.add(_Assignment(order, placement));
    return placement;
  }

  /// Marks [order] as takeaway. Takeaway never occupies a table and never
  /// conflicts with table occupancy.
  OrderPlacement assignTakeaway({required LocalOrder order}) {
    if (order.orderType != OrderType.takeaway) {
      throw const OrderTypeMismatchException(
        'assignTakeaway requires an order with OrderType.takeaway',
      );
    }
    final placement = OrderPlacement.takeaway(order.orderId);
    _assignments.add(_Assignment(order, placement));
    return placement;
  }

  /// The OPEN (non-terminal) dine-in orders currently assigned to [tableId].
  /// Terminal orders (completed/cancelled/voided) no longer occupy the table.
  Iterable<LocalOrder> _openDineInOrdersForTable(String tableId) => _assignments
      .where(
        (a) =>
            a.placement.orderType == OrderType.dineIn &&
            a.placement.tableId == tableId &&
            !a.order.isTerminal,
      )
      .map((a) => a.order);
}

class _Assignment {
  _Assignment(this.order, this.placement);

  final LocalOrder order;
  final OrderPlacement placement;
}
