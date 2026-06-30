import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_admin/src/widgets/platform_widgets.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Widget _wrap() => const ProviderScope(
  child: MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: PlatformAdminScreen(),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _kpi(WidgetTester tester, String key) =>
    tester.widget<PlatformMetricCard>(find.byKey(Key(key))).value;

void main() {
  testWidgets('renders the overview: banner, title, as-of, refresh', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-demo-banner')), findsOneWidget);
    expect(
      find.text(
        'Demo platform data — computed locally on this device, not synced '
        'to a backend.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('platform-overview-title')), findsOneWidget);
    expect(find.text('Platform overview'), findsOneWidget);
    expect(find.text('As of 2026-06-28'), findsOneWidget);
    expect(find.text('Demo data'), findsOneWidget); // the demo-day pill
    expect(find.byKey(const Key('platform-refresh-button')), findsOneWidget);
  });

  testWidgets('KPI cards show the values computed from the demo dataset', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(_kpi(tester, 'kpi-organizations'), '3');
    expect(_kpi(tester, 'kpi-restaurants'), '4');
    expect(_kpi(tester, 'kpi-branches'), '6');
    expect(_kpi(tester, 'kpi-active-branches'), '5');
    expect(_kpi(tester, 'kpi-devices'), '10');
    expect(_kpi(tester, 'kpi-alerts'), '2');
    expect(_kpi(tester, 'kpi-orders-today'), '215');
  });

  testWidgets('organizations, branch-health and activity sections render', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Organizations card lists all three orgs, in order, scoped to the card.
    final orgCard = find.byKey(const Key('organizations-card'));
    for (final name in const ['Bistro Group', 'Cafe Noor', 'Pizza Plaza']) {
      expect(
        find.descendant(of: orgCard, matching: find.text(name)),
        findsOneWidget,
      );
    }
    // The suspended org shows a suspended status pill (only one in the dataset).
    expect(find.text('suspended'), findsOneWidget);

    // Branch health: branch names + exactly two "Needs attention" chips.
    final branchCard = find.byKey(const Key('branch-health-card'));
    expect(
      find.descendant(of: branchCard, matching: find.text('Downtown Main')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: branchCard, matching: find.text('Noor Airport')),
      findsOneWidget,
    );
    expect(find.text('Needs attention'), findsNWidgets(2));

    // Recent activity: a warning event and an org-created event.
    final activityCard = find.byKey(const Key('recent-activity-card'));
    expect(
      find.descendant(of: activityCard, matching: find.text('sync_warning')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: activityCard,
        matching: find.text('Pizza Plaza · Plaza HQ device offline'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('refresh reloads the overview (still renders after invalidate)', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('platform-refresh-button')));
    await tester.pumpAndSettle();

    // The whole overview recomputes (not just one card).
    expect(_kpi(tester, 'kpi-organizations'), '3');
    expect(_kpi(tester, 'kpi-branches'), '6');
    expect(_kpi(tester, 'kpi-devices'), '10');
  });
}
