/// In-memory demo data for the RF-104 owner dashboard.
///
/// FAKE local data only — no Supabase, no report views, no backend. The field
/// shapes mirror the real RF-075/RF-092 report views (integer `_minor` money,
/// per-branch grain, currency code) so the demo is forward-compatible, but
/// nothing here reads or wires those views. Money is integer MINOR units
/// (DECISION D-007) — there is no floating-point money. Single currency (ILS).
library;

/// ISO 4217 currency for the demo, locked to ILS / ₪ for RF-104.
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

/// One top-selling item row (illustrative demo only — there is no top-items
/// report view in the real schema).
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

/// An immutable, single-day owner/manager report snapshot.
class DashboardReport {
  const DashboardReport({
    required this.currencyCode,
    required this.businessDateLabel,
    required this.netSalesMinor,
    required this.collectedMinor,
    required this.orderCount,
    required this.completedOrderCount,
    required this.openOrderCount,
    required this.discountTotalMinor,
    required this.voidCount,
    required this.voidTotalMinor,
    required this.openingFloatMinor,
    required this.expectedCashMinor,
    required this.countedCashMinor,
    required this.shiftStatus,
    required this.branches,
    required this.topItems,
  });

  final String currencyCode;

  /// Business date as a plain data string (not localized chrome).
  final String businessDateLabel;

  // Money fields are integer MINOR units (D-007). No floats anywhere.
  final int netSalesMinor;
  final int collectedMinor;
  final int discountTotalMinor;
  final int voidTotalMinor;
  final int openingFloatMinor;
  final int expectedCashMinor;
  final int countedCashMinor;

  // Plain integer counts (never money).
  final int orderCount;
  final int completedOrderCount;
  final int openOrderCount;
  final int voidCount;

  /// Current shift status as a plain data string (e.g. `open` / `reconciled`).
  final String shiftStatus;

  final List<BranchSales> branches;
  final List<TopItem> topItems;

  /// Cash reconciliation variance = counted - expected (signed, integer minor).
  int get varianceMinor => countedCashMinor - expectedCashMinor;

  /// Average order value in integer MINOR units via integer (truncating)
  /// division — never floating-point money (D-007). Guards a zero order count.
  int get avgOrderValueMinor =>
      orderCount == 0 ? 0 : netSalesMinor ~/ orderCount;
}

/// The single demo report rendered by the dashboard (in-memory; one org, three
/// ILS branches). All money is integer minor units.
DashboardReport demoDashboardReport() => const DashboardReport(
  currencyCode: kDemoCurrencyCode,
  businessDateLabel: '2026-06-24',
  netSalesMinor: 1234500, // ₪12,345.00
  collectedMinor: 1234500,
  orderCount: 87,
  completedOrderCount: 81,
  openOrderCount: 6,
  discountTotalMinor: 48000, // ₪480.00
  voidCount: 3,
  voidTotalMinor: 21500, // ₪215.00
  openingFloatMinor: 50000, // ₪500.00
  expectedCashMinor: 1284500,
  countedCashMinor: 1283200, // variance -₪13.00
  shiftStatus: 'open',
  branches: [
    BranchSales(
      branchName: 'Downtown',
      orderCount: 39,
      netSalesMinor: 612300,
      currencyCode: kDemoCurrencyCode,
    ),
    BranchSales(
      branchName: 'Seaside',
      orderCount: 31,
      netSalesMinor: 428900,
      currencyCode: kDemoCurrencyCode,
    ),
    BranchSales(
      branchName: 'Airport',
      orderCount: 17,
      netSalesMinor: 193300,
      currencyCode: kDemoCurrencyCode,
    ),
  ],
  topItems: [
    TopItem(
      name: 'Classic Burger',
      quantity: 64,
      lineRevenueMinor: 268800,
      currencyCode: kDemoCurrencyCode,
    ),
    TopItem(
      name: 'Margherita Pizza',
      quantity: 41,
      lineRevenueMinor: 229600,
      currencyCode: kDemoCurrencyCode,
    ),
    TopItem(
      name: 'Fresh Lemonade',
      quantity: 58,
      lineRevenueMinor: 81200,
      currencyCode: kDemoCurrencyCode,
    ),
    TopItem(
      name: 'French Fries',
      quantity: 73,
      lineRevenueMinor: 116800,
      currencyCode: kDemoCurrencyCode,
    ),
  ],
);
