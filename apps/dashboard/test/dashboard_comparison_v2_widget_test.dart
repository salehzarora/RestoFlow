import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-B) — the Overview comparison layer.
///
/// The load-bearing assertions are about what is NOT shown: no comparison is
/// offered for a metric the server did not send a prior for, no percentage is
/// drawn against a zero baseline, and the `today` wording never implies an
/// elapsed-time match the backend does not compute.

/// Serves one fixed report so a test can post an exact comparison shape.
class _FixedRepository implements OwnerReportsRepository {
  _FixedRepository(this.report);

  final DashboardReport report;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
    DashboardAnalyticsScope? analyticsScope,
  }) async => report;
}

DashboardReport _report({
  ReportComparison? comparison,
  ReportRange range = ReportRange.today,
  int orderCount = 8,
  int completedOrderCount = 6,
  int netSalesMinor = 22500,
  int discountTotalMinor = 1500,
}) => DashboardReport(
  currencyCode: 'ILS',
  businessDateLabel: '2026-08-08',
  grossSalesMinor: 24000,
  netSalesMinor: netSalesMinor,
  discountTotalMinor: discountTotalMinor,
  collectedMinor: 20000,
  cashSalesMinor: 12000,
  lastCashPaymentMinor: 3000,
  orderCount: orderCount,
  completedOrderCount: completedOrderCount,
  openOrderCount: 2,
  unpaidOrderCount: 1,
  voidCount: 1,
  voidTotalMinor: 900,
  openingFloatMinor: 0,
  expectedCashMinor: 0,
  countedCashMinor: 0,
  shiftStatus: 'none',
  branches: const [],
  topItems: const [],
  recentOrders: const [],
  paymentMethods: const [],
  comparison: comparison,
  range: range,
);

/// The pre-SERVER-B prior window: the five original keys and nothing else.
const _legacyComparison = ReportComparison(
  grossSalesMinor: 18000,
  netSalesMinor: 17000,
  orderCount: 5,
  cashSalesMinor: 9000,
);

/// A SERVER-B prior window carrying both additive primitives.
const _serverBComparison = ReportComparison(
  grossSalesMinor: 18000,
  netSalesMinor: 17000,
  orderCount: 5,
  cashSalesMinor: 9000,
  completedOrderCount: 4,
  discountTotalMinor: 1200,
);

Widget _wrap(DashboardReport report, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: [
        ownerReportsRepositoryProvider.overrideWithValue(
          _FixedRepository(report),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        theme: restoflowBaseTheme(),
        home: const DashboardHomeScreen(),
      ),
    );

void _size(WidgetTester tester, [Size size = const Size(1320, 3200)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _deltaText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key('$key-delta'))).data!;

RestoflowMetricDelta? _kpiDelta(WidgetTester tester, String key) =>
    tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).delta;

void main() {
  group('the deployment seam', () {
    testWidgets('a PRE-SERVER-B server shows NO comparison strip at all — the '
        'absent keys are not rendered as zero deltas', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report(comparison: _legacyComparison)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('period-comparison-card')), findsNothing);
      expect(find.byKey(const Key('comparison-completed-delta')), findsNothing);
      expect(find.byKey(const Key('comparison-discounts-delta')), findsNothing);

      // The rest of the comparison layer is unaffected: the KPI deltas that
      // only need the ORIGINAL keys still render.
      expect(_kpiDelta(tester, 'kpi-net-sales'), isNotNull);
      expect(_kpiDelta(tester, 'kpi-orders'), isNotNull);
    });

    testWidgets('with NO comparison at all, nothing comparative renders', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('period-comparison-card')), findsNothing);
      expect(_kpiDelta(tester, 'kpi-net-sales'), isNull);
      expect(_kpiDelta(tester, 'kpi-avg-ticket'), isNull);
    });

    testWidgets('ONE additive key present renders ONLY that row', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            comparison: const ReportComparison(
              grossSalesMinor: 18000,
              netSalesMinor: 17000,
              orderCount: 5,
              cashSalesMinor: 9000,
              discountTotalMinor: 1200,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('period-comparison-card')), findsOneWidget);
      expect(
        find.byKey(const Key('comparison-discounts-delta')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('comparison-completed-delta')),
        findsNothing,
        reason: 'completed_count was absent — no row, not a zero row',
      );
    });
  });

  group('the comparison strip', () {
    testWidgets('renders completed orders and discounts with signed integer '
        'deltas', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report(comparison: _serverBComparison)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('period-comparison-card')), findsOneWidget);
      // completed: 6 vs 4 => +2, +50%
      expect(_deltaText(tester, 'comparison-completed'), '+2 · +50%');
      // discounts: ₪15.00 vs ₪12.00 => +₪3.00, +25%
      expect(_deltaText(tester, 'comparison-discounts'), '+₪3.00 · +25%');
    });

    testWidgets('a DECREASE carries its own sign, from MoneyFormatter', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            completedOrderCount: 3,
            discountTotalMinor: 900,
            comparison: _serverBComparison,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // completed: 3 vs 4 => -1, -25%
      expect(_deltaText(tester, 'comparison-completed'), '-1 · -25%');
      // discounts: ₪9.00 vs ₪12.00 => -₪3.00, -25%
      expect(_deltaText(tester, 'comparison-discounts'), '-₪3.00 · -25%');
    });

    testWidgets('a measured NO CHANGE renders a real zero, not an em dash', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            completedOrderCount: 4,
            discountTotalMinor: 1200,
            comparison: _serverBComparison,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_deltaText(tester, 'comparison-completed'), '0 · 0%');
      expect(_deltaText(tester, 'comparison-discounts'), '₪0.00 · 0%');
      expect(find.byIcon(Icons.remove), findsNWidgets(2));
    });

    testWidgets('a ZERO prior renders an em dash — never a percentage against '
        'nothing', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            comparison: const ReportComparison(
              grossSalesMinor: 18000,
              netSalesMinor: 17000,
              orderCount: 5,
              cashSalesMinor: 9000,
              completedOrderCount: 0,
              discountTotalMinor: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_deltaText(tester, 'comparison-completed'), '—');
      expect(_deltaText(tester, 'comparison-discounts'), '—');
      // A zero baseline is not a direction, so no arrow is drawn either.
      expect(find.byIcon(Icons.north), findsNothing);
      expect(find.byIcon(Icons.south), findsNothing);
    });

    testWidgets('direction is shown NEUTRALLY — the strip never borrows the '
        "KPI cards' success/danger arrows", (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report(comparison: _serverBComparison)));
      await tester.pumpAndSettle();

      // Both rows rose; both use the neutral mark.
      expect(find.byIcon(Icons.north), findsNWidgets(2));
      // The toned KPI arrows belong to the KPI cards only. Four KPI deltas rise
      // here (gross, net, orders, cash) plus average ticket; none of the five
      // comes from the strip.
      expect(
        find.descendant(
          of: find.byKey(const Key('period-comparison-card')),
          matching: find.byIcon(Icons.arrow_upward),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('period-comparison-card')),
          matching: find.byIcon(Icons.arrow_downward),
        ),
        findsNothing,
      );
    });

    testWidgets('the strip does not repeat values the KPI cards already show', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report(comparison: _serverBComparison)));
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('period-comparison-card'));
      // Net sales / order count / their values live on the KPI cards; the strip
      // carries comparisons only.
      expect(
        find.descendant(of: card, matching: find.text('₪225.00')),
        findsNothing,
      );
      expect(find.descendant(of: card, matching: find.text('8')), findsNothing);
    });
  });

  group('average order value', () {
    testWidgets('gains a delta computed from INTEGER minor units on both '
        'sides', (tester) async {
      _size(tester);
      // current 22500 / 8 = 2812 ; prior 17000 / 5 = 3400 => -588, -17%
      await tester.pumpWidget(_wrap(_report(comparison: _serverBComparison)));
      await tester.pumpAndSettle();

      final card = tester.widget<RestoflowMetricCard>(
        find.byKey(const Key('kpi-avg-ticket')),
      );
      expect(card.value, '₪28.12');
      expect(card.delta, isNotNull);
      expect(card.delta!.positive, isFalse);
      expect(card.delta!.label, contains('17%'));
    });

    testWidgets('a prior window with NO orders gives no average-ticket delta', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            comparison: const ReportComparison(
              grossSalesMinor: 0,
              netSalesMinor: 0,
              orderCount: 0,
              cashSalesMinor: 0,
              completedOrderCount: 0,
              discountTotalMinor: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_kpiDelta(tester, 'kpi-avg-ticket'), isNull);
      expect(_kpiDelta(tester, 'kpi-net-sales'), isNull);
    });
  });

  group('comparison wording', () {
    testWidgets('TODAY says "all of yesterday", in the strip heading and in '
        'every KPI delta', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report(comparison: _serverBComparison)));
      await tester.pumpAndSettle();

      expect(find.text('Compared with all of yesterday'), findsOneWidget);
      expect(find.textContaining('vs all of yesterday'), findsWidgets);
    });

    testWidgets('no wording implies an elapsed-time match', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report(comparison: _serverBComparison)));
      await tester.pumpAndSettle();

      for (final forbidden in const [
        'same time',
        'same elapsed',
        'so far',
        'this time yesterday',
      ]) {
        expect(
          find.textContaining(forbidden, skipOffstage: false),
          findsNothing,
          reason: 'no backend computes "$forbidden" — it must not be claimed',
        );
      }
    });

    for (final (locale, heading) in const [
      (Locale('ar'), 'مقارنةً بكامل يوم أمس'),
      (Locale('he'), 'לעומת כל יום אתמול'),
    ]) {
      testWidgets('TODAY says "all of yesterday" in ${locale.languageCode}', (
        tester,
      ) async {
        _size(tester);
        await tester.pumpWidget(
          _wrap(_report(comparison: _serverBComparison), locale: locale),
        );
        await tester.pumpAndSettle();

        expect(find.text(heading), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final (range, heading) in const [
      (ReportRange.yesterday, 'Compared with the day before'),
      (ReportRange.last7, 'Compared with the previous 7 days'),
      (ReportRange.last30, 'Compared with the previous 30 days'),
    ]) {
      testWidgets('${range.wire} names the immediately preceding equal-length '
          'window', (tester) async {
        _size(tester);
        await tester.pumpWidget(
          _wrap(_report(comparison: _serverBComparison, range: range)),
        );
        await tester.pumpAndSettle();

        expect(find.text(heading), findsOneWidget);
        // Never a calendar-week / calendar-month claim.
        expect(find.textContaining('last week'), findsNothing);
        expect(find.textContaining('last month'), findsNothing);
      });
    }
  });

  testWidgets('the strip survives a 2x text scale at phone width', (
    tester,
  ) async {
    _size(tester, const Size(390, 3600));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_wrap(_report(comparison: _serverBComparison)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('period-comparison-card')), findsOneWidget);
  });
}
