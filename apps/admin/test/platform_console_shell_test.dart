/// ADMIN-125C.2 — the platform console SHELL.
///
/// Proves the four top-level destinations exist and switch, that Subscriber
/// detail is reached from Subscribers and returns there, that navigation adapts
/// to width (rail vs drawer), that refresh refreshes only the CURRENT page, and
/// that the console offers no control that writes anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';

import 'console_test_harness.dart';

void main() {
  testWidgets('exposes exactly the four top-level destinations', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(
      find.byKey(const Key('console-rail')),
    );
    expect(rail.destinations, hasLength(4));
    for (final label in [
      l10n.adminNavOverview,
      l10n.adminNavSubscribers,
      l10n.adminNavRestaurants,
      l10n.adminNavAuditLog,
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing destination');
    }
    // Subscriber detail is NOT a destination: it always belongs to a tenant
    // chosen from the Subscribers list.
    expect(rail.destinations.length, ConsoleSection.values.length);
  });

  testWidgets('switching a destination swaps the page', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();

    // The Overview is TWO reads: the tenant counts, and today's sales grouped
    // by currency (a separate endpoint, rendered independently).
    expect(repo.calls, ['overview', 'operations']);
    expect(find.byKey(const Key('kpi-organizations')), findsOneWidget);

    await goToSection(tester, l10n.adminNavSubscribers);
    expect(find.byKey(const Key('subscribers-card')), findsOneWidget);
    expect(find.byKey(const Key('kpi-organizations')), findsNothing);

    await goToSection(tester, l10n.adminNavRestaurants);
    expect(find.byKey(const Key('restaurants-card')), findsOneWidget);

    await goToSection(tester, l10n.adminNavAuditLog);
    expect(find.byKey(const Key('audit-card')), findsOneWidget);

    // Each destination read its OWN endpoint, and only when opened. The
    // Restaurants page reads OPERATIONS (ADMIN-126), not the plain list.
    expect(repo.calls, [
      'overview',
      'operations',
      'subscribers',
      'operations',
      'audit',
    ]);
  });

  testWidgets(
    'a subscriber detail opens from the list and Back returns to it',
    (tester) async {
      useSize(tester, kDesktop);
      final l10n = await englishStrings();
      final repo = RecordingConsoleRepository();
      await tester.pumpWidget(consoleApp(repo: repo));
      await tester.pumpAndSettle();
      await goToSection(tester, l10n.adminNavSubscribers);

      await tester.tap(find.text('Bistro Group'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('subscriber-organization-card')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('subscribers-card')), findsNothing);

      await tester.tap(find.byKey(const Key('subscriber-detail-back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('subscribers-card')), findsOneWidget);
      expect(
        find.byKey(const Key('subscriber-organization-card')),
        findsNothing,
      );
    },
  );

  testWidgets('leaving Subscribers closes an open detail', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await goToSection(tester, l10n.adminNavSubscribers);
    await tester.tap(find.text('Bistro Group'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('subscriber-organization-card')),
      findsOneWidget,
    );

    await goToSection(tester, l10n.adminNavRestaurants);
    await goToSection(tester, l10n.adminNavSubscribers);

    // Back on the list, not on the tenant the operator has moved on from.
    expect(find.byKey(const Key('subscribers-card')), findsOneWidget);
    expect(find.byKey(const Key('subscriber-organization-card')), findsNothing);
  });

  testWidgets('navigation adapts to width: drawer below 900, rail at/above', (
    tester,
  ) async {
    for (final (size, wantsRail) in <(Size, bool)>[
      (kPhone, false),
      (kTablet, false),
      (kLaptop, true),
      (kDesktop, true),
    ]) {
      useSize(tester, size);
      await tester.pumpWidget(consoleApp());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('console-rail')),
        wantsRail ? findsOneWidget : findsNothing,
        reason: 'rail at ${size.width}',
      );
      expect(
        find.byTooltip('Open navigation menu'),
        wantsRail ? findsNothing : findsOneWidget,
        reason: 'drawer at ${size.width}',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${size.width}',
      );
    }
  });

  testWidgets('the rail extends its labels only on a wide desktop', (
    tester,
  ) async {
    useSize(tester, kLaptop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NavigationRail>(find.byKey(const Key('console-rail')))
          .extended,
      isFalse,
    );

    useSize(tester, const Size(1440, 1600));
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NavigationRail>(find.byKey(const Key('console-rail')))
          .extended,
      isTrue,
    );
  });

  testWidgets('the drawer navigates on a phone', (tester) async {
    useSize(tester, kPhone);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console-drawer')), findsOneWidget);

    await tester.tap(find.text(l10n.adminNavRestaurants).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restaurants-card')), findsOneWidget);
  });

  testWidgets('refresh re-reads ONLY the current page', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await goToSection(tester, l10n.adminNavRestaurants);
    repo.calls.clear();

    await tester.tap(find.byKey(const Key('platform-refresh-button')));
    await tester.pumpAndSettle();

    // Exactly the operations read: a blanket invalidate would re-read every
    // endpoint and write an audit row for each, for one operator gesture.
    expect(repo.calls, ['operations']);
  });

  testWidgets('the shell shows identity, mode and the read-only marker', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(
      consoleApp(operatorEmail: 'op@example.test', onSignOut: () {}),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-signed-in-as')), findsOneWidget);
    expect(find.text(l10n.adminSignedInAs('op@example.test')), findsOneWidget);
    expect(find.byKey(const Key('platform-data-source-pill')), findsOneWidget);
    expect(find.byKey(const Key('platform-readonly-pill')), findsOneWidget);
    expect(find.byKey(const Key('platform-signout-button')), findsOneWidget);
    expect(find.byKey(const Key('platform-refresh-button')), findsOneWidget);
  });

  testWidgets('provenance stays visible on EVERY page, not just the first', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    for (final section in [
      l10n.adminNavSubscribers,
      l10n.adminNavRestaurants,
      l10n.adminNavAuditLog,
      l10n.adminNavOverview,
    ]) {
      await goToSection(tester, section);
      expect(
        find.byKey(const Key('platform-data-source-pill')),
        findsOneWidget,
        reason: 'a demo figure must never be readable without its provenance',
      );
    }
  });

  testWidgets('the console offers NO control that writes (D-026 read-only)', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();

    const forbidden = <String>[
      'Suspend',
      'Activate',
      'Assign plan',
      'Change plan',
      'Delete',
      'Impersonate',
      'Grant',
      'Revoke',
      'Save',
      'Create',
    ];
    for (final section in [
      l10n.adminNavOverview,
      l10n.adminNavSubscribers,
      l10n.adminNavRestaurants,
      l10n.adminNavAuditLog,
    ]) {
      await goToSection(tester, section);
      for (final label in forbidden) {
        expect(
          find.text(label),
          findsNothing,
          reason: '"$label" on $section would be a write control',
        );
      }
    }

    // And on a subscriber detail, the surface most likely to grow one.
    await goToSection(tester, l10n.adminNavSubscribers);
    await tester.tap(find.text('Bistro Group'));
    await tester.pumpAndSettle();
    for (final label in forbidden) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('an empty platform renders the empty state, not a broken shell', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(
      consoleApp(
        repo: RecordingConsoleRepository(dataset: emptyPlatformDataset()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-empty')), findsOneWidget);
    expect(find.byKey(const Key('console-rail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
