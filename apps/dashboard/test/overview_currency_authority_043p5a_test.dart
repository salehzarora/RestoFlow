import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/owner_top_items_query_key.dart'
    show kOverviewTopItemsLimit;
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart'
    show CustomAnalyticsWindow;
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_top_items.dart';
import 'package:restoflow_dashboard/src/data/owner_top_items_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// OPS-043 Phase 5A — THE WINDOW'S CURRENCY IS THE ONLY LABEL ON THE PAGE.
///
/// Phase 2B gave the KPI row its authority from the currency guard. Every other
/// money card kept formatting with `report.currencyCode`, the RPC envelope —
/// and four report RPCs advertised the ORGANIZATION default rather than the
/// restaurant's operating currency. While `currency_override` was always null
/// the two agreed, so nothing showed. The moment a restaurant sets an operating
/// currency they diverge, ON THE SAME SCREEN.
///
/// The fixture below is the one the old Phase-2B suite could not have caught
/// this with: it POPULATES `shiftCash` and `paymentMethods`, because the old
/// fixture left both empty and the offending cards were therefore absent from
/// the widget tree.
///
/// JOD is chosen deliberately. It has exponent 3, so a wrong label is not a
/// wrong symbol but a wrong NUMBER: `MoneyFormatter` takes its exponent from
/// the code it is handed, and 47400 minor units reads `JOD 47.400` under one
/// label and `₪474.00` under the other. Nobody spots that by looking.
const int kRepro = 47400;

void main() {
  group('A. the window currency wins over a stale envelope', () {
    testWidgets('A1. with the guard on JOD and the envelope still on ILS, '
        'EVERY money surface renders JOD — no ₪474.00 anywhere', (
      tester,
    ) async {
      await _pump(
        tester,
        guard: const ReportCurrencyGuard.single('JOD'),
        envelopeCurrency: 'ILS',
      );

      // The KPI row (guarded since Phase 2B).
      expect(_kpi(tester, 'kpi-cash-sales'), 'JOD 47.400');
      expect(_kpi(tester, 'kpi-gross-sales'), 'JOD 62.600');

      // The cards that used to read the envelope. The exact string matters:
      // ₪474.00 and JOD 47.400 are the SAME integer under two exponents.
      expect(
        find.textContaining('₪474.00'),
        findsNothing,
        reason: 'the 2-decimal reading of $kRepro must not appear anywhere',
      );
      expect(
        find.textContaining('₪'),
        findsNothing,
        reason: 'no ILS symbol survives anywhere on a JOD window',
      );
      expect(find.textContaining('JOD 47.400'), findsWidgets);
    });

    testWidgets(
      'A2. the shift-cash card follows the window, not the envelope',
      (tester) async {
        await _pump(
          tester,
          guard: const ReportCurrencyGuard.single('JOD'),
          envelopeCurrency: 'ILS',
        );

        final shiftCard = find.byKey(const Key('shift-cash-card'));
        expect(shiftCard, findsOneWidget);
        expect(
          find.descendant(of: shiftCard, matching: find.textContaining('JOD')),
          findsWidgets,
        );
        expect(
          find.descendant(of: shiftCard, matching: find.textContaining('₪')),
          findsNothing,
        );
      },
    );

    testWidgets('A3. the payment-mix card follows the window too', (
      tester,
    ) async {
      await _pump(
        tester,
        guard: const ReportCurrencyGuard.single('JOD'),
        envelopeCurrency: 'ILS',
      );

      final mix = find.byKey(const Key('payment-mix-card'));
      expect(mix, findsOneWidget);
      expect(
        find.descendant(of: mix, matching: find.textContaining('JOD 47.400')),
        findsWidgets,
      );
      expect(
        find.descendant(of: mix, matching: find.textContaining('₪')),
        findsNothing,
      );
    });

    testWidgets('A4. top items follow the window, not the top-items envelope', (
      tester,
    ) async {
      await _pump(
        tester,
        guard: const ReportCurrencyGuard.single('JOD'),
        envelopeCurrency: 'ILS',
        topItemsCurrency: 'ILS',
      );

      final card = find.byKey(const Key('top-items-list'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.textContaining('JOD 47.400')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('₪')),
        findsNothing,
      );
    });
  });

  // =========================================================================
  group('B. history is never relabelled with today\'s currency', () {
    testWidgets('B1. a historical ILS window stays ILS while the restaurant '
        'now operates in JOD', (tester) async {
      // The envelope carries the restaurant's CURRENT operating currency; the
      // window's money is the old one. The screen must say the window's.
      await _pump(
        tester,
        guard: const ReportCurrencyGuard.single('ILS'),
        envelopeCurrency: 'JOD',
        topItemsCurrency: 'JOD',
      );

      expect(_kpi(tester, 'kpi-cash-sales'), '₪474.00');
      expect(
        find.textContaining('JOD'),
        findsNothing,
        reason: 'the current operating currency must not reach an old window',
      );

      for (final key in const ['shift-cash-card', 'payment-mix-card']) {
        expect(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.textContaining('₪'),
          ),
          findsWidgets,
          reason: '$key must render the WINDOW currency',
        );
      }
    });

    testWidgets('B2. 47400 reads with TWO decimals under ILS and THREE under '
        'JOD — the same integer, and the label decides', (tester) async {
      await _pump(
        tester,
        guard: const ReportCurrencyGuard.single('ILS'),
        envelopeCurrency: 'ILS',
      );
      expect(_kpi(tester, 'kpi-cash-sales'), '₪474.00');
    });
  });

  // =========================================================================
  group('C. mixed and unavailable suppression is untouched', () {
    testWidgets('C1. a MIXED window renders no merged money, even with the '
        'envelope-driven cards populated', (tester) async {
      await _pump(tester, guard: _mixed, envelopeCurrency: 'ILS');

      for (final key in const [
        'kpi-gross-sales',
        'kpi-net-sales',
        'kpi-avg-ticket',
        'kpi-cash-sales',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      expect(find.byKey(const Key('shift-cash-card')), findsNothing);
      expect(find.byKey(const Key('payment-mix-card')), findsNothing);
      expect(find.byKey(const Key('reports-currency-split')), findsOneWidget);
      expect(find.byKey(const Key('currency-split-ILS')), findsOneWidget);
      expect(find.byKey(const Key('currency-split-JOD')), findsOneWidget);
    });

    testWidgets('C2. an UNAVAILABLE breakdown hides merged money rather than '
        'degrading to the envelope', (tester) async {
      await _pump(
        tester,
        guard: const ReportCurrencyGuard.unknown(),
        envelopeCurrency: 'ILS',
      );

      expect(find.byKey(const Key('kpi-gross-sales')), findsNothing);
      expect(find.byKey(const Key('shift-cash-card')), findsNothing);
      expect(find.byKey(const Key('payment-mix-card')), findsNothing);
      expect(
        find.byKey(const Key('reports-currency-unavailable')),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  group('D. the three locales', () {
    for (final locale in const ['ar', 'he', 'en']) {
      testWidgets('D1-$locale. a JOD window renders without overflow and with '
          'no stale ILS symbol', (tester) async {
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) =>
            errors.add(details.exceptionAsString());
        addTearDown(() => FlutterError.onError = previous);

        await _pump(
          tester,
          guard: const ReportCurrencyGuard.single('JOD'),
          envelopeCurrency: 'ILS',
          locale: Locale(locale),
        );
        expect(find.textContaining('₪'), findsNothing);
        expect(find.textContaining('JOD 47.400'), findsWidgets);

        FlutterError.onError = previous;
        expect(
          errors.where((e) => e.contains('overflowed')),
          isEmpty,
          reason: 'RTL/LTR must not overflow in $locale: $errors',
        );
      });
    }
  });
}

// ---------------------------------------------------------------------------

const _ils = CurrencyTotals(
  currencyCode: 'ILS',
  orderCount: 1,
  grossMinor: 1000,
  discountMinor: 0,
  netMinor: 1000,
  collectedMinor: 800,
  cashMinor: 800,
);
const _jod = CurrencyTotals(
  currencyCode: 'JOD',
  orderCount: 1,
  grossMinor: 700,
  discountMinor: 0,
  netMinor: 700,
  collectedMinor: 500,
  cashMinor: 0,
);
const _mixed = ReportCurrencyGuard.mixed([_ils, _jod]);

String _kpi(WidgetTester tester, String key) =>
    tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).value;

/// A report with the envelope-driven cards POPULATED — the whole point of this
/// suite. `cashSalesMinor` is the Phase-5 repro amount so the same integer can
/// be searched for under both exponents.
DashboardReport _report(String currency) => DashboardReport(
  currencyCode: currency,
  businessDateLabel: '2026-08-19',
  grossSalesMinor: 62600,
  netSalesMinor: 62000,
  discountTotalMinor: 600,
  collectedMinor: 50000,
  cashSalesMinor: kRepro,
  lastCashPaymentMinor: 1200,
  orderCount: 7,
  completedOrderCount: 6,
  openOrderCount: 1,
  unpaidOrderCount: 2,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 50000,
  expectedCashMinor: kRepro,
  countedCashMinor: kRepro,
  shiftStatus: 'closed',
  branches: const [],
  topItems: const [],
  recentOrders: const [],
  paymentMethods: [
    PaymentMethodLine(
      method: 'cash',
      count: 6,
      totalMinor: kRepro,
      currencyCode: currency,
    ),
  ],
  shiftCash: const ShiftCash(
    closedShiftCount: 1,
    openShiftCount: 0,
    expectedCashMinor: kRepro,
    countedCashMinor: kRepro,
    varianceMinor: 0,
  ),
  rangeStartLabel: '2026-08-19',
  rangeEndLabel: '2026-08-19',
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

/// Top items carrying their OWN envelope currency, so the test can prove the
/// card ignores it in favour of the window's.
class _TopItemsRepo implements OwnerTopItemsRepository {
  const _TopItemsRepo(this.currency);

  final String currency;

  @override
  Future<OwnerTopItems> loadTopItems({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    int limit = kOverviewTopItemsLimit,
  }) async => OwnerTopItems(
    currencyCode: currency,
    rangeWire: 'today',
    items: [
      TopItem(
        name: 'Shawarma',
        quantity: 1,
        lineRevenueMinor: kRepro,
        currencyCode: currency,
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required ReportCurrencyGuard guard,
  required String envelopeCurrency,
  String? topItemsCurrency,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 3000);
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
        ownerTopItemsRepositoryProvider.overrideWithValue(
          _TopItemsRepo(topItemsCurrency ?? envelopeCurrency),
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
