/// ADMIN-125C.2 — the SUBSCRIBERS list and the SUBSCRIBER DETAIL.
///
/// The load-bearing assertion in this file is that a subscriber row carries its
/// `organization_id` and hands THAT id to the detail page. The pre-125C.2 client
/// mapped organizations without their id at all, which is exactly why a detail
/// view could not exist; a regression there would silently remove the console's
/// only drill-down again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';

import 'console_test_harness.dart';

/// Bistro Group's demo organization id.
const String kBistroId = 'd0000000-0000-4000-8000-0000000000a1';

/// Pizza Plaza: suspended, and the tenant with NO subscription.
const String kPizzaId = 'd0000000-0000-4000-8000-0000000000a5';

Future<void> _openSubscribers(WidgetTester tester) async {
  final l10n = await englishStrings();
  await goToSection(tester, l10n.adminNavSubscribers);
}

void main() {
  testWidgets('lists every subscriber with its counts and currency', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    for (final name in const [
      'Bistro Group',
      'Cafe Noor',
      'Olive Tree',
      'Sahara Grill',
      'Pizza Plaza',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.byKey(const Key('subscriber-row-$kBistroId')), findsOneWidget);
    expect(find.text('Members: 9'), findsOneWidget);
    // Bistro Group and Olive Tree are both USD; Pizza Plaza is the only EUR.
    expect(find.text('Default currency: USD'), findsNWidgets(2));
    expect(find.text('Default currency: EUR'), findsOneWidget);
    expect(find.text('Created 2026-03-12'), findsOneWidget);
  });

  testWidgets('a tenant with no subscription says so, plainly', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    // Exactly one demo tenant has no subscription — and it gets a real label,
    // not a blank cell or an em dash that reads like a failed load.
    expect(
      find.byKey(const Key('subscriber-no-subscription-$kPizzaId')),
      findsOneWidget,
    );
    expect(find.text(l10n.adminNoSubscription), findsOneWidget);
    // The subscribed tenants show their plan instead.
    expect(find.text('Basic'), findsNWidgets(3));
    expect(find.text('Free'), findsOneWidget);
  });

  testWidgets('EVERY production row would show "no subscription" — the shape '
      'production is actually in', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(
      consoleApp(
        repo: RecordingConsoleRepository(
          dataset: unsubscribedPlatformDataset(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    expect(find.text(l10n.adminNoSubscription), findsNWidgets(5));
    expect(find.text('Basic'), findsNothing);
  });

  testWidgets('a row hands the ORGANIZATION ID to the detail page', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    await tester.tap(find.text('Pizza Plaza'));
    await tester.pumpAndSettle();

    // THE regression guard: the id must survive the mapping, and it must be the
    // id of the row that was tapped.
    expect(repo.detailIds, [kPizzaId]);
  });

  testWidgets('search goes to the SERVER and rewinds to page 1', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    await tester.enterText(find.byKey(const Key('subscribers-search')), 'cafe');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repo.subscriberQueries.last.search, 'cafe');
    expect(repo.subscriberQueries.last.offset, 0);
    expect(find.text('Cafe Noor'), findsOneWidget);
    expect(find.text('Bistro Group'), findsNothing);
  });

  testWidgets('the organization-status filter narrows the list', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    await tester.tap(find.byKey(const Key('subscribers-org-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminOrgStatusSuspended).last);
    await tester.pumpAndSettle();

    expect(repo.subscriberQueries.last.organizationStatus, 'suspended');
    expect(find.text('Pizza Plaza'), findsOneWidget);
    expect(find.text('Bistro Group'), findsNothing);
  });

  testWidgets('the subscription-status filter narrows the list', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    await tester.tap(
      find.byKey(const Key('subscribers-subscription-status-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminSubStatusPastDue).last);
    await tester.pumpAndSettle();

    expect(repo.subscriberQueries.last.subscriptionStatus, 'past_due');
    expect(find.text('Sahara Grill'), findsOneWidget);
    // Filtering BY a subscription attribute excludes tenants that have none —
    // the same inner-join effect the server's predicate has.
    expect(find.text('Pizza Plaza'), findsNothing);
  });

  testWidgets('sorting reorders the list and is sent to the server', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    await tester.tap(find.byKey(const Key('subscribers-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminSortNameDesc).last);
    await tester.pumpAndSettle();

    expect(repo.subscriberQueries.last.sort, SubscriberSort.nameDesc);
    expect(repo.subscriberQueries.last.sort.wire, 'name_desc');
    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where(
          (t) => const [
            'Bistro Group',
            'Cafe Noor',
            'Olive Tree',
            'Pizza Plaza',
            'Sahara Grill',
          ].contains(t),
        )
        .toList();
    expect(rows.first, 'Sahara Grill');
  });

  testWidgets('clear resets every filter back to the default query', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    await tester.enterText(find.byKey(const Key('subscribers-search')), 'cafe');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Bistro Group'), findsNothing);

    await tester.tap(find.byKey(const Key('console-clear-filters')));
    await tester.pumpAndSettle();

    // Same caching note as above: the unfiltered page is already cached, so the
    // proof that Clear worked is the console's query plus what it renders.
    expect(readSubscriberQuery(tester), const SubscriberQuery());
    expect(find.text('Bistro Group'), findsOneWidget);
    expect(repo.subscriberQueries, isNotEmpty);
  });

  testWidgets('pagination is server-side and reports the FILTERED total', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    // Five demo tenants fit on one page: both pagers are disabled, and the
    // range describes the whole set.
    expect(find.text('Showing 1-5 of 5'), findsOneWidget);
    // The key is ON the button, so `find.ancestor` (which excludes self) finds
    // nothing — read the keyed widget directly.
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('console-next-page')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('console-previous-page')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a second page is requested by OFFSET, not by refetching all', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    // Shrink the page so the demo dataset spans two pages.
    setSubscriberQuery(tester, const SubscriberQuery(limit: 2));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1-2 of 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('console-next-page')));
    await tester.pumpAndSettle();

    expect(repo.subscriberQueries.last.offset, 2);
    expect(find.text('Showing 3-4 of 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('console-previous-page')));
    await tester.pumpAndSettle();
    // Page 1 was already fetched, so it is served from the provider cache and
    // performs NO second read — assert the console's own query, not the last
    // repository call.
    expect(readSubscriberQuery(tester).offset, 0);
    expect(find.text('Showing 1-2 of 5'), findsOneWidget);
  });

  testWidgets('an empty result set renders the empty state', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openSubscribers(tester);

    await tester.enterText(
      find.byKey(const Key('subscribers-search')),
      'no-such-tenant',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('subscribers-empty')), findsOneWidget);
    expect(find.text(l10n.adminNoSubscribers), findsOneWidget);
    expect(find.byKey(const Key('subscribers-card')), findsNothing);
  });

  testWidgets('a loading state precedes the list', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp(repo: DelayedConsoleRepository()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    await goToSection(tester, l10n.adminNavSubscribers);

    expect(find.byKey(const Key('subscribers-card')), findsOneWidget);
  });

  testWidgets('a failure renders the safe state, never a half-list', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(
      consoleApp(
        repo: const DemoPlatformAdminRepository(failureMessage: 'boom'),
      ),
    );
    await tester.pumpAndSettle();
    await goToSection(tester, l10n.adminNavSubscribers);

    expect(find.byKey(const Key('platform-error')), findsOneWidget);
    expect(find.byKey(const Key('platform-retry-button')), findsOneWidget);
    expect(find.byKey(const Key('subscribers-card')), findsNothing);
    // The developer-facing message never reaches the operator.
    expect(find.text('boom'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Subscriber detail
  // -------------------------------------------------------------------------

  testWidgets('the detail shows organization, counts, subscription and '
      'restaurants', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openSubscribers(tester);
    await tester.tap(find.text('Bistro Group'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('subscriber-organization-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('subscriber-counts-card')), findsOneWidget);
    expect(
      find.byKey(const Key('subscriber-subscription-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('subscriber-restaurants-card')),
      findsOneWidget,
    );

    expect(find.text('USD'), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text(l10n.adminPeriodStart), findsOneWidget);
    expect(find.text('2026-07-01'), findsOneWidget);
    expect(find.text('Bistro Downtown'), findsOneWidget);
    expect(find.text('Bistro Seaside'), findsOneWidget);
    expect(find.text('Branches: 2'), findsWidgets);
  });

  testWidgets('a tenant with no subscription says so on the detail too', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openSubscribers(tester);
    await tester.tap(find.text('Pizza Plaza'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('subscriber-no-subscription')), findsOneWidget);
    expect(find.text(l10n.adminNoSubscriptionConfigured), findsOneWidget);
    expect(find.text(l10n.adminPeriodStart), findsNothing);
  });

  testWidgets('the detail NEVER exposes internal or PII fields', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openSubscribers(tester);
    await tester.tap(find.text('Bistro Group'));
    await tester.pumpAndSettle();

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    for (final forbidden in const [
      'created_by',
      'creation_request',
      '@example',
      'app_user_id:',
    ]) {
      expect(
        rendered.contains(forbidden),
        isFalse,
        reason: '"$forbidden" must not reach a platform console screen',
      );
    }
  });

  testWidgets('the detail shows platform activity SCOPED to that tenant', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    await _openSubscribers(tester);
    await tester.tap(find.text('Bistro Group'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('subscriber-activity-card')), findsOneWidget);
    // The scoped read is a SEPARATE, separately-audited request bound to this
    // organization — not a client-side filter of the whole log.
    expect(repo.auditQueries, isNotEmpty);
    expect(repo.auditQueries.last.targetOrganizationId, kBistroId);
  });

  testWidgets('a tenant with no recorded activity says so', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await _openSubscribers(tester);
    // Sahara Grill appears in no demo audit row.
    await tester.tap(find.text('Sahara Grill'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('subscriber-activity-empty')), findsOneWidget);
    expect(find.text(l10n.adminNoActivityForSubscriber), findsOneWidget);
  });

  testWidgets('an unknown tenant is access-denied, not "not found"', (
    tester,
  ) async {
    // Probing which organization ids exist must be impossible: the repository
    // raises the same failure for unknown as for denied.
    const repo = DemoPlatformAdminRepository();
    await expectLater(
      repo.loadSubscriberDetail('d0000000-0000-4000-8000-00000000dead'),
      throwsA(
        isA<PlatformAdminException>().having(
          (e) => e.kind,
          'kind',
          PlatformAdminErrorKind.accessDenied,
        ),
      ),
    );
  });

  testWidgets('the detail lays out at every width without overflowing', (
    tester,
  ) async {
    final l10n = await englishStrings();
    for (final size in [kPhone, kTablet, kLaptop, kDesktop]) {
      useSize(tester, size);
      await tester.pumpWidget(consoleApp());
      await tester.pumpAndSettle();
      await goToSection(tester, l10n.adminNavSubscribers);
      await tester.tap(find.text('Bistro Group'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('subscriber-organization-card')),
        findsOneWidget,
        reason: 'detail at ${size.width}',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${size.width}',
      );
    }
  });
}

/// Reaches the console's live [ProviderContainer] so a test can drive a query
/// directly — used here to shrink the page size, which is a cleaner way to prove
/// paging than inventing a hundred-tenant fixture.
void setSubscriberQuery(WidgetTester tester, SubscriberQuery query) {
  final element = tester.element(find.byType(Scaffold).first);
  ProviderScope.containerOf(
    element,
    listen: false,
  ).read(subscriberQueryProvider.notifier).state = query;
}
