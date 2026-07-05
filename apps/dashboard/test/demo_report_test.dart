import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';

DashboardReport _report({
  int netSalesMinor = 0,
  int orderCount = 0,
  int expectedCashMinor = 0,
  int countedCashMinor = 0,
  int collectedMinor = 0,
  List<RecentOrderRow> recentOrders = const [],
}) => DashboardReport(
  currencyCode: 'ILS',
  businessDateLabel: '2026-06-28',
  grossSalesMinor: netSalesMinor,
  netSalesMinor: netSalesMinor,
  discountTotalMinor: 0,
  collectedMinor: collectedMinor,
  cashSalesMinor: 0,
  lastCashPaymentMinor: 0,
  orderCount: orderCount,
  completedOrderCount: 0,
  openOrderCount: 0,
  unpaidOrderCount: 0,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 0,
  expectedCashMinor: expectedCashMinor,
  countedCashMinor: countedCashMinor,
  shiftStatus: 'open',
  branches: const [],
  topItems: const [],
  recentOrders: recentOrders,
  paymentMethods: const [],
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
    final report = _report(
      expectedCashMinor: 1284500,
      countedCashMinor: 1283200,
    );
    expect(report.varianceMinor, -1300); // 1283200 - 1284500
  });

  test('isEmpty is true only with no orders, no recent rows AND no money', () {
    expect(_report(orderCount: 0).isEmpty, isTrue);
    expect(_report(orderCount: 7).isEmpty, isFalse);
    expect(
      _report(
        orderCount: 0,
        recentOrders: const [
          RecentOrderRow(
            orderNumber: 'O-1',
            timeLabel: '12:00',
            isDineIn: false,
            status: 'voided',
            isPaid: false,
            totalMinor: 4200,
            currencyCode: 'ILS',
          ),
        ],
      ).isEmpty,
      isFalse,
    );
    // LIVE-UX-001: a day that collected real revenue on earlier-created orders
    // (0 orders created today) is NOT empty — money is never hidden.
    expect(_report(netSalesMinor: 8000, orderCount: 0).isEmpty, isFalse);
    expect(_report(collectedMinor: 8000, orderCount: 0).isEmpty, isFalse);
  });
}
