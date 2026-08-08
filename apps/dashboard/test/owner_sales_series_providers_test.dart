import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/owner_sales_series_query_key.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — sales-series request identity
/// and REQUEST COUNT.
///
/// The count is the thing an owner actually pays for, in latency and in server
/// load, so it is asserted directly rather than inferred from a widget being on
/// screen. The load gate is asserted the same way: `today`/`yesterday` must
/// issue ZERO `owner_sales_series` requests, because they already have an hourly
/// curve and a one-point daily chart would be a wasted round trip.
class _CountingSeriesRepository implements OwnerSalesSeriesRepository {
  _CountingSeriesRepository({this.failTimes = 0});

  /// Every range this repository was asked for, in order.
  final List<AnalyticsRange> calls = <AnalyticsRange>[];

  int failTimes;

  int get callCount => calls.length;

  @override
  Future<OwnerSalesSeries> loadSeries({required AnalyticsRange range}) async {
    calls.add(range);
    if (failTimes > 0) {
      failTimes--;
      throw const OwnerSalesSeriesException('forced failure');
    }
    return DemoOwnerSalesSeriesRepository(
      clock: () => DateTime(2026, 8, 8),
    ).loadSeries(range: range);
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

MembershipContext _membershipOtherBranch = MembershipContext(
  id: 'm-b',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest',
  branchId: 'branch-2',
  branchName: 'Branch',
  role: MembershipRole.orgOwner,
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
  _CountingSeriesRepository repo, {
  MembershipContext? membership,
}) {
  final container = ProviderContainer(
    overrides: [
      ownerSalesSeriesRepositoryProvider.overrideWithValue(repo),
      dashboardMembershipProvider.overrideWithValue(membership ?? _membershipA),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Reads the series the way the Overview does: through the current key, or not
/// at all when there is no key.
Future<OwnerSalesSeries?> readSeries(ProviderContainer c) {
  final key = c.read(currentOwnerSalesSeriesKeyProvider);
  if (key == null) return Future.value(null);
  return c.read(ownerSalesSeriesForKeyProvider(key).future);
}

void main() {
  group('OwnerSalesSeriesQueryKey', () {
    const base = OwnerSalesSeriesQueryKey(
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
      range: AnalyticsRange.last7,
      isDemoMode: true,
    );

    test('is value-equal and hash-stable', () {
      const same = OwnerSalesSeriesQueryKey(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        range: AnalyticsRange.last7,
        isDemoMode: true,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      expect({base: 1}[same], 1);
    });

    test('EVERY field participates in identity', () {
      const variants = <OwnerSalesSeriesQueryKey>[
        OwnerSalesSeriesQueryKey(
          organizationId: 'org-2',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          range: AnalyticsRange.last7,
          isDemoMode: true,
        ),
        OwnerSalesSeriesQueryKey(
          organizationId: 'org-1',
          restaurantId: 'rest-2',
          branchId: 'branch-1',
          range: AnalyticsRange.last7,
          isDemoMode: true,
        ),
        OwnerSalesSeriesQueryKey(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-2',
          range: AnalyticsRange.last7,
          isDemoMode: true,
        ),
        OwnerSalesSeriesQueryKey(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: null,
          range: AnalyticsRange.last7,
          isDemoMode: true,
        ),
        OwnerSalesSeriesQueryKey(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          range: AnalyticsRange.last30,
          isDemoMode: true,
        ),
        OwnerSalesSeriesQueryKey(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          range: AnalyticsRange.last7,
          isDemoMode: false,
        ),
      ];
      for (final v in variants) {
        expect(base, isNot(v), reason: '$v must not equal the base key');
      }
    });
  });

  group('the load gate', () {
    test('G. today and yesterday build NO key and issue NO request — the '
        'hourly curve already answers a single day', () async {
      for (final range in const [ReportRange.today, ReportRange.yesterday]) {
        final repo = _CountingSeriesRepository();
        final c = makeContainer(repo);
        c.read(reportRangeProvider.notifier).state = range;

        expect(c.read(currentOwnerSalesSeriesKeyProvider), isNull);
        expect(await readSeries(c), isNull);
        expect(
          repo.callCount,
          0,
          reason: 'no owner_sales_series request for $range',
        );
      }
    });

    test(
      'last7 and last30 DO build a key, carrying the canonical range',
      () async {
        final repo = _CountingSeriesRepository();
        final c = makeContainer(repo);

        c.read(reportRangeProvider.notifier).state = ReportRange.last7;
        expect(
          c.read(currentOwnerSalesSeriesKeyProvider)!.range,
          AnalyticsRange.last7,
        );

        c.read(reportRangeProvider.notifier).state = ReportRange.last30;
        expect(
          c.read(currentOwnerSalesSeriesKeyProvider)!.range,
          AnalyticsRange.last30,
        );
      },
    );

    test(
      'the key carries the resolved MEMBERSHIP scope, never a filter',
      () async {
        final c = makeContainer(_CountingSeriesRepository());
        c.read(reportRangeProvider.notifier).state = ReportRange.last7;

        final key = c.read(currentOwnerSalesSeriesKeyProvider)!;
        expect(key.organizationId, 'org-1');
        expect(key.restaurantId, 'rest-1');
        expect(key.branchId, 'branch-1');
        expect(key.isDemoMode, isTrue);
      },
    );
  });

  group('request counts', () {
    test('A. the first last7 read issues exactly ONE request', () async {
      final repo = _CountingSeriesRepository();
      final c = makeContainer(repo);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;

      await readSeries(c);

      expect(repo.callCount, 1);
      expect(repo.calls, [AnalyticsRange.last7]);
    });

    test('B. re-reading the SAME key reuses the entry — the tab-away-and-back '
        'case', () async {
      final repo = _CountingSeriesRepository();
      final c = makeContainer(repo);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;

      final first = await readSeries(c);
      final second = await readSeries(c);

      expect(repo.callCount, 1, reason: 'returning must not refetch');
      expect(identical(first, second), isTrue, reason: 'same cached instance');
    });

    test('C. last7 -> last30 issues exactly ONE more request', () async {
      final repo = _CountingSeriesRepository();
      final c = makeContainer(repo);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);

      c.read(reportRangeProvider.notifier).state = ReportRange.last30;
      await readSeries(c);

      expect(repo.callCount, 2);
      expect(repo.calls, [AnalyticsRange.last7, AnalyticsRange.last30]);
    });

    test('D. returning to a retained last7 adds NO request', () async {
      final repo = _CountingSeriesRepository();
      final c = makeContainer(repo);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);
      c.read(reportRangeProvider.notifier).state = ReportRange.last30;
      await readSeries(c);
      expect(repo.callCount, 2);

      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);

      expect(repo.callCount, 2, reason: 'last7 was already loaded');
    });

    test('passing THROUGH today does not disturb the retained multi-day '
        'entries', () async {
      final repo = _CountingSeriesRepository();
      final c = makeContainer(repo);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);

      c.read(reportRangeProvider.notifier).state = ReportRange.today;
      await readSeries(c);
      expect(repo.callCount, 1, reason: 'today issues nothing');

      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);
      expect(repo.callCount, 1, reason: 'and last7 is still cached');
    });

    test('E. a different BRANCH is a different request', () async {
      final repoA = _CountingSeriesRepository();
      final a = makeContainer(repoA);
      a.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(a);

      final repoB = _CountingSeriesRepository();
      final b = makeContainer(repoB, membership: _membershipOtherBranch);
      b.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(b);

      expect(
        a.read(currentOwnerSalesSeriesKeyProvider),
        isNot(b.read(currentOwnerSalesSeriesKeyProvider)),
      );
      expect(repoB.callCount, 1, reason: 'must not reuse the other branch');
    });

    test('E2. a different ORG/RESTAURANT is a different request', () async {
      final repo = _CountingSeriesRepository();
      final c = makeContainer(repo, membership: _membershipOtherOrg);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);

      final key = c.read(currentOwnerSalesSeriesKeyProvider)!;
      expect(key.organizationId, 'org-2');
      expect(key.restaurantId, 'rest-9');
      expect(key.branchId, 'branch-9');
      expect(repo.callCount, 1);
    });

    test('F. separate containers share nothing', () async {
      final repoA = _CountingSeriesRepository();
      final repoB = _CountingSeriesRepository();
      final a = makeContainer(repoA);
      final b = makeContainer(repoB);
      a.read(reportRangeProvider.notifier).state = ReportRange.last7;
      b.read(reportRangeProvider.notifier).state = ReportRange.last7;

      await readSeries(a);
      await readSeries(b);

      expect(repoA.callCount, 1);
      expect(repoB.callCount, 1);
    });

    test(
      'concurrent readers of one key share a single in-flight request',
      () async {
        final repo = _CountingSeriesRepository();
        final c = makeContainer(repo);
        c.read(reportRangeProvider.notifier).state = ReportRange.last7;

        final results = await Future.wait([
          readSeries(c),
          readSeries(c),
          readSeries(c),
        ]);

        expect(repo.callCount, 1);
        expect(results, hasLength(3));
      },
    );

    test('a FAILED entry is retryable, not permanently poisoned', () async {
      final repo = _CountingSeriesRepository(failTimes: 1);
      final c = makeContainer(repo);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;

      await expectLater(
        readSeries(c),
        throwsA(isA<OwnerSalesSeriesException>()),
      );
      expect(repo.callCount, 1);

      c.invalidate(
        ownerSalesSeriesForKeyProvider(
          c.read(currentOwnerSalesSeriesKeyProvider)!,
        ),
      );
      final recovered = await readSeries(c);

      expect(repo.callCount, 2);
      expect(recovered, isA<OwnerSalesSeries>());
    });

    test('refreshing the series does NOT refetch another range', () async {
      final repo = _CountingSeriesRepository();
      final c = makeContainer(repo);
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);
      c.read(reportRangeProvider.notifier).state = ReportRange.last30;
      await readSeries(c);
      expect(repo.callCount, 2);

      c.invalidate(
        ownerSalesSeriesForKeyProvider(
          c.read(currentOwnerSalesSeriesKeyProvider)!,
        ),
      );
      await readSeries(c);
      expect(repo.callCount, 3);

      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await readSeries(c);
      expect(repo.callCount, 3, reason: 'the other range was not invalidated');
    });
  });
}
