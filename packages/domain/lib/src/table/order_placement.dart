/// An immutable order placement / service mode (RF-035): a dine-in order
/// assigned to a table, or a takeaway order with no table. Reuses RF-032
/// [OrderType]. Pure-Dart value object — it does NOT write to or mutate
/// `LocalOrder`, and no `tableId` is added to `LocalOrder`.
library;

import '../order/order_type.dart';
import 'table_exceptions.dart';

class OrderPlacement {
  OrderPlacement._({
    required this.orderId,
    required this.orderType,
    this.tableId,
  }) {
    if (orderId.trim().isEmpty) {
      throw const InvalidOrderPlacementException('orderId must not be empty');
    }
    if (orderType == OrderType.dineIn &&
        (tableId == null || tableId!.trim().isEmpty)) {
      throw const MissingTableForDineInException();
    }
    if (orderType == OrderType.takeaway && tableId != null) {
      throw const InvalidOrderPlacementException(
        'a takeaway placement must not carry a tableId',
      );
    }
  }

  /// A dine-in placement: requires a non-empty [tableId].
  factory OrderPlacement.dineIn(String orderId, String tableId) =>
      OrderPlacement._(
        orderId: orderId,
        orderType: OrderType.dineIn,
        tableId: tableId,
      );

  /// A takeaway placement: carries no table.
  factory OrderPlacement.takeaway(String orderId) =>
      OrderPlacement._(orderId: orderId, orderType: OrderType.takeaway);

  final String orderId;
  final OrderType orderType;

  /// The assigned table for dine-in; always null for takeaway.
  final String? tableId;

  @override
  bool operator ==(Object other) =>
      other is OrderPlacement &&
      other.orderId == orderId &&
      other.orderType == orderType &&
      other.tableId == tableId;

  @override
  int get hashCode => Object.hash(orderId, orderType, tableId);
}
