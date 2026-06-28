/// The owner-report CALCULATOR (RF-119): derives a [DashboardReport] from a
/// structured [OwnerReportDataset]. Pure + deterministic — every figure is
/// computed from the dataset's orders / payments / shift; nothing is hardcoded.
/// All money is integer MINOR units (DECISION D-007); the only division is
/// integer (truncating). No floating-point money anywhere.
library;

import 'demo_report.dart';
import 'owner_report_source.dart';

/// Computes the owner [DashboardReport] for [data].
DashboardReport computeOwnerReport(OwnerReportDataset data) {
  final currency = data.currencyCode;

  // Sales = every order except voided/cancelled.
  final sales = data.orders.where((o) => o.status.isSale).toList();
  final paid = data.orders.where((o) => o.isPaid).toList();

  final grossSalesMinor = sales.fold<int>(0, (s, o) => s + o.grossMinor);
  final discountTotalMinor = sales.fold<int>(0, (s, o) => s + o.discountMinor);
  final netSalesMinor = grossSalesMinor - discountTotalMinor;

  final orderCount = sales.length;
  final completedOrderCount = sales.where((o) => o.status.isCompleted).length;
  final openOrderCount = orderCount - completedOrderCount;
  final unpaidOrderCount = sales.where((o) => !o.isPaid).length;

  final voided = data.orders
      .where((o) => o.status == ReportOrderStatus.voided)
      .toList();
  final voidCount = voided.length;
  final voidTotalMinor = voided.fold<int>(0, (s, o) => s + o.netMinor);

  // Cash is the only payment method in the MVP — report it honestly.
  final cashSalesMinor = paid.fold<int>(
    0,
    (s, o) => s + o.payment!.amountMinor,
  );

  // Last cash payment by time (zero-padded HH:mm sorts lexicographically).
  var lastCashPaymentMinor = 0;
  var lastPaidAt = '';
  for (final order in paid) {
    final payment = order.payment!;
    if (payment.paidAtLabel.compareTo(lastPaidAt) >= 0) {
      lastPaidAt = payment.paidAtLabel;
      lastCashPaymentMinor = payment.amountMinor;
    }
  }

  // Shift / drawer reconciliation: expected = opening float + cash sales.
  final expectedCashMinor = data.shift.openingFloatMinor + cashSalesMinor;

  return DashboardReport(
    currencyCode: currency,
    businessDateLabel: data.businessDateLabel,
    grossSalesMinor: grossSalesMinor,
    netSalesMinor: netSalesMinor,
    discountTotalMinor: discountTotalMinor,
    collectedMinor: cashSalesMinor,
    cashSalesMinor: cashSalesMinor,
    lastCashPaymentMinor: lastCashPaymentMinor,
    orderCount: orderCount,
    completedOrderCount: completedOrderCount,
    openOrderCount: openOrderCount,
    unpaidOrderCount: unpaidOrderCount,
    voidCount: voidCount,
    voidTotalMinor: voidTotalMinor,
    openingFloatMinor: data.shift.openingFloatMinor,
    expectedCashMinor: expectedCashMinor,
    countedCashMinor: data.shift.countedCashMinor,
    shiftStatus: data.shift.status,
    branches: _branches(sales, currency),
    topItems: _topItems(sales, currency),
    recentOrders: _recentOrders(data.orders, currency),
    paymentMethods: _paymentMethods(paid, cashSalesMinor, currency),
  );
}

/// Per-branch sales (order count + net), in first-seen branch order. The branch
/// nets sum exactly to total net sales.
List<BranchSales> _branches(List<ReportOrder> sales, String currency) {
  final counts = <String, int>{};
  final nets = <String, int>{};
  for (final order in sales) {
    counts[order.branchName] = (counts[order.branchName] ?? 0) + 1;
    nets[order.branchName] = (nets[order.branchName] ?? 0) + order.netMinor;
  }
  return [
    for (final name in counts.keys)
      BranchSales(
        branchName: name,
        orderCount: counts[name]!,
        netSalesMinor: nets[name]!,
        currencyCode: currency,
      ),
  ];
}

/// Top items grouped by name, ranked by net revenue desc (name as a stable
/// tie-break). The item revenues sum exactly to total net sales.
List<TopItem> _topItems(List<ReportOrder> sales, String currency) {
  final qty = <String, int>{};
  final revenue = <String, int>{};
  for (final order in sales) {
    for (final line in order.lines) {
      qty[line.itemName] = (qty[line.itemName] ?? 0) + line.quantity;
      revenue[line.itemName] = (revenue[line.itemName] ?? 0) + line.netMinor;
    }
  }
  final items = [
    for (final name in qty.keys)
      TopItem(
        name: name,
        quantity: qty[name]!,
        lineRevenueMinor: revenue[name]!,
        currencyCode: currency,
      ),
  ];
  items.sort((a, b) {
    final byRevenue = b.lineRevenueMinor.compareTo(a.lineRevenueMinor);
    return byRevenue != 0 ? byRevenue : a.name.compareTo(b.name);
  });
  return items;
}

/// Recent orders (all orders, including voided/cancelled), newest first by time,
/// capped at [_recentLimit].
const int _recentLimit = 8;

List<RecentOrderRow> _recentOrders(List<ReportOrder> orders, String currency) {
  final sorted = [...orders]
    ..sort((a, b) => b.placedAtLabel.compareTo(a.placedAtLabel));
  return [
    for (final order in sorted.take(_recentLimit))
      RecentOrderRow(
        orderNumber: order.orderNumber,
        timeLabel: order.placedAtLabel,
        isDineIn: order.isDineIn,
        tableLabel: order.tableLabel,
        status: order.status.wireName,
        isPaid: order.isPaid,
        totalMinor: order.netMinor,
        currencyCode: currency,
      ),
  ];
}

/// Payment-method breakdown. The MVP records cash only, so this is a single
/// `cash` line when there are payments, and empty otherwise.
List<PaymentMethodLine> _paymentMethods(
  List<ReportOrder> paid,
  int cashSalesMinor,
  String currency,
) {
  if (paid.isEmpty) return const [];
  return [
    PaymentMethodLine(
      method: 'cash',
      count: paid.length,
      totalMinor: cashSalesMinor,
      currencyCode: currency,
    ),
  ];
}

/// Convenience: the standard computed demo report (used by tests and as the
/// default repository result). Built from the structured demo dataset — not a
/// hardcoded snapshot.
DashboardReport demoDashboardReport() =>
    computeOwnerReport(demoOwnerReportDataset());
