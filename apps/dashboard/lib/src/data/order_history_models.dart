/// Models for the Dashboard order-history feature (ORDERS-HISTORY-001).
///
/// All money is integer MINOR units (D-007), read STRAIGHT from the stored
/// order/payment/item snapshots the backend returns (D-008) — nothing here
/// recomputes a total from live menu prices. These are plain immutable value
/// objects so the demo and real (RPC) repositories map into the SAME shape and
/// the UI never branches on the source.
library;

/// The date window for the history list — mirrors the backend `p_range` and the
/// reports' ranges (today / yesterday / last7 / last30).
enum OrderHistoryRange {
  today('today'),
  yesterday('yesterday'),
  last7('last7'),
  last30('last30');

  const OrderHistoryRange(this.wire);

  /// The exact token the RPC expects for `p_range`.
  final String wire;

  static OrderHistoryRange fromWire(String wire) => OrderHistoryRange.values
      .firstWhere((r) => r.wire == wire, orElse: () => OrderHistoryRange.today);
}

/// Order-type filter. `all` sends null (no filter); the others map to the
/// backend `order_type` values.
enum OrderTypeFilter {
  all(null),
  dineIn('dine_in'),
  takeaway('takeaway');

  const OrderTypeFilter(this.wire);
  final String? wire;
}

/// Payment filter. `all` sends null; the others map to the backend `p_payment`
/// values (paid / unpaid / cash).
enum PaymentFilter {
  all(null),
  paid('paid'),
  unpaid('unpaid'),
  cash('cash');

  const PaymentFilter(this.wire);
  final String? wire;
}

/// Status filter — a curated subset of the order-status set plus `all` (null).
enum OrderStatusFilter {
  all(null),
  submitted('submitted'),
  preparing('preparing'),
  ready('ready'),
  completed('completed'),
  voided('voided'),
  cancelled('cancelled');

  const OrderStatusFilter(this.wire);
  final String? wire;
}

/// The full set of list controls (range + optional filters + search text). The
/// repository turns this into RPC params; the UI turns it into chips/dropdowns.
class OrderHistoryQuery {
  const OrderHistoryQuery({
    this.range = OrderHistoryRange.today,
    this.search = '',
    this.status = OrderStatusFilter.all,
    this.orderType = OrderTypeFilter.all,
    this.payment = PaymentFilter.all,
  });

  final OrderHistoryRange range;
  final String search;
  final OrderStatusFilter status;
  final OrderTypeFilter orderType;
  final PaymentFilter payment;

  OrderHistoryQuery copyWith({
    OrderHistoryRange? range,
    String? search,
    OrderStatusFilter? status,
    OrderTypeFilter? orderType,
    PaymentFilter? payment,
  }) => OrderHistoryQuery(
    range: range ?? this.range,
    search: search ?? this.search,
    status: status ?? this.status,
    orderType: orderType ?? this.orderType,
    payment: payment ?? this.payment,
  );

  /// The trimmed search, or null when blank (so the RPC skips the filter).
  String? get searchOrNull {
    final s = search.trim();
    return s.isEmpty ? null : s;
  }
}

/// One summary row in the history list (no line items — those load lazily via
/// [OrderDetail]).
class OrderHistoryRow {
  const OrderHistoryRow({
    required this.orderId,
    required this.orderCode,
    required this.status,
    required this.orderType,
    required this.createdAtLabel,
    required this.itemCount,
    required this.grandTotalMinor,
    required this.currencyCode,
    required this.paid,
    this.receiptNumber,
    this.customerName,
    this.tableLabel,
    this.staffName,
    this.paymentMethod,
    this.paidAmountMinor,
  });

  final String orderId;

  /// The shared human display code (`#XXXXXX`), the SAME one POS/KDS/receipt show.
  final String orderCode;
  final String status;
  final String orderType;
  final String createdAtLabel;
  final int itemCount;
  final int grandTotalMinor;
  final String currencyCode;

  /// Whether a completed payment exists for this order.
  final bool paid;
  final String? receiptNumber;
  final String? customerName;
  final String? tableLabel;
  final String? staffName;
  final String? paymentMethod;
  final int? paidAmountMinor;
}

/// One page of history rows + the keyset continuation.
class OrderHistoryPage {
  const OrderHistoryPage({
    required this.rows,
    this.hasMore = false,
    this.nextCursor,
  });

  const OrderHistoryPage.empty()
    : rows = const [],
      hasMore = false,
      nextCursor = null;

  final List<OrderHistoryRow> rows;
  final bool hasMore;
  final String? nextCursor;

  bool get isEmpty => rows.isEmpty;
}

/// A single non-money prep/kitchen component captured on an item at order time.
class OrderPrepComponent {
  const OrderPrepComponent({
    required this.name,
    required this.quantity,
    this.unit,
  });

  final String name;
  final num quantity;
  final String? unit;
}

/// A captured modifier snapshot on a line item. `meatUnit`/`meatQuantity` carry
/// the optional non-money kitchen-count snapshot (KITCHEN-MEAT/COUNT-001).
class OrderDetailModifier {
  const OrderDetailModifier({
    required this.optionName,
    this.modifierName,
    this.quantity = 1,
    this.priceMinor = 0,
    this.meatQuantity,
    this.meatUnit,
  });

  final String optionName;
  final String? modifierName;
  final int quantity;
  final int priceMinor;
  final num? meatQuantity;
  final String? meatUnit;
}

/// A line item on the order detail (with its captured modifier + prep snapshots).
class OrderDetailItem {
  const OrderDetailItem({
    required this.name,
    required this.quantity,
    this.unitPriceMinor = 0,
    this.lineDiscountMinor = 0,
    this.lineTotalMinor = 0,
    this.notes,
    this.modifiers = const [],
    this.prepComponents = const [],
  });

  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int lineDiscountMinor;
  final int lineTotalMinor;
  final String? notes;
  final List<OrderDetailModifier> modifiers;
  final List<OrderPrepComponent> prepComponents;
}

/// A recorded payment against the order (stored values; never recomputed).
class OrderPayment {
  const OrderPayment({
    required this.method,
    required this.status,
    required this.amountMinor,
    this.tenderedMinor = 0,
    this.changeMinor = 0,
    this.receiptNumber,
    this.createdAtLabel,
  });

  final String method;
  final String status;
  final int amountMinor;
  final int tenderedMinor;
  final int changeMinor;
  final String? receiptNumber;
  final String? createdAtLabel;

  bool get isCompleted => status == 'completed';
}

/// The full order detail: header + items + payments. Money is integer minor,
/// read from stored snapshots.
class OrderDetail {
  const OrderDetail({
    required this.orderId,
    required this.orderCode,
    required this.status,
    required this.orderType,
    required this.currencyCode,
    required this.subtotalMinor,
    required this.discountTotalMinor,
    required this.taxTotalMinor,
    required this.grandTotalMinor,
    this.createdAtLabel,
    this.customerName,
    this.tableLabel,
    this.branchName,
    this.staffName,
    this.receiptNumber,
    this.notes,
    this.items = const [],
    this.payments = const [],
  });

  final String orderId;
  final String orderCode;
  final String status;
  final String orderType;
  final String currencyCode;
  final int subtotalMinor;
  final int discountTotalMinor;
  final int taxTotalMinor;
  final int grandTotalMinor;
  final String? createdAtLabel;
  final String? customerName;
  final String? tableLabel;
  final String? branchName;
  final String? staffName;
  final String? receiptNumber;
  final String? notes;
  final List<OrderDetailItem> items;
  final List<OrderPayment> payments;

  /// The single completed payment, if any (at most one per order; D-024/D-025).
  OrderPayment? get completedPayment {
    for (final p in payments) {
      if (p.isCompleted) return p;
    }
    return null;
  }
}

/// One aggregated whole-order kitchen count line (e.g. "9 patties").
class KitchenCountLine {
  const KitchenCountLine({required this.quantity, required this.unit});

  final num quantity;
  final String unit;
}

/// Aggregates the whole-order kitchen count total from the detail's modifier
/// `meat_snapshot`s, using the SAME rule as the KDS (KITCHEN-MEAT/COUNT-001):
/// `meat.quantity × modifier.quantity × item.quantity`, grouped by unit,
/// preserving first-seen order. Money-free (never touches prices).
List<KitchenCountLine> aggregateKitchenCounts(OrderDetail detail) {
  final order = <String>[];
  final totals = <String, num>{};
  for (final item in detail.items) {
    for (final mod in item.modifiers) {
      final unit = mod.meatUnit;
      final qty = mod.meatQuantity;
      if (unit == null || qty == null) continue;
      final contribution = qty * mod.quantity * item.quantity;
      if (!totals.containsKey(unit)) {
        order.add(unit);
        totals[unit] = 0;
      }
      totals[unit] = totals[unit]! + contribution;
    }
  }
  return [
    for (final unit in order)
      KitchenCountLine(quantity: totals[unit]!, unit: unit),
  ];
}

/// Formats a kitchen-count quantity: an integer value prints without a decimal
/// point (9, not 9.0); a fractional value keeps up to 2 places.
String formatCountQuantity(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}
