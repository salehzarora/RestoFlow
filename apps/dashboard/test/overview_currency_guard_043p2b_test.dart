import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart'
    show CustomAnalyticsWindow;
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// OPS-043 Phase 2B — the REAL Dashboard Overview under D3.
///
/// D3 is one sentence — never sum unlike currencies — and it has exactly one
/// dangerous failure mode: a screen that adds ₪1,000 to $700 and prints
/// ₪1,700. Nobody can spot that by looking, which is why the decision is made
/// once, in a guard, and asserted here against the PRODUCTION screen rather
/// than against a helper.
void main() {
  group('A. single currency — nothing about today changes', () {
    testWidgets('A1. an ILS range renders the ordinary money KPIs', (
      tester,
    ) async {
      await _pump(tester, guard: const ReportCurrencyGuard.single('ILS'));

      expect(_kpi(tester, 'kpi-gross-sales'), '₪626.00');
      expect(_kpi(tester, 'kpi-net-sales'), '₪620.00');
      expect(_kpi(tester, 'kpi-orders'), '7');
      expect(find.byKey(const Key('reports-currency-split')), findsNothing);
      expect(
        find.byKey(const Key('reports-currency-unavailable')),
        findsNothing,
      );
    });

    testWidgets('A2. a USD range renders the same layout in USD', (
      tester,
    ) async {
      await _pump(tester, guard: const ReportCurrencyGuard.single('USD'));

      expect(_kpi(tester, 'kpi-gross-sales'), r'$626.00');
      expect(_kpi(tester, 'kpi-net-sales'), r'$620.00');
    });

    testWidgets('A3. LABEL AUTHORITY: the guard wins over the report envelope, '
        'so a historical ILS range is not relabelled with the restaurant\'s '
        'current USD', (tester) async {
      // The envelope says USD (today's operating currency); the window's money
      // is ILS. The screen must say ILS.
      await _pump(
        tester,
        envelopeCurrency: 'USD',
        guard: const ReportCurrencyGuard.single('ILS'),
      );

      expect(_kpi(tester, 'kpi-net-sales'), '₪620.00');
      expect(_kpi(tester, 'kpi-net-sales'), isNot(contains(r'$')));
    });

    testWidgets('A4. a 0-decimal currency renders without a fabricated '
        'fraction', (tester) async {
      await _pump(tester, guard: const ReportCurrencyGuard.single('JPY'));
      expect(_kpi(tester, 'kpi-net-sales'), 'JPY 62000');
    });

    testWidgets('A5. a 3-decimal currency keeps three digits', (tester) async {
      await _pump(tester, guard: const ReportCurrencyGuard.single('KWD'));
      expect(_kpi(tester, 'kpi-net-sales'), 'KWD 62.000');
    });
  });

  group('B. mixed currency — split, never merged', () {
    testWidgets('B1. NO merged monetary KPI survives', (tester) async {
      await _pump(tester, guard: _mixed);

      for (final key in const [
        'kpi-gross-sales',
        'kpi-net-sales',
        'kpi-avg-ticket',
        'kpi-cash-sales',
      ]) {
        expect(
          find.byKey(Key(key)),
          findsNothing,
          reason: '$key would be a sum of unlike currencies',
        );
      }
      expect(find.byKey(const Key('shift-cash-card')), findsNothing);
      expect(find.byKey(const Key('sales-by-hour-card')), findsNothing);
    });

    testWidgets('B2. each currency shows its OWN totals, unconverted', (
      tester,
    ) async {
      await _pump(tester, guard: _mixed);

      expect(find.byKey(const Key('reports-currency-split')), findsOneWidget);
      expect(find.byKey(const Key('currency-split-ILS')), findsOneWidget);
      expect(find.byKey(const Key('currency-split-USD')), findsOneWidget);
      expect(find.text('₪10.00'), findsOneWidget); // ILS net
      expect(find.text('₪8.00'), findsOneWidget); // ILS collected
      expect(find.text(r'$7.00'), findsOneWidget); // USD net
      expect(find.text(r'$5.00'), findsOneWidget); // USD collected
      // 1000 + 700 = 1700 minor units is arithmetically possible and
      // semantically meaningless. Neither it nor the collected sum may appear.
      expect(find.textContaining('17.00'), findsNothing);
      expect(find.textContaining('13.00'), findsNothing);
    });

    testWidgets('B3. the non-money COUNT survives — an order count is a valid '
        'integer whatever currency the orders were taken in', (tester) async {
      await _pump(tester, guard: _mixed);
      expect(_kpi(tester, 'currency-safety-order-count'), '7');
    });

    testWidgets('B4. the owner is told why, in their language', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(tester, guard: _mixed);
      expect(find.text(l10n.dashboardCurrencyMixedTitle), findsOneWidget);
      expect(find.text(l10n.dashboardCurrencyMixedBody), findsOneWidget);
    });
  });

  group('C. UNKNOWN — money is hidden, never guessed', () {
    testWidgets('C1. no monetary figure renders at all', (tester) async {
      await _pump(tester, guard: const ReportCurrencyGuard.unknown());

      expect(
        find.byKey(const Key('reports-currency-unavailable')),
        findsOneWidget,
      );
      for (final key in const [
        'kpi-gross-sales',
        'kpi-net-sales',
        'kpi-avg-ticket',
        'kpi-cash-sales',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      expect(find.textContaining('₪'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('C2. it says so honestly rather than showing an empty range', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(tester, guard: const ReportCurrencyGuard.unknown());
      expect(find.text(l10n.dashboardCurrencyCheckUnavailable), findsOneWidget);
      expect(find.byKey(const Key('reports-empty')), findsNothing);
    });
  });

  group('D. locales', () {
    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      testWidgets('D1. ${locale.languageCode}: the split renders without '
          'overflow', (tester) async {
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        await _pump(tester, guard: _mixed, locale: locale);
        FlutterError.onError = prior;

        expect(find.byKey(const Key('reports-currency-split')), findsOneWidget);
        expect(
          overflows.where((o) => o.contains('dashboard_home_screen.dart')),
          isEmpty,
        );
      });
    }
  });

  group('E. how the guard decides', () {
    test('E1. one currency in the breakdown = single, labelled with THAT '
        'currency — not the report envelope', () {
      final guard = ReportCurrencyGuard.resolve(
        breakdown: const CurrencyBreakdown(available: true, totals: [_ils]),
        envelopeCurrency: 'USD',
        orderCount: 7,
      );
      expect(guard.mode, ReportMoneyMode.single);
      expect(guard.displayCurrency, 'ILS');
      expect(guard.canRenderMergedMoney, isTrue);
    });

    test('E2. two currencies = mixed', () {
      final guard = ReportCurrencyGuard.resolve(
        breakdown: const CurrencyBreakdown(
          available: true,
          totals: [_ils, _usd],
        ),
        envelopeCurrency: 'ILS',
        orderCount: 7,
      );
      expect(guard.mode, ReportMoneyMode.mixed);
      expect(guard.canRenderMergedMoney, isFalse);
      expect(guard.totals, hasLength(2));
    });

    test('E3. UNAVAILABLE with orders = unknown. This is the whole point: an '
        'undeployed RPC must never read as "one currency"', () {
      final guard = ReportCurrencyGuard.resolve(
        breakdown: const CurrencyBreakdown.unavailable(),
        envelopeCurrency: 'ILS',
        orderCount: 7,
      );
      expect(guard.mode, ReportMoneyMode.unknown);
      expect(guard.canRenderMergedMoney, isFalse);
      expect(guard.displayCurrency, isNull);
    });

    test('E4. UNAVAILABLE with NO orders is safe — a window with nothing in it '
        'has no unlike currencies to add', () {
      final guard = ReportCurrencyGuard.resolve(
        breakdown: const CurrencyBreakdown.unavailable(),
        envelopeCurrency: 'ILS',
        orderCount: 0,
      );
      expect(guard.mode, ReportMoneyMode.single);
      expect(guard.displayCurrency, 'ILS');
    });

    test('E5. an available-but-empty breakdown is single (nothing to '
        'mislabel)', () {
      final guard = ReportCurrencyGuard.resolve(
        breakdown: const CurrencyBreakdown(available: true, totals: []),
        envelopeCurrency: 'ILS',
        orderCount: 3,
      );
      expect(guard.mode, ReportMoneyMode.single);
    });
  });
}

// ---------------------------------------------------------------------------

const _ils = CurrencyTotals(
  currencyCode: 'ILS',
  orderCount: 1,
  grossMinor: 1000,
  discountMinor: 0,
  netMinor: 1000,
  // deliberately NOT equal to net: two identical figures in one card would
  // make the finder below ambiguous and hide a real mistake.
  collectedMinor: 800,
  cashMinor: 800,
);
const _usd = CurrencyTotals(
  currencyCode: 'USD',
  orderCount: 1,
  grossMinor: 700,
  discountMinor: 0,
  netMinor: 700,
  collectedMinor: 500,
  cashMinor: 0,
);
const _mixed = ReportCurrencyGuard.mixed([_ils, _usd]);

String _kpi(WidgetTester tester, String key) =>
    tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).value;

/// A report shaped like a real `owner_report_range` answer: real figures and a
/// real window, so the screen has something to render or refuse to render.
DashboardReport _report(String currency) => DashboardReport(
  currencyCode: currency,
  businessDateLabel: '2026-08-18',
  grossSalesMinor: 62600,
  netSalesMinor: 62000,
  discountTotalMinor: 600,
  collectedMinor: 50000,
  cashSalesMinor: 47400,
  lastCashPaymentMinor: 1200,
  orderCount: 7,
  completedOrderCount: 6,
  openOrderCount: 1,
  unpaidOrderCount: 2,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 50000,
  expectedCashMinor: 97400,
  countedCashMinor: 97250,
  shiftStatus: 'closed',
  branches: const [],
  topItems: const [],
  recentOrders: const [],
  paymentMethods: const [],
  rangeStartLabel: '2026-08-18',
  rangeEndLabel: '2026-08-18',
);

class _Repo implements OwnerReportsRepository {
  const _Repo(this.currency);

  final String currency;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async => _report(currency);
}

Future<void> _pump(
  WidgetTester tester, {
  required ReportCurrencyGuard guard,
  String envelopeCurrency = 'ILS',
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        ownerReportsRepositoryProvider.overrideWithValue(
          _Repo(envelopeCurrency),
        ),
        dashboardCurrencyGuardProvider.overrideWith((ref) async => guard),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const DashboardHomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
