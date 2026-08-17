import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/owner_report_query_key.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:flutter/material.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';

/// DASHBOARD-OWNER-ANALYTICS-F0.6 — scoped report retention.
///
/// The defect: leaving Overview and returning refetched the report even with an
/// unchanged scope and range. The cause was NOT autoDispose — the report
/// provider is a plain FutureProvider — but nested ProviderScope recreation.
/// Each surface built its own scope INSIDE the tab-switch KeyedSubtree, so
/// switching tabs destroyed the container holding the loaded report.
///
/// These tests pin the request COUNT, which is the only thing an owner actually
/// pays for, and the scope isolation that makes caching safe to do at all.
class _CountingRepository implements OwnerReportsRepository {
  _CountingRepository({this.failTimes = 0});

  /// Every range this repository was asked for, in order.
  final List<ReportRange> calls = <ReportRange>[];

  /// Fail the first N calls, to prove an error is retryable rather than a
  /// permanently poisoned cache entry.
  int failTimes;

  int get callCount => calls.length;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async {
    calls.add(range);
    if (failTimes > 0) {
      failTimes--;
      throw const OwnerReportsException('forced failure');
    }
    return const DemoOwnerReportsRepository().loadReport(range: range);
  }
}

MembershipContext _membershipA = MembershipContext(
  id: 'm-a',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest',
  branchId: 'branch-1',
  branchName: 'Branch',
  role: MembershipRole.orgOwner,
  status: 'active',
);

/// CLIENT-E1: branch-scoped roles, so their COVERAGE really is one branch.
/// They were org owners before, which no longer distinguishes them: an org
/// owner covers the whole organization no matter which branch the tenant
/// resolver happened to pin onto the membership.
MembershipContext _membershipBranchOne = MembershipContext(
  id: 'm-b1',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest',
  branchId: 'branch-1',
  branchName: 'Branch One',
  role: MembershipRole.manager,
  status: 'active',
);

MembershipContext _membershipOtherBranch = MembershipContext(
  id: 'm-b',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest',
  branchId: 'branch-2',
  branchName: 'Branch Two',
  role: MembershipRole.manager,
  status: 'active',
);

MembershipContext _membershipOtherOrg = MembershipContext(
  id: 'm-c',
  organizationId: 'org-2',
  organizationName: 'Org',
  restaurantId: 'rest-9',
  restaurantName: 'Rest',
  branchId: 'branch-9',
  branchName: 'Branch',
  role: MembershipRole.orgOwner,
  status: 'active',
);

ProviderContainer makeContainer(
  _CountingRepository repo, {
  MembershipContext? membership,
}) {
  final container = ProviderContainer(
    overrides: [
      ownerReportsRepositoryProvider.overrideWithValue(repo),
      dashboardMembershipProvider.overrideWithValue(membership ?? _membershipA),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('F0.6 OwnerReportQueryKey', () {
    const base = OwnerReportQueryKey(
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
      range: ReportRange.today,
      isDemoMode: true,
    );

    test('is value-equal and hash-stable', () {
      const same = OwnerReportQueryKey(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        range: ReportRange.today,
        isDemoMode: true,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      // Usable as a map/family key.
      expect({base: 1}[same], 1);
    });

    test('EVERY field participates in identity', () {
      expect(
        base,
        isNot(
          const OwnerReportQueryKey(
            organizationId: 'org-2',
            restaurantId: 'rest-1',
            branchId: 'branch-1',
            range: ReportRange.today,
            isDemoMode: true,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const OwnerReportQueryKey(
            organizationId: 'org-1',
            restaurantId: 'rest-2',
            branchId: 'branch-1',
            range: ReportRange.today,
            isDemoMode: true,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const OwnerReportQueryKey(
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: 'branch-2',
            range: ReportRange.today,
            isDemoMode: true,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const OwnerReportQueryKey(
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: 'branch-1',
            range: ReportRange.last7,
            isDemoMode: true,
          ),
        ),
      );
      // Demo and real are different data sources on one provider path.
      expect(
        base,
        isNot(
          const OwnerReportQueryKey(
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: 'branch-1',
            range: ReportRange.today,
            isDemoMode: false,
          ),
        ),
      );
    });

    test('a NULL branch is a distinct, valid all-branches identity — not a '
        'missing value that collides with a branch-scoped key', () {
      const allBranches = OwnerReportQueryKey(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: null,
        range: ReportRange.today,
        isDemoMode: true,
      );
      expect(allBranches, isNot(base));
    });
  });

  _shellRetentionTests();

  group('F0.6 request counts', () {
    test('A. first read issues exactly ONE request', () async {
      final repo = _CountingRepository();
      final c = makeContainer(repo);
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 1);
    });

    test('B. a disposed-and-rebuilt LISTENER reuses the cached entry — the '
        'tab-away-and-back case', () async {
      final repo = _CountingRepository();
      final c = makeContainer(repo);
      final first = await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 1);

      // A tab switch destroys the Overview subtree and every listener in it.
      // The keyed entry lives in the shared scope above, so re-reading it must
      // NOT hit the repository again.
      final second = await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 1, reason: 'returning must not refetch');
      expect(identical(first, second), isTrue, reason: 'same cached instance');
    });

    test('C. explicit refresh issues exactly ONE more request', () async {
      final repo = _CountingRepository();
      final c = makeContainer(repo);
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 1);

      c.invalidate(
        ownerReportForKeyProvider(c.read(currentOwnerReportKeyProvider)),
      );
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 2);

      // A rebuild after the refresh must not add a third.
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 2, reason: 'no duplicate from rebuild');
    });

    test(
      'D. changing range issues exactly one request for the NEW range',
      () async {
        final repo = _CountingRepository();
        final c = makeContainer(repo);
        await c.read(dashboardReportProvider.future);

        c.read(reportRangeProvider.notifier).state = ReportRange.last7;
        await c.read(dashboardReportProvider.future);

        expect(repo.callCount, 2);
        expect(repo.calls, [ReportRange.today, ReportRange.last7]);
      },
    );

    test('E. returning to a previously loaded range REUSES its entry — no '
        'extra request while the shared container lives', () async {
      final repo = _CountingRepository();
      final c = makeContainer(repo);
      await c.read(dashboardReportProvider.future);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 2);

      c.read(reportRangeProvider.notifier).state = ReportRange.today;
      await c.read(dashboardReportProvider.future);
      expect(
        repo.callCount,
        2,
        reason: 'today was already loaded and is retained',
      );
    });

    test('F. a different BRANCH is a different request', () async {
      // CLIENT-E1: both memberships are BRANCH-SCOPED, so their coverage — and
      // therefore their key — really is one branch each.
      final repoA = _CountingRepository();
      final a = makeContainer(repoA, membership: _membershipBranchOne);
      await a.read(dashboardReportProvider.future);

      final repoB = _CountingRepository();
      final b = makeContainer(repoB, membership: _membershipOtherBranch);
      await b.read(dashboardReportProvider.future);

      expect(a.read(currentOwnerReportKeyProvider).branchId, 'branch-1');
      expect(b.read(currentOwnerReportKeyProvider).branchId, 'branch-2');
      expect(
        a.read(currentOwnerReportKeyProvider),
        isNot(b.read(currentOwnerReportKeyProvider)),
      );
      expect(repoB.callCount, 1, reason: 'must not reuse the other branch');
    });

    test('G. a different ORG/RESTAURANT is a different request', () async {
      final repo = _CountingRepository();
      final c = makeContainer(repo, membership: _membershipOtherOrg);
      await c.read(dashboardReportProvider.future);

      final key = c.read(currentOwnerReportKeyProvider);
      expect(key.organizationId, 'org-2');
      // CLIENT-E1: an ORG owner reports on the whole organization. The
      // restaurant/branch the tenant resolver pinned onto the membership
      // ('rest-9' / 'branch-9', the first of each) is NOT their scope — reading
      // it as such was the silent narrowing this slice removes.
      expect(key.restaurantId, isNull);
      expect(key.branchId, isNull);
      expect(repo.callCount, 1);
    });

    test('H. separate containers share nothing', () async {
      final repoA = _CountingRepository();
      final repoB = _CountingRepository();
      final a = makeContainer(repoA);
      final b = makeContainer(repoB);

      await a.read(dashboardReportProvider.future);
      await b.read(dashboardReportProvider.future);

      // Each container performed its OWN load; no cross-container bleed.
      expect(repoA.callCount, 1);
      expect(repoB.callCount, 1);
    });

    test('I. a failed entry is NOT permanently poisoned — refresh retries and '
        'recovers', () async {
      final repo = _CountingRepository(failTimes: 1);
      final c = makeContainer(repo);

      await expectLater(
        c.read(dashboardReportProvider.future),
        throwsA(isA<OwnerReportsException>()),
      );
      expect(repo.callCount, 1);

      c.invalidate(
        ownerReportForKeyProvider(c.read(currentOwnerReportKeyProvider)),
      );
      final recovered = await c.read(dashboardReportProvider.future);

      expect(repo.callCount, 2);
      expect(recovered, isA<DashboardReport>());
    });

    test('K. refreshing one range does NOT refetch another', () async {
      final repo = _CountingRepository();
      final c = makeContainer(repo);
      await c.read(dashboardReportProvider.future); // today
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await c.read(dashboardReportProvider.future); // last7
      expect(repo.callCount, 2);

      // Refresh ONLY last7 (the current key).
      c.invalidate(
        ownerReportForKeyProvider(c.read(currentOwnerReportKeyProvider)),
      );
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 3);

      // today must still be cached, untouched by that refresh.
      c.read(reportRangeProvider.notifier).state = ReportRange.today;
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 3, reason: 'the other range was not invalidated');
    });

    test(
      'J. concurrent readers of the same key share ONE in-flight request',
      () async {
        final repo = _CountingRepository();
        final c = makeContainer(repo);
        final results = await Future.wait([
          c.read(dashboardReportProvider.future),
          c.read(dashboardReportProvider.future),
          c.read(dashboardReportProvider.future),
        ]);
        expect(repo.callCount, 1);
        expect(results, hasLength(3));
      },
    );
  });
}

/// The load-bearing regression test: the REAL shell, a REAL tab switch.
///
/// The container-level tests above would have passed BEFORE this fix too — a
/// plain FutureProvider already caches within one container. What was broken
/// is that leaving Overview DESTROYED that container, because each surface
/// built its own ProviderScope inside the tab-switch KeyedSubtree. Only a test
/// that drives the actual shell can prove the hoist works.
void _shellRetentionTests() {
  testWidgets('M. leaving Overview and returning does NOT refetch', (
    tester,
  ) async {
    // Phone width so the KEYED bottom NavigationBar renders; the side rail
    // is a private widget with no stable test handle.
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _CountingRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ownerReportsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          theme: restoflowBaseTheme(),
          home: const DashboardShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.callCount, 1, reason: 'first Overview build loads once');

    final nav = () => tester.widget<NavigationBar>(
      find.byKey(const Key('dashboard-bottom-nav')),
    );

    // Leave Overview for Orders through the real navigation callback.
    nav().onDestinationSelected!(DashboardDestination.orders.visibleIndex!);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reports-heading')),
      findsNothing,
      reason: 'the Overview subtree really was torn down',
    );

    // ...and come back.
    nav().onDestinationSelected!(DashboardDestination.overview.visibleIndex!);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reports-heading')), findsOneWidget);

    expect(
      repo.callCount,
      1,
      reason: 'returning to Overview must reuse the retained report',
    );
  });
}
