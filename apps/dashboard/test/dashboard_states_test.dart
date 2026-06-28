import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_report_source.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/report_calculator.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A repository whose [loadReport] resolves after a delay (to observe loading).
class _DelayedRepo implements OwnerReportsRepository {
  @override
  Future<DashboardReport> loadReport() => Future.delayed(
    const Duration(milliseconds: 50),
    () => computeOwnerReport(demoOwnerReportDataset()),
  );
}

Widget _wrap(OwnerReportsRepository repo) => ProviderScope(
  overrides: [ownerReportsRepositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: DashboardHomeScreen(),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shows a loading state while the report resolves', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(_DelayedRepo()));
    await tester.pump(); // first frame: future still pending

    expect(find.byKey(const Key('reports-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading reports…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80)); // resolve the future
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reports-loading')), findsNothing);
    expect(find.byKey(const Key('reports-heading')), findsOneWidget);
  });

  testWidgets('shows an error state with a retry action', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(const DemoOwnerReportsRepository(failureMessage: 'boom')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reports-error')), findsOneWidget);
    expect(find.text("Couldn't load reports."), findsOneWidget);
    expect(find.byKey(const Key('reports-retry-button')), findsOneWidget);
  });

  testWidgets('shows an empty state when there is no report data', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(DemoOwnerReportsRepository(dataset: emptyOwnerReportDataset())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reports-empty')), findsOneWidget);
    expect(find.text('No report data for this day.'), findsOneWidget);
    // The honest demo banner is still shown above the empty state.
    expect(find.byKey(const Key('reports-demo-banner')), findsOneWidget);
  });
}
