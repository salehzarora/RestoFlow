/// ADMIN-125C.2 — the DEMO console calculator.
///
/// Proves every demo figure is DERIVED from the structured dataset rather than
/// hardcoded, and — more importantly — that the demo semantics match the
/// server's. If the demo calculator and the SQL disagree about `nulls last`, or
/// about whether a subscription filter excludes unsubscribed tenants, then every
/// widget test above is proving the wrong contract.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/demo_console_calculator.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';

void main() {
  final data = demoPlatformDataset();

  group('overview', () {
    test('every count is derived from the dataset', () {
      final overview = computeConsoleOverview(data);
      expect(overview.organizationsTotal, data.organizations.length);
      expect(overview.organizationsActive, 4);
      expect(overview.organizationsSuspended, 1);
      expect(
        overview.restaurantsTotal,
        data.organizations.fold<int>(0, (s, o) => s + o.restaurants.length),
      );
      expect(overview.branchesTotal, 8);
      expect(overview.activeMembershipsTotal, 23);
      expect(overview.subscriptionsTrialing, 1);
      expect(overview.subscriptionsActive, 1);
      expect(overview.subscriptionsPastDue, 1);
      expect(overview.subscriptionsCanceled, 1);
      // Five tenants, four subscriptions: the states do not sum to the total.
      expect(overview.hasNoSubscriptions, isFalse);
      expect(overview.isEmpty, isFalse);
    });

    test('an empty platform is empty; an unsubscribed one is not', () {
      expect(computeConsoleOverview(emptyPlatformDataset()).isEmpty, isTrue);
      final unsubscribed = computeConsoleOverview(
        unsubscribedPlatformDataset(),
      );
      expect(unsubscribed.isEmpty, isFalse);
      expect(unsubscribed.organizationsTotal, 5);
      expect(unsubscribed.hasNoSubscriptions, isTrue);
    });
  });

  group('subscribers', () {
    test('the default page is name-ascending and carries the total', () {
      final page = computeSubscriberPage(data, const SubscriberQuery());
      expect(page.totalCount, 5);
      expect(page.rows.map((r) => r.organizationName), [
        'Bistro Group',
        'Cafe Noor',
        'Olive Tree',
        'Pizza Plaza',
        'Sahara Grill',
      ]);
      expect(page.firstRowNumber, 1);
      expect(page.lastRowNumber, 5);
      expect(page.hasPrevious, isFalse);
      expect(page.hasNext, isFalse);
    });

    test('every row carries its organization id', () {
      final page = computeSubscriberPage(data, const SubscriberQuery());
      expect(page.rows.every((r) => r.organizationId.isNotEmpty), isTrue);
      expect(
        page.rows.map((r) => r.organizationId).toSet(),
        hasLength(page.rows.length),
      );
    });

    test('totalCount is the FILTERED total, not the platform total', () {
      final page = computeSubscriberPage(
        data,
        const SubscriberQuery(organizationStatus: 'suspended'),
      );
      expect(page.totalCount, 1);
      expect(page.rows.single.organizationName, 'Pizza Plaza');
    });

    test('paging keeps the filtered total and moves the window', () {
      final first = computeSubscriberPage(
        data,
        const SubscriberQuery(limit: 2),
      );
      expect(first.totalCount, 5);
      expect(first.rows, hasLength(2));
      expect(first.hasNext, isTrue);
      expect(first.hasPrevious, isFalse);

      final second = computeSubscriberPage(
        data,
        const SubscriberQuery(limit: 2, offset: 2),
      );
      expect(second.firstRowNumber, 3);
      expect(second.lastRowNumber, 4);
      expect(second.hasPrevious, isTrue);
      expect(second.hasNext, isTrue);

      final last = computeSubscriberPage(
        data,
        const SubscriberQuery(limit: 2, offset: 4),
      );
      expect(last.rows, hasLength(1));
      expect(last.hasNext, isFalse);
    });

    test('search is case-insensitive and blank means no filter', () {
      expect(
        computeSubscriberPage(
          data,
          const SubscriberQuery(search: 'BISTRO'),
        ).totalCount,
        1,
      );
      expect(
        computeSubscriberPage(
          data,
          const SubscriberQuery(search: '   '),
        ).totalCount,
        5,
      );
    });

    test(
      'a subscription filter excludes tenants that have NO subscription',
      () {
        final page = computeSubscriberPage(
          data,
          const SubscriberQuery(subscriptionStatus: 'active'),
        );
        expect(page.rows.map((r) => r.organizationName), ['Bistro Group']);
        // Pizza Plaza has no subscription, so it cannot match a subscription
        // status — the same inner-join effect the server predicate has.
        expect(
          page.rows.any((r) => r.organizationName == 'Pizza Plaza'),
          isFalse,
        );
      },
    );

    test('a plan filter behaves the same way', () {
      expect(
        computeSubscriberPage(
          data,
          const SubscriberQuery(planCode: 'free'),
        ).rows.map((r) => r.organizationName),
        ['Cafe Noor'],
      );
    });

    test('period-end sorts put tenants with NO subscription LAST in BOTH '
        'directions', () {
      final asc = computeSubscriberPage(
        data,
        const SubscriberQuery(sort: SubscriberSort.periodEndAsc),
      );
      final desc = computeSubscriberPage(
        data,
        const SubscriberQuery(sort: SubscriberSort.periodEndDesc),
      );
      // A tenant with no period end is not "earliest" or "latest" — it is
      // absent, so it must never displace a real date at either end.
      expect(asc.rows.last.organizationName, 'Pizza Plaza');
      expect(desc.rows.last.organizationName, 'Pizza Plaza');
      expect(asc.rows.first.organizationName, 'Olive Tree'); // 2026-05-10
      expect(desc.rows.first.organizationName, 'Cafe Noor'); // 2026-07-15
    });

    test('name and created sorts are exact', () {
      expect(
        computeSubscriberPage(
          data,
          const SubscriberQuery(sort: SubscriberSort.nameDesc),
        ).rows.first.organizationName,
        'Sahara Grill',
      );
      expect(
        computeSubscriberPage(
          data,
          const SubscriberQuery(sort: SubscriberSort.createdAsc),
        ).rows.first.organizationName,
        'Olive Tree', // 2026-02-10
      );
      expect(
        computeSubscriberPage(
          data,
          const SubscriberQuery(sort: SubscriberSort.createdDesc),
        ).rows.first.organizationName,
        'Pizza Plaza', // 2026-05-20
      );
    });

    test('the page size is clamped the way the server clamps it', () {
      expect(clampConsoleLimit(0), 1);
      expect(clampConsoleLimit(9999), 200);
      expect(clampConsoleLimit(25), 25);
      expect(
        computeSubscriberPage(data, const SubscriberQuery(limit: 9999)).limit,
        200,
      );
    });

    test('the wire sort values match the server vocabulary exactly', () {
      expect(SubscriberSort.values.map((s) => s.wire), [
        'name_asc',
        'name_desc',
        'created_asc',
        'created_desc',
        'period_end_asc',
        'period_end_desc',
      ]);
      expect(RestaurantSort.values.map((s) => s.wire), [
        'name_asc',
        'name_desc',
        'created_asc',
        'created_desc',
        'organization_asc',
        'organization_desc',
      ]);
    });
  });

  group('subscriber detail', () {
    test('resolves counts, subscription and restaurants', () {
      final detail = computeSubscriberDetail(
        data,
        'd0000000-0000-4000-8000-0000000000a1',
      )!;
      expect(detail.organization.name, 'Bistro Group');
      expect(detail.counts.restaurantsCount, 2);
      expect(detail.counts.branchesCount, 3);
      expect(detail.counts.activeMembershipsCount, 9);
      expect(detail.subscription!.planCode, 'basic');
      expect(detail.restaurants.map((r) => r.name), [
        'Bistro Downtown',
        'Bistro Seaside',
      ]);
    });

    test('a tenant with no subscription resolves with a NULL subscription', () {
      final detail = computeSubscriberDetail(
        data,
        'd0000000-0000-4000-8000-0000000000a5',
      )!;
      expect(detail.hasSubscription, isFalse);
      expect(detail.subscription, isNull);
    });

    test('an unknown id resolves to null (the caller denies)', () {
      expect(computeSubscriberDetail(data, 'nope'), isNull);
    });
  });

  group('restaurants', () {
    test('flattens every restaurant with its organization', () {
      final page = computeRestaurantPage(data, const RestaurantQuery());
      expect(page.totalCount, 6);
      expect(page.rows.first.restaurantName, 'Bistro Downtown');
      expect(page.rows.first.organizationName, 'Bistro Group');
    });

    test(
      'effective currency is the override, else the organization default',
      () {
        final page = computeRestaurantPage(data, const RestaurantQuery());
        final olive = page.rows.firstWhere(
          (r) => r.restaurantName == 'Olive Tree Bistro',
        );
        expect(olive.currencyOverride, 'EUR');
        expect(olive.effectiveCurrency, 'EUR');
        expect(olive.hasCurrencyOverride, isTrue);

        final bistro = page.rows.firstWhere(
          (r) => r.restaurantName == 'Bistro Downtown',
        );
        expect(bistro.currencyOverride, isNull);
        expect(bistro.effectiveCurrency, 'USD');
        expect(bistro.hasCurrencyOverride, isFalse);
      },
    );

    test('search spans the restaurant name AND the organization name', () {
      // "Pizza Plaza" is both here, so use a tenant whose restaurant is named
      // differently: Cafe Noor's restaurant is "Cafe Noor Central" — instead
      // search a tenant name that its restaurant does NOT contain.
      final byOrg = computeRestaurantPage(
        data,
        const RestaurantQuery(search: 'Olive Tree'),
      );
      expect(byOrg.rows.single.restaurantName, 'Olive Tree Bistro');

      final byRestaurant = computeRestaurantPage(
        data,
        const RestaurantQuery(search: 'Seaside'),
      );
      expect(byRestaurant.rows.single.organizationName, 'Bistro Group');
    });

    test('the organization-status filter follows the ORGANIZATION', () {
      final page = computeRestaurantPage(
        data,
        const RestaurantQuery(organizationStatus: 'suspended'),
      );
      // The restaurant itself is active; its organization is not.
      expect(page.rows.single.restaurantName, 'Pizza Plaza HQ');
      expect(page.rows.single.restaurantStatus, 'active');
      expect(page.rows.single.organizationStatus, 'suspended');
    });

    test('organization sorts group by tenant', () {
      final asc = computeRestaurantPage(
        data,
        const RestaurantQuery(sort: RestaurantSort.organizationAsc),
      );
      expect(asc.rows.first.organizationName, 'Bistro Group');
      final desc = computeRestaurantPage(
        data,
        const RestaurantQuery(sort: RestaurantSort.organizationDesc),
      );
      expect(desc.rows.first.organizationName, 'Sahara Grill');
    });
  });

  group('audit', () {
    test('is newest-first and pages by keyset', () {
      final page1 = computeAuditPage(data, const AuditQuery(limit: 10));
      expect(page1.rows, hasLength(10));
      expect(page1.hasMore, isTrue);
      expect(page1.nextCursor, isNotNull);
      expect(page1.rows.first.occurredAtRaw, '2026-06-28T09:10:00Z');

      final page2 = computeAuditPage(
        data,
        AuditQuery(limit: 10, cursor: page1.nextCursor),
      );
      // No duplicate and no gap across the boundary.
      final ids1 = page1.rows.map((e) => e.id).toSet();
      final ids2 = page2.rows.map((e) => e.id).toSet();
      expect(ids1.intersection(ids2), isEmpty);
      expect(page2.rows.first.occurredAtRaw, '2026-06-27T09:10:00Z');

      final page3 = computeAuditPage(
        data,
        AuditQuery(limit: 10, cursor: page2.nextCursor),
      );
      expect(page3.rows, hasLength(10));
      expect(page3.hasMore, isFalse);
      expect(page3.nextCursor, isNull);
      // Thirty rows, no row seen twice.
      expect({...ids1, ...ids2, ...page3.rows.map((e) => e.id)}, hasLength(30));
    });

    test('filters by action, target and an inclusive range', () {
      expect(
        computeAuditPage(
          data,
          const AuditQuery(action: 'platform.restaurants.list'),
        ).rows,
        hasLength(3),
      );
      expect(
        computeAuditPage(
          data,
          const AuditQuery(
            targetOrganizationId: 'd0000000-0000-4000-8000-0000000000a2',
          ),
        ).rows,
        hasLength(3),
      );
      final ranged = computeAuditPage(
        data,
        const AuditQuery(
          from: '2026-06-27T00:00:00Z',
          to: '2026-06-27T23:59:59Z',
        ),
      );
      expect(ranged.rows, hasLength(10));
      expect(
        ranged.rows.every((e) => e.occurredAtRaw.startsWith('2026-06-27')),
        isTrue,
      );
    });

    test(
      'a row exposes short ids and keeps the RAW timestamp for the cursor',
      () {
        final page = computeAuditPage(data, const AuditQuery(limit: 1));
        final row = page.rows.single;
        expect(row.actorShortId, hasLength(8));
        expect(row.actorShortId, 'd0000000');
        expect(row.occurredAtRaw, '2026-06-28T09:10:00Z');
        expect(row.occurredAtLabel, '2026-06-28 09:10');
        // The cursor is built from the RAW value, not the display label — a lossy
        // round-trip here would skip or repeat rows at the page boundary.
        expect(page.nextCursor!.occurredAt, row.occurredAtRaw);
      },
    );

    test('a platform-wide row has no target', () {
      final page = computeAuditPage(
        data,
        const AuditQuery(action: 'platform.console.overview'),
      );
      expect(page.rows.every((e) => e.targetOrganizationId == null), isTrue);
      expect(page.rows.every((e) => e.targetShortId == null), isTrue);
    });

    test('resetToFirstPage drops the cursor but keeps the filters', () {
      const query = AuditQuery(
        action: 'platform.audit.search',
        cursor: AuditCursor(occurredAt: 'x', id: 'y'),
      );
      final reset = query.resetToFirstPage();
      expect(reset.cursor, isNull);
      expect(reset.action, 'platform.audit.search');
    });
  });

  group('query value semantics', () {
    test('copyWith can CLEAR a filter, not just replace it', () {
      const query = SubscriberQuery(search: 'x', organizationStatus: 'active');
      expect(query.copyWith(search: null).search, isNull);
      // An omitted argument keeps the existing value.
      expect(query.copyWith(offset: 5).search, 'x');
      expect(query.copyWith(offset: 5).organizationStatus, 'active');
    });

    test('queries compare by value, so a provider family can key on them', () {
      expect(const SubscriberQuery(), const SubscriberQuery());
      expect(
        const SubscriberQuery(offset: 1) == const SubscriberQuery(),
        isFalse,
      );
      expect(const RestaurantQuery(), const RestaurantQuery());
      expect(const AuditQuery(), const AuditQuery());
    });

    test('shortId is safe on a short input', () {
      expect(shortId('abc'), 'abc');
      expect(shortId('0123456789'), '01234567');
    });
  });
}
