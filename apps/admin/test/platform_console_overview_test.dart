/// ADMIN-125C.2 — the platform console OVERVIEW page.
///
/// Proves every metric comes from `platform_admin_console_overview`, that the
/// suspended count is named for what it IS, that the four subscription zeros are
/// explained rather than left to look like an outage, and that the metrics the
/// platform cannot measure are ABSENT rather than fabricated as `0`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'console_test_harness.dart';

String _metric(WidgetTester tester, String key) =>
    tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).value;

void main() {
  testWidgets('shows every platform metric, derived from the dataset', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    // Five organizations (four active, one suspended), six restaurants, eight
    // branches, twenty-three active memberships — all hand-verifiable against
    // demoPlatformDataset().
    expect(_metric(tester, 'kpi-organizations'), '5');
    expect(_metric(tester, 'kpi-suspended-organizations'), '1');
    expect(_metric(tester, 'kpi-restaurants'), '6');
    expect(_metric(tester, 'kpi-branches'), '8');
    expect(_metric(tester, 'kpi-active-memberships'), '23');
    expect(find.text('Active: 4'), findsOneWidget);
  });

  testWidgets('shows each subscription state', (tester) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    expect(_metric(tester, 'kpi-subscriptions-trialing'), '1');
    expect(_metric(tester, 'kpi-subscriptions-active'), '1');
    expect(_metric(tester, 'kpi-subscriptions-past-due'), '1');
    expect(_metric(tester, 'kpi-subscriptions-canceled'), '1');
    // One tenant has NO subscription, so the four states do not sum to five.
    expect(find.byKey(const Key('no-subscriptions-notice')), findsNothing);
  });

  testWidgets('the suspended count is labelled Suspended organizations, NOT '
      'alerts', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminKpiSuspendedOrganizations), findsOneWidget);
    // The pre-125C.2 console showed this same number as "Open alerts", which
    // invites an operator to hunt for an incident that does not exist.
    expect(find.text(l10n.adminKpiAlerts), findsNothing);
  });

  testWidgets('metrics the platform cannot measure are ABSENT, not zero', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    for (final key in const [
      'kpi-devices',
      'kpi-orders-today',
      'kpi-active-branches',
      'kpi-alerts',
      'branch-health-card',
    ]) {
      expect(
        find.byKey(Key(key)),
        findsNothing,
        reason: '$key is not measured',
      );
    }
    for (final label in [
      l10n.adminKpiDevices,
      l10n.adminKpiOrdersToday,
      l10n.adminKpiActiveBranches,
      l10n.adminBranchHealthHeading,
    ]) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('zero subscriptions everywhere gets an honest explanation', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    // The shape production is actually in: tenants exist, no plan assigned.
    await tester.pumpWidget(
      consoleApp(
        repo: RecordingConsoleRepository(
          dataset: unsubscribedPlatformDataset(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-subscriptions-notice')), findsOneWidget);
    expect(find.text(l10n.adminNoSubscriptionsConfiguredTitle), findsOneWidget);
    expect(find.text(l10n.adminNoSubscriptionsConfiguredBody), findsOneWidget);
    // The counts are still shown — the notice explains them, it does not hide
    // them.
    expect(_metric(tester, 'kpi-subscriptions-active'), '0');
    expect(_metric(tester, 'kpi-subscriptions-trialing'), '0');
    // And the tenants themselves are still counted honestly.
    expect(_metric(tester, 'kpi-organizations'), '5');
  });

  testWidgets('the suspended card is only toned when something IS suspended', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RestoflowMetricCard>(
            find.byKey(const Key('kpi-suspended-organizations')),
          )
          .tone,
      RestoflowTone.danger,
    );

    // With nothing suspended the card must not sit permanently red — a constant
    // alarm is one the operator learns to ignore.
    await tester.pumpWidget(
      consoleApp(
        repo: RecordingConsoleRepository(
          dataset: PlatformDataset(
            serverDateLabel: '2026-06-28',
            organizations: demoPlatformDataset().organizations
                .where((o) => o.status == 'active')
                .toList(),
            auditEvents: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_metric(tester, 'kpi-suspended-organizations'), '0');
    expect(
      tester
          .widget<RestoflowMetricCard>(
            find.byKey(const Key('kpi-suspended-organizations')),
          )
          .tone,
      RestoflowTone.neutral,
    );
  });

  testWidgets('the header shows the SERVER day, not this device clock', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    expect(find.text('As of 2026-06-28'), findsOneWidget);
  });

  testWidgets('the overview survives every tested width without overflowing', (
    tester,
  ) async {
    for (final size in [kPhone, kTablet, kLaptop, kDesktop]) {
      useSize(tester, size);
      await tester.pumpWidget(consoleApp());
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${size.width}',
      );
      expect(find.byKey(const Key('kpi-organizations')), findsOneWidget);
    }
  });
}
