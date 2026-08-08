/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-D) — the dine-in / takeaway split.
///
/// Aggregates `owner_sales_series.buckets[].by_order_type` across a window. It
/// adds no request: the series is the one CLIENT-A already loads for the daily
/// sales trend, so this is arithmetic over data that is already on the device.
///
/// WHAT THE SERVER GUARANTEES, and why the totals here are safe to trust:
/// `type_day` and `billed_day` in migration `20260810090000` read the SAME
/// `order_win` CTE, with the SAME billed predicate
/// (`status not in ('voided','cancelled','draft')`) and the SAME net formula
/// (`sum(subtotal_minor - discount_total_minor)`) — the only difference is an
/// extra `group by order_type`. `orders.order_type` is NOT NULL and constrained
/// to the persisted tokens, so every billed order lands in exactly one row.
/// Per bucket, therefore, the typed counts and nets sum EXACTLY to the bucket's
/// own `order_count` and `net_minor`.
///
/// Gross and discount are deliberately absent: the server cannot decompose them
/// by type (they need the order-items rollup), so it does not send them, and
/// deriving them here would be invention.
library;

import '../data/owner_sales_series.dart';

/// The persisted order-type tokens, in the order an owner reads them.
///
/// Used ONLY for display ordering. An unrecognised future token is not dropped
/// — see [aggregateOrderTypeAnalytics].
const List<String> kOrderTypeWireTokens = <String>['dine_in', 'takeaway'];

/// One order type's totals for a window.
class OrderTypeAnalyticsRow {
  const OrderTypeAnalyticsRow({
    required this.orderType,
    required this.orderCount,
    required this.netMinor,
    required this.shareBps,
  });

  /// The persisted wire token (`dine_in` / `takeaway`, or an unrecognised
  /// future one), kept verbatim. Display is resolved by `orderTypeLabel`.
  final String orderType;

  /// Billed orders of this type across the window.
  final int orderCount;

  /// Billed net for this type, integer minor units.
  final int netMinor;

  /// Share of the window's ORDERS — not of its money — in basis points
  /// (1% = 100 bps), or null when the window has no orders to take a share of.
  ///
  /// Orders rather than money because the two answer different questions and a
  /// single unlabelled "share" would be read as whichever the reader assumed.
  /// The net amount is shown beside it as its own figure.
  final int? shareBps;

  /// True when a share can honestly be rendered.
  bool get hasShare => shareBps != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderTypeAnalyticsRow &&
          other.orderType == orderType &&
          other.orderCount == orderCount &&
          other.netMinor == netMinor &&
          other.shareBps == shareBps;

  @override
  int get hashCode => Object.hash(orderType, orderCount, netMinor, shareBps);

  @override
  String toString() =>
      'OrderTypeAnalyticsRow($orderType, orders: $orderCount, '
      'net: $netMinor, shareBps: $shareBps)';
}

/// Aggregates every bucket's `by_order_type` into one row per type.
///
/// A type absent from a day contributes nothing for that day and still appears
/// if any other day carries it — the server omits a type with no billed orders
/// rather than sending a zero, so absence is a real zero and needs no
/// interpolation.
///
/// UNKNOWN TOKENS ARE KEPT. A future server that starts persisting, say,
/// `delivery` must not have its orders quietly vanish: dropping the row would
/// leave the visible rows failing to sum to the window's own order count, and a
/// breakdown that does not add up is worse than one with an unfamiliar name in
/// it. Unknown types therefore count toward the denominator like any other.
///
/// Ordering is deterministic: the known tokens first, in
/// [kOrderTypeWireTokens] order, then any unknown ones alphabetically. Not
/// by size — a card whose rows reorder as the day progresses is a card an owner
/// has to re-read every time.
List<OrderTypeAnalyticsRow> aggregateOrderTypeAnalytics(
  List<OwnerSalesSeriesBucket> buckets,
) {
  final counts = <String, int>{};
  final nets = <String, int>{};
  for (final bucket in buckets) {
    for (final line in bucket.byOrderType) {
      counts[line.orderType] = (counts[line.orderType] ?? 0) + line.orderCount;
      nets[line.orderType] = (nets[line.orderType] ?? 0) + line.netMinor;
    }
  }
  if (counts.isEmpty) return const [];

  final totalOrders = counts.values.fold<int>(0, (sum, c) => sum + c);
  final tokens = counts.keys.toList()
    ..sort((a, b) {
      final ai = kOrderTypeWireTokens.indexOf(a);
      final bi = kOrderTypeWireTokens.indexOf(b);
      if (ai != -1 && bi != -1) return ai.compareTo(bi);
      if (ai != -1) return -1;
      if (bi != -1) return 1;
      return a.compareTo(b);
    });

  return [
    for (final token in tokens)
      OrderTypeAnalyticsRow(
        orderType: token,
        orderCount: counts[token]!,
        netMinor: nets[token]!,
        shareBps: orderShareBasisPoints(counts[token]!, totalOrders),
      ),
  ];
}

/// Share of orders in basis points, or null when there are no orders.
///
/// Integer arithmetic (D-007-adjacent discipline: no float enters a figure the
/// owner reads). A zero denominator yields null rather than 0: "there were no
/// orders" is not "this type had none of them".
int? orderShareBasisPoints(int typeOrderCount, int totalOrderCount) {
  if (totalOrderCount <= 0) return null;
  return (typeOrderCount * 10000) ~/ totalOrderCount;
}
