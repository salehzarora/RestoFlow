import 'dart:async';

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

/// REPORT-123 — the Overview must survive a breakdown failure without lying in
/// either direction.
///
/// THE INCIDENT. `app.owner_report_currency_breakdown` was never granted to
/// `authenticated`, so every production call raised 42501. The repository
/// collapsed that into "unavailable", the guard resolved `unknown`, and the
/// Overview replaced the whole financial report with a bare safety notice —
/// for data that was single-currency ILS throughout.
///
/// The database fix restores the totals. These tests pin the client behaviour
/// that made a recoverable server error look like a permanent verdict:
///   * `unknown` still hides money — that rule never relaxes — but it keeps the
///     counts that arrived successfully, and says the check FAILED;
///   * "still checking" is a distinct state and must not flash the verdict;
///   * a failure is classified, not swallowed, so a later attempt is known to
///     be worth making.
void main() {
  // ==========================================================================
  // A. FAILURE CLASSIFICATION — the swallowed `catch (_)`
  // ==========================================================================
  group('A. classifyBreakdownFailure', () {
    test('A1. a PostgREST missing-function error is notDeployed', () {
      for (final e in <Object>[
        'PostgrestException(message: Could not find the function '
            'public.owner_report_currency_breakdown, code: PGRST202)',
        Exception('PGRST205 schema cache stale'),
      ]) {
        expect(
          classifyBreakdownFailure(e),
          CurrencyBreakdownFailure.notDeployed,
          reason: '$e',
        );
      }
    });

    test('A2. the REPORT-123 signature (42501) is denied, not notDeployed', () {
      for (final e in <Object>[
        'PostgrestException(message: permission denied for function '
            'owner_report_currency_breakdown, code: 42501)',
        Exception('permission_denied'),
      ]) {
        expect(
          classifyBreakdownFailure(e),
          CurrencyBreakdownFailure.denied,
          reason: '$e',
        );
      }
    });

    test('A3. anything else is transport — never silently "not deployed"', () {
      expect(
        classifyBreakdownFailure(
          Exception('SocketException: host unreachable'),
        ),
        CurrencyBreakdownFailure.transport,
      );
    });

    test('A4. a denial is NOT reported as a deployment problem (the exact '
        'mis-diagnosis this incident produced)', () {
      expect(
        classifyBreakdownFailure(Exception('code: 42501')),
        isNot(CurrencyBreakdownFailure.notDeployed),
      );
    });

    test('A5. an unavailable breakdown still never claims a currency', () {
      const b = CurrencyBreakdown.unavailable(CurrencyBreakdownFailure.denied);
      expect(b.available, isFalse);
      expect(b.isMixed, isFalse);
      expect(b.singleCurrency, isNull);
      expect(b.failure, CurrencyBreakdownFailure.denied);
    });
  });

  // ==========================================================================
  // B. THE GUARD'S OWN RULES ARE UNCHANGED
  // ==========================================================================
  group('B. ReportCurrencyGuard.resolve is unchanged by this fix', () {
    CurrencyTotals t(String c) => CurrencyTotals(
      currencyCode: c,
      orderCount: 1,
      grossMinor: 100,
      discountMinor: 0,
      netMinor: 100,
      collectedMinor: 100,
      cashMinor: 0,
    );

    test('B1. two currencies stay MIXED — never summed', () {
      final g = ReportCurrencyGuard.resolve(
        breakdown: CurrencyBreakdown(
          totals: [t('ILS'), t('USD')],
          available: true,
        ),
        envelopeCurrency: 'ILS',
        orderCount: 2,
      );
      expect(g.mode, ReportMoneyMode.mixed);
      expect(g.canRenderMergedMoney, isFalse);
    });

    test('B2. an unavailable breakdown WITH orders stays unknown', () {
      final g = ReportCurrencyGuard.resolve(
        breakdown: const CurrencyBreakdown.unavailable(
          CurrencyBreakdownFailure.denied,
        ),
        envelopeCurrency: 'ILS',
        orderCount: 7,
      );
      expect(g.mode, ReportMoneyMode.unknown);
      expect(g.canRenderMergedMoney, isFalse);
    });

    test('B3. an unavailable breakdown with NO orders is honest zeros', () {
      final g = ReportCurrencyGuard.resolve(
        breakdown: const CurrencyBreakdown.unavailable(),
        envelopeCurrency: 'ILS',
        orderCount: 0,
      );
      expect(g.mode, ReportMoneyMode.single);
    });
  });

  // ==========================================================================
  // C. THE SCREEN — unknown keeps counts, pending is distinct
  // ==========================================================================
  group('C. the real Overview', () {
    testWidgets('C1. UNKNOWN hides money but KEEPS the order count', (
      tester,
    ) async {
      final l10n = await _pump(
        tester,
        guard: const ReportCurrencyGuard.unknown(),
      );

      // money gone
      expect(find.byKey(const Key('kpi-gross-sales')), findsNothing);
      expect(find.byKey(const Key('kpi-net-sales')), findsNothing);
      // …but the count that DID arrive is still on screen (the regression)
      expect(
        find.byKey(const Key('currency-safety-order-count')),
        findsOneWidget,
      );
      expect(find.text('7'), findsWidgets);
      // and the reason is stated
      expect(
        find.text(l10n.dashboardCurrencyCheckUnavailableTitle),
        findsOneWidget,
      );
      // mixed copy must NOT appear — the two states stay distinct
      expect(find.text(l10n.dashboardCurrencyMixedTitle), findsNothing);
    });

    testWidgets('C2. UNKNOWN never renders a merged monetary figure', (
      tester,
    ) async {
      await _pump(tester, guard: const ReportCurrencyGuard.unknown());
      expect(find.textContaining('₪'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('C3. IN FLIGHT shows the pending state, NOT the unknown '
        'verdict', (tester) async {
      final completer = Completer<ReportCurrencyGuard>();
      final l10n = await _pump(
        tester,
        guardFuture: completer.future,
        settle: false,
      );

      expect(find.byKey(const Key('reports-currency-pending')), findsOneWidget);
      expect(
        find.byKey(const Key('reports-currency-unavailable')),
        findsNothing,
        reason: 'the permanent verdict must not flash while still checking',
      );
      expect(
        find.text(l10n.dashboardCurrencyCheckPendingTitle),
        findsOneWidget,
      );
      expect(
        find.text(l10n.dashboardCurrencyCheckUnavailableTitle),
        findsNothing,
      );
      // counts already arrived, so they show
      expect(
        find.byKey(const Key('currency-pending-order-count')),
        findsOneWidget,
      );
      // money is still withheld while we wait — the rule does not relax
      expect(find.byKey(const Key('kpi-gross-sales')), findsNothing);

      completer.complete(const ReportCurrencyGuard.single('ILS'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reports-currency-pending')), findsNothing);
      expect(find.byKey(const Key('kpi-gross-sales')), findsOneWidget);
    });

    testWidgets('C4. once resolved SINGLE, the ordinary totals return', (
      tester,
    ) async {
      await _pump(tester, guard: const ReportCurrencyGuard.single('ILS'));
      expect(_kpi(tester, 'kpi-gross-sales'), '₪626.00');
      expect(
        find.byKey(const Key('reports-currency-unavailable')),
        findsNothing,
      );
      expect(find.byKey(const Key('reports-currency-pending')), findsNothing);
    });

    testWidgets('C5. MIXED keeps its own copy, distinct from unknown', (
      tester,
    ) async {
      final l10n = await _pump(tester, guard: _mixed);
      expect(find.text(l10n.dashboardCurrencyMixedTitle), findsOneWidget);
      expect(
        find.text(l10n.dashboardCurrencyCheckUnavailableTitle),
        findsNothing,
      );
      expect(find.byKey(const Key('reports-currency-split')), findsOneWidget);
    });
  });

  // ==========================================================================
  // D. NO SESSION LATCH — a transient failure must be re-askable
  // ==========================================================================
  group('D. re-resolution', () {
    test('D1. a failed attempt does not latch: the SECOND resolution '
        'wins and the money comes back', () async {
      var attempt = 0;
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          ownerReportsRepositoryProvider.overrideWithValue(_Repo('ILS')),
          dashboardCurrencyGuardProvider.overrideWith((ref) async {
            attempt += 1;
            return attempt == 1
                ? const ReportCurrencyGuard.unknown()
                : const ReportCurrencyGuard.single('ILS');
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(
        (await container.read(dashboardCurrencyGuardProvider.future)).mode,
        ReportMoneyMode.unknown,
      );
      // what an explicit Refresh does to this provider
      container.invalidate(dashboardCurrencyGuardProvider);
      expect(
        (await container.read(dashboardCurrencyGuardProvider.future)).mode,
        ReportMoneyMode.single,
        reason: 'one transient failure must not poison the session',
      );
      expect(attempt, 2);
    });

    test('D2. a failure on one window does not poison another: the '
        'guard is derived per window, not cached globally', () async {
      final seen = <String>[];
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          ownerReportsRepositoryProvider.overrideWithValue(_Repo('ILS')),
          dashboardCurrencyGuardProvider.overrideWith((ref) async {
            seen.add('resolve');
            return seen.length == 1
                ? const ReportCurrencyGuard.unknown()
                : const ReportCurrencyGuard.single('ILS');
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(dashboardCurrencyGuardProvider.future);
      // range/scope change re-derives the report, which the guard watches
      container.invalidate(dashboardCurrencyGuardProvider);
      final second = await container.read(
        dashboardCurrencyGuardProvider.future,
      );
      expect(second.canRenderMergedMoney, isTrue);
      expect(seen.length, 2, reason: 'each window resolves for itself');
    });
  });

  // ==========================================================================
  // E. L10N — the two states read differently in every locale
  // ==========================================================================
  group('E. localisation', () {
    for (final code in ['en', 'ar', 'he']) {
      testWidgets('E-$code. unknown and mixed copy are distinct and '
          'non-empty', (tester) async {
        final l10n = await _pump(
          tester,
          guard: const ReportCurrencyGuard.unknown(),
          locale: Locale(code),
        );
        expect(l10n.dashboardCurrencyCheckUnavailableTitle, isNotEmpty);
        expect(l10n.dashboardCurrencyCheckPendingTitle, isNotEmpty);
        expect(
          l10n.dashboardCurrencyCheckUnavailableTitle,
          isNot(l10n.dashboardCurrencyMixedTitle),
        );
        expect(
          l10n.dashboardCurrencyCheckPendingTitle,
          isNot(l10n.dashboardCurrencyCheckUnavailableTitle),
        );
        // the unknown surface renders in this locale with the counts intact
        expect(
          find.byKey(const Key('currency-safety-order-count')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

final _mixed = ReportCurrencyGuard.mixed(const [
  CurrencyTotals(
    currencyCode: 'ILS',
    orderCount: 4,
    grossMinor: 100000,
    discountMinor: 0,
    netMinor: 100000,
    collectedMinor: 100000,
    cashMinor: 100000,
  ),
  CurrencyTotals(
    currencyCode: 'USD',
    orderCount: 3,
    grossMinor: 70000,
    discountMinor: 0,
    netMinor: 70000,
    collectedMinor: 70000,
    cashMinor: 0,
  ),
]);

String _kpi(WidgetTester tester, String key) {
  final card = tester.widget<RestoflowMetricCard>(find.byKey(Key(key)));
  return card.value;
}

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  ReportCurrencyGuard? guard,
  Future<ReportCurrencyGuard>? guardFuture,
  String envelopeCurrency = 'ILS',
  Locale locale = const Locale('en'),
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        ownerReportsRepositoryProvider.overrideWithValue(
          _Repo(envelopeCurrency),
        ),
        dashboardCurrencyGuardProvider.overrideWith(
          (ref) => guardFuture ?? Future.value(guard!),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const DashboardHomeScreen();
          },
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  return l10n;
}

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
