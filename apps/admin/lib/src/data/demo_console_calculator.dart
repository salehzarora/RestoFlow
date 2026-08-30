/// The DEMO platform-console calculator (ADMIN-125C.2): derives every console
/// page from a structured [PlatformDataset].
///
/// Pure and deterministic — no clock, no randomness, no backend. Each function
/// mirrors the semantics of its ADMIN-125C.1 server counterpart so the demo and
/// real repositories are interchangeable behind [PlatformAdminRepository]:
///
///   * filters are applied BEFORE the total is counted, so `totalCount` is the
///     filtered total (not the platform total and not the page length);
///   * `period_end` sorts put tenants with NO subscription LAST in both
///     directions, matching the server's `nulls last`;
///   * the restaurant search matches the restaurant name OR its organization
///     name, as the server's does;
///   * the audit feed pages by KEYSET on `(occurred_at, id)` descending and
///     answers `hasMore` by looking one row past the page — the same trick the
///     server uses to avoid a second count.
///
/// Where the server would clamp or reject, this clamps or rejects identically,
/// so a bug that only shows up under a filter cannot hide in demo mode.
library;

import 'console_models.dart';
import 'platform_admin_source.dart';

/// Clamps a page size the way the server does (`[1, 200]`).
int clampConsoleLimit(int limit) => limit < 1 ? 1 : (limit > 200 ? 200 : limit);

/// Case-insensitive "contains", with an empty/blank needle meaning "no filter".
bool _matches(String haystack, String? needle) {
  final q = needle?.trim().toLowerCase() ?? '';
  return q.isEmpty || haystack.toLowerCase().contains(q);
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

/// Computes the [ConsoleOverview] for [data].
ConsoleOverview computeConsoleOverview(PlatformDataset data) {
  final orgs = data.organizations;
  var trialing = 0, active = 0, pastDue = 0, canceled = 0;
  for (final org in orgs) {
    switch (org.subscription?.status) {
      case 'trialing':
        trialing++;
      case 'active':
        active++;
      case 'past_due':
        pastDue++;
      case 'canceled':
        canceled++;
      default:
        break;
    }
  }
  return ConsoleOverview(
    organizationsTotal: orgs.length,
    organizationsActive: orgs.where((o) => o.status == 'active').length,
    organizationsSuspended: orgs.where((o) => o.status == 'suspended').length,
    restaurantsTotal: orgs.fold<int>(0, (s, o) => s + o.restaurants.length),
    branchesTotal: orgs.fold<int>(0, (s, o) => s + o.branchCount),
    activeMembershipsTotal: orgs.fold<int>(
      0,
      (s, o) => s + o.activeMembershipCount,
    ),
    subscriptionsTrialing: trialing,
    subscriptionsActive: active,
    subscriptionsPastDue: pastDue,
    subscriptionsCanceled: canceled,
    serverDateLabel: data.serverDateLabel,
  );
}

// ---------------------------------------------------------------------------
// Subscribers
// ---------------------------------------------------------------------------

SubscriberRow _rowOf(PlatformOrganization org) {
  final sub = org.subscription;
  return SubscriberRow(
    organizationId: org.id,
    organizationName: org.name,
    organizationStatus: org.status,
    createdAtLabel: org.createdAtLabel,
    defaultCurrency: org.defaultCurrency,
    restaurantsCount: org.restaurants.length,
    branchesCount: org.branchCount,
    activeMembershipsCount: org.activeMembershipCount,
    planCode: sub?.planCode,
    planDisplayName: sub?.planDisplayName,
    subscriptionStatus: sub?.status,
    currentPeriodStartLabel: sub?.currentPeriodStartLabel,
    currentPeriodEndLabel: sub?.currentPeriodEndLabel,
  );
}

/// Applies [query] to [data] exactly as `platform_admin_list_subscribers` does.
SubscriberPage computeSubscriberPage(
  PlatformDataset data,
  SubscriberQuery query,
) {
  final limit = clampConsoleLimit(query.limit);
  final offset = query.offset < 0 ? 0 : query.offset;

  final filtered = data.organizations.where((org) {
    if (!_matches(org.name, query.search)) return false;
    if (query.organizationStatus != null &&
        org.status != query.organizationStatus) {
      return false;
    }
    // Filtering BY a subscription attribute necessarily excludes tenants that
    // have no subscription — the same inner-join effect the server's predicate
    // produces, and the intended meaning of these two filters.
    if (query.planCode != null &&
        org.subscription?.planCode != query.planCode) {
      return false;
    }
    if (query.subscriptionStatus != null &&
        org.subscription?.status != query.subscriptionStatus) {
      return false;
    }
    return true;
  }).toList();

  int byName(PlatformOrganization a, PlatformOrganization b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  int byCreated(PlatformOrganization a, PlatformOrganization b) =>
      a.createdAtLabel.compareTo(b.createdAtLabel);
  // `nulls last` in BOTH directions: a tenant with no period end is not
  // "earliest" or "latest", it is absent, so it never displaces a real date.
  int byPeriodEnd(PlatformOrganization a, PlatformOrganization b, bool asc) {
    final x = a.subscription?.currentPeriodEndLabel;
    final y = b.subscription?.currentPeriodEndLabel;
    if (x == null && y == null) return byName(a, b);
    if (x == null) return 1;
    if (y == null) return -1;
    final cmp = asc ? x.compareTo(y) : y.compareTo(x);
    return cmp != 0 ? cmp : byName(a, b);
  }

  filtered.sort(switch (query.sort) {
    SubscriberSort.nameAsc => byName,
    SubscriberSort.nameDesc => (a, b) => byName(b, a),
    SubscriberSort.createdAsc => (a, b) {
      final c = byCreated(a, b);
      return c != 0 ? c : byName(a, b);
    },
    SubscriberSort.createdDesc => (a, b) {
      final c = byCreated(b, a);
      return c != 0 ? c : byName(a, b);
    },
    SubscriberSort.periodEndAsc => (a, b) => byPeriodEnd(a, b, true),
    SubscriberSort.periodEndDesc => (a, b) => byPeriodEnd(a, b, false),
  });

  final page = filtered.skip(offset).take(limit).map(_rowOf).toList();
  return SubscriberPage(
    rows: page,
    totalCount: filtered.length,
    limit: limit,
    offset: offset,
  );
}

/// Resolves one subscriber detail, or null when [organizationId] is unknown —
/// the caller turns that into the same access-denied failure the server raises,
/// so demo mode cannot be used to probe which ids exist either.
SubscriberDetail? computeSubscriberDetail(
  PlatformDataset data,
  String organizationId,
) {
  PlatformOrganization? found;
  for (final org in data.organizations) {
    if (org.id == organizationId) {
      found = org;
      break;
    }
  }
  if (found == null) return null;
  final org = found;
  final sub = org.subscription;
  return SubscriberDetail(
    organization: SubscriberOrganization(
      id: org.id,
      name: org.name,
      status: org.status,
      defaultCurrency: org.defaultCurrency,
      createdAtLabel: org.createdAtLabel,
    ),
    counts: SubscriberCounts(
      restaurantsCount: org.restaurants.length,
      branchesCount: org.branchCount,
      activeMembershipsCount: org.activeMembershipCount,
    ),
    subscription: sub == null
        ? null
        : SubscriptionInfo(
            planCode: sub.planCode,
            planDisplayName: sub.planDisplayName,
            status: sub.status,
            currentPeriodStartLabel: sub.currentPeriodStartLabel,
            currentPeriodEndLabel: sub.currentPeriodEndLabel,
          ),
    ownerContacts: org.ownerContacts,
    restaurants: [
      for (final r in org.restaurants)
        SubscriberRestaurant(
          id: r.id,
          name: r.name,
          status: r.status,
          branchesCount: r.branchCount,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );
}

// ---------------------------------------------------------------------------
// Restaurants
// ---------------------------------------------------------------------------

/// Applies [query] to [data] exactly as `platform_admin_list_restaurants` does.
RestaurantPage computeRestaurantPage(
  PlatformDataset data,
  RestaurantQuery query,
) {
  final limit = clampConsoleLimit(query.limit);
  final offset = query.offset < 0 ? 0 : query.offset;

  final all = <(PlatformOrganization, PlatformRestaurant)>[
    for (final org in data.organizations)
      for (final r in org.restaurants) (org, r),
  ];

  final filtered = all.where((pair) {
    final (org, r) = pair;
    // The search spans BOTH names: an operator hunting a tenant by its
    // organization name should still find its restaurants.
    if (!(_matches(r.name, query.search) || _matches(org.name, query.search))) {
      return false;
    }
    if (query.organizationStatus != null &&
        org.status != query.organizationStatus) {
      return false;
    }
    return true;
  }).toList();

  int byRestaurant(
    (PlatformOrganization, PlatformRestaurant) a,
    (PlatformOrganization, PlatformRestaurant) b,
  ) => a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
  int byOrg(
    (PlatformOrganization, PlatformRestaurant) a,
    (PlatformOrganization, PlatformRestaurant) b,
  ) => a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase());
  int byCreated(
    (PlatformOrganization, PlatformRestaurant) a,
    (PlatformOrganization, PlatformRestaurant) b,
  ) => a.$2.createdAtLabel.compareTo(b.$2.createdAtLabel);

  filtered.sort(switch (query.sort) {
    RestaurantSort.nameAsc => byRestaurant,
    RestaurantSort.nameDesc => (a, b) => byRestaurant(b, a),
    RestaurantSort.createdAsc => (a, b) {
      final c = byCreated(a, b);
      return c != 0 ? c : byRestaurant(a, b);
    },
    RestaurantSort.createdDesc => (a, b) {
      final c = byCreated(b, a);
      return c != 0 ? c : byRestaurant(a, b);
    },
    RestaurantSort.organizationAsc => (a, b) {
      final c = byOrg(a, b);
      return c != 0 ? c : byRestaurant(a, b);
    },
    RestaurantSort.organizationDesc => (a, b) {
      final c = byOrg(b, a);
      return c != 0 ? c : byRestaurant(a, b);
    },
  });

  final rows = [
    for (final (org, r) in filtered.skip(offset).take(limit))
      RestaurantRow(
        restaurantId: r.id,
        restaurantName: r.name,
        restaurantStatus: r.status,
        organizationId: org.id,
        organizationName: org.name,
        organizationStatus: org.status,
        branchesCount: r.branchCount,
        createdAtLabel: r.createdAtLabel,
        currencyOverride: r.currencyOverride,
        effectiveCurrency: r.currencyOverride ?? org.defaultCurrency,
      ),
  ];
  return RestaurantPage(
    rows: rows,
    totalCount: filtered.length,
    limit: limit,
    offset: offset,
  );
}

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

/// Applies [query] to [data] exactly as `platform_admin_audit_search` does,
/// including the keyset cursor and the fetch-one-extra `hasMore`.
AuditPage computeAuditPage(PlatformDataset data, AuditQuery query) {
  final limit = clampConsoleLimit(query.limit);

  final filtered =
      data.auditEvents.where((e) {
          if (query.action != null && e.action != query.action) return false;
          if (query.targetOrganizationId != null &&
              e.targetOrganizationId != query.targetOrganizationId) {
            return false;
          }
          if (query.from != null &&
              e.occurredAtRaw.compareTo(query.from!) < 0) {
            return false;
          }
          if (query.to != null && e.occurredAtRaw.compareTo(query.to!) > 0) {
            return false;
          }
          return true;
        }).toList()
        // Newest first, id breaking ties — the exact server ORDER BY, and the
        // total order a keyset cursor requires.
        ..sort((a, b) {
          final c = b.occurredAtRaw.compareTo(a.occurredAtRaw);
          return c != 0 ? c : b.id.compareTo(a.id);
        });

  final cursor = query.cursor;
  final after = cursor == null
      ? filtered
      : filtered.where((e) {
          final c = e.occurredAtRaw.compareTo(cursor.occurredAt);
          // Strictly BEFORE the cursor row, comparing the pair — not just the
          // timestamp, or rows sharing a timestamp would be skipped.
          return c < 0 || (c == 0 && e.id.compareTo(cursor.id) < 0);
        }).toList();

  // One past the page answers hasMore without counting the whole log.
  final window = after.take(limit + 1).toList();
  final hasMore = window.length > limit;
  final pageSeeds = hasMore ? window.take(limit).toList() : window;
  final rows = [
    for (final e in pageSeeds)
      AuditEvent(
        id: e.id,
        actorAppUserId: e.actorAppUserId,
        action: e.action,
        reason: e.reason,
        occurredAtRaw: e.occurredAtRaw,
        targetOrganizationId: e.targetOrganizationId,
      ),
  ];
  return AuditPage(
    rows: rows,
    hasMore: hasMore,
    limit: limit,
    nextCursor: hasMore && rows.isNotEmpty
        ? AuditCursor(occurredAt: rows.last.occurredAtRaw, id: rows.last.id)
        : null,
  );
}

/// The distinct audit actions present in [data], newest-first order irrelevant —
/// sorted alphabetically so the console's action filter is stable. Derived, so a
/// new demo action shows up in the filter without a second edit.
List<String> demoAuditActions(PlatformDataset data) =>
    (data.auditEvents.map((e) => e.action).toSet().toList())..sort();

// ---------------------------------------------------------------------------
// Restaurant operations (ADMIN-126)
// ---------------------------------------------------------------------------

/// Applies [query] to [data] exactly as
/// `platform_admin_restaurant_operations` does — same filters, same sorts, same
/// per-currency totalling, and the same refusal to add currencies together.
RestaurantOperationsPage computeRestaurantOperationsPage(
  PlatformDataset data,
  RestaurantOperationsQuery query,
) {
  final limit = clampConsoleLimit(query.limit);
  final offset = query.offset < 0 ? 0 : query.offset;

  var pairs =
      <(PlatformOrganization, PlatformRestaurant)>[
        for (final org in data.organizations)
          for (final r in org.restaurants) (org, r),
      ].where((pair) {
        final (org, r) = pair;
        if (!(_matches(r.name, query.search) ||
            _matches(org.name, query.search))) {
          return false;
        }
        if (query.organizationStatus != null &&
            org.status != query.organizationStatus) {
          return false;
        }
        return true;
      }).toList();

  // The with/without-sales filter is applied BEFORE the total is counted, so
  // the pager describes the filtered set rather than the platform.
  if (query.withSales != null) {
    pairs = pairs
        .where((p) => (p.$2.todayRevenueMinor != 0) == query.withSales)
        .toList();
  }

  int byRestaurant(
    (PlatformOrganization, PlatformRestaurant) a,
    (PlatformOrganization, PlatformRestaurant) b,
  ) => a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());

  pairs.sort((a, b) {
    final primary = switch (query.sort) {
      RestaurantOperationsSort.nameAsc => byRestaurant(a, b),
      RestaurantOperationsSort.nameDesc => byRestaurant(b, a),
      RestaurantOperationsSort.organizationAsc =>
        a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase()),
      RestaurantOperationsSort.organizationDesc =>
        b.$1.name.toLowerCase().compareTo(a.$1.name.toLowerCase()),
      // Money is compared as integer minor units. Across currencies this is an
      // ORDERING only — the figures are never added, and the UI shows each row
      // in its own currency.
      RestaurantOperationsSort.salesDesc => b.$2.todayRevenueMinor.compareTo(
        a.$2.todayRevenueMinor,
      ),
      RestaurantOperationsSort.salesAsc => a.$2.todayRevenueMinor.compareTo(
        b.$2.todayRevenueMinor,
      ),
      RestaurantOperationsSort.ordersDesc => b.$2.todayOrdersCount.compareTo(
        a.$2.todayOrdersCount,
      ),
      RestaurantOperationsSort.ordersAsc => a.$2.todayOrdersCount.compareTo(
        b.$2.todayOrdersCount,
      ),
    };
    // Name is the tiebreaker for every sort, so paging is stable: without a
    // total order two equal-revenue restaurants could swap between pages and
    // one would vanish.
    return primary != 0 ? primary : byRestaurant(a, b);
  });

  final rows = [
    for (final (org, r) in pairs.skip(offset).take(limit))
      RestaurantOperationsRow(
        restaurantId: r.id,
        restaurantName: r.name,
        restaurantStatus: r.status,
        organizationId: org.id,
        organizationName: org.name,
        organizationStatus: org.status,
        branchesCount: r.branchCount,
        currencyCode: r.currencyOverride ?? org.defaultCurrency,
        reportingDate: data.serverDateLabel,
        todayOrdersCount: r.todayOrdersCount,
        todayRevenueMinor: r.todayRevenueMinor,
        ownerContacts: org.ownerContacts,
      ),
  ];

  // Totals GROUPED BY CURRENCY, over the whole filtered set (not the page).
  final byCurrency = <String, CurrencyDayTotal>{};
  for (final (org, r) in pairs) {
    final code = r.currencyOverride ?? org.defaultCurrency;
    final prior = byCurrency[code];
    byCurrency[code] = CurrencyDayTotal(
      currencyCode: code,
      restaurantsCount: (prior?.restaurantsCount ?? 0) + 1,
      todayOrdersCount: (prior?.todayOrdersCount ?? 0) + r.todayOrdersCount,
      todayRevenueMinor: (prior?.todayRevenueMinor ?? 0) + r.todayRevenueMinor,
    );
  }
  final totals = byCurrency.values.toList()
    ..sort((a, b) => a.currencyCode.compareTo(b.currencyCode));

  return RestaurantOperationsPage(
    rows: rows,
    totalCount: pairs.length,
    totalsByCurrency: totals,
    limit: limit,
    offset: offset,
  );
}
