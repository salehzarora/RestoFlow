import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-OWNER-ANALYTICS-F0.4 — KPI drill-down wiring.
///
/// The seam and its filter semantics were proven in F0.3/F0.7. What is new here
/// is that a real KPI on the real Overview actually invokes it: an owner taps
/// "Unpaid" and lands on the unpaid list, not on whatever Orders last showed.
///
/// These tests mount the REAL DashboardHomeScreen in demo mode, so the KPI
/// values come from the app's own demo report rather than a fixture invented
/// here.
Future<void> pumpOverview(
  WidgetTester tester, {
  void Function(DashboardDestination)? onNavigate,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        theme: restoflowBaseTheme(),
        home: DashboardHomeScreen(onNavigate: onNavigate),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the unpaid KPI is tappable and lands on Orders with ONLY the '
      'unpaid filter applied', (tester) async {
    final destinations = <DashboardDestination>[];
    await pumpOverview(tester, onNavigate: destinations.add);

    final card = find.byKey(const Key('kpi-unpaid'));
    expect(card, findsOneWidget);
    expect(
      tester.widget<RestoflowMetricCard>(card).onTap,
      isNotNull,
      reason: 'the KPI must be interactive when a navigation seam exists',
    );

    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(destinations, [DashboardDestination.orders]);

    final element = tester.element(find.byType(DashboardHomeScreen));
    final container = ProviderScope.containerOf(element);
    expect(container.read(ordersInitialTabProvider), OrdersTab.history);
    final query = container.read(orderHistoryQueryProvider);
    expect(query.payment, PaymentFilter.unpaid);
    // The drill-down owns payment only; everything else is at its default, so
    // the list cannot silently contradict the number that opened it.
    expect(query.status, OrderStatusFilter.all);
    expect(query.orderType, OrderTypeFilter.all);
    expect(query.search, '');
  });

  testWidgets('the cash KPI drills to the cash-tender list', (tester) async {
    final destinations = <DashboardDestination>[];
    await pumpOverview(tester, onNavigate: destinations.add);

    final card = find.byKey(const Key('kpi-cash-sales'));
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(destinations, [DashboardDestination.orders]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardHomeScreen)),
    );
    expect(
      container.read(orderHistoryQueryProvider).payment,
      PaymentFilter.cash,
    );
    expect(container.read(ordersInitialTabProvider), OrdersTab.history);
  });

  testWidgets('WITHOUT a navigation seam every KPI stays display-only — no '
      'dead affordance is offered', (tester) async {
    await pumpOverview(tester);

    for (final key in ['kpi-unpaid', 'kpi-cash-sales']) {
      final card = find.byKey(Key(key));
      expect(card, findsOneWidget);
      expect(
        tester.widget<RestoflowMetricCard>(card).onTap,
        isNull,
        reason: '$key must not look tappable when there is nowhere to go',
      );
    }
  });

  testWidgets('a NON-drill-down KPI is not made tappable by this change', (
    tester,
  ) async {
    await pumpOverview(tester, onNavigate: (_) {});
    // Gross sales has no honest single destination — the history list cannot
    // express "the orders behind this money total" — so it stays display-only.
    // This pins that we wired specific questions, not every card reflexively.
    final gross = find.byKey(const Key('kpi-gross-sales'));
    expect(gross, findsOneWidget);
    expect(tester.widget<RestoflowMetricCard>(gross).onTap, isNull);
  });

  testWidgets('tapping a KPI does not disturb the OTHER surface providers', (
    tester,
  ) async {
    await pumpOverview(tester, onNavigate: (_) {});
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardHomeScreen)),
    );
    final tabBefore = container.read(ordersInitialTabProvider);
    expect(tabBefore, OrdersTab.active);

    await tester.tap(find.byKey(const Key('kpi-unpaid')));
    await tester.pumpAndSettle();

    // Orders moved (that is the point); nothing else should have.
    expect(container.read(ordersInitialTabProvider), OrdersTab.history);
  });
}
