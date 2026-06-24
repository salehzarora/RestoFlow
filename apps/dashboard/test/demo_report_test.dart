import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';

DashboardReport _report({
  required int netSalesMinor,
  required int orderCount,
}) => DashboardReport(
  currencyCode: 'ILS',
  businessDateLabel: '2026-06-24',
  netSalesMinor: netSalesMinor,
  collectedMinor: 0,
  orderCount: orderCount,
  completedOrderCount: 0,
  openOrderCount: 0,
  discountTotalMinor: 0,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 0,
  expectedCashMinor: 1284500,
  countedCashMinor: 1283200,
  shiftStatus: 'open',
  branches: const [],
  topItems: const [],
);

void main() {
  test('avgOrderValueMinor uses integer (truncating) division — no float', () {
    final report = _report(netSalesMinor: 1234500, orderCount: 87);
    expect(report.avgOrderValueMinor, 14189); // 1234500 ~/ 87, truncated
  });

  test('avgOrderValueMinor guards a zero order count', () {
    final report = _report(netSalesMinor: 5000, orderCount: 0);
    expect(report.avgOrderValueMinor, 0);
  });

  test('varianceMinor is counted minus expected (signed integer minor)', () {
    final report = _report(netSalesMinor: 0, orderCount: 1);
    expect(report.varianceMinor, -1300); // 1283200 - 1284500
  });

  test('demo report is self-consistent: branch sales sum to net sales', () {
    final report = demoDashboardReport();
    final branchSum = report.branches.fold<int>(
      0,
      (sum, branch) => sum + branch.netSalesMinor,
    );
    expect(branchSum, report.netSalesMinor);
    expect(report.currencyCode, kDemoCurrencyCode);
  });
}
