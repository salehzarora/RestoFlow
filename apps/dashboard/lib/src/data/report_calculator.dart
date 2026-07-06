/// The owner-report CALCULATOR (RF-119): derives a [DashboardReport] from a
/// structured [OwnerReportDataset]. Pure + deterministic — every figure is
/// computed from the dataset's orders / payments / shift; nothing is hardcoded.
/// All money is integer MINOR units (DECISION D-007); the only division is
/// integer (truncating). No floating-point money anywhere.
library;

import 'demo_report.dart';
import 'owner_report_source.dart';

/// Computes the owner [DashboardReport] for [data] over [range]. The dataset is
/// a single computed period; [range] only labels the report and gates the hourly
/// curve (single-day ranges carry it, multi-day ranges never do).
DashboardReport computeOwnerReport(
  OwnerReportDataset data, {
  ReportRange range = ReportRange.today,
}) {
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

  // RF-REPORT-003 (demo): a representative TODAY shift/cash reconciliation so the
  // Overview's "Shift & cash" card renders in demo mode. Uses the same expected
  // (opening float + cash sales) + the dataset's counted amount; variance signed.
  // Real mode gets this from owner_daily_report; the fallback leaves it null.
  //
  // Only built when the dataset has ACTUAL shift/drawer activity — an empty day
  // (no orders, no float, no counted cash) leaves shiftCash null so it never
  // fabricates a closed shift and never keeps a truly-empty report out of the
  // generic empty state (RF-REPORT-003 blocker: isEmpty accounts for shiftCash).
  final hasShiftActivity =
      orderCount > 0 ||
      data.shift.openingFloatMinor > 0 ||
      data.shift.countedCashMinor > 0;
  final demoVariance = data.shift.countedCashMinor - expectedCashMinor;
  final demoClosedShift = ClosedShiftSummary(
    shiftId: 'demo-shift-1',
    branchName: sales.isNotEmpty ? sales.first.branchName : '',
    openedAtLabel: '${data.businessDateLabel} 09:00',
    closedAtLabel: '${data.businessDateLabel} 18:30',
    closedByName: data.shift.closedByName,
    expectedCashMinor: expectedCashMinor,
    countedCashMinor: data.shift.countedCashMinor,
    varianceMinor: demoVariance,
  );
  final demoShiftCash = hasShiftActivity
      ? ShiftCash(
          closedShiftCount: 1,
          openShiftCount: 1,
          expectedCashMinor: expectedCashMinor,
          countedCashMinor: data.shift.countedCashMinor,
          varianceMinor: demoVariance,
          lastClosedShift: demoClosedShift,
          recentClosedShifts: [demoClosedShift],
        )
      : null;

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
    // DESIGN-002 (display-only): pass the dataset's demo hourly curve and
    // prior-period summary straight through. Both are empty/null in real mode,
    // so the Overview's chart and deltas simply don't render there — the money
    // totals above are unaffected (still derived from `orders`).
    hourlyNetSales: range.isSingleDay ? data.hourlyNetSales : const [],
    comparison: data.priorPeriod,
    shiftCash: demoShiftCash,
    range: range,
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

// ===========================================================================
// RF-REPORT-004 — DEMO range reports. Demo data is explicitly illustrative (the
// Overview shows a "Demo data" banner), so these deterministic, clock-free
// per-day figures are honest demo content — never "fake real analytics". They
// exercise the range chips + prior-period comparison + deeper shift card in demo
// mode. Money is integer MINOR units (D-007); the only division is integer.
// ===========================================================================

/// Deterministic demo net / cash / order figures for `dayOffset` days ago
/// (0 = today). Day 0 and 1 match the detailed today report + its "yesterday"
/// prior, so today/last7/last30 stay coherent; older days follow a fixed
/// pseudo-seasonal pattern (weekend lift). Pure — no clock, no randomness.
({int netMinor, int cashMinor, int orders}) _demoDay(int dayOffset) {
  if (dayOffset <= 0) return (netMinor: 62000, cashMinor: 47400, orders: 7);
  if (dayOffset == 1) return (netMinor: 56800, cashMinor: 44100, orders: 6);
  final weekday = dayOffset % 7;
  final base = 48000 + 1700 * ((dayOffset * 3) % 12);
  final weekendLift = (weekday == 5 || weekday == 6) ? 12000 : 0;
  final net = base + weekendLift;
  final cash = net * 3 ~/ 5; // ~60% cash, integer (truncating) — never float
  final orders = 5 + (dayOffset * 2) % 9;
  return (netMinor: net, cashMinor: cash, orders: orders);
}

/// The demo day's illustrative net-by-hour shape (sums to 62000 minor); index 9
/// (19:00) is the peak the exact-sum remainder is folded into.
const List<int> _demoHourShape = <int>[
  1200,
  2900,
  6800,
  9200,
  4600,
  2500,
  2000,
  3300,
  7400,
  10100,
  7800,
  4200,
];
const List<String> _demoHourLabels = <String>[
  '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', //
  '16:00', '17:00', '18:00', '19:00', '20:00', '21:00',
];

/// Scales the demo hour shape to sum EXACTLY to [target] minor (integer division
/// with the remainder folded into the peak bucket), so a single-day range's
/// hourly curve reconciles with its net. Empty when [target] is zero.
List<HourlyNetSales> _demoHourlyScaled(int target) {
  if (target <= 0) return const [];
  const total = 62000;
  final scaled = [for (final v in _demoHourShape) v * target ~/ total];
  final sum = scaled.fold<int>(0, (a, b) => a + b);
  scaled[9] += target - sum; // exact reconciliation into the peak hour
  return [
    for (var i = 0; i < scaled.length; i++)
      HourlyNetSales(hourLabel: _demoHourLabels[i], netSalesMinor: scaled[i]),
  ];
}

/// A deep demo shift/cash block for [range]: one closed shift per day in the
/// window (newest first, capped at 8 for the list; aggregates over the full
/// window), each with opening float, opened/closed-by, duration and the FK-style
/// per-shift order/collected/cash detail — showcasing the RF-REPORT-004 card.
ShiftCash _demoRangeShiftCash(ReportRange range) {
  final startOffset = range == ReportRange.yesterday ? 1 : 0;
  final days = switch (range) {
    ReportRange.yesterday => 1,
    ReportRange.last7 => 7,
    ReportRange.last30 => 30,
    ReportRange.today => 1,
  };
  const floatMinor = 50000; // ₪500 opening float
  ClosedShiftSummary shiftFor(int offset) {
    final day = _demoDay(offset);
    final expected = floatMinor + day.cashMinor;
    final variance = (offset % 3 - 1) * 250; // -250 / 0 / +250, deterministic
    return ClosedShiftSummary(
      shiftId: 'demo-shift-$offset',
      branchName: offset.isEven ? 'Downtown' : 'Seaside',
      openedAtLabel: '09:00',
      closedAtLabel: '18:30',
      openedByName: 'Amira K.',
      closedByName: offset.isEven ? 'Amira K.' : 'Yusuf D.',
      openingFloatMinor: floatMinor,
      durationMinutes: 570, // 09:00 -> 18:30
      orderCount: day.orders,
      collectedMinor: day.netMinor,
      cashSalesMinor: day.cashMinor,
      expectedCashMinor: expected,
      countedCashMinor: expected + variance,
      varianceMinor: variance,
    );
  }

  var expectedTotal = 0;
  var countedTotal = 0;
  for (var i = 0; i < days; i++) {
    final s = shiftFor(startOffset + i);
    expectedTotal += s.expectedCashMinor;
    countedTotal += s.countedCashMinor;
  }
  final recent = [
    for (var i = 0; i < (days < 8 ? days : 8); i++) shiftFor(startOffset + i),
  ];
  return ShiftCash(
    closedShiftCount: days,
    openShiftCount: 1,
    expectedCashMinor: expectedTotal,
    countedCashMinor: countedTotal,
    varianceMinor: countedTotal - expectedTotal,
    lastClosedShift: recent.isEmpty ? null : recent.first,
    recentClosedShifts: recent,
  );
}

/// The demo owner report for a chosen [range]. `today` returns the full detailed
/// report (branches / top items / recent orders); the other ranges return an
/// aggregate report (KPIs + comparison + hourly for single-day + the deep shift
/// card) with the detail sections empty (the UI hides them). Deterministic.
DashboardReport demoRangeReport(ReportRange range) {
  if (range == ReportRange.today) {
    return computeOwnerReport(demoOwnerReportDataset(), range: range);
  }
  const currency = kDemoCurrencyCode;
  final (int curStart, int curEnd) = switch (range) {
    ReportRange.yesterday => (1, 1),
    ReportRange.last7 => (0, 6),
    ReportRange.last30 => (0, 29),
    ReportRange.today => (0, 0),
  };
  final span = curEnd - curStart + 1;
  var net = 0, cash = 0, orders = 0;
  for (var d = curStart; d <= curEnd; d++) {
    final x = _demoDay(d);
    net += x.netMinor;
    cash += x.cashMinor;
    orders += x.orders;
  }
  var priorNet = 0, priorCash = 0, priorOrders = 0;
  for (var d = curEnd + 1; d <= curEnd + span; d++) {
    final x = _demoDay(d);
    priorNet += x.netMinor;
    priorCash += x.cashMinor;
    priorOrders += x.orders;
  }
  return DashboardReport(
    currencyCode: currency,
    businessDateLabel: '',
    grossSalesMinor: net, // demo has no discount engine; gross == net
    netSalesMinor: net,
    discountTotalMinor: 0,
    collectedMinor: cash,
    cashSalesMinor: cash,
    lastCashPaymentMinor: 0,
    orderCount: orders,
    completedOrderCount: orders,
    openOrderCount: 0,
    unpaidOrderCount: 0,
    voidCount: 0,
    voidTotalMinor: 0,
    openingFloatMinor: 0,
    expectedCashMinor: 0,
    countedCashMinor: 0,
    shiftStatus: 'closed',
    branches: const [],
    topItems: const [],
    recentOrders: const [],
    paymentMethods: [
      PaymentMethodLine(
        method: 'cash',
        count: orders,
        totalMinor: cash,
        currencyCode: currency,
      ),
    ],
    hourlyNetSales: _demoHourlyScaled(range.isSingleDay ? net : 0),
    comparison: ReportComparison(
      grossSalesMinor: priorNet,
      netSalesMinor: priorNet,
      orderCount: priorOrders,
      cashSalesMinor: priorCash,
    ),
    shiftCash: _demoRangeShiftCash(range),
    range: range,
  );
}
