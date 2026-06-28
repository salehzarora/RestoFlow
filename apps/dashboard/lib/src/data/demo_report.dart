/// The owner-report OUTPUT models for the RF-104/RF-119 dashboard.
///
/// These are the immutable shapes the UI renders. They are PRODUCED by
/// `computeOwnerReport` from a structured demo dataset (`owner_report_source`) —
/// nothing here holds hardcoded totals. The field shapes mirror the real
/// RF-075/RF-092 report views (integer `_minor` money, per-branch grain,
/// currency code) so a future Supabase-backed repository can fill the same model
/// without touching the UI. Money is integer MINOR units (DECISION D-007) —
/// there is no floating-point money. Single currency (ILS) for the demo.
library;

/// ISO 4217 currency for the demo, locked to ILS / ₪.
const String kDemoCurrencyCode = 'ILS';

/// One branch's daily sales row (mirrors `daily_branch_sales_report`).
class BranchSales {
  const BranchSales({
    required this.branchName,
    required this.orderCount,
    required this.netSalesMinor,
    required this.currencyCode,
  });

  /// Display name (data, not localized chrome).
  final String branchName;
  final int orderCount;
  final int netSalesMinor;
  final String currencyCode;
}

/// One top-selling item row, ranked by net revenue.
class TopItem {
  const TopItem({
    required this.name,
    required this.quantity,
    required this.lineRevenueMinor,
    required this.currencyCode,
  });

  /// Display name (data, not localized chrome).
  final String name;
  final int quantity;
  final int lineRevenueMinor;
  final String currencyCode;
}

/// One recent-orders row (order number, time, type/table, status, paid flag and
/// net total). Money is integer minor units.
class RecentOrderRow {
  const RecentOrderRow({
    required this.orderNumber,
    required this.timeLabel,
    required this.isDineIn,
    required this.status,
    required this.isPaid,
    required this.totalMinor,
    required this.currencyCode,
    this.tableLabel,
  });

  /// Display number (data, not localized chrome).
  final String orderNumber;

  /// Plain `HH:mm` data string.
  final String timeLabel;
  final bool isDineIn;
  final String? tableLabel;

  /// Canonical order status as a plain data string (e.g. `completed`).
  final String status;
  final bool isPaid;
  final int totalMinor;
  final String currencyCode;
}

/// One payment-method breakdown row (count + total). The MVP records cash only,
/// so this honestly reports a single `cash` line.
class PaymentMethodLine {
  const PaymentMethodLine({
    required this.method,
    required this.count,
    required this.totalMinor,
    required this.currencyCode,
  });

  /// Canonical method key as a plain data string (e.g. `cash`).
  final String method;
  final int count;
  final int totalMinor;
  final String currencyCode;
}

/// An immutable, single-day owner/manager report. Every field is DERIVED from
/// the source dataset by `computeOwnerReport`. Money fields are integer MINOR
/// units (D-007); plain counts are never money.
class DashboardReport {
  const DashboardReport({
    required this.currencyCode,
    required this.businessDateLabel,
    required this.grossSalesMinor,
    required this.netSalesMinor,
    required this.discountTotalMinor,
    required this.collectedMinor,
    required this.cashSalesMinor,
    required this.lastCashPaymentMinor,
    required this.orderCount,
    required this.completedOrderCount,
    required this.openOrderCount,
    required this.unpaidOrderCount,
    required this.voidCount,
    required this.voidTotalMinor,
    required this.openingFloatMinor,
    required this.expectedCashMinor,
    required this.countedCashMinor,
    required this.shiftStatus,
    required this.branches,
    required this.topItems,
    required this.recentOrders,
    required this.paymentMethods,
  });

  final String currencyCode;

  /// Business date as a plain data string (not localized chrome).
  final String businessDateLabel;

  // Money fields are integer MINOR units (D-007). No floats anywhere.
  final int grossSalesMinor;
  final int netSalesMinor;
  final int discountTotalMinor;
  final int collectedMinor;
  final int cashSalesMinor;
  final int lastCashPaymentMinor;
  final int voidTotalMinor;
  final int openingFloatMinor;
  final int expectedCashMinor;
  final int countedCashMinor;

  // Plain integer counts (never money).
  final int orderCount;
  final int completedOrderCount;
  final int openOrderCount;
  final int unpaidOrderCount;
  final int voidCount;

  /// Current shift status as a plain data string (e.g. `open` / `closed`).
  final String shiftStatus;

  final List<BranchSales> branches;
  final List<TopItem> topItems;
  final List<RecentOrderRow> recentOrders;
  final List<PaymentMethodLine> paymentMethods;

  /// True when there is nothing to report (drives the empty state).
  bool get isEmpty => orderCount == 0 && recentOrders.isEmpty;

  /// Cash reconciliation variance = counted - expected (signed, integer minor).
  int get varianceMinor => countedCashMinor - expectedCashMinor;

  /// Average order value in integer MINOR units via integer (truncating)
  /// division — never floating-point money (D-007). Guards a zero order count.
  int get avgOrderValueMinor =>
      orderCount == 0 ? 0 : netSalesMinor ~/ orderCount;
}
