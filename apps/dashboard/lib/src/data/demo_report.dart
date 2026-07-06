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

/// DESIGN-002 — one hour's net sales for the sales-by-hour chart. Money is
/// integer MINOR units (D-007); [hourLabel] is a plain `HH:00` data string.
/// DISPLAY-ONLY: present in demo mode; absent (empty list) in real mode until a
/// backend hourly report is wired, so real mode never fabricates a curve.
class HourlyNetSales {
  const HourlyNetSales({required this.hourLabel, required this.netSalesMinor});

  /// Plain `HH:00` data string (not localized chrome).
  final String hourLabel;
  final int netSalesMinor;
}

/// DESIGN-002 — a prior-period comparison summary for KPI deltas. DISPLAY-ONLY.
/// Populated in demo mode, and in live mode from a SAFE "vs yesterday" derived
/// from `sales_summary.last_7_days` (LIVE-UX-001); it is null only when no honest
/// prior exists, so a delta is NEVER shown against data that doesn't exist. Money
/// is integer MINOR units (D-007).
class ReportComparison {
  const ReportComparison({
    required this.grossSalesMinor,
    required this.netSalesMinor,
    required this.orderCount,
    required this.cashSalesMinor,
  });

  final int grossSalesMinor;
  final int netSalesMinor;
  final int orderCount;
  final int cashSalesMinor;
}

/// A signed integer percentage change of [current] vs [prior], or null when a
/// delta can't be computed (no prior, or prior is zero). Integer (truncating)
/// math only — never floating-point (D-007-adjacent discipline). Positive means
/// growth.
int? deltaPercent(int current, int? prior) {
  if (prior == null || prior == 0) return null;
  return (current - prior) * 100 ~/ prior;
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

/// RF-REPORT-003 (display-only) — one CLOSED shift's cash-reconciliation summary.
/// Money is integer MINOR units (D-007); [varianceMinor] is SIGNED (counted −
/// expected; negative = shortage). Values come only from the shift-close record.
class ClosedShiftSummary {
  const ClosedShiftSummary({
    required this.shiftId,
    required this.branchName,
    required this.closedAtLabel,
    required this.closedByName,
    required this.expectedCashMinor,
    required this.countedCashMinor,
    required this.varianceMinor,
    this.openedAtLabel,
  });

  final String shiftId;
  final String branchName;

  /// Plain data timestamp strings (not localized chrome).
  final String closedAtLabel;
  final String? openedAtLabel;
  final String closedByName;

  final int expectedCashMinor;
  final int countedCashMinor;

  /// counted − expected (SIGNED; negative = shortage).
  final int varianceMinor;
}

/// RF-REPORT-003 (display-only) — TODAY's shift / cash reconciliation. All money
/// integer MINOR units (D-007); [varianceMinor] is SIGNED. Null on the report in
/// the sales_summary fallback (no real shift data); present in demo and in the
/// real owner_daily_report. [expectedCashMinor] / [countedCashMinor] /
/// [varianceMinor] aggregate TODAY's closed shifts (never derived from sales).
class ShiftCash {
  const ShiftCash({
    required this.closedShiftCount,
    required this.openShiftCount,
    required this.expectedCashMinor,
    required this.countedCashMinor,
    required this.varianceMinor,
    this.lastClosedShift,
    this.recentClosedShifts = const <ClosedShiftSummary>[],
  });

  final int closedShiftCount;
  final int openShiftCount;
  final int expectedCashMinor;
  final int countedCashMinor;
  final int varianceMinor;
  final ClosedShiftSummary? lastClosedShift;
  final List<ClosedShiftSummary> recentClosedShifts;

  bool get hasClosedShifts => closedShiftCount > 0;

  /// True when this block carries ANY meaningful reconciliation signal — a closed
  /// or open shift, a non-zero expected/counted/variance, or a last/recent close.
  /// Used to keep a shift-only day (zero orders/sales but real closed-shift cash)
  /// OUT of the report's generic empty state so the "Shift & cash" card renders.
  bool get hasData =>
      closedShiftCount > 0 ||
      openShiftCount > 0 ||
      expectedCashMinor != 0 ||
      countedCashMinor != 0 ||
      varianceMinor != 0 ||
      lastClosedShift != null ||
      recentClosedShifts.isNotEmpty;
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
    this.hourlyNetSales = const <HourlyNetSales>[],
    this.comparison,
    this.shiftCash,
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

  /// DESIGN-002 (display-only): net sales per hour for the sales-by-hour chart.
  /// Empty in real mode (no fabricated curve) — the chart hides when empty.
  final List<HourlyNetSales> hourlyNetSales;

  /// DESIGN-002 (display-only): the prior-period totals KPI deltas compare
  /// against. Populated in demo and in the live-limited "vs yesterday" fallback
  /// (LIVE-UX-001); null only when no honest prior exists — deltas hide then
  /// (never invented).
  final ReportComparison? comparison;

  /// RF-REPORT-003 (display-only): TODAY's shift / cash reconciliation. Present in
  /// demo and in the real owner_daily_report; NULL in the sales_summary fallback
  /// (no real shift data — the card hides, never fabricated).
  final ShiftCash? shiftCash;

  /// True when there is nothing to report (drives the empty state). LIVE-UX-001:
  /// this also requires NO money — a day can collect real revenue
  /// (`grossSalesMinor` / `collectedMinor` > 0) on orders created earlier while
  /// having zero orders created today, and that money must never be hidden behind
  /// a "No report data" empty state.
  /// RF-REPORT-003: it ALSO requires no meaningful shift/cash reconciliation — a
  /// real day can have zero orders/sales yet a closed shift with counted cash (an
  /// opening float / drawer reconciliation), and that must render the "Shift &
  /// cash" card instead of being hidden behind the generic empty state.
  bool get isEmpty =>
      orderCount == 0 &&
      completedOrderCount == 0 &&
      recentOrders.isEmpty &&
      grossSalesMinor == 0 &&
      collectedMinor == 0 &&
      !(shiftCash?.hasData ?? false);

  /// Cash reconciliation variance = counted - expected (signed, integer minor).
  int get varianceMinor => countedCashMinor - expectedCashMinor;

  /// Average order value in integer MINOR units via integer (truncating)
  /// division — never floating-point money (D-007). Guards a zero order count.
  int get avgOrderValueMinor =>
      orderCount == 0 ? 0 : netSalesMinor ~/ orderCount;
}
