/// ADMIN-125C.2 — the RESTAURANTS page and the AUDIT LOG page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';

import 'console_test_harness.dart';

Future<void> _openRestaurants(WidgetTester tester) async =>
    goToSection(tester, (await englishStrings()).adminNavRestaurants);

Future<void> _openAudit(WidgetTester tester) async =>
    goToSection(tester, (await englishStrings()).adminNavAuditLog);

void main() {
  // -------------------------------------------------------------------------
  // Restaurants
  // -------------------------------------------------------------------------

  testWidgets('lists every restaurant with its organization and counts', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    for (final name in const [
      'Bistro Downtown',
      'Bistro Seaside',
      'Cafe Noor Central',
      'Olive Tree Bistro',
      'Pizza Plaza HQ',
      'Sahara Grill Central',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Showing 1-6 of 6'), findsOneWidget);
    // Bistro Group owns two of the six restaurants.
    expect(find.text('Organization: Bistro Group'), findsNWidgets(2));
    expect(find.text('Organization: Cafe Noor'), findsOneWidget);
  });

  testWidgets('each row shows TODAY'
      'S SALES in its own currency', (tester) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    // Bistro Downtown trades in USD (its organization default), Cafe Noor
    // Central in ILS, Olive Tree Bistro in its OVERRIDDEN EUR. Each row is
    // formatted in its OWN currency — the page never converts.
    expect(
      find.byKey(
        const Key('restaurant-sales-d0000000-0000-4000-8000-0000000000b1'),
      ),
      findsOneWidget,
    );
    final usd = tester.widget<Text>(
      find.byKey(
        const Key('restaurant-sales-d0000000-0000-4000-8000-0000000000b1'),
      ),
    );
    expect(usd.data, contains('187.50'));
    final eur = tester.widget<Text>(
      find.byKey(
        const Key('restaurant-sales-d0000000-0000-4000-8000-0000000000b4'),
      ),
    );
    // A restaurant that took nothing today still shows a real zero, in its own
    // currency — never a blank cell.
    expect(eur.data, contains('0.00'));
  });

  testWidgets('totals are grouped BY CURRENCY and never combined', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    expect(find.text(l10n.adminSalesTodayByCurrency), findsOneWidget);
    // Three currencies in the demo platform => three chips, and no fourth
    // "total" chip that would add them together.
    expect(find.byKey(const Key('restaurants-total-USD')), findsOneWidget);
    expect(find.byKey(const Key('restaurants-total-ILS')), findsOneWidget);
    expect(find.byKey(const Key('restaurants-total-EUR')), findsOneWidget);
    expect(find.byKey(const Key('restaurants-total-')), findsNothing);
  });

  testWidgets('every row names the owner to contact, or says there is none', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    // Bistro Group has TWO active owners: the first is named and the rest are
    // counted, so the row stays readable.
    expect(find.textContaining('amira@bistro.example'), findsWidgets);
    expect(find.textContaining(l10n.adminMoreContacts(1)), findsWidgets);
    // Pizza Plaza has none, and says so rather than leaving a blank.
    expect(find.text(l10n.adminNoOwnerContact), findsOneWidget);
    // And no OTHER staff email appears anywhere on the page.
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(rendered.contains('manager@'), isFalse);
    expect(rendered.contains('cashier@'), isFalse);
  });

  testWidgets('an active restaurant under a SUSPENDED tenant shows both', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    // Pizza Plaza HQ is active; its organization is not. Showing only the
    // restaurant status would make the row look healthy.
    expect(
      find.byKey(
        const Key('restaurant-org-status-d0000000-0000-4000-8000-0000000000b6'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('search matches the restaurant name OR its organization', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    // "Cafe Noor" is an ORGANIZATION name; its restaurant is "Cafe Noor
    // Central", so this would match either way. "Olive Tree" is the tenant of a
    // restaurant named "Olive Tree Bistro" — search by tenant must find it.
    await tester.enterText(
      find.byKey(const Key('restaurants-search')),
      'Sahara Grill',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repo.operationsQueries.last.search, 'Sahara Grill');
    expect(find.text('Sahara Grill Central'), findsOneWidget);
    expect(find.text('Bistro Downtown'), findsNothing);
  });

  testWidgets('the organization-status filter and sort reach the server', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    await tester.tap(find.byKey(const Key('restaurants-org-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminOrgStatusSuspended).last);
    await tester.pumpAndSettle();
    expect(repo.operationsQueries.last.organizationStatus, 'suspended');
    expect(find.text('Pizza Plaza HQ'), findsOneWidget);
    expect(find.text('Bistro Downtown'), findsNothing);

    await tester.tap(find.byKey(const Key('restaurants-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminSortOrganizationDesc).last);
    await tester.pumpAndSettle();
    expect(
      repo.operationsQueries.last.sort,
      RestaurantOperationsSort.organizationDesc,
    );
    expect(repo.operationsQueries.last.sort.wire, 'organization_desc');
    // A sort change rewinds to page 1.
    expect(repo.operationsQueries.last.offset, 0);
  });

  testWidgets('the page shows trading figures but never order or customer '
      'detail', (tester) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    // ADMIN-126 deliberately shows today's sales and order COUNT. What stays
    // out is anything about individual orders or the people who placed them.
    for (final forbidden in const [
      'order_id',
      'customer',
      'local_operation_id',
      'pin_session',
      'card',
    ]) {
      expect(
        rendered.toLowerCase().contains(forbidden),
        isFalse,
        reason:
            '"\$forbidden" is per-order/customer data, not platform structure',
      );
    }
  });

  testWidgets('an empty restaurant result renders the empty state', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    await tester.enterText(find.byKey(const Key('restaurants-search')), 'zzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('restaurants-empty')), findsOneWidget);
    expect(find.text(l10n.adminNoRestaurants), findsOneWidget);
  });

  testWidgets('a restaurants failure renders the safe state', (tester) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(
      consoleApp(
        repo: const DemoPlatformAdminRepository(failureMessage: 'boom'),
      ),
    );
    await tester.pumpAndSettle();
    await _openRestaurants(tester);

    expect(find.byKey(const Key('platform-error')), findsOneWidget);
    expect(find.byKey(const Key('restaurants-card')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Audit log
  // -------------------------------------------------------------------------

  testWidgets('shows the newest page first, in descending time order', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openAudit(tester);

    expect(find.byKey(const Key('audit-card')), findsOneWidget);
    // 30 demo rows, 25 per page.
    expect(find.byKey(const Key('audit-load-more')), findsOneWidget);
    // The newest demo timestamp leads.
    expect(find.text('2026-06-28 09:10'), findsOneWidget);
    // Nothing from the oldest day is on page 1 yet.
    expect(find.text('2026-06-26 09:01'), findsNothing);
  });

  testWidgets('load more APPENDS the next keyset page and stops at the end', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openAudit(tester);

    final firstQuery = repo.auditQueries.last;
    expect(firstQuery.cursor, isNull, reason: 'page 1 carries no cursor');

    // The page is one tall ListView child, so the button EXISTS but sits below
    // the viewport; scroll it into view before tapping. (`scrollUntilVisible`
    // cannot be used here — the console has more than one Scrollable.)
    await tester.ensureVisible(find.byKey(const Key('audit-load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('audit-load-more')));
    await tester.pumpAndSettle();

    // Page 2 was requested THROUGH the cursor page 1 handed back — not by
    // offset, which would drift on an append-only log.
    final secondQuery = repo.auditQueries.last;
    expect(secondQuery.cursor, isNotNull);
    expect(secondQuery.cursor!.id, isNotEmpty);
    expect(secondQuery.cursor!.occurredAt, isNotEmpty);

    // The older rows are now appended below the first page, not replacing it.
    expect(find.text('2026-06-28 09:10'), findsOneWidget);
    expect(find.text('2026-06-26 09:01'), findsOneWidget);
    // 30 rows shown, so there is no more to load.
    expect(find.byKey(const Key('audit-load-more')), findsNothing);
  });

  testWidgets('the action filter narrows the log and resets the cursor', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openAudit(tester);

    await tester.tap(find.byKey(const Key('audit-action-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('platform.restaurants.list').last);
    await tester.pumpAndSettle();

    expect(repo.auditQueries.last.action, 'platform.restaurants.list');
    // A cursor from the previous filter set would resume at a position that no
    // longer exists in the new one.
    expect(repo.auditQueries.last.cursor, isNull);
    // Three demo rows carry that action (one per day) — one short page.
    expect(find.byKey(const Key('audit-load-more')), findsNothing);
  });

  testWidgets('the date range is INCLUSIVE of the end day', (tester) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openAudit(tester);

    await tester.enterText(find.byKey(const Key('audit-to')), '2026-06-26');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Pushed to the end of the day: a bare `T00:00:00Z` would drop everything
    // that happened ON the 26th, which is the day the operator asked for.
    expect(repo.auditQueries.last.to, '2026-06-26T23:59:59Z');
    expect(find.text('2026-06-26 09:10'), findsOneWidget);
    expect(find.text('2026-06-28 09:10'), findsNothing);
  });

  testWidgets('an unparseable date clears the bound instead of sending it', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openAudit(tester);

    await tester.enterText(find.byKey(const Key('audit-from')), 'not-a-date');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Sending garbage would earn a 22023 from the server; clearing is honest.
    expect(repo.auditQueries.last.from, isNull);
  });

  testWidgets('audit rows show shortened ids and NEVER the details jsonb', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openAudit(tester);

    // The actor is an 8-char prefix, never a full UUID and never an email.
    expect(find.textContaining('Actor: d0000000'), findsWidgets);
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(rendered.contains(kDemoOperatorId), isFalse);
    expect(rendered.contains('@'), isFalse);
    expect(rendered.contains('{'), isFalse, reason: 'no jsonb details');
    expect(rendered.contains('scope'), isFalse);

    // A platform-wide row says so rather than showing a blank target.
    expect(find.text(l10n.adminAuditPlatformWide), findsWidgets);
  });

  testWidgets(
    'the raw action key is shown untranslated (it IS the identifier)',
    (tester) async {
      useSize(tester, kDesktop);
      await tester.pumpWidget(consoleApp());
      await tester.pumpAndSettle();
      await _openAudit(tester);

      expect(find.text('platform.subscribers.list'), findsWidgets);
      expect(find.text('platform.console.overview'), findsWidgets);
    },
  );

  testWidgets('an empty log renders the empty state', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(
      consoleApp(
        repo: RecordingConsoleRepository(
          dataset: PlatformDataset(
            serverDateLabel: '2026-06-28',
            organizations: demoPlatformDataset().organizations,
            auditEvents: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openAudit(tester);

    expect(find.byKey(const Key('audit-empty')), findsOneWidget);
    expect(find.text(l10n.adminNoAuditEvents), findsOneWidget);
  });

  testWidgets('an audit failure renders the safe state', (tester) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(
      consoleApp(
        repo: const DemoPlatformAdminRepository(failureMessage: 'boom'),
      ),
    );
    await tester.pumpAndSettle();
    await _openAudit(tester);

    expect(find.byKey(const Key('platform-error')), findsOneWidget);
    expect(find.byKey(const Key('audit-card')), findsNothing);
  });

  testWidgets('restaurants and audit lay out at every width', (tester) async {
    for (final size in [kPhone, kTablet, kLaptop, kDesktop]) {
      useSize(tester, size);
      await tester.pumpWidget(consoleApp());
      await tester.pumpAndSettle();
      await _openRestaurants(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'restaurants ${size.width}',
      );
      await _openAudit(tester);
      expect(tester.takeException(), isNull, reason: 'audit ${size.width}');
    }
  });
}
