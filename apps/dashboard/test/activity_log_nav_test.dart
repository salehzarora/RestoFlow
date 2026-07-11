import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/activity/activity_log_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// AUDIT-LOG-DASHBOARD-001 — the Activity-log tab is wired into the dashboard nav
/// and opens the read-only timeline surface (demo mode).
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1300, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const ProviderScope(child: DashboardApp(demoMode: true)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'D54 the dashboard nav exposes Activity log and opens the timeline surface',
    (tester) async {
      final l10n = await _en();
      await _pump(tester);

      expect(find.text(l10n.dashboardNavActivity), findsWidgets);
      expect(find.byType(ActivityLogScreen), findsNothing);

      await tester.tap(find.text(l10n.dashboardNavActivity).first);
      await tester.pumpAndSettle();

      expect(find.byType(ActivityLogScreen), findsOneWidget);
      expect(find.text(l10n.activityLogTitle), findsWidgets);
    },
  );
}
