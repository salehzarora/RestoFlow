import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart'
    show CustomAnalyticsWindow;
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/overview/overview_visuals.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/widgets/section_card.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-DASHBOARD-VERIFICATION — the known,
/// separate defect DASHBOARD-COLLECTED-LABEL-001, RECORDED and NOT fixed.
///
/// Two pre-existing defects sit beside the card surfaces 001G verifies:
///   * the all-tender collected total is labelled "Cash collected" (the
///     Overview Daily summary row and each mixed-currency split card), so a
///     card, Bit or external amount reads under a cash label;
///   * the latent `sales_summary` fallback of `RealOwnerReportsRepository`
///     reports the all-tender gross as cash sales (today and "vs yesterday").
///
/// Every test below states the CORRECT behaviour, so none of them treats the
/// defect as correct. They are skipped by default — the defect is owned by
/// its own Work ID, and 001G changes no production file — and they are
/// expected to FAIL when run with
/// `--dart-define=ZCREDIT_001G_KNOWN_DEFECTS=true` until
/// DASHBOARD-COLLECTED-LABEL-001 ships. That Work ID removes the skip gate when
/// it ships, so K1-K4 then run by default (if it chooses to refuse the
/// fallback, it pins K3's refusal branch to that refusal), or it replaces
/// these checks with its own focused tests carrying the same assertions. The
/// LIVE gate stays: deploy that Work ID, or record the owner's explicit
/// acceptance of the mislabel and of the fallback (DEPLOYMENT §18.1 step 9;
/// D-057 point 8, D-058 point 4).
const _runKnownDefects = bool.fromEnvironment('ZCREDIT_001G_KNOWN_DEFECTS');

const _locales = ['en', 'ar', 'he'];

/// The wording the defect ships today, pinned as literals so these tests keep
/// compiling if the fix renames or removes the l10n key.
const _defectiveLabel = {
  'en': 'Cash collected',
  'ar': 'النقد المُحصَّل',
  'he': 'מזומן שנאסף',
};

/// A cash-specific stem per locale. A tender-neutral label ("Total collected"
/// or its equivalent) carries none of them.
const _cashStem = {'en': 'cash', 'ar': 'نقد', 'he': 'מזומן'};

void _expectTenderNeutral(String code, String label) {
  expect(
    label,
    isNot(_defectiveLabel[code]),
    reason: 'an all-tender total must not carry the cash-only label',
  );
  expect(
    label.toLowerCase().contains(_cashStem[code]!),
    isFalse,
    reason:
        '"$label" names cash for a total that includes card, Bit and external',
  );
}

class _FixedRepository implements OwnerReportsRepository {
  _FixedRepository(this.report);

  final DashboardReport report;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async => report;
}

/// A window with cash 12000 and card 8000: collected (all tenders) 20000, cash
/// sales 12000. Net deliberately differs from collected so the collected value
/// is unique inside the Daily summary card.
DashboardReport _cardAndCashReport() => const DashboardReport(
  currencyCode: 'ILS',
  businessDateLabel: '2026-10-31',
  grossSalesMinor: 24000,
  netSalesMinor: 22500,
  discountTotalMinor: 1500,
  collectedMinor: 20000,
  cashSalesMinor: 12000,
  lastCashPaymentMinor: 3000,
  orderCount: 6,
  completedOrderCount: 5,
  openOrderCount: 1,
  unpaidOrderCount: 1,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 0,
  expectedCashMinor: 0,
  countedCashMinor: 0,
  shiftStatus: 'none',
  branches: [],
  topItems: [],
  recentOrders: [],
  paymentMethods: [
    PaymentMethodLine(
      method: 'cash',
      count: 3,
      totalMinor: 12000,
      currencyCode: 'ILS',
    ),
    PaymentMethodLine(
      method: 'card',
      count: 2,
      totalMinor: 8000,
      currencyCode: 'ILS',
    ),
  ],
);

/// Per-currency totals whose collected figure includes a card amount: ILS
/// collected 800 of which cash 300, USD collected 500 of which cash 0.
const _ils = CurrencyTotals(
  currencyCode: 'ILS',
  orderCount: 2,
  grossMinor: 1000,
  discountMinor: 0,
  netMinor: 1000,
  collectedMinor: 800,
  cashMinor: 300,
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

/// owner_report_range and owner_daily_report both missing (PGRST202), so the
/// repository takes the `sales_summary` fallback. The summary's gross is the
/// sum of completed payments of EVERY method — here it includes card.
class _FallbackTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'owner_report_range' || function == 'owner_daily_report') {
      throw SyncTransportException(
        SyncTransportErrorKind.server,
        code: 'PGRST202',
        message: 'Could not find the function public.$function',
      );
    }
    if (function == 'sales_summary') {
      return <String, dynamic>{
        'ok': true,
        'entity': 'sales_summary',
        'currency_code': 'ILS',
        'today': <String, dynamic>{
          'orders_count': 0,
          'payments_count': 0,
          'gross_minor': 12000,
        },
        'last_7_days': <Map<String, dynamic>>[
          {'day': '2026-10-30', 'orders_count': 4, 'gross_minor': 8000},
          {'day': '2026-10-31', 'orders_count': 0, 'gross_minor': 12000},
        ],
      };
    }
    throw StateError('unexpected RPC $function');
  }
}

RealOwnerReportsRepository _fallbackRepository() => RealOwnerReportsRepository(
  null,
  scope: const MembershipContext(
    id: 'm1',
    organizationId: 'org-1',
    organizationName: 'Org 1',
    restaurantId: 'rest-1',
    restaurantName: 'Rest 1',
    branchId: 'branch-1',
    branchName: 'Branch 1',
    role: MembershipRole.orgOwner,
    status: 'active',
  ),
  transport: _FallbackTransport(),
);

/// The fallback's report, or null when the repository refuses the fallback
/// with its declared failure type: a refusal states nothing about cash, which
/// is also correct. Any other error (the fake's StateError on an unexpected
/// RPC, an unwired repository) still fails the test.
Future<DashboardReport?> _loadFallbackOrRefusal() async {
  try {
    return await _fallbackRepository().loadReport();
  } on OwnerReportsException {
    return null;
  }
}

Future<void> _pumpOverview(
  WidgetTester tester, {
  required OwnerReportsRepository repository,
  required ReportCurrencyGuard guard,
  required String code,
}) async {
  tester.view.physicalSize = const Size(1400, 3400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        ownerReportsRepositoryProvider.overrideWithValue(repository),
        dashboardCurrencyGuardProvider.overrideWith((ref) async => guard),
      ],
      child: MaterialApp(
        locale: Locale(code),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        theme: restoflowBaseTheme(),
        home: const DashboardHomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('K. DASHBOARD-COLLECTED-LABEL-001 — the correct behaviour, skipped '
      'until that Work ID ships', () {
    for (final code in _locales) {
      testWidgets('K1 $code: the Daily summary does not label the all-tender '
          'collected total as cash', (tester) async {
        await _pumpOverview(
          tester,
          repository: _FixedRepository(_cardAndCashReport()),
          guard: const ReportCurrencyGuard.single('ILS'),
          code: code,
        );
        // ₪200.00 is cash 12000 + card 8000: the only all-tender figure there.
        final value = find.descendant(
          of: find.byKey(const Key('daily-summary-card')),
          matching: find.text('₪200.00'),
        );
        expect(value, findsOneWidget);
        final row = tester.widget<OverviewValueRow>(
          find.ancestor(of: value, matching: find.byType(OverviewValueRow)),
        );
        _expectTenderNeutral(code, (row.label as Text).data!);
      }, skip: !_runKnownDefects);

      testWidgets('K2 $code: a mixed-currency split card does not label its '
          'all-tender collected total as cash', (tester) async {
        await _pumpOverview(
          tester,
          repository: _FixedRepository(_cardAndCashReport()),
          guard: const ReportCurrencyGuard.mixed([_ils, _usd]),
          code: code,
        );
        for (final ccy in const ['ILS', 'USD']) {
          final row = find.byKey(Key('currency-split-collected-$ccy'));
          expect(row, findsOneWidget);
          _expectTenderNeutral(code, tester.widget<SectionRow>(row).label);
        }
      }, skip: !_runKnownDefects);
    }

    test(
      'K3a: the sales_summary fallback does not report the all-tender gross '
      'as today\'s cash sales',
      () async {
        final report = await _loadFallbackOrRefusal();
        if (report == null) return;
        expect(
          report.cashSalesMinor,
          isNot(12000),
          reason: 'sales_summary gross includes card, Bit and external',
        );
      },
      skip: _runKnownDefects
          ? null
          : 'DASHBOARD-COLLECTED-LABEL-001 (known defect, recorded by 001G)',
    );

    test(
      'K3b: the sales_summary fallback does not report yesterday\'s '
      'all-tender gross as "vs yesterday" cash sales',
      () async {
        // A null comparison states no prior cash figure, which is correct too;
        // a comparison that is present must not carry yesterday's gross.
        final comparison = (await _loadFallbackOrRefusal())?.comparison;
        if (comparison == null) return;
        expect(
          comparison.cashSalesMinor,
          isNot(8000),
          reason: 'yesterday\'s sales_summary gross includes every tender',
        );
      },
      skip: _runKnownDefects
          ? null
          : 'DASHBOARD-COLLECTED-LABEL-001 (known defect, recorded by 001G)',
    );

    testWidgets('K4: on the fallback the Cash sales KPI does not show the '
        'all-tender gross', (tester) async {
      await _pumpOverview(
        tester,
        repository: _fallbackRepository(),
        guard: const ReportCurrencyGuard.single('ILS'),
        code: 'en',
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final kpi = find.byKey(const Key('kpi-cash-sales'));
      if (kpi.evaluate().isNotEmpty) {
        expect(tester.widget<RestoflowMetricCard>(kpi).value, isNot('₪120.00'));
      } else {
        // Hiding the KPI or refusing the fallback (an error state) is
        // acceptable; an unexplained absence is not.
        expect(
          find.byKey(const Key('kpi-gross-sales')).evaluate().isNotEmpty ||
              find.byKey(const Key('reports-error')).evaluate().isNotEmpty,
          isTrue,
          reason: 'the Cash sales KPI is absent for an unexplained reason',
        );
      }
      // Key-independent: a renamed KPI cannot pass silently.
      for (final card in tester.widgetList<RestoflowMetricCard>(
        find.byType(RestoflowMetricCard),
      )) {
        if (card.label.toLowerCase().contains(_cashStem['en']!)) {
          expect(card.value, isNot('₪120.00'), reason: card.label);
        }
      }
      // The payment summary's "Cash sales" row reads the same figure.
      final cashRow = find.descendant(
        of: find.byKey(const Key('payment-summary-card')),
        matching: find.text(l10n.dashboardCashSales),
      );
      for (final row in tester.widgetList<OverviewValueRow>(
        find.ancestor(of: cashRow, matching: find.byType(OverviewValueRow)),
      )) {
        expect((row.value as Text).data, isNot('₪120.00'));
      }
    }, skip: !_runKnownDefects);
  });
}
