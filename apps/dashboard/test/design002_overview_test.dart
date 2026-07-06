import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/owner_report_source.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DESIGN-002 Overview v2:
///  * KPI cards carry a trend delta vs the prior period (demo data);
///  * a sales-by-hour chart card renders from the demo hourly series;
///  * both are DATA-GATED: a report with no prior-period / hourly data (the
///    real-data shape) shows neither, so real mode never fabricates them;
///  * the header is the consolidated RestoflowPageHeader (keys/strings intact).
Widget _wrap({List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: DashboardHomeScreen(),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A report shaped like REAL data: real orders, but no demo hourly series and
/// no prior-period comparison — so the chart + deltas must not render.
OwnerReportDataset _noExtrasDataset() => const OwnerReportDataset(
  currencyCode: 'ILS',
  businessDateLabel: '2026-06-29',
  shift: ReportShift(openingFloatMinor: 0, countedCashMinor: 0, status: 'open'),
  orders: [
    ReportOrder(
      orderNumber: 'X-1',
      branchName: 'Branch',
      isDineIn: true,
      status: ReportOrderStatus.completed,
      placedAtLabel: '10:00',
      lines: [
        ReportOrderLine(itemName: 'Item', quantity: 1, unitPriceMinor: 1000),
      ],
      payment: ReportPayment(
        amountMinor: 1000,
        tenderedMinor: 1000,
        paidAtLabel: '10:00',
      ),
    ),
  ],
);

void main() {
  testWidgets('demo Overview shows KPI deltas and the sales-by-hour chart', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The consolidated header still carries the pinned key + title.
    expect(find.byKey(const Key('reports-heading')), findsOneWidget);
    expect(find.text('Owner reports'), findsOneWidget);
    expect(find.byKey(const Key('reports-refresh-button')), findsOneWidget);

    // The sales-by-hour chart card + the chart.
    expect(find.byKey(const Key('sales-by-hour-card')), findsOneWidget);
    expect(find.byType(RestoflowBarChart), findsOneWidget);

    // Trend deltas: the four money/count KPIs + the "1c" hero net-sales delta —
    // all up in the demo data.
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(5));
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
    expect(find.textContaining('vs yesterday'), findsWidgets);
  });

  testWidgets('a report with no hourly/prior data hides the chart and deltas '
      '(real-data shape stays honest)', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(
        overrides: [
          ownerReportsRepositoryProvider.overrideWithValue(
            DemoOwnerReportsRepository(dataset: _noExtrasDataset()),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Real orders render (not the empty state) ...
    expect(find.byKey(const Key('reports-heading')), findsOneWidget);
    // ... but nothing is fabricated: no chart, no deltas.
    expect(find.byKey(const Key('sales-by-hour-card')), findsNothing);
    expect(find.byType(RestoflowBarChart), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
  });
}
