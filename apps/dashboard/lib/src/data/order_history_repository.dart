/// The order-history data SEAM (ORDERS-HISTORY-001).
///
/// The single place the Dashboard order-history + detail data is sourced. The
/// demo implementation returns a deterministic in-memory dataset (no Supabase,
/// no backend); the real implementation ([RealOrderHistoryRepository]) reads the
/// `public.owner_order_history` / `public.owner_order_detail` RPCs over the same
/// authenticated transport the rest of the real dashboard uses. Same return
/// types, so the UI never branches on the source. Reads are async so the UI has
/// honest loading / error / empty states.
library;

import 'order_history_models.dart';

/// Loads order-history pages and single-order details for a scope.
abstract class OrderHistoryRepository {
  /// A page of history rows for [query], continuing from [cursor] (null = first
  /// page). Implementations may fail (network, auth, RLS) — surfaced as an error.
  Future<OrderHistoryPage> loadHistory(
    OrderHistoryQuery query, {
    String? cursor,
  });

  /// The full detail for [orderId] (header + items + payments).
  Future<OrderDetail> loadDetail(String orderId);
}

/// A failure loading order history / detail.
class OrderHistoryException implements Exception {
  const OrderHistoryException(this.message);

  final String message;

  @override
  String toString() => 'OrderHistoryException: $message';
}

/// One demo order + how many days ago it happened (for range filtering).
class DemoOrder {
  const DemoOrder({required this.daysAgo, required this.detail});

  final int daysAgo;
  final OrderDetail detail;
}

/// Serves order history from a deterministic in-memory dataset — honest demo
/// data, no backend. Filters/searches/paginates in memory so the UI behaves
/// exactly as it will against the real RPCs.
class DemoOrderHistoryRepository implements OrderHistoryRepository {
  DemoOrderHistoryRepository({
    List<DemoOrder>? orders,
    this.failureMessage,
    this.pageSize = 25,
  }) : _orders = orders ?? demoOrderHistory();

  final List<DemoOrder> _orders;

  /// When non-null, both loads throw an [OrderHistoryException] with this
  /// message (drives/tests the error state).
  final String? failureMessage;

  /// How many rows a page holds (so tests can exercise "load more").
  final int pageSize;

  @override
  Future<OrderHistoryPage> loadHistory(
    OrderHistoryQuery query, {
    String? cursor,
  }) async {
    final message = failureMessage;
    if (message != null) throw OrderHistoryException(message);

    final matched = _orders.where((o) => _matches(o, query)).toList();
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final slice = matched.skip(offset).take(pageSize).toList();
    final consumed = offset + slice.length;
    final hasMore = consumed < matched.length;
    return OrderHistoryPage(
      rows: slice.map(_rowOf).toList(growable: false),
      hasMore: hasMore,
      nextCursor: hasMore ? consumed.toString() : null,
    );
  }

  @override
  Future<OrderDetail> loadDetail(String orderId) async {
    final message = failureMessage;
    if (message != null) throw OrderHistoryException(message);
    for (final o in _orders) {
      if (o.detail.orderId == orderId) return o.detail;
    }
    throw const OrderHistoryException('order not found');
  }

  bool _matches(DemoOrder o, OrderHistoryQuery q) {
    final within = switch (q.range) {
      OrderHistoryRange.today => o.daysAgo == 0,
      OrderHistoryRange.yesterday => o.daysAgo == 1,
      OrderHistoryRange.last7 => o.daysAgo >= 0 && o.daysAgo <= 6,
      OrderHistoryRange.last30 => o.daysAgo >= 0 && o.daysAgo <= 29,
    };
    if (!within) return false;
    final d = o.detail;
    if (q.status.wire != null && d.status != q.status.wire) return false;
    if (q.orderType.wire != null && d.orderType != q.orderType.wire)
      return false;
    final paid = d.completedPayment != null;
    switch (q.payment) {
      case PaymentFilter.paid:
        if (!paid) return false;
      case PaymentFilter.unpaid:
        if (paid) return false;
      case PaymentFilter.cash:
        if (d.completedPayment?.method != 'cash') return false;
      case PaymentFilter.all:
        break;
    }
    final search = q.searchOrNull;
    if (search != null) {
      final needle = search.toLowerCase().replaceAll('#', '');
      final haystacks = <String?>[
        d.orderCode.toLowerCase().replaceAll('#', ''),
        d.customerName?.toLowerCase(),
        d.tableLabel?.toLowerCase(),
        d.receiptNumber?.toLowerCase(),
      ];
      if (!haystacks.any((h) => h != null && h.contains(needle))) return false;
    }
    return true;
  }

  OrderHistoryRow _rowOf(DemoOrder o) {
    final d = o.detail;
    final pay = d.completedPayment;
    var items = 0;
    for (final it in d.items) {
      items += it.quantity;
    }
    return OrderHistoryRow(
      orderId: d.orderId,
      orderCode: d.orderCode,
      status: d.status,
      orderType: d.orderType,
      createdAtLabel: d.createdAtLabel ?? '',
      itemCount: items,
      grandTotalMinor: d.grandTotalMinor,
      currencyCode: d.currencyCode,
      paid: pay != null,
      receiptNumber: d.receiptNumber,
      customerName: d.customerName,
      tableLabel: d.tableLabel,
      staffName: d.staffName,
      paymentMethod: pay?.method,
      paidAmountMinor: pay?.amountMinor,
    );
  }
}

/// The standard demo order-history dataset (ILS): a handful of orders across
/// today / yesterday / this week with variety — dine-in & takeaway, paid & open,
/// a named customer & an anonymous one, a table, item notes, and a whole-order
/// kitchen count (KITCHEN-COUNT-001) so the money-free kitchen preview has data.
List<DemoOrder> demoOrderHistory() {
  OrderDetail order({
    required String id,
    required String code,
    required String status,
    required String type,
    required int subtotal,
    required int total,
    String? customer,
    String? table,
    String? staff,
    String? receipt,
    String? createdAt,
    List<OrderDetailItem> items = const [],
    List<OrderPayment> payments = const [],
  }) => OrderDetail(
    orderId: id,
    orderCode: code,
    status: status,
    orderType: type,
    currencyCode: 'ILS',
    subtotalMinor: subtotal,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: total,
    createdAtLabel: createdAt,
    customerName: customer,
    tableLabel: table,
    branchName: 'Downtown',
    staffName: staff,
    receiptNumber: receipt,
    items: items,
    payments: payments,
  );

  OrderPayment cash(int amount, {String? receipt, String? at}) => OrderPayment(
    method: 'cash',
    status: 'completed',
    amountMinor: amount,
    tenderedMinor: amount,
    changeMinor: 0,
    receiptNumber: receipt,
    createdAtLabel: at,
  );

  return [
    DemoOrder(
      daysAgo: 0,
      detail: order(
        id: 'demo-ord-1001',
        code: '#1001AA',
        status: 'completed',
        type: 'dine_in',
        subtotal: 8400,
        total: 8400,
        customer: 'Layla',
        table: 'T3',
        staff: 'Amira',
        receipt: 'R-1001',
        createdAt: '12:40',
        items: [
          const OrderDetailItem(
            name: 'Double Burger',
            quantity: 2,
            unitPriceMinor: 3200,
            lineTotalMinor: 6400,
            notes: 'No pickles',
            modifiers: [
              OrderDetailModifier(
                optionName: 'Double patty',
                quantity: 1,
                priceMinor: 0,
                meatQuantity: 2,
                meatUnit: 'patties',
              ),
            ],
          ),
          const OrderDetailItem(
            name: 'Fries',
            quantity: 2,
            unitPriceMinor: 1000,
            lineTotalMinor: 2000,
          ),
        ],
        payments: [cash(8400, receipt: 'R-1001', at: '12:41')],
      ),
    ),
    DemoOrder(
      daysAgo: 0,
      detail: order(
        id: 'demo-ord-1002',
        code: '#1002BB',
        status: 'preparing',
        type: 'takeaway',
        subtotal: 3600,
        total: 3600,
        staff: 'Amira',
        createdAt: '12:58',
        items: [
          const OrderDetailItem(
            name: 'Chicken Wrap',
            quantity: 1,
            unitPriceMinor: 3600,
            lineTotalMinor: 3600,
            notes: 'Spicy',
          ),
        ],
      ),
    ),
    DemoOrder(
      daysAgo: 0,
      detail: order(
        id: 'demo-ord-1003',
        code: '#1003CC',
        status: 'completed',
        type: 'takeaway',
        subtotal: 2200,
        total: 2200,
        customer: 'Noah',
        staff: 'Sami',
        receipt: 'R-1002',
        createdAt: '13:20',
        items: [
          const OrderDetailItem(
            name: 'Falafel Plate',
            quantity: 1,
            unitPriceMinor: 2200,
            lineTotalMinor: 2200,
          ),
        ],
        payments: [cash(2200, receipt: 'R-1002', at: '13:21')],
      ),
    ),
    DemoOrder(
      daysAgo: 1,
      detail: order(
        id: 'demo-ord-0991',
        code: '#0991DD',
        status: 'completed',
        type: 'dine_in',
        subtotal: 12600,
        total: 12600,
        customer: 'Maya',
        table: 'T7',
        staff: 'Amira',
        receipt: 'R-0991',
        createdAt: 'Yesterday 19:05',
        items: [
          const OrderDetailItem(
            name: 'Mixed Grill',
            quantity: 1,
            unitPriceMinor: 9800,
            lineTotalMinor: 9800,
          ),
          const OrderDetailItem(
            name: 'Lemonade',
            quantity: 2,
            unitPriceMinor: 1400,
            lineTotalMinor: 2800,
          ),
        ],
        payments: [cash(12600, receipt: 'R-0991', at: 'Yesterday 19:40')],
      ),
    ),
    DemoOrder(
      daysAgo: 3,
      detail: order(
        id: 'demo-ord-0955',
        code: '#0955EE',
        status: 'voided',
        type: 'dine_in',
        subtotal: 4500,
        total: 4500,
        table: 'T2',
        staff: 'Sami',
        createdAt: '3 days ago',
        items: [
          const OrderDetailItem(
            name: 'Shakshuka',
            quantity: 1,
            unitPriceMinor: 4500,
            lineTotalMinor: 4500,
          ),
        ],
      ),
    ),
  ];
}
