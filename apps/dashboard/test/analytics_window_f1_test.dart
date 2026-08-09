/// DASHBOARD-VISUAL-RANGE-REFRESH-F1 — the extended range domain.
///
/// The server gained last60/last90 and a custom From/To window in S0. These
/// assertions pin the CLIENT half of that contract: the tokens it sends, the
/// windows it refuses to build, and — the part no compiler checks — that a
/// preset and a custom window covering the same days are never mistaken for one
/// another by a cache key.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';
import 'package:restoflow_dashboard/src/analytics/owner_report_query_key.dart';
import 'package:restoflow_dashboard/src/analytics/owner_sales_series_query_key.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart' show ReportRange;
import 'package:restoflow_dashboard/src/data/order_history_models.dart';

void main() {
  group('F1.A AnalyticsRange', () {
    test('six presets, and their day counts are the server windows', () {
      expect(AnalyticsRange.values.length, 6);
      expect(AnalyticsRange.today.days, 1);
      expect(AnalyticsRange.yesterday.days, 1);
      expect(AnalyticsRange.last7.days, 7);
      expect(AnalyticsRange.last30.days, 30);
      expect(AnalyticsRange.last60.days, 60);
      expect(AnalyticsRange.last90.days, 90);
    });

    test('only today/yesterday are single-day — the hourly-curve rule did not '
        'widen with the enum', () {
      for (final r in AnalyticsRange.values) {
        expect(
          r.isSingleDay,
          r == AnalyticsRange.today || r == AnalyticsRange.yesterday,
          reason: '${r.name} single-day eligibility',
        );
      }
    });

    test('last60/last90 round-trip through both legacy enums losslessly', () {
      for (final r in [AnalyticsRange.last60, AnalyticsRange.last90]) {
        expect(AnalyticsRange.fromReportRange(r.asReportRange), r);
        expect(AnalyticsRange.fromOrderHistoryRange(r.asOrderHistoryRange), r);
        expect(r.asReportRange.wire, r.wire);
        expect(r.asOrderHistoryRange.wire, r.wire);
      }
    });

    test('every preset compares against an equal-length prior window except '
        'today, which is partial', () {
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
          reason: '${r.name} must not claim a partial comparison',
        );
      }
    });
  });

  group('F1.B AnalyticsWindow', () {
    DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

    test('a preset window carries no dates — its bounds are the server\'s', () {
      const w = AnalyticsWindow.preset(AnalyticsRange.last60);
      expect(w.isPreset, isTrue);
      expect(w.isCustom, isFalse);
      expect(w.presetRange, AnalyticsRange.last60);
      expect(w.startDay, isNull);
      expect(w.endDay, isNull);
      expect(w.inclusiveDayCount, 60);
      expect(w.wire, 'last60');
    });

    test('preset equality and hash are by range', () {
      expect(
        const AnalyticsWindow.preset(AnalyticsRange.last60),
        const AnalyticsWindow.preset(AnalyticsRange.last60),
      );
      expect(
        const AnalyticsWindow.preset(AnalyticsRange.last60).hashCode,
        const AnalyticsWindow.preset(AnalyticsRange.last60).hashCode,
      );
      expect(
        const AnalyticsWindow.preset(AnalyticsRange.last60),
        isNot(const AnalyticsWindow.preset(AnalyticsRange.last90)),
      );
    });

    test(
      'custom bounds are DATE-ONLY: a time of day cannot change identity',
      () {
        final noon = AnalyticsWindow.custom(
          DateTime.utc(2026, 3, 1, 12, 34, 56),
          DateTime.utc(2026, 3, 10, 23, 59),
        );
        final midnight = AnalyticsWindow.custom(d(2026, 3, 1), d(2026, 3, 10));
        expect(noon, midnight);
        expect(noon.hashCode, midnight.hashCode);
        expect((noon as CustomAnalyticsWindow).startWire, '2026-03-01');
        expect(noon.endWire, '2026-03-10');
      },
    );

    test('different dates are different windows', () {
      expect(
        AnalyticsWindow.custom(d(2026, 3, 1), d(2026, 3, 10)),
        isNot(AnalyticsWindow.custom(d(2026, 3, 2), d(2026, 3, 10))),
      );
      expect(
        AnalyticsWindow.custom(d(2026, 3, 1), d(2026, 3, 10)),
        isNot(AnalyticsWindow.custom(d(2026, 3, 1), d(2026, 3, 11))),
      );
    });

    test('the day count is INCLUSIVE of both endpoints', () {
      expect(
        AnalyticsWindow.custom(d(2026, 3, 1), d(2026, 3, 1)).inclusiveDayCount,
        1,
      );
      expect(
        AnalyticsWindow.custom(d(2026, 3, 1), d(2026, 3, 10)).inclusiveDayCount,
        10,
      );
    });

    test('92 inclusive days is accepted and 93 is refused — the same boundary '
        'the migration enforces with 22023', () {
      final start = d(2026, 1, 1);
      final ok = AnalyticsWindow.custom(
        start,
        start.add(const Duration(days: 91)),
      );
      expect(ok.inclusiveDayCount, 92);
      expect(
        () =>
            AnalyticsWindow.custom(start, start.add(const Duration(days: 92))),
        throwsArgumentError,
      );
      expect(
        CustomAnalyticsWindow.tryCreate(
          start,
          start.add(const Duration(days: 92)),
        ),
        isNull,
      );
    });

    test('a reversed window is refused', () {
      expect(
        () => AnalyticsWindow.custom(d(2026, 3, 10), d(2026, 3, 1)),
        throwsArgumentError,
      );
      expect(
        CustomAnalyticsWindow.tryCreate(d(2026, 3, 10), d(2026, 3, 1)),
        isNull,
      );
    });

    test('a HALF-supplied window is refused — both bounds or neither, exactly '
        'as the server requires', () {
      expect(CustomAnalyticsWindow.tryCreate(d(2026, 3, 1), null), isNull);
      expect(CustomAnalyticsWindow.tryCreate(null, d(2026, 3, 1)), isNull);
      expect(CustomAnalyticsWindow.tryCreate(null, null), isNull);
      expect(
        CustomAnalyticsWindow.isValidRange(d(2026, 3, 1), d(2026, 3, 2)),
        isTrue,
      );
    });

    test('THE LOAD-BEARING ONE: preset last60 is NOT a custom 60-day window, '
        'even when the dates line up exactly', () {
      final end = d(2026, 3, 31);
      final custom = AnalyticsWindow.custom(
        end.subtract(const Duration(days: 59)),
        end,
      );
      const preset = AnalyticsWindow.preset(AnalyticsRange.last60);
      expect(custom.inclusiveDayCount, preset.inclusiveDayCount);
      expect(custom, isNot(preset));
      expect(preset, isNot(custom));
    });
  });

  group('F1.C RPC parameter mapping', () {
    test('a preset sends ONLY p_range — never dates', () {
      for (final r in AnalyticsRange.values) {
        final p = analyticsWindowParams(AnalyticsWindow.preset(r));
        expect(p, {'p_range': r.wire});
        expect(p.containsKey('p_start'), isFalse);
        expect(p.containsKey('p_end'), isFalse);
      }
    });

    test('60/90 go out as REAL TOKENS, never emulated as client-computed '
        'custom dates — the branch-local resolution stays on the server', () {
      expect(
        analyticsWindowParams(
          const AnalyticsWindow.preset(AnalyticsRange.last60),
        ),
        {'p_range': 'last60'},
      );
      expect(
        analyticsWindowParams(
          const AnalyticsWindow.preset(AnalyticsRange.last90),
        ),
        {'p_range': 'last90'},
      );
    });

    test('a custom window sends ONLY the two inclusive dates', () {
      final p = analyticsWindowParams(
        AnalyticsWindow.custom(
          DateTime.utc(2026, 3, 1),
          DateTime.utc(2026, 3, 9),
        ),
      );
      expect(p, {'p_start': '2026-03-01', 'p_end': '2026-03-09'});
      expect(p.containsKey('p_range'), isFalse);
    });
  });

  group('F1.D query-key identity', () {
    OwnerReportQueryKey reportKey({
      ReportRange range = ReportRange.last30,
      CustomAnalyticsWindow? custom,
      String? branch = 'b1',
      bool demo = false,
    }) => OwnerReportQueryKey(
      organizationId: 'o1',
      restaurantId: 'r1',
      branchId: branch,
      range: range,
      customWindow: custom,
      isDemoMode: demo,
    );

    test('last60 and last90 are different report requests', () {
      expect(
        reportKey(range: ReportRange.last60),
        isNot(reportKey(range: ReportRange.last90)),
      );
    });

    test('a custom window is a different request from any preset, and two '
        'identical custom windows are the same request', () {
      final w = CustomAnalyticsWindow.tryCreate(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 10),
      );
      expect(reportKey(custom: w), isNot(reportKey()));
      expect(reportKey(custom: w), reportKey(custom: w));
      expect(reportKey(custom: w).hashCode, reportKey(custom: w).hashCode);
    });

    test('moving either bound is a different request — no stale reuse', () {
      final a = CustomAnalyticsWindow.tryCreate(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 10),
      );
      final movedStart = CustomAnalyticsWindow.tryCreate(
        DateTime.utc(2026, 3, 2),
        DateTime.utc(2026, 3, 10),
      );
      final movedEnd = CustomAnalyticsWindow.tryCreate(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 11),
      );
      expect(reportKey(custom: a), isNot(reportKey(custom: movedStart)));
      expect(reportKey(custom: a), isNot(reportKey(custom: movedEnd)));
    });

    test('scope and mode remain part of identity alongside the window', () {
      final w = CustomAnalyticsWindow.tryCreate(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 10),
      );
      expect(reportKey(custom: w), isNot(reportKey(custom: w, branch: 'b2')));
      expect(reportKey(custom: w), isNot(reportKey(custom: w, demo: true)));
    });

    test('the series key behaves the same way', () {
      OwnerSalesSeriesQueryKey k({
        AnalyticsRange range = AnalyticsRange.last30,
        CustomAnalyticsWindow? custom,
      }) => OwnerSalesSeriesQueryKey(
        organizationId: 'o1',
        restaurantId: 'r1',
        branchId: 'b1',
        range: range,
        customWindow: custom,
        isDemoMode: false,
      );
      final w = CustomAnalyticsWindow.tryCreate(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 10),
      );
      expect(
        k(range: AnalyticsRange.last60),
        isNot(k(range: AnalyticsRange.last90)),
      );
      expect(k(custom: w), isNot(k()));
      expect(k(custom: w), k(custom: w));
      expect(k(custom: w).window, w);
      expect(
        k(range: AnalyticsRange.last60).window,
        const AnalyticsWindow.preset(AnalyticsRange.last60),
      );
    });
  });

  group('F1.E order-history query', () {
    test('a custom window rides alongside the preset and can be CLEARED — a '
        'bare null in copyWith could not express that', () {
      final w = CustomAnalyticsWindow.tryCreate(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 10),
      )!;
      const base = OrderHistoryQuery(range: OrderHistoryRange.last90);
      final custom = base.copyWith(customWindow: w);
      expect(custom.isCustomWindow, isTrue);
      expect(custom.range, OrderHistoryRange.last90);

      // Returning to a preset restores the previous one rather than resetting
      // to today.
      final cleared = custom.copyWith(clearCustomWindow: true);
      expect(cleared.isCustomWindow, isFalse);
      expect(cleared.range, OrderHistoryRange.last90);

      // And an unrelated copyWith must NOT drop the window.
      expect(custom.copyWith(search: 'x').customWindow, w);
    });
  });

  group('F1.F the Overview control stays at four presets until F2', () {
    test(
      'the legacy segmented control exposes exactly today/yesterday/7/30',
      () {
        expect(kOverviewRangePresetsBeforeCustomUx, const [
          ReportRange.today,
          ReportRange.yesterday,
          ReportRange.last7,
          ReportRange.last30,
        ]);
      },
    );

    test('last60/last90 are supported by the DOMAIN while deliberately absent '
        'from that control — F2 owns exposing them', () {
      expect(
        kOverviewRangePresetsBeforeCustomUx,
        isNot(contains(ReportRange.last60)),
      );
      expect(
        kOverviewRangePresetsBeforeCustomUx,
        isNot(contains(ReportRange.last90)),
      );
      // The domain still knows them, which is the whole point of the split.
      expect(ReportRange.values, contains(ReportRange.last60));
      expect(ReportRange.values, contains(ReportRange.last90));
      expect(AnalyticsRange.fromReportRange(ReportRange.last90).wire, 'last90');
    });
  });
}
