import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — the Overview daily sales trend.
///
/// The trend replaces the hourly curve for the multi-day ranges and must not
/// disturb the single-day ones. Every state is asserted for HONESTY rather than
/// for pixels: an empty window must not grow bars, a failed load must not remove
/// the rest of the Overview, and the money on screen must be the integer-minor
/// figure the series carried.

/// A stub series repository: deterministic, and it records what it was asked
/// for so a test can prove today/yesterday ask for nothing.
class _StubSeriesRepository implements OwnerSalesSeriesRepository {
  _StubSeriesRepository({
    this.buckets,
    this.fail = false,
    this.unavailable = false,
  });

  final List<OwnerSalesSeriesBucket>? buckets;
  final bool fail;
  final bool unavailable;

  final List<AnalyticsRange> calls = <AnalyticsRange>[];

  @override
  Future<OwnerSalesSeries> loadSeries({required AnalyticsRange range}) async {
    calls.add(range);
    if (fail) throw const OwnerSalesSeriesException('boom');
    if (unavailable) return OwnerSalesSeries.unavailable(range.wire);
    return OwnerSalesSeries(
      currencyCode: 'ILS',
      rangeWire: range.wire,
      buckets: buckets ?? _threeDays,
    );
  }
}

/// Three days whose peak (₪312.45) is a value no other number on the Overview
/// carries, so finding it proves it came from the SERIES and not the report.
final List<OwnerSalesSeriesBucket> _threeDays = <OwnerSalesSeriesBucket>[
  _bucket('2026-08-06', net: 18000, orders: 5),
  _bucket('2026-08-07', net: 31245, orders: 11),
  _bucket('2026-08-08', net: 22500, orders: 8),
];

OwnerSalesSeriesBucket _bucket(
  String day, {
  required int net,
  required int orders,
}) => OwnerSalesSeriesBucket(
  day: BusinessDay.tryParse(day)!,
  orderCount: orders,
  grossMinor: net,
  discountMinor: 0,
  netMinor: net,
  voidCount: 0,
  voidTotalMinor: 0,
  collectedMinor: net,
  cashMinor: net,
);

Widget _wrap(
  _StubSeriesRepository repo, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [ownerSalesSeriesRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const DashboardHomeScreen(),
  ),
);

void _size(WidgetTester tester, [Size size = const Size(1320, 3000)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _selectRange(WidgetTester tester, String wire) async {
  await tester.tap(find.byKey(Key('range-chip-$wire')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('last7 renders the daily trend in the analytics slot', (
    tester,
  ) async {
    _size(tester);
    final repo = _StubSeriesRepository();
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await _selectRange(tester, 'last7');

    expect(find.byKey(const Key('sales-by-day-card')), findsOneWidget);
    expect(find.byKey(const Key('sales-by-day-chart')), findsOneWidget);
    expect(repo.calls, [AnalyticsRange.last7]);
  });

  testWidgets('last30 renders the daily trend and asks for the last30 window', (
    tester,
  ) async {
    _size(tester);
    final repo = _StubSeriesRepository();
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await _selectRange(tester, 'last30');

    expect(find.byKey(const Key('sales-by-day-chart')), findsOneWidget);
    expect(repo.calls, [AnalyticsRange.last30]);
  });

  testWidgets('today keeps the sales-by-HOUR curve and asks for no series', (
    tester,
  ) async {
    _size(tester);
    final repo = _StubSeriesRepository();
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // today is the default range — nothing to select.
    expect(find.byKey(const Key('sales-by-hour-card')), findsOneWidget);
    expect(find.byKey(const Key('sales-by-day-card')), findsNothing);
    expect(repo.calls, isEmpty);
  });

  testWidgets(
    'yesterday keeps the sales-by-HOUR curve and asks for no series',
    (tester) async {
      _size(tester);
      final repo = _StubSeriesRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      await _selectRange(tester, 'yesterday');

      expect(find.byKey(const Key('sales-by-day-card')), findsNothing);
      expect(repo.calls, isEmpty);
    },
  );

  testWidgets('returning from last7 to today puts the hourly curve back', (
    tester,
  ) async {
    _size(tester);
    final repo = _StubSeriesRepository();
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await _selectRange(tester, 'last7');
    expect(find.byKey(const Key('sales-by-day-card')), findsOneWidget);
    expect(find.byKey(const Key('sales-by-hour-card')), findsNothing);

    await _selectRange(tester, 'today');
    expect(find.byKey(const Key('sales-by-day-card')), findsNothing);
    expect(find.byKey(const Key('sales-by-hour-card')), findsOneWidget);
  });

  testWidgets('the chart plots the series NET, formatted as integer-minor '
      'money', (tester) async {
    _size(tester);
    await tester.pumpWidget(_wrap(_StubSeriesRepository()));
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last7');

    final chart = tester.widget<RestoflowAreaChart>(
      find.byKey(const Key('sales-by-day-chart')),
    );

    // One point per day, in the series' order, carrying the raw minor value.
    expect(chart.points.map((p) => p.value), [18000, 31245, 22500]);
    // The x axis shows the day of month, mirroring the hourly chart's hour.
    expect(chart.points.map((p) => p.label), ['06', '07', '08']);
    // The peak label is the formatted peak NET — never a rounded double.
    expect(chart.peakValueLabel, '₪312.45');
  });

  testWidgets('the tooltip carries the exact branch-local date, the net, and '
      'the order count', (tester) async {
    _size(tester);
    await tester.pumpWidget(_wrap(_StubSeriesRepository()));
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last7');

    final chart = tester.widget<RestoflowAreaChart>(
      find.byKey(const Key('sales-by-day-chart')),
    );
    final tooltip = chart.tooltipBuilder!(chart.points[1]);

    expect(tooltip, contains('2026-08-07'));
    expect(tooltip, contains('₪312.45'));
    expect(tooltip, contains('11'));
    expect(tooltip, contains('Orders'));
  });

  testWidgets('the tooltip follows the DAY, not the axis label — a window that '
      'repeats a day-of-month must not mix two days up', (tester) async {
    _size(tester);
    // 2026-07-08 and 2026-08-08 share the axis label "08".
    final repo = _StubSeriesRepository(
      buckets: <OwnerSalesSeriesBucket>[
        _bucket('2026-07-08', net: 1000, orders: 1),
        _bucket('2026-08-08', net: 9000, orders: 9),
      ],
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last30');

    final chart = tester.widget<RestoflowAreaChart>(
      find.byKey(const Key('sales-by-day-chart')),
    );
    expect(chart.points.map((p) => p.label), ['08', '08']);
    expect(chart.tooltipBuilder!(chart.points[0]), contains('2026-07-08'));
    expect(chart.tooltipBuilder!(chart.points[0]), contains('₪10.00'));
    expect(chart.tooltipBuilder!(chart.points[1]), contains('2026-08-08'));
    expect(chart.tooltipBuilder!(chart.points[1]), contains('₪90.00'));
  });

  testWidgets('an accessible summary names the best day and its value', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(_wrap(_StubSeriesRepository()));
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last7');

    final chart = tester.widget<RestoflowAreaChart>(
      find.byKey(const Key('sales-by-day-chart')),
    );
    expect(chart.semanticsLabel, contains('2026-08-07'));
    expect(chart.semanticsLabel, contains('₪312.45'));
  });

  testWidgets('an EMPTY window shows an honest empty state — no bars, no '
      'fabricated zeros', (tester) async {
    _size(tester);
    final repo = _StubSeriesRepository(buckets: const []);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last7');

    expect(find.byKey(const Key('sales-by-day-card')), findsOneWidget);
    expect(find.byKey(const Key('sales-by-day-empty')), findsOneWidget);
    expect(find.byKey(const Key('sales-by-day-chart')), findsNothing);
  });

  testWidgets('a NOT-DEPLOYED series says "unavailable", which is not the same '
      'claim as "no sales"', (tester) async {
    _size(tester);
    await tester.pumpWidget(_wrap(_StubSeriesRepository(unavailable: true)));
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last7');

    expect(find.byKey(const Key('sales-by-day-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('sales-by-day-empty')), findsNothing);
    expect(find.byKey(const Key('sales-by-day-chart')), findsNothing);
  });

  testWidgets('a FAILED series shows a local error and leaves the rest of the '
      'Overview standing', (tester) async {
    _size(tester);
    await tester.pumpWidget(_wrap(_StubSeriesRepository(fail: true)));
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last7');

    expect(find.byKey(const Key('sales-by-day-error')), findsOneWidget);
    expect(find.byKey(const Key('sales-by-day-chart')), findsNothing);

    // The report itself loaded fine and must still be on screen.
    expect(find.byKey(const Key('reports-error')), findsNothing);
    expect(find.byKey(const Key('kpi-net-sales')), findsOneWidget);
    expect(find.byKey(const Key('kpi-orders')), findsOneWidget);
  });

  testWidgets('the demo Overview renders a real daily trend for last7 — the '
      'demo repository is wired, not stubbed away', (tester) async {
    _size(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ownerSalesSeriesRepositoryProvider.overrideWithValue(
            DemoOwnerSalesSeriesRepository(clock: () => DateTime(2026, 8, 8)),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          theme: restoflowBaseTheme(),
          home: const DashboardHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectRange(tester, 'last7');

    final chart = tester.widget<RestoflowAreaChart>(
      find.byKey(const Key('sales-by-day-chart')),
    );
    expect(chart.points, hasLength(7));
    // The trend sums to the "Net sales" KPI shown above it.
    final total = chart.points.fold<int>(0, (s, p) => s + p.value);
    final kpi = tester
        .widget<RestoflowMetricCard>(find.byKey(const Key('kpi-net-sales')))
        .value;
    expect(
      kpi,
      '₪${(total ~/ 100)}.${(total % 100).toString().padLeft(2, '0')}',
    );
  });

  for (final locale in const [Locale('ar'), Locale('he')]) {
    testWidgets('the trend renders under RTL (${locale.languageCode}) without '
        'overflow', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_StubSeriesRepository(), locale: locale));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.byKey(const Key('sales-by-day-chart')), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('sales-by-day-card'))),
        ),
        TextDirection.rtl,
      );
      // The numeric axis/peak content stays the same integer-minor money in
      // every locale — only the chrome is translated.
      final chart = tester.widget<RestoflowAreaChart>(
        find.byKey(const Key('sales-by-day-chart')),
      );
      expect(chart.peakValueLabel, '₪312.45');
      expect(tester.takeException(), isNull);
    });
  }
}
