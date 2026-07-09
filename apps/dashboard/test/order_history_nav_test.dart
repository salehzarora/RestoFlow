import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDERS-HISTORY-001 — the Orders tab is wired into the dashboard nav and opens
/// the order-history surface (demo mode).
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
    'the dashboard nav exposes Orders and opens the history surface',
    (tester) async {
      final l10n = await _en();
      await _pump(tester);

      expect(find.text(l10n.dashboardNavOrders), findsWidgets);
      expect(find.byType(OrderHistoryScreen), findsNothing);

      await tester.tap(find.text(l10n.dashboardNavOrders).first);
      await tester.pumpAndSettle();

      expect(find.byType(OrderHistoryScreen), findsOneWidget);
      expect(find.text(l10n.ordersHistoryTitle), findsWidgets);
    },
  );
}
