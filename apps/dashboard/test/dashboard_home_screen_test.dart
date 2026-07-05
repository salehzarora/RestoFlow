import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A live-LIMITED report like the sales_summary fallback produces (LIVE-UX-001):
/// KPIs + a safe "vs yesterday" comparison, but NO hourly / branch / top-item /
/// recent-order data (nothing fabricated).
class _LimitedRepo implements OwnerReportsRepository {
  const _LimitedRepo();
  @override
  Future<DashboardReport> loadReport() async => const DashboardReport(
    currencyCode: 'ILS',
    businessDateLabel: '2026-07-05',
    grossSalesMinor: 12000,
    netSalesMinor: 12000,
    discountTotalMinor: 0,
    collectedMinor: 12000,
    cashSalesMinor: 12000,
    lastCashPaymentMinor: 0,
    orderCount: 5,
    completedOrderCount: 3,
    openOrderCount: 2,
    unpaidOrderCount: 2,
    voidCount: 0,
    voidTotalMinor: 0,
    openingFloatMinor: 0,
    expectedCashMinor: 0,
    countedCashMinor: 0,
    shiftStatus: 'none',
    branches: [],
    topItems: [],
    recentOrders: [],
    paymentMethods: [],
    comparison: ReportComparison(
      grossSalesMinor: 8000,
      netSalesMinor: 8000,
      orderCount: 4,
      cashSalesMinor: 8000,
    ),
  );
}

Widget _wrapLimited() => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: false),
    ),
    ownerReportsRepositoryProvider.overrideWithValue(const _LimitedRepo()),
  ],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: DashboardHomeScreen(),
  ),
);

Widget _wrap() => const ProviderScope(
  child: MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: DashboardHomeScreen(),
  ),
);

/// Wraps the screen forcing REAL mode. The demo repository still supplies the
/// data, so what is under test is the mode-aware banner/pill (driven by
/// [runtimeConfigProvider]) — not the repository (RF-140).
Widget _wrapRealMode() => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: false),
    ),
    ownerReportsRepositoryProvider.overrideWithValue(
      const DemoOwnerReportsRepository(),
    ),
  ],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: DashboardHomeScreen(),
  ),
);

void _useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _kpi(WidgetTester tester, String key) =>
    tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).value;

void main() {
  testWidgets('renders the reports area: banner, day context, refresh', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Honest demo-data banner + reports heading + day context.
    expect(find.byKey(const Key('reports-demo-banner')), findsOneWidget);
    expect(
      find.text(
        'Demo reports — calculated locally from sample orders, not synced '
        'to a backend.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reports-heading')), findsOneWidget);
    expect(find.text('Owner reports'), findsOneWidget);
    expect(find.text('Report day: 2026-06-28'), findsOneWidget);
    expect(find.text('Demo day'), findsOneWidget);
    expect(find.byKey(const Key('reports-refresh-button')), findsOneWidget);
  });

  testWidgets('real mode shows the live·limited notice, not the demo banner', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrapRealMode());
    await tester.pumpAndSettle();

    // The caution real-mode banner replaces the demo banner, and the header pill
    // flips from "Demo day" to "Live · limited" (RF-140 honesty).
    expect(find.byKey(const Key('reports-realmode-banner')), findsOneWidget);
    expect(find.byKey(const Key('reports-demo-banner')), findsNothing);
    expect(
      find.text(
        "Live reports — read-only and limited. Some figures aren't "
        'available here yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('Live · limited'), findsOneWidget);
    expect(find.text('Demo day'), findsNothing);
  });

  testWidgets('KPI cards show the values computed from the demo dataset', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(_kpi(tester, 'kpi-gross-sales'), '₪626.00');
    expect(_kpi(tester, 'kpi-net-sales'), '₪620.00');
    expect(_kpi(tester, 'kpi-orders'), '7');
    expect(_kpi(tester, 'kpi-avg-ticket'), '₪88.57'); // 62000 ~/ 7 integer math
    expect(_kpi(tester, 'kpi-cash-sales'), '₪474.00');
    expect(_kpi(tester, 'kpi-completed'), '5');
    expect(_kpi(tester, 'kpi-unpaid'), '2');
  });

  testWidgets('payment & cash summary shows the expected drawer math', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-summary-card')), findsOneWidget);
    expect(find.text('Payment & cash summary'), findsOneWidget);
    expect(find.text('Expected in drawer'), findsOneWidget);
    expect(find.text('₪500.00'), findsWidgets); // opening float
    expect(find.text('₪974.00'), findsWidgets); // expected drawer (50000+47400)
    expect(find.text('₪972.50'), findsWidgets); // counted cash
    expect(find.text('-₪1.50'), findsWidgets); // variance 97250 - 97400
    expect(find.text('5 · ₪474.00'), findsOneWidget); // cash method breakdown
  });

  testWidgets('daily summary shows discounts and voids', (tester) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Daily summary'), findsOneWidget);
    expect(find.text('₪6.00'), findsWidgets); // discounts (62600 - 62000)
    expect(find.text('1 · ₪42.00'), findsOneWidget); // void count · void total
  });

  testWidgets('branch, top-item and recent-order sections render', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Branches render, in order, scoped to the sales-by-branch card.
    final branchCard = find.byKey(const Key('sales-by-branch-card'));
    expect(find.text('Sales by branch'), findsOneWidget);
    for (final name in const ['Downtown', 'Seaside', 'Airport']) {
      expect(
        find.descendant(of: branchCard, matching: find.text(name)),
        findsOneWidget,
      );
    }

    // Top items: #1 and #2 ranked, with quantities.
    expect(find.text('Top items'), findsOneWidget);
    expect(find.text('Margherita Pizza'), findsOneWidget);
    expect(find.text('#1 · ×4'), findsOneWidget);
    expect(find.text('Classic Burger'), findsOneWidget);
    expect(find.text('#2 · ×4'), findsOneWidget);

    // Recent orders: numbers, statuses and a dine-in table label.
    expect(find.text('Recent orders'), findsOneWidget);
    expect(find.text('O-1009'), findsOneWidget); // newest (cancelled)
    expect(find.text('O-1005'), findsOneWidget); // a paid order
    expect(find.text('cancelled'), findsWidgets); // O-1009 status pill
    expect(find.text('completed'), findsWidgets); // a completed order status
    expect(find.textContaining('Table T5'), findsWidgets); // dine-in table
  });

  testWidgets('refresh reloads the report (still renders after invalidate)', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reports-refresh-button')));
    await tester.pumpAndSettle();

    expect(_kpi(tester, 'kpi-net-sales'), '₪620.00');
  });

  testWidgets(
    'LIVE-UX-001: a live-LIMITED report reads as intentional — a pending-'
    'analytics note, honest KPI deltas, NO empty section cards, NO fake chart',
    (tester) async {
      _useWideSurface(tester);
      await tester.pumpWidget(_wrapLimited());
      await tester.pumpAndSettle();

      // The titled live banner + the calm "more analytics coming" note.
      expect(find.byKey(const Key('reports-realmode-banner')), findsOneWidget);
      expect(find.text('Live reports'), findsWidgets); // banner title
      expect(
        find.byKey(const Key('reports-limited-analytics')),
        findsOneWidget,
      );

      // Empty sections are HIDDEN (never bare titled cards) and NO fabricated
      // sales-by-hour chart is drawn.
      expect(find.byKey(const Key('sales-by-branch-card')), findsNothing);
      expect(find.byKey(const Key('top-items-card')), findsNothing);
      expect(find.byKey(const Key('recent-orders-card')), findsNothing);
      expect(find.byKey(const Key('sales-by-hour-card')), findsNothing);

      // The safe prior-day comparison lights up honest, integer-% KPI deltas
      // (today 12000 vs yesterday 8000 = +50%), so live no longer looks bare.
      expect(find.textContaining('50% vs yesterday'), findsWidgets);
      // Still real data only — the KPI values are the live figures, not demo.
      expect(_kpi(tester, 'kpi-net-sales'), '₪120.00');
    },
  );
}
