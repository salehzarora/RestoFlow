import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/comparison_delta.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart'
    show ReportRange, deltaPercent;
import 'package:restoflow_dashboard/src/data/order_history_models.dart'
    show OrderHistoryRange;

/// DASHBOARD-OWNER-ANALYTICS-F0 — foundations.
///
/// The point of these tests is not that the new types "work"; it is that
/// adopting them cannot move a wire token or change a rendered number. Two
/// range enums and a loose `deltaPercent` are being unified, and the only safe
/// unification is one that is provably lossless.
void main() {
  group('F0.1 AnalyticsRange — wire compatibility', () {
    test('wire tokens are exactly the server p_range contract', () {
      expect(AnalyticsRange.values.map((r) => r.wire).toList(), [
        'today',
        'yesterday',
        'last7',
        'last30',
      ]);
    });

    test('every legacy ReportRange round-trips losslessly, wire included', () {
      for (final legacy in ReportRange.values) {
        final unified = AnalyticsRange.fromReportRange(legacy);
        expect(
          unified.wire,
          legacy.wire,
          reason: 'wire must not move for ${legacy.name}',
        );
        expect(unified.asReportRange, legacy);
      }
      // Total in both directions: no legacy value is left unrepresented.
      expect(ReportRange.values.length, AnalyticsRange.values.length);
    });

    test('every legacy OrderHistoryRange round-trips losslessly', () {
      for (final legacy in OrderHistoryRange.values) {
        final unified = AnalyticsRange.fromOrderHistoryRange(legacy);
        expect(unified.wire, legacy.wire);
        expect(unified.asOrderHistoryRange, legacy);
      }
      expect(OrderHistoryRange.values.length, AnalyticsRange.values.length);
    });

    test('the two legacy enums agree on the wire — which is what makes one '
        'canonical type safe', () {
      for (final r in AnalyticsRange.values) {
        expect(r.asReportRange.wire, r.asOrderHistoryRange.wire);
      }
    });

    test('fromWire parses every token and never throws on junk', () {
      for (final r in AnalyticsRange.values) {
        expect(AnalyticsRange.fromWire(r.wire), r);
      }
      // Matching the pre-existing forgiving behaviour of BOTH legacy enums: a
      // malformed echo degrades to today rather than crashing a dashboard.
      expect(AnalyticsRange.fromWire(null), AnalyticsRange.today);
      expect(AnalyticsRange.fromWire(''), AnalyticsRange.today);
      expect(AnalyticsRange.fromWire('last90'), AnalyticsRange.today);
      expect(AnalyticsRange.fromWire('TODAY'), AnalyticsRange.today);
    });

    test('isSingleDay matches the legacy ReportRange definition exactly', () {
      for (final r in AnalyticsRange.values) {
        expect(
          r.isSingleDay,
          r.asReportRange.isSingleDay,
          reason: 'hourly-curve eligibility must not drift for ${r.name}',
        );
      }
      expect(AnalyticsRange.today.isSingleDay, isTrue);
      expect(AnalyticsRange.yesterday.isSingleDay, isTrue);
      expect(AnalyticsRange.last7.isSingleDay, isFalse);
      expect(AnalyticsRange.last30.isSingleDay, isFalse);
    });

    test('days reports the window length for labelling', () {
      expect(AnalyticsRange.today.days, 1);
      expect(AnalyticsRange.yesterday.days, 1);
      expect(AnalyticsRange.last7.days, 7);
      expect(AnalyticsRange.last30.days, 30);
    });
  });

  group('F0.1 AnalyticsRange — comparison honesty', () {
    test('today is the ONLY partial-vs-complete range', () {
      expect(
        AnalyticsRange.today.comparisonKind,
        AnalyticsComparisonKind.partialVsCompletePriorDay,
      );
      for (final r in AnalyticsRange.values.where(
        (r) => r != AnalyticsRange.today,
      )) {
        expect(
          r.comparisonKind,
          AnalyticsComparisonKind.equalLengthPriorWindow,
          reason: '${r.name} compares equal-length windows',
        );
      }
    });
  });

  group('F0.2 ComparisonDelta', () {
    test('increase reports both absolute and percent', () {
      final d = ComparisonDelta.of(150, 100);
      expect(d.state, ComparisonState.increase);
      expect(d.absolute, 50);
      expect(d.percent, 50);
      expect(d.hasBasis, isTrue);
      expect(d.isIncrease, isTrue);
      expect(d.isDecrease, isFalse);
    });

    test('decrease is signed, not absolute-valued', () {
      final d = ComparisonDelta.of(75, 100);
      expect(d.state, ComparisonState.decrease);
      expect(d.absolute, -25);
      expect(d.percent, -25);
      expect(d.isDecrease, isTrue);
    });

    test('flat is a measured no-change, distinct from noBasis', () {
      final d = ComparisonDelta.of(100, 100);
      expect(d.state, ComparisonState.flat);
      expect(d.absolute, 0);
      expect(d.percent, 0);
      // The distinction that matters: flat HAS a basis and may render "0%",
      // whereas noBasis must render an em dash.
      expect(d.hasBasis, isTrue);
      expect(ComparisonDelta.of(100, 0).hasBasis, isFalse);
    });

    test('a null prior yields no basis and NO fabricated percentage', () {
      final d = ComparisonDelta.of(500, null);
      expect(d.state, ComparisonState.noBasis);
      expect(d.absolute, isNull);
      expect(d.percent, isNull);
    });

    test('a ZERO prior yields no basis — growth from nothing has no honest '
        'percentage', () {
      final d = ComparisonDelta.of(500, 0);
      expect(d.state, ComparisonState.noBasis);
      expect(d.percent, isNull);
      // The trap this guards: 500 vs 0 must never render as +100% or +50000%.
      expect(d.absolute, isNull);
    });

    test('zero current against a real prior is a true -100%', () {
      final d = ComparisonDelta.of(0, 250);
      expect(d.state, ComparisonState.decrease);
      expect(d.absolute, -250);
      expect(d.percent, -100);
    });

    test('percent matches the pre-existing deltaPercent EXACTLY, so adopting '
        'this cannot move a rendered number', () {
      const cases = <(int, int?)>[
        (150, 100),
        (75, 100),
        (100, 100),
        (0, 250),
        (1, 3),
        (2, 3),
        (-50, 100),
        (99, 100),
        (101, 100),
        (7, 2),
        (500, null),
        (500, 0),
      ];
      for (final (current, prior) in cases) {
        expect(
          ComparisonDelta.of(current, prior).percent,
          deltaPercent(current, prior),
          reason: 'divergence at current=$current prior=$prior',
        );
      }
    });

    test(
      'truncates toward zero for negatives, exactly like integer division',
      () {
        // -1 * 100 ~/ 3 == -33 (toward zero), not -34.
        expect(ComparisonDelta.of(2, 3).percent, -33);
        expect(ComparisonDelta.of(2, 3).percent, deltaPercent(2, 3));
      },
    );

    test('carries integer minor units without introducing a double', () {
      final d = ComparisonDelta.of(123456, 100000);
      expect(d.absolute, 23456);
      expect(d.percent, 23);
      expect(d.absolute, isA<int>());
      expect(d.percent, isA<int>());
    });

    test('value equality so widgets can compare cheaply', () {
      expect(ComparisonDelta.of(10, 5), ComparisonDelta.of(10, 5));
      expect(
        ComparisonDelta.of(10, 5).hashCode,
        ComparisonDelta.of(10, 5).hashCode,
      );
      expect(ComparisonDelta.of(10, 5), isNot(ComparisonDelta.of(10, 6)));
      // null prior and zero prior are both noBasis but remain distinguishable.
      expect(ComparisonDelta.of(10, null), isNot(ComparisonDelta.of(10, 0)));
    });
  });
}
