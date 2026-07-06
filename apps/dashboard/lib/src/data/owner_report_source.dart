/// The STRUCTURED demo dataset the owner reports are CALCULATED from (RF-119).
///
/// This is deliberately NOT a pre-baked report snapshot: it is a realistic set
/// of sample orders, line items, completed cash payments and a shift. Every
/// owner-report metric is DERIVED from it by `computeOwnerReport` — there are no
/// hardcoded totals. There is no Supabase, no report view, no backend: the real
/// RF-075/RF-092 report views exist server-side but are not wired here (real
/// backend reporting is deferred). Money is integer MINOR units (DECISION
/// D-007); single currency (ILS). Times are plain zero-padded `HH:mm` data
/// strings — no clock dependency, so the reports are deterministic and testable.
library;

import 'demo_report.dart'
    show HourlyNetSales, ReportComparison, kDemoCurrencyCode;

/// One ordered line: a menu item at a snapshot unit price, a quantity, and an
/// optional integer line discount (minor units). `gross = unitPrice * quantity`;
/// `net = gross - discount` — all integer minor units, never float.
class ReportOrderLine {
  const ReportOrderLine({
    required this.itemName,
    required this.quantity,
    required this.unitPriceMinor,
    this.lineDiscountMinor = 0,
  });

  /// Display name (data, not localized chrome).
  final String itemName;
  final int quantity;
  final int unitPriceMinor;
  final int lineDiscountMinor;

  int get grossMinor => unitPriceMinor * quantity;
  int get netMinor => grossMinor - lineDiscountMinor;
}

/// A demo order's lifecycle status (a subset of the domain `OrderStatus`,
/// surfaced as its canonical snake_case data string).
enum ReportOrderStatus {
  completed,
  preparing,
  ready,
  served,
  voided,
  cancelled;

  /// True when the order counts as a SALE (everything except voided/cancelled).
  bool get isSale => this != voided && this != cancelled;

  /// True only for the terminal completed state.
  bool get isCompleted => this == completed;

  /// The canonical data string shown as the order's status (e.g. `preparing`).
  String get wireName => name;
}

/// A completed cash payment. Cash is the only method in the MVP (RF-054), so the
/// report is honest about payment methods — there is no card/online data.
class ReportPayment {
  const ReportPayment({
    required this.amountMinor,
    required this.tenderedMinor,
    required this.paidAtLabel,
  });

  final int amountMinor;
  final int tenderedMinor;

  /// Plain zero-padded `HH:mm` data string.
  final String paidAtLabel;

  int get changeMinor => tenderedMinor - amountMinor;
}

/// One demo order: its branch, type, optional table, status, placed-at time,
/// itemised lines and (optionally) the completed cash payment that settled it.
class ReportOrder {
  const ReportOrder({
    required this.orderNumber,
    required this.branchName,
    required this.isDineIn,
    required this.status,
    required this.placedAtLabel,
    required this.lines,
    this.tableLabel,
    this.payment,
  });

  /// Display number (data, not localized chrome).
  final String orderNumber;
  final String branchName;
  final bool isDineIn;
  final String? tableLabel;
  final ReportOrderStatus status;

  /// Plain zero-padded `HH:mm` data string (deterministic; no clock dependency).
  final String placedAtLabel;
  final List<ReportOrderLine> lines;

  /// The completed cash payment for this order, or null if not yet paid.
  final ReportPayment? payment;

  int get grossMinor =>
      lines.fold<int>(0, (sum, line) => sum + line.grossMinor);
  int get discountMinor =>
      lines.fold<int>(0, (sum, line) => sum + line.lineDiscountMinor);
  int get netMinor => grossMinor - discountMinor;
  bool get isPaid => payment != null;
}

/// The shift / cash-drawer context: opening float, the physically counted cash
/// and the shift status. Expected cash is derived (float + cash sales), so the
/// variance is computed, not stored.
class ReportShift {
  const ReportShift({
    required this.openingFloatMinor,
    required this.countedCashMinor,
    required this.status,
    this.closedByName = '',
  });

  final int openingFloatMinor;
  final int countedCashMinor;

  /// Shift status as a plain data string (e.g. `open`).
  final String status;

  /// Who closed the shift (display name) — a plain data string, used by the
  /// RF-REPORT-003 demo shift/cash card. Empty when unknown.
  final String closedByName;
}

/// The full structured dataset an owner report is computed from.
class OwnerReportDataset {
  const OwnerReportDataset({
    required this.currencyCode,
    required this.businessDateLabel,
    required this.orders,
    required this.shift,
    this.hourlyNetSales = const <HourlyNetSales>[],
    this.priorPeriod,
  });

  final String currencyCode;

  /// Business day as a plain data string (not localized chrome).
  final String businessDateLabel;
  final List<ReportOrder> orders;
  final ReportShift shift;

  /// DESIGN-002 (DISPLAY-ONLY demo data): illustrative net sales per hour for
  /// the sales-by-hour chart, and a prior-period summary for KPI deltas. Both
  /// are sample data for the demo surface (the dashboard's demo banner labels
  /// it as such) and are absent in real mode, so the real Overview never shows
  /// a fabricated curve or delta. The KPI totals are still DERIVED from
  /// [orders] — these fields never feed the money sums.
  final List<HourlyNetSales> hourlyNetSales;
  final ReportComparison? priorPeriod;
}

// Demo menu unit prices (integer minor units, ILS).
const int _burger = 4200; // ₪42.00
const int _pizza = 5600; // ₪56.00
const int _salad = 3800; // ₪38.00
const int _lemonade = 1400; // ₪14.00
const int _fries = 1600; // ₪16.00

/// The standard demo dataset: one business day, three ILS branches, nine sample
/// orders (five completed+paid, two open+unpaid, one voided, one cancelled) and
/// one open shift. Hand-tuned to clean, hand-verifiable totals (see the
/// report-calculator tests). Money is integer minor units throughout.
OwnerReportDataset demoOwnerReportDataset() => const OwnerReportDataset(
  currencyCode: kDemoCurrencyCode,
  businessDateLabel: '2026-06-28',
  shift: ReportShift(
    openingFloatMinor: 50000, // ₪500.00
    countedCashMinor: 97250, // expected ₪974.00 -> variance -₪1.50
    status: 'open',
    closedByName: 'Amira K.', // demo data (not localized chrome)
  ),
  orders: [
    ReportOrder(
      orderNumber: 'O-1001',
      branchName: 'Downtown',
      isDineIn: true,
      tableLabel: 'T1',
      status: ReportOrderStatus.completed,
      placedAtLabel: '12:05',
      lines: [
        ReportOrderLine(
          itemName: 'Classic Burger',
          quantity: 2,
          unitPriceMinor: _burger,
        ),
        ReportOrderLine(
          itemName: 'Fresh Lemonade',
          quantity: 2,
          unitPriceMinor: _lemonade,
        ),
      ],
      payment: ReportPayment(
        amountMinor: 11200,
        tenderedMinor: 12000,
        paidAtLabel: '12:05',
      ),
    ),
    ReportOrder(
      orderNumber: 'O-1002',
      branchName: 'Downtown',
      isDineIn: false,
      status: ReportOrderStatus.completed,
      placedAtLabel: '12:20',
      lines: [
        ReportOrderLine(
          itemName: 'Margherita Pizza',
          quantity: 1,
          unitPriceMinor: _pizza,
          lineDiscountMinor: 200,
        ),
        ReportOrderLine(
          itemName: 'French Fries',
          quantity: 1,
          unitPriceMinor: _fries,
        ),
      ],
      payment: ReportPayment(
        amountMinor: 7000,
        tenderedMinor: 7000,
        paidAtLabel: '12:20',
      ),
    ),
    ReportOrder(
      orderNumber: 'O-1003',
      branchName: 'Seaside',
      isDineIn: true,
      tableLabel: 'T4',
      status: ReportOrderStatus.completed,
      placedAtLabel: '12:40',
      lines: [
        ReportOrderLine(
          itemName: 'Caesar Salad',
          quantity: 1,
          unitPriceMinor: _salad,
        ),
        ReportOrderLine(
          itemName: 'Classic Burger',
          quantity: 1,
          unitPriceMinor: _burger,
        ),
        ReportOrderLine(
          itemName: 'Fresh Lemonade',
          quantity: 1,
          unitPriceMinor: _lemonade,
        ),
      ],
      payment: ReportPayment(
        amountMinor: 9400,
        tenderedMinor: 10000,
        paidAtLabel: '12:40',
      ),
    ),
    ReportOrder(
      orderNumber: 'O-1004',
      branchName: 'Seaside',
      isDineIn: false,
      status: ReportOrderStatus.completed,
      placedAtLabel: '13:00',
      lines: [
        ReportOrderLine(
          itemName: 'Margherita Pizza',
          quantity: 2,
          unitPriceMinor: _pizza,
          lineDiscountMinor: 400,
        ),
        ReportOrderLine(
          itemName: 'French Fries',
          quantity: 2,
          unitPriceMinor: _fries,
        ),
      ],
      payment: ReportPayment(
        amountMinor: 14000,
        tenderedMinor: 15000,
        paidAtLabel: '13:00',
      ),
    ),
    ReportOrder(
      orderNumber: 'O-1005',
      branchName: 'Airport',
      isDineIn: false,
      status: ReportOrderStatus.completed,
      placedAtLabel: '13:15',
      lines: [
        ReportOrderLine(
          itemName: 'Classic Burger',
          quantity: 1,
          unitPriceMinor: _burger,
        ),
        ReportOrderLine(
          itemName: 'French Fries',
          quantity: 1,
          unitPriceMinor: _fries,
        ),
      ],
      payment: ReportPayment(
        amountMinor: 5800,
        tenderedMinor: 6000,
        paidAtLabel: '13:15',
      ),
    ),
    ReportOrder(
      orderNumber: 'O-1006',
      branchName: 'Downtown',
      isDineIn: true,
      tableLabel: 'T2',
      status: ReportOrderStatus.preparing,
      placedAtLabel: '13:30',
      lines: [
        ReportOrderLine(
          itemName: 'Margherita Pizza',
          quantity: 1,
          unitPriceMinor: _pizza,
        ),
        ReportOrderLine(
          itemName: 'Fresh Lemonade',
          quantity: 1,
          unitPriceMinor: _lemonade,
        ),
      ],
    ),
    ReportOrder(
      orderNumber: 'O-1007',
      branchName: 'Seaside',
      isDineIn: true,
      tableLabel: 'T5',
      status: ReportOrderStatus.ready,
      placedAtLabel: '13:40',
      lines: [
        ReportOrderLine(
          itemName: 'Caesar Salad',
          quantity: 2,
          unitPriceMinor: _salad,
        ),
      ],
    ),
    ReportOrder(
      orderNumber: 'O-1008',
      branchName: 'Airport',
      isDineIn: false,
      status: ReportOrderStatus.voided,
      placedAtLabel: '13:45',
      lines: [
        ReportOrderLine(
          itemName: 'Classic Burger',
          quantity: 1,
          unitPriceMinor: _burger,
        ),
      ],
    ),
    ReportOrder(
      orderNumber: 'O-1009',
      branchName: 'Downtown',
      isDineIn: false,
      status: ReportOrderStatus.cancelled,
      placedAtLabel: '13:50',
      lines: [
        ReportOrderLine(
          itemName: 'French Fries',
          quantity: 1,
          unitPriceMinor: _fries,
        ),
      ],
    ),
  ],
  // DESIGN-002 (DISPLAY-ONLY demo data): an illustrative lunch + dinner
  // service curve for the sales-by-hour chart, and a prior-period ("yesterday")
  // summary for the KPI deltas. Sample data for the demo surface only — the
  // KPI money totals above are still DERIVED from `orders`; these never feed
  // the sums, and real mode leaves both absent (no fabricated curve/delta).
  // The 12 hourly values SUM to the demo day's net sales (62000 minor /
  // ₪620.00) so the chart reconciles with the "Net sales" KPI on the same
  // screen; no single hour exceeds the day's total.
  hourlyNetSales: [
    HourlyNetSales(hourLabel: '10:00', netSalesMinor: 1200),
    HourlyNetSales(hourLabel: '11:00', netSalesMinor: 2900),
    HourlyNetSales(hourLabel: '12:00', netSalesMinor: 6800),
    HourlyNetSales(hourLabel: '13:00', netSalesMinor: 9200),
    HourlyNetSales(hourLabel: '14:00', netSalesMinor: 4600),
    HourlyNetSales(hourLabel: '15:00', netSalesMinor: 2500),
    HourlyNetSales(hourLabel: '16:00', netSalesMinor: 2000),
    HourlyNetSales(hourLabel: '17:00', netSalesMinor: 3300),
    HourlyNetSales(hourLabel: '18:00', netSalesMinor: 7400),
    HourlyNetSales(hourLabel: '19:00', netSalesMinor: 10100),
    HourlyNetSales(hourLabel: '20:00', netSalesMinor: 7800),
    HourlyNetSales(hourLabel: '21:00', netSalesMinor: 4200),
  ],
  priorPeriod: ReportComparison(
    grossSalesMinor: 57200,
    netSalesMinor: 56800,
    orderCount: 6,
    cashSalesMinor: 44100,
  ),
);

/// An EMPTY business day (no orders), used to render and test the empty state.
/// The shift is present but flat (a zero opening float), so every derived figure
/// is zero.
OwnerReportDataset emptyOwnerReportDataset() => const OwnerReportDataset(
  currencyCode: kDemoCurrencyCode,
  businessDateLabel: '2026-06-28',
  shift: ReportShift(
    openingFloatMinor: 0,
    countedCashMinor: 0,
    status: 'closed',
  ),
  orders: [],
);
