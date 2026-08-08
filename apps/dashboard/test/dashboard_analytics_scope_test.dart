import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-E1) — the explicit analytics scope.
///
/// THE DEFECT. `resolveTenantContext` pins a concrete FIRST restaurant and
/// FIRST branch onto every resolved membership, because the menu/printer/staff
/// surfaces need one. The Overview then read its reporting scope off those
/// pinned ids, so an org owner asking for "sales" was shown one branch's sales
/// with nothing on screen saying so.
///
/// These tests pin the correction: coverage comes from the ROLE, the default is
/// the broadest authorized scope, and a selection can only ever narrow within
/// coverage — never widen, and never survive a membership that no longer
/// authorizes it.

MembershipContext _membership({
  required MembershipRole role,
  String organizationId = 'org-1',
  String? restaurantId = 'rest-1',
  String? branchId = 'branch-1',
  String? branchName = 'Downtown',
}) => MembershipContext(
  id: 'm-1',
  organizationId: organizationId,
  organizationName: 'Org',
  restaurantId: restaurantId,
  restaurantName: 'Rest',
  branchId: branchId,
  branchName: branchName,
  role: role,
  status: 'active',
);

const _branchInRest1 = AuditBranchOption(
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  label: 'Rest One · Downtown',
);
const _otherBranchInRest1 = AuditBranchOption(
  branchId: 'branch-2',
  restaurantId: 'rest-1',
  label: 'Rest One · Harbor',
);
const _branchInRest2 = AuditBranchOption(
  branchId: 'branch-9',
  restaurantId: 'rest-2',
  label: 'Rest Two · Airport',
);

class _CountingRepository implements OwnerReportsRepository {
  final List<ReportRange> calls = <ReportRange>[];
  int get callCount => calls.length;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
  }) async {
    calls.add(range);
    return const DemoOwnerReportsRepository().loadReport(range: range);
  }
}

class _CountingSeriesRepository implements OwnerSalesSeriesRepository {
  final List<AnalyticsRange> calls = <AnalyticsRange>[];
  int get callCount => calls.length;

  @override
  Future<OwnerSalesSeries> loadSeries({required AnalyticsRange range}) async {
    calls.add(range);
    return DemoOwnerSalesSeriesRepository(
      clock: () => DateTime(2026, 8, 8),
    ).loadSeries(range: range);
  }
}

ProviderContainer _container({
  required MembershipContext membership,
  OwnerReportsRepository? reports,
  OwnerSalesSeriesRepository? series,
}) {
  final c = ProviderContainer(
    overrides: [
      dashboardMembershipProvider.overrideWithValue(membership),
      if (reports != null)
        ownerReportsRepositoryProvider.overrideWithValue(reports),
      if (series != null)
        ownerSalesSeriesRepositoryProvider.overrideWithValue(series),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<OwnerSalesSeries?> _readSeries(ProviderContainer c) {
  final key = c.read(currentOwnerSalesSeriesKeyProvider);
  if (key == null) return Future.value(null);
  return c.read(ownerSalesSeriesForKeyProvider(key).future);
}

void main() {
  group('scope derivation from the membership ROLE', () {
    test('A. a branch-scoped membership covers exactly its branch, and has no '
        '"all" to offer', () {
      for (final role in const [
        MembershipRole.manager,
        MembershipRole.cashier,
        MembershipRole.kitchenStaff,
        MembershipRole.accountant,
      ]) {
        final scope = DashboardAnalyticsScope.coveredBy(
          _membership(role: role),
        );
        expect(scope.kind, DashboardAnalyticsScopeKind.singleBranch);
        expect(scope.restaurantId, 'rest-1');
        expect(scope.branchId, 'branch-1');
        expect(scope.isAllPermitted, isFalse);
        expect(scope.branchLabel, 'Downtown');
        // It cannot reach a sibling branch, nor another restaurant.
        expect(scope.covers(_branchInRest1), isTrue);
        expect(scope.covers(_otherBranchInRest1), isFalse);
        expect(scope.covers(_branchInRest2), isFalse);
      }
    });

    test('B. a restaurant-scoped membership covers its whole restaurant, and '
        'no sibling restaurant', () {
      final scope = DashboardAnalyticsScope.coveredBy(
        _membership(role: MembershipRole.restaurantOwner),
      );
      expect(scope.kind, DashboardAnalyticsScopeKind.restaurantWide);
      expect(scope.restaurantId, 'rest-1');
      expect(scope.branchId, isNull);
      expect(scope.isAllPermitted, isTrue);
      expect(scope.covers(_branchInRest1), isTrue);
      expect(scope.covers(_otherBranchInRest1), isTrue);
      expect(scope.covers(_branchInRest2), isFalse);
    });

    test('C. an org-scoped membership covers the whole organization', () {
      final scope = DashboardAnalyticsScope.coveredBy(
        _membership(role: MembershipRole.orgOwner),
      );
      expect(scope.kind, DashboardAnalyticsScopeKind.orgWide);
      expect(scope.restaurantId, isNull);
      expect(scope.branchId, isNull);
      expect(scope.covers(_branchInRest1), isTrue);
      expect(scope.covers(_branchInRest2), isTrue);
    });

    test('F. a broad membership NEVER defaults to the pinned first branch — '
        'the whole point of this slice', () {
      // Exactly the shape resolveTenantContext produces for an org-wide owner:
      // concrete first-restaurant and first-branch ids on the membership.
      final resolved = _membership(
        role: MembershipRole.orgOwner,
        restaurantId: 'rest-1',
        branchId: 'branch-1',
      );
      final scope = DashboardAnalyticsScope.coveredBy(resolved);

      expect(scope.restaurantId, isNull, reason: 'not the first restaurant');
      expect(scope.branchId, isNull, reason: 'not the first branch');
      expect(scope.restaurantId, isNot(resolved.restaurantId));
      expect(scope.branchId, isNot(resolved.branchId));
    });

    test('D. selecting a branch carries BOTH ids, from the option', () {
      final scope = DashboardAnalyticsScope.branch(
        organizationId: 'org-1',
        option: _branchInRest2,
      );
      expect(scope.organizationId, 'org-1');
      // From the OPTION, not from the membership — an org owner picking a
      // branch of their second restaurant must send that restaurant's id.
      expect(scope.restaurantId, 'rest-2');
      expect(scope.branchId, 'branch-9');
      expect(scope.kind, DashboardAnalyticsScopeKind.singleBranch);
    });

    test('E. option labels keep the source disambiguation, so identical branch '
        'names across restaurants stay distinguishable', () {
      const a = AuditBranchOption(
        branchId: 'b-1',
        restaurantId: 'r-1',
        label: 'Rest One · Main',
      );
      const b = AuditBranchOption(
        branchId: 'b-2',
        restaurantId: 'r-2',
        label: 'Rest Two · Main',
      );
      expect(
        DashboardAnalyticsScope.branch(
          organizationId: 'org-1',
          option: a,
        ).branchLabel,
        'Rest One · Main',
      );
      expect(
        DashboardAnalyticsScope.branch(
          organizationId: 'org-1',
          option: b,
        ).branchLabel,
        'Rest Two · Main',
      );
    });

    test('scopes are value-equal and hash-stable', () {
      final a = DashboardAnalyticsScope.coveredBy(
        _membership(role: MembershipRole.orgOwner),
      );
      final b = DashboardAnalyticsScope.coveredBy(
        _membership(role: MembershipRole.orgOwner),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          DashboardAnalyticsScope.coveredBy(
            _membership(role: MembershipRole.restaurantOwner),
          ),
        ),
      );
    });
  });

  group('selection is a filter over coverage, never a widening', () {
    test('an org owner starts broad and narrows to a chosen branch', () {
      final c = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      expect(
        c.read(dashboardAnalyticsScopeProvider)!.kind,
        DashboardAnalyticsScopeKind.orgWide,
      );

      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest2;
      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.kind, DashboardAnalyticsScopeKind.singleBranch);
      expect(scope.restaurantId, 'rest-2');
      expect(scope.branchId, 'branch-9');
    });

    test('a restaurant owner CANNOT select a sibling restaurant\'s branch — '
        'the selection is ignored and coverage stands', () {
      final c = _container(
        membership: _membership(role: MembershipRole.restaurantOwner),
      );
      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest2;

      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.kind, DashboardAnalyticsScopeKind.restaurantWide);
      expect(scope.restaurantId, 'rest-1');
      expect(scope.branchId, isNull);
    });

    test('a branch-scoped membership cannot escape its branch', () {
      final c = _container(
        membership: _membership(role: MembershipRole.cashier),
      );
      c.read(selectedAnalyticsBranchProvider.notifier).state =
          _otherBranchInRest1;

      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(
        scope.branchId,
        'branch-1',
        reason: 'its own branch, not branch-2',
      );
    });

    test('a selection that a NEW membership no longer authorizes is dropped, '
        'not retained', () {
      // An org owner picks a branch of their second restaurant...
      final broad = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      broad.read(selectedAnalyticsBranchProvider.notifier).state =
          _branchInRest2;
      expect(broad.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-9');

      // ...and the SAME selection under a branch-scoped membership is refused.
      final narrow = _container(
        membership: _membership(role: MembershipRole.manager),
      );
      narrow.read(selectedAnalyticsBranchProvider.notifier).state =
          _branchInRest2;
      final scope = narrow.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.branchId, 'branch-1');
      expect(scope.restaurantId, 'rest-1');
      expect(scope.branchId, isNot('branch-9'));
    });

    test('no membership (demo) yields no scope and no selector data', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(dashboardCoveredScopeProvider), isNull);
      expect(c.read(dashboardAnalyticsScopeProvider), isNull);
    });

    test('separate containers do not share the selection', () {
      final a = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      final b = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      a.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest1;

      expect(a.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-1');
      expect(b.read(dashboardAnalyticsScopeProvider)!.branchId, isNull);
    });
  });

  group('cache keys follow the scope', () {
    test('branch A and branch B are different report keys', () {
      final c = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      final broad = c.read(currentOwnerReportKeyProvider);

      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest1;
      final a = c.read(currentOwnerReportKeyProvider);
      c.read(selectedAnalyticsBranchProvider.notifier).state =
          _otherBranchInRest1;
      final b = c.read(currentOwnerReportKeyProvider);

      expect(a, isNot(b));
      expect(a, isNot(broad));
      expect(b, isNot(broad));
      expect(a.branchId, 'branch-1');
      expect(b.branchId, 'branch-2');
      expect(broad.branchId, isNull);
    });

    test('org-all and restaurant-all are different keys', () {
      final org = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      ).read(currentOwnerReportKeyProvider);
      final rest = _container(
        membership: _membership(role: MembershipRole.restaurantOwner),
      ).read(currentOwnerReportKeyProvider);

      expect(org, isNot(rest));
      expect(org.restaurantId, isNull);
      expect(rest.restaurantId, 'rest-1');
    });

    test('the report key and the series key agree on scope — the KPIs and the '
        'trends can never describe different branches', () {
      final c = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest2;

      final report = c.read(currentOwnerReportKeyProvider);
      final series = c.read(currentOwnerSalesSeriesKeyProvider)!;
      expect(series.organizationId, report.organizationId);
      expect(series.restaurantId, report.restaurantId);
      expect(series.branchId, report.branchId);
      expect(report.branchId, 'branch-9');
    });
  });

  group('request counts across scope changes', () {
    test('owner_report_range: broad -> A -> B -> back to A', () async {
      final repo = _CountingRepository();
      final c = _container(
        membership: _membership(role: MembershipRole.orgOwner),
        reports: repo,
      );

      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 1, reason: 'the broad default');

      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest1;
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 2);

      c.read(selectedAnalyticsBranchProvider.notifier).state =
          _otherBranchInRest1;
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 3);

      // Returning to a retained scope costs nothing.
      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest1;
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 3, reason: 'branch A was already loaded');

      // And a rebuild on the same key adds nothing.
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 3);
    });

    test('refresh targets ONLY the current scope + range', () async {
      final repo = _CountingRepository();
      final c = _container(
        membership: _membership(role: MembershipRole.orgOwner),
        reports: repo,
      );
      await c.read(dashboardReportProvider.future); // broad
      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest1;
      await c.read(dashboardReportProvider.future); // branch A
      expect(repo.callCount, 2);

      c.invalidate(
        ownerReportForKeyProvider(c.read(currentOwnerReportKeyProvider)),
      );
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 3);

      // The broad entry was NOT invalidated.
      c.read(selectedAnalyticsBranchProvider.notifier).state = null;
      await c.read(dashboardReportProvider.future);
      expect(repo.callCount, 3);
    });

    test(
      'owner_sales_series: one call per scope on last7, reused on return',
      () async {
        final repo = _CountingSeriesRepository();
        final c = _container(
          membership: _membership(role: MembershipRole.orgOwner),
          series: repo,
        );
        c.read(reportRangeProvider.notifier).state = ReportRange.last7;

        await _readSeries(c);
        expect(repo.callCount, 1);

        c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest1;
        await _readSeries(c);
        expect(repo.callCount, 2);

        c.read(selectedAnalyticsBranchProvider.notifier).state = null;
        await _readSeries(c);
        expect(repo.callCount, 2, reason: 'the broad entry is retained');
      },
    );

    test('today and yesterday issue ZERO series calls no matter which branch '
        'is selected', () async {
      final repo = _CountingSeriesRepository();
      final c = _container(
        membership: _membership(role: MembershipRole.orgOwner),
        series: repo,
      );

      for (final range in const [ReportRange.today, ReportRange.yesterday]) {
        c.read(reportRangeProvider.notifier).state = range;
        for (final option in const [null, _branchInRest1, _branchInRest2]) {
          c.read(selectedAnalyticsBranchProvider.notifier).state = option;
          expect(c.read(currentOwnerSalesSeriesKeyProvider), isNull);
          expect(await _readSeries(c), isNull);
        }
      }
      expect(repo.callCount, 0);
    });
  });

  group('no cross-tenant bleed', () {
    test('another organization is a different key and a different result', () {
      final orgA = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      final orgB = _container(
        membership: _membership(
          role: MembershipRole.orgOwner,
          organizationId: 'org-2',
        ),
      );

      final a = orgA.read(currentOwnerReportKeyProvider);
      final b = orgB.read(currentOwnerReportKeyProvider);
      expect(a.organizationId, 'org-1');
      expect(b.organizationId, 'org-2');
      expect(a, isNot(b));
    });

    test('a selection made under org A does not leak into org B', () {
      final orgA = _container(
        membership: _membership(role: MembershipRole.orgOwner),
      );
      orgA.read(selectedAnalyticsBranchProvider.notifier).state =
          _branchInRest1;

      final orgB = _container(
        membership: _membership(
          role: MembershipRole.orgOwner,
          organizationId: 'org-2',
        ),
      );
      expect(orgB.read(dashboardAnalyticsScopeProvider)!.branchId, isNull);
      expect(orgB.read(currentOwnerReportKeyProvider).organizationId, 'org-2');
    });

    test('the selector writes ONLY the selection — the membership is never '
        'mutated or replaced', () {
      final membership = _membership(role: MembershipRole.orgOwner);
      final c = _container(membership: membership);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchInRest2;

      final after = c.read(dashboardMembershipProvider)!;
      expect(identical(after, membership), isTrue);
      expect(after.role, MembershipRole.orgOwner);
      expect(after.organizationId, 'org-1');
      expect(after.restaurantId, 'rest-1');
      expect(after.branchId, 'branch-1');
    });
  });
}
