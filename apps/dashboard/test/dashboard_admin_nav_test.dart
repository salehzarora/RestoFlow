import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> pumpDashboard(WidgetTester tester) async {
  // A tall, wide surface so the side rail + the admin lists are fully laid out.
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
  testWidgets('the dashboard nav exposes Settings, Users, and Devices', (
    tester,
  ) async {
    final l10n = await en();
    await pumpDashboard(tester);
    // All three new destinations are visible in the navigation.
    expect(find.text(l10n.dashboardNavSettings), findsWidgets);
    expect(find.text(l10n.dashboardNavUsers), findsWidgets);
    expect(find.text(l10n.dashboardNavDevices), findsWidgets);
  });

  testWidgets('navigating to Settings shows the settings surface', (
    tester,
  ) async {
    final l10n = await en();
    await pumpDashboard(tester);
    expect(find.byType(AdminSettingsScreen), findsNothing);
    await tester.tap(find.text(l10n.dashboardNavSettings).first);
    await tester.pumpAndSettle();
    expect(find.byType(AdminSettingsScreen), findsOneWidget);
    expect(find.text(l10n.adminDemoBanner), findsOneWidget);
    expect(find.text(l10n.adminSectionOrg), findsOneWidget);
  });

  testWidgets('navigating to Users shows the users surface', (tester) async {
    final l10n = await en();
    await pumpDashboard(tester);
    await tester.tap(find.text(l10n.dashboardNavUsers).first);
    await tester.pumpAndSettle();
    expect(find.byType(AdminUsersScreen), findsOneWidget);
    expect(find.text('Dana Reyes'), findsOneWidget); // seeded member
  });

  testWidgets('navigating to Devices shows the devices surface', (
    tester,
  ) async {
    final l10n = await en();
    await pumpDashboard(tester);
    await tester.tap(find.text(l10n.dashboardNavDevices).first);
    await tester.pumpAndSettle();
    expect(find.byType(AdminDevicesScreen), findsOneWidget);
    expect(find.text('Front Counter POS'), findsOneWidget); // seeded device
  });
}
