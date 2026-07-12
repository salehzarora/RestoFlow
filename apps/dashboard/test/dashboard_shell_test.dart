import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/state/locale_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-125 — the dashboard shell chrome: responsive rail modes at the existing
/// breakpoints (560 / 720 / 1100), reading-start rail placement in LTR/RTL,
/// preserved navigation order, and accessible (semantic + labelled) rail tiles.
/// Presentation-only: it drives the SAME demo shell the nav tests use.

const _railKey = Key('dashboard-side-rail');
const _bottomNavKey = Key('dashboard-bottom-nav');

Future<AppLocalizations> _l10n(Locale locale) =>
    AppLocalizations.delegate.load(locale);

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [initialLocaleProvider.overrideWithValue(locale)],
      child: const DashboardApp(demoMode: true),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _railLabel(String label) =>
    find.descendant(of: find.byKey(_railKey), matching: find.text(label));

void main() {
  testWidgets('desktop width (1320) shows the full labelled side rail', (
    tester,
  ) async {
    final l10n = await _l10n(const Locale('en'));
    await _pump(tester, size: const Size(1320, 1200));

    expect(find.byKey(_railKey), findsOneWidget);
    expect(find.byKey(_bottomNavKey), findsNothing);
    // Labels are visible in the rail (full / labelled mode).
    expect(_railLabel(l10n.dashboardNavOverview), findsOneWidget);
    expect(_railLabel(l10n.dashboardNavSettings), findsOneWidget);
  });

  testWidgets('tablet width (940) shows the labelled side rail', (
    tester,
  ) async {
    final l10n = await _l10n(const Locale('en'));
    await _pump(tester, size: const Size(940, 1200));

    expect(find.byKey(_railKey), findsOneWidget);
    expect(find.byKey(_bottomNavKey), findsNothing);
    expect(_railLabel(l10n.dashboardNavOverview), findsOneWidget);
  });

  testWidgets('compact-tablet width (700) shows the icon-only rail', (
    tester,
  ) async {
    final l10n = await _l10n(const Locale('en'));
    await _pump(tester, size: const Size(700, 1200));

    expect(find.byKey(_railKey), findsOneWidget);
    expect(find.byKey(_bottomNavKey), findsNothing);
    // Icon-only: no visible label text in the rail...
    expect(_railLabel(l10n.dashboardNavOverview), findsNothing);
    // ...but the destination name is still reachable via the tooltip.
    expect(find.byTooltip(l10n.dashboardNavOverview), findsOneWidget);
  });

  testWidgets('phone width (390) shows the bottom navigation bar', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 1600));

    expect(find.byKey(_bottomNavKey), findsOneWidget);
    expect(find.byKey(_railKey), findsNothing);
  });

  testWidgets('English (LTR) places the rail on the reading-start (left)', (
    tester,
  ) async {
    const width = 1320.0;
    await _pump(
      tester,
      size: const Size(width, 1200),
      locale: const Locale('en'),
    );
    final railLeft = tester.getTopLeft(find.byKey(_railKey)).dx;
    expect(railLeft, lessThan(width / 2));
  });

  testWidgets('Arabic (RTL) places the rail on the reading-start (right)', (
    tester,
  ) async {
    const width = 1320.0;
    await _pump(
      tester,
      size: const Size(width, 1200),
      locale: const Locale('ar'),
    );
    final railLeft = tester.getTopLeft(find.byKey(_railKey)).dx;
    expect(railLeft, greaterThan(width / 2));
  });

  testWidgets('Hebrew (RTL) places the rail on the reading-start (right)', (
    tester,
  ) async {
    const width = 1320.0;
    await _pump(
      tester,
      size: const Size(width, 1200),
      locale: const Locale('he'),
    );
    final railLeft = tester.getTopLeft(find.byKey(_railKey)).dx;
    expect(railLeft, greaterThan(width / 2));
  });

  testWidgets('navigation keeps its order and switches to the right surface', (
    tester,
  ) async {
    final l10n = await _l10n(const Locale('en'));
    await _pump(tester, size: const Size(1320, 1600));

    // Orders (index 7) opens the Orders area, landing on the ACTIVE-ORDERS
    // operations centre (ACTIVE-ORDERS-001); the History view is one tab away
    // in the SAME destination (no duplicate nav entry).
    await tester.tap(_railLabel(l10n.dashboardNavOrders));
    await tester.pumpAndSettle();
    expect(find.text(l10n.ordersActiveTitle), findsWidgets);

    await tester.tap(find.byKey(const Key('orders-tab-history')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.ordersHistoryTitle), findsWidgets);

    // Activity (index 8) opens the activity-log surface.
    await tester.tap(_railLabel(l10n.dashboardNavActivity));
    await tester.pumpAndSettle();
    expect(find.text(l10n.activityLogTitle), findsWidgets);
  });

  testWidgets('rail tiles expose a semantic selected state and labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final l10n = await _l10n(const Locale('en'));
    // Compact (icon-only) rail: the label must come from semantics, not text.
    await _pump(tester, size: const Size(700, 1200));

    // The selected destination (Overview, index 0) is a selected button.
    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.dashboardNavOverview)),
      isSemantics(isSelected: true, isButton: true),
    );
    // A non-selected destination is a button that is not selected — and it
    // still carries its label even though the tile is icon-only.
    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.dashboardNavStaff)),
      isSemantics(isButton: true, isSelected: false),
    );

    handle.dispose();
  });
}
