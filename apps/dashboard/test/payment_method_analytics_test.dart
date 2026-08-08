import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/payment_method_analytics.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-C) — payment analytics arithmetic
/// and the SERVER-B capability gate.
///
/// Every number here is an integer, and two of them are refusals: a window that
/// collected nothing has no share to divide, and a method with no payments has
/// nothing to average. Both must be ABSENT rather than zero, because a `0%`
/// beside a real amount is a contradiction and a `₪0.00` average reads as a
/// measurement.

PaymentMethodLine _line(
  String method, {
  required int amount,
  required int count,
}) => PaymentMethodLine(
  method: method,
  count: count,
  totalMinor: amount,
  currencyCode: 'ILS',
);

DashboardReport _report({ReportComparison? comparison}) => DashboardReport(
  currencyCode: 'ILS',
  businessDateLabel: '2026-08-08',
  grossSalesMinor: 24000,
  netSalesMinor: 22500,
  discountTotalMinor: 1500,
  collectedMinor: 20000,
  cashSalesMinor: 12000,
  lastCashPaymentMinor: 3000,
  orderCount: 8,
  completedOrderCount: 6,
  openOrderCount: 2,
  unpaidOrderCount: 1,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 0,
  expectedCashMinor: 0,
  countedCashMinor: 0,
  shiftStatus: 'none',
  branches: const [],
  topItems: const [],
  recentOrders: const [],
  paymentMethods: const [],
  comparison: comparison,
);

void main() {
  group('share — basis points against COLLECTED money', () {
    test('exact basis points', () {
      // 12000 of 20000 collected = 60.00% = 6000 bps.
      expect(PaymentMethodAnalytics.shareBasisPoints(12000, 20000), 6000);
      // 5000 of 20000 = 25% = 2500 bps.
      expect(PaymentMethodAnalytics.shareBasisPoints(5000, 20000), 2500);
      // A third: truncating, never rounding up.
      expect(PaymentMethodAnalytics.shareBasisPoints(10000, 30000), 3333);
      // A small tender keeps its precision where a whole percent would lose it.
      expect(PaymentMethodAnalytics.shareBasisPoints(80, 20000), 40);
    });

    test('a zero collected total yields NULL, not 0%', () {
      expect(PaymentMethodAnalytics.shareBasisPoints(0, 0), isNull);
      // Even a non-zero amount: the denominator is what is missing.
      expect(PaymentMethodAnalytics.shareBasisPoints(500, 0), isNull);
      expect(PaymentMethodAnalytics.shareBasisPoints(500, -1), isNull);
    });

    test('the denominator is COLLECTED — billed sales never enter it', () {
      // A window where billed net (22500) differs sharply from collected
      // (20000) because an order went unpaid. The share must be measured
      // against the money that actually came in.
      final report = _report();
      final analytics = PaymentMethodAnalytics.forLines([
        _line('cash', amount: 12000, count: 4),
      ], totalCollectedMinor: report.collectedMinor);
      expect(analytics.single.shareBps, 6000);
      // Had billed net been used the answer would have been 5333 — visibly
      // different, and wrong.
      expect(
        PaymentMethodAnalytics.shareBasisPoints(12000, report.netSalesMinor),
        isNot(analytics.single.shareBps),
      );
    });

    test(
      'the shares of a complete breakdown sum to 100% (within truncation)',
      () {
        final analytics = PaymentMethodAnalytics.forLines([
          _line('cash', amount: 12000, count: 4),
          _line('card', amount: 5000, count: 2),
          _line('bit', amount: 2000, count: 1),
          _line('external', amount: 1000, count: 1),
        ], totalCollectedMinor: 20000);
        final total = analytics.fold<int>(0, (s, a) => s + a.shareBps!);
        expect(total, 10000);
      },
    );

    test('formats basis points as one decimal, with integer math only', () {
      expect(formatShareBps(6000), '60.0');
      expect(formatShareBps(3421), '34.2');
      expect(formatShareBps(40), '0.4');
      expect(formatShareBps(0), '0.0');
      expect(formatShareBps(10000), '100.0');
      // Truncates the hundredths rather than rounding them into the tenth.
      expect(formatShareBps(3429), '34.2');
    });

    test('rounds to a whole percent half-up, matching the previous double '
        'rendering without creating a double', () {
      expect(roundedPercentFromBps(6000), 60);
      expect(roundedPercentFromBps(3449), 34);
      expect(roundedPercentFromBps(3450), 35);
      expect(roundedPercentFromBps(0), 0);
      expect(roundedPercentFromBps(10000), 100);
    });
  });

  group('average recorded payment', () {
    test('integer truncation, pinned', () {
      expect(PaymentMethodAnalytics.averagePaymentMinor(1000, 4), 250);
      expect(PaymentMethodAnalytics.averagePaymentMinor(1000, 3), 333);
      expect(PaymentMethodAnalytics.averagePaymentMinor(999, 2), 499);
    });

    test('a zero COUNT has nothing to average — null, not ₪0.00', () {
      expect(PaymentMethodAnalytics.averagePaymentMinor(0, 0), isNull);
      expect(PaymentMethodAnalytics.averagePaymentMinor(5000, 0), isNull);
    });

    test('a zero AMOUNT across real payments is a valid zero average', () {
      // A fully-discounted order settled by a zero tender is a real event.
      expect(PaymentMethodAnalytics.averagePaymentMinor(0, 3), 0);
      expect(PaymentMethodAnalytics.averagePaymentMinor(0, 3), isNotNull);
    });

    test('the value is an int — money is never divided into a double', () {
      final avg = PaymentMethodAnalytics.averagePaymentMinor(1000, 3);
      expect(avg, isA<int>());
      expect(avg, isNot(isA<double>()));
    });
  });

  group('per-method analytics', () {
    test('carries amount, count, share and average for every known method', () {
      final analytics = PaymentMethodAnalytics.forLines([
        _line('cash', amount: 12000, count: 4),
        _line('card', amount: 5000, count: 2),
        _line('bit', amount: 2000, count: 1),
        _line('external', amount: 1000, count: 1),
      ], totalCollectedMinor: 20000);

      expect(analytics.map((a) => a.method), [
        'cash',
        'card',
        'bit',
        'external',
      ]);
      expect(analytics.map((a) => a.amountMinor), [12000, 5000, 2000, 1000]);
      expect(analytics.map((a) => a.count), [4, 2, 1, 1]);
      expect(analytics.map((a) => a.shareBps), [6000, 2500, 1000, 500]);
      expect(analytics.map((a) => a.averageMinor), [3000, 2500, 2000, 1000]);
    });

    test('an UNKNOWN future method is preserved with truthful figures', () {
      final analytics = PaymentMethodAnalytics.forLines([
        _line('cash', amount: 15000, count: 5),
        _line('crypto', amount: 5000, count: 2),
      ], totalCollectedMinor: 20000);

      final unknown = analytics.last;
      expect(unknown.method, 'crypto');
      expect(unknown.amountMinor, 5000);
      expect(unknown.count, 2);
      expect(unknown.shareBps, 2500);
      expect(unknown.averageMinor, 2500);
    });

    test('a window that collected nothing has amounts but no shares', () {
      final analytics = PaymentMethodAnalytics.forLines([
        _line('cash', amount: 0, count: 0),
      ], totalCollectedMinor: 0);
      expect(analytics.single.amountMinor, 0);
      expect(analytics.single.hasShare, isFalse);
      expect(analytics.single.shareBps, isNull);
      expect(analytics.single.averageMinor, isNull);
    });
  });

  group('SERVER-B capability gate', () {
    test('A. a PRE-SERVER-B comparison (additive fields absent) => false', () {
      final report = _report(
        comparison: const ReportComparison(
          grossSalesMinor: 18000,
          netSalesMinor: 17000,
          orderCount: 5,
          cashSalesMinor: 9000,
        ),
      );
      expect(report.supportsPaymentMethodHistoryFilters, isFalse);
    });

    test('B. additive fields present as ZERO => true — a real value, and proof '
        'the migration ran', () {
      final report = _report(
        comparison: const ReportComparison(
          grossSalesMinor: 0,
          netSalesMinor: 0,
          orderCount: 0,
          cashSalesMinor: 0,
          completedOrderCount: 0,
          discountTotalMinor: 0,
        ),
      );
      expect(report.supportsPaymentMethodHistoryFilters, isTrue);
    });

    test('C. additive fields present and non-zero => true', () {
      final report = _report(
        comparison: const ReportComparison(
          grossSalesMinor: 18000,
          netSalesMinor: 17000,
          orderCount: 5,
          cashSalesMinor: 9000,
          completedOrderCount: 4,
          discountTotalMinor: 1200,
        ),
      );
      expect(report.supportsPaymentMethodHistoryFilters, isTrue);
    });

    test('BOTH keys are required — a half-present payload does not count', () {
      for (final cmp in const [
        ReportComparison(
          grossSalesMinor: 1,
          netSalesMinor: 1,
          orderCount: 1,
          cashSalesMinor: 1,
          completedOrderCount: 4,
        ),
        ReportComparison(
          grossSalesMinor: 1,
          netSalesMinor: 1,
          orderCount: 1,
          cashSalesMinor: 1,
          discountTotalMinor: 1200,
        ),
      ]) {
        expect(
          _report(comparison: cmp).supportsPaymentMethodHistoryFilters,
          isFalse,
        );
      }
    });

    test('NO comparison at all => false', () {
      expect(_report().supportsPaymentMethodHistoryFilters, isFalse);
    });

    test('D. the gate reads the PAYLOAD — nothing about the app, its version, '
        'or how much data the window happened to hold', () {
      // Two reports whose only difference is the additive keys. Everything
      // else — money, counts, currency, the range — is identical, so no other
      // signal can be what is being consulted.
      const withKeys = ReportComparison(
        grossSalesMinor: 18000,
        netSalesMinor: 17000,
        orderCount: 5,
        cashSalesMinor: 9000,
        completedOrderCount: 4,
        discountTotalMinor: 1200,
      );
      const withoutKeys = ReportComparison(
        grossSalesMinor: 18000,
        netSalesMinor: 17000,
        orderCount: 5,
        cashSalesMinor: 9000,
      );
      expect(
        _report(comparison: withKeys).supportsPaymentMethodHistoryFilters,
        isTrue,
      );
      expect(
        _report(comparison: withoutKeys).supportsPaymentMethodHistoryFilters,
        isFalse,
      );
    });
  });
}
