import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_report_source.dart';
import 'package:restoflow_dashboard/src/data/report_calculator.dart';

void main() {
  group('computeOwnerReport over the demo dataset', () {
    final report = computeOwnerReport(demoOwnerReportDataset());

    test('sales totals: gross, discounts, net (gross - discounts)', () {
      expect(report.grossSalesMinor, 62600); // ₪626.00
      expect(report.discountTotalMinor, 600); // ₪6.00
      expect(report.netSalesMinor, 62000); // ₪620.00 (gross 62600 - disc 600)
    });

    test('order counts exclude voided/cancelled; open + unpaid split', () {
      expect(report.orderCount, 7); // 9 orders - 1 void - 1 cancelled
      expect(report.completedOrderCount, 5);
      expect(report.openOrderCount, 2);
      expect(report.unpaidOrderCount, 2);
    });

    test('voids are counted and totalled separately', () {
      expect(report.voidCount, 1);
      expect(report.voidTotalMinor, 4200); // ₪42.00
    });

    test('average ticket uses integer truncating division (no float)', () {
      expect(report.avgOrderValueMinor, 8857); // 62000 ~/ 7 = 8857 (truncated)
      expect(report.avgOrderValueMinor, isA<int>());
    });

    test('cash sales = sum of completed cash payments', () {
      expect(report.cashSalesMinor, 47400); // ₪474.00
      expect(report.collectedMinor, 47400); // cash collected == cash sales
      expect(report.lastCashPaymentMinor, 5800); // latest payment (13:15)
    });

    test(
      'expected drawer = opening float + cash sales; variance = counted - expected',
      () {
        expect(report.openingFloatMinor, 50000); // ₪500.00
        expect(report.expectedCashMinor, 97400); // 50000 + 47400
        expect(report.countedCashMinor, 97250);
        expect(report.varianceMinor, -150); // 97250 - 97400 = -₪1.50
      },
    );

    test('payment methods report cash only (honest — MVP records cash)', () {
      expect(report.paymentMethods, hasLength(1));
      expect(report.paymentMethods.single.method, 'cash');
      expect(report.paymentMethods.single.count, 5);
      expect(report.paymentMethods.single.totalMinor, 47400);
    });

    test(
      'branches: first-seen order, counts/nets, and nets sum to net sales',
      () {
        expect(report.branches.map((b) => b.branchName).toList(), [
          'Downtown',
          'Seaside',
          'Airport',
        ]);
        final downtown = report.branches.firstWhere(
          (b) => b.branchName == 'Downtown',
        );
        expect(downtown.orderCount, 3);
        expect(downtown.netSalesMinor, 25200); // ₪252.00

        final seaside = report.branches.firstWhere(
          (b) => b.branchName == 'Seaside',
        );
        expect(seaside.orderCount, 3);
        expect(seaside.netSalesMinor, 31000); // ₪310.00

        final airport = report.branches.firstWhere(
          (b) => b.branchName == 'Airport',
        );
        expect(airport.orderCount, 1);
        expect(airport.netSalesMinor, 5800); // ₪58.00

        final branchNetSum = report.branches.fold<int>(
          0,
          (s, b) => s + b.netSalesMinor,
        );
        expect(branchNetSum, report.netSalesMinor);
        final branchCountSum = report.branches.fold<int>(
          0,
          (s, b) => s + b.orderCount,
        );
        expect(branchCountSum, report.orderCount);
      },
    );

    test(
      'top items: ranked by net revenue desc; revenues sum to net sales',
      () {
        expect(report.topItems.first.name, 'Margherita Pizza');
        expect(report.topItems.first.lineRevenueMinor, 21800); // ₪218.00
        expect(report.topItems.first.quantity, 4);

        // The full ranking, pinned to exact names + net revenues.
        expect(report.topItems.map((t) => t.name).toList(), [
          'Margherita Pizza',
          'Classic Burger',
          'Caesar Salad',
          'French Fries',
          'Fresh Lemonade',
        ]);
        expect(report.topItems.map((t) => t.lineRevenueMinor).toList(), [
          21800, // Margherita Pizza
          16800, // Classic Burger
          11400, // Caesar Salad
          6400, // French Fries
          5600, // Fresh Lemonade
        ]);

        // Strictly non-increasing revenue (ranked).
        for (var i = 1; i < report.topItems.length; i++) {
          expect(
            report.topItems[i].lineRevenueMinor <=
                report.topItems[i - 1].lineRevenueMinor,
            isTrue,
          );
        }
        final itemRevenueSum = report.topItems.fold<int>(
          0,
          (s, t) => s + t.lineRevenueMinor,
        );
        expect(itemRevenueSum, report.netSalesMinor);
      },
    );

    test(
      'recent orders: newest first, capped at 8, includes void/cancelled',
      () {
        expect(report.recentOrders, hasLength(8)); // 9 orders, capped at 8
        expect(
          report.recentOrders.first.orderNumber,
          'O-1009',
        ); // 13:50, newest
        expect(report.recentOrders.first.status, 'cancelled');
        expect(report.recentOrders.first.isPaid, isFalse);
        // Times strictly descending.
        for (var i = 1; i < report.recentOrders.length; i++) {
          expect(
            report.recentOrders[i].timeLabel.compareTo(
                  report.recentOrders[i - 1].timeLabel,
                ) <=
                0,
            isTrue,
          );
        }
        // A paid completed order is marked paid.
        final paidRow = report.recentOrders.firstWhere(
          (r) => r.orderNumber == 'O-1005',
        );
        expect(paidRow.isPaid, isTrue);
        expect(paidRow.status, 'completed');
      },
    );

    test('currency is the demo currency on every money-bearing row', () {
      expect(report.currencyCode, kDemoCurrencyCode);
      for (final b in report.branches) {
        expect(b.currencyCode, kDemoCurrencyCode);
      }
      for (final t in report.topItems) {
        expect(t.currencyCode, kDemoCurrencyCode);
      }
    });
  });

  group('computeOwnerReport over an empty day', () {
    final report = computeOwnerReport(emptyOwnerReportDataset());

    test('every figure is zero and lists are empty', () {
      expect(report.isEmpty, isTrue);
      expect(report.grossSalesMinor, 0);
      expect(report.netSalesMinor, 0);
      expect(report.orderCount, 0);
      expect(report.avgOrderValueMinor, 0);
      expect(report.cashSalesMinor, 0);
      expect(report.expectedCashMinor, 0);
      expect(report.varianceMinor, 0);
      expect(report.branches, isEmpty);
      expect(report.topItems, isEmpty);
      expect(report.recentOrders, isEmpty);
      expect(report.paymentMethods, isEmpty);
    });
  });

  // RF-REPORT-004 — deterministic demo range reports.
  group('demoRangeReport', () {
    test('today delegates to the detailed report (branches / top items)', () {
      final r = demoRangeReport(ReportRange.today);
      expect(r.range, ReportRange.today);
      expect(r.rangeSupported, isTrue);
      expect(r.netSalesMinor, 62000); // same as the detailed demo day
      expect(r.branches, isNotEmpty);
      expect(r.hourlyNetSales, isNotEmpty); // single day -> curve present
    });

    test('yesterday: single-day -> hourly present and reconciles with net', () {
      final r = demoRangeReport(ReportRange.yesterday);
      expect(r.range, ReportRange.yesterday);
      expect(r.netSalesMinor, 56800); // matches the today-report prior period
      expect(r.hourlyNetSales, isNotEmpty);
      final hourlySum = r.hourlyNetSales.fold<int>(
        0,
        (s, h) => s + h.netSalesMinor,
      );
      expect(hourlySum, r.netSalesMinor); // exact integer reconciliation
      expect(r.comparison, isNotNull); // vs the day before
    });

    test('last7: multi-day -> NO hourly curve, but a prior-7 comparison', () {
      final r = demoRangeReport(ReportRange.last7);
      expect(r.range, ReportRange.last7);
      expect(r.hourlyNetSales, isEmpty); // multi-day: chart hides
      expect(r.comparison, isNotNull);
      expect(r.netSalesMinor, greaterThan(62000)); // a week sums above one day
      // Deep shift card populated with per-shift detail.
      expect(r.shiftCash, isNotNull);
      expect(r.shiftCash!.closedShiftCount, 7);
      expect(r.shiftCash!.lastClosedShift!.hasDetail, isTrue);
      expect(r.shiftCash!.recentClosedShifts.length, 7);
    });

    test('last30: multi-day, 30 closed shifts, deterministic + integer', () {
      final a = demoRangeReport(ReportRange.last30);
      final b = demoRangeReport(ReportRange.last30);
      expect(a.hourlyNetSales, isEmpty);
      expect(a.shiftCash!.closedShiftCount, 30);
      expect(a.shiftCash!.recentClosedShifts.length, 8); // list capped at 8
      // Deterministic (no clock / randomness).
      expect(a.netSalesMinor, b.netSalesMinor);
      expect(a.cashSalesMinor, b.cashSalesMinor);
      expect(a.shiftCash!.varianceMinor, b.shiftCash!.varianceMinor);
    });
  });
}
