import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// Startup-state coverage for the launch fix: the dashboard must never crash or
/// blank at boot — every configuration lands on an honest, visible screen.
void main() {
  testWidgets('real mode without config shows the help page, not a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: DashboardApp(demoMode: false, realModeUnconfigured: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
    expect(find.byType(DashboardShell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real mode without a context fetcher also fails closed to the '
      'help page', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: DashboardApp(demoMode: false)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
    expect(find.byType(DashboardShell), findsNothing);
  });

  testWidgets('demo mode still renders the demo shell', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: DashboardApp(demoMode: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DashboardShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RF-LIVE-002: an accidental production demo (misconfigured) '
      'fails closed to the blocked page — never the demo shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: DashboardApp(demoMode: true, demoModeMisconfigured: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
    expect(find.byKey(const Key('production-demo-blocked')), findsOneWidget);
    expect(find.byType(DashboardShell), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
