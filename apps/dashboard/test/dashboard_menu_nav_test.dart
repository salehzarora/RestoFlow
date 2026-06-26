import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('navigating to Menu shows the demo-backed menu surface', (
    tester,
  ) async {
    final l10n = await en();
    await tester.pumpWidget(
      const ProviderScope(child: DashboardApp(demoMode: true)),
    );
    await tester.pumpAndSettle();

    // Starts on the overview; the menu surface is not built yet.
    expect(find.byType(MenuManagementScreen), findsNothing);

    await tester.tap(find.text(l10n.dashboardNavMenu));
    await tester.pumpAndSettle();

    expect(find.byType(MenuManagementScreen), findsOneWidget);
    expect(find.text(l10n.menuDemoBanner), findsOneWidget);
    // The demo menu loaded.
    expect(find.text('Hot Drinks'), findsOneWidget);
  });
}
