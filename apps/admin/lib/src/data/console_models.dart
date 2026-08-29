/// The Platform Console V1 read models (ADMIN-125C.2).
///
/// These are the immutable shapes the console pages render, and they mirror the
/// ADMIN-125C.1 read contract 1:1 (migration
/// `20260902090000_platform_admin_console_reads_125c1.sql`):
///
///   * `public.platform_admin_console_overview`  -> [ConsoleOverview]
///   * `public.platform_admin_list_subscribers`  -> [SubscriberPage]
///   * `public.platform_admin_get_subscriber`    -> [SubscriberDetail]
///   * `public.platform_admin_list_restaurants`  -> [RestaurantPage]
///   * `public.platform_admin_audit_search`      -> [AuditPage]
///
/// NULLABILITY IS THE CONTRACT, NOT AN ACCIDENT. Every production tenant today
/// has NO row in `organization_subscriptions`, so the subscription fields are
/// genuinely null on every real row. They are modelled as nullable here and the
/// UI renders an honest "no subscription" — never a fabricated plan, never a
/// silent `—` that reads like data.
///
/// Counts are plain integers. There is NO money on the platform console: plan
/// prices are deliberately not part of this read contract, so no `_minor` value
/// ever reaches this layer (DECISION D-007 cannot be violated by a surface that
/// never carries money).
library;

/// Shortens a UUID for display (`92b4483f-0be3-...` -> `92b4483f`). Platform
/// audit rows identify the actor and target by ID ONLY in this phase — no user
/// email/name resolution — so the console shows a stable prefix instead of a
/// wall of hex. Returns [id] unchanged when it is shorter than the prefix.
String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// `2026-06-28T10:15:30.123Z` -> `2026-06-28` (empty when absent/short).
String dateLabelOf(Object? iso) =>
    iso is String && iso.length >= 10 ? iso.substring(0, 10) : '';

/// `2026-06-28T10:15:30Z` -> `2026-06-28 10:15` (empty when absent/short).
String timestampLabelOf(Object? iso) => iso is String && iso.length >= 16
    ? iso.substring(0, 16).replaceFirst('T', ' ')
    : (iso is String ? iso : '');

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

/// The platform-wide counts behind the Overview page.
///
/// Every field maps to a key the server actually returns. There are NO device,
/// order or "alert" metrics here: the read contract does not provide them, and
/// inventing a `0` for a metric the platform cannot measure would be a lie the
/// operator could act on.
class ConsoleOverview {
  const ConsoleOverview({
    required this.organizationsTotal,
    required this.organizationsActive,
    required this.organizationsSuspended,
    required this.restaurantsTotal,
    required this.branchesTotal,
    required this.activeMembershipsTotal,
    required this.subscriptionsTrialing,
    required this.subscriptionsActive,
    required this.subscriptionsPastDue,
    required this.subscriptionsCanceled,
    required this.serverDateLabel,
  });

  final int organizationsTotal;
  final int organizationsActive;

  /// Organizations whose status is `suspended`. This is a SUSPENDED-SUBSCRIBER
  /// count, not an alert count — the pre-125C.2 console labelled the same number
  /// "Open alerts", which implied an operational alerting system that does not
  /// exist.
  final int organizationsSuspended;

  final int restaurantsTotal;
  final int branchesTotal;
  final int activeMembershipsTotal;

  final int subscriptionsTrialing;
  final int subscriptionsActive;
  final int subscriptionsPastDue;
  final int subscriptionsCanceled;

  /// The server's own "as of" day (`server_ts`), so the operator sees the
  /// BACKEND's clock rather than this device's.
  final String serverDateLabel;

  /// True when no organization carries a subscription in any state. Drives the
  /// honest "no subscriptions configured yet" notice instead of four zeros that
  /// look like a billing collapse.
  bool get hasNoSubscriptions =>
      subscriptionsTrialing == 0 &&
      subscriptionsActive == 0 &&
      subscriptionsPastDue == 0 &&
      subscriptionsCanceled == 0;

  /// True when the platform has no tenants at all (drives the empty state).
  bool get isEmpty => organizationsTotal == 0;
}

// ---------------------------------------------------------------------------
// Subscribers
// ---------------------------------------------------------------------------

/// How a subscriber page is ordered. The wire values are a FIXED vocabulary the
/// server validates (an unknown value raises SQLSTATE `22023`), so this enum and
/// the SQL CASE ladder cannot drift apart silently.
enum SubscriberSort {
  nameAsc('name_asc'),
  nameDesc('name_desc'),
  createdAsc('created_asc'),
  createdDesc('created_desc'),
  periodEndAsc('period_end_asc'),
  periodEndDesc('period_end_desc');

  const SubscriberSort(this.wire);

  /// The exact `p_sort` value sent to `platform_admin_list_subscribers`.
  final String wire;
}

/// The subscriber-list request. Filtering and paging happen ON THE SERVER: the
/// console never pulls an unbounded tenant list and filters it in the browser.
class SubscriberQuery {
  const SubscriberQuery({
    this.limit = kConsolePageSize,
    this.offset = 0,
    this.search,
    this.organizationStatus,
    this.planCode,
    this.subscriptionStatus,
    this.sort = SubscriberSort.nameAsc,
  });

  final int limit;
  final int offset;

  /// Free-text match on the organization name (null/empty = no filter).
  final String? search;

  /// `active` / `suspended`, or null for all.
  final String? organizationStatus;

  /// A `plans.code` value, or null for all.
  final String? planCode;

  /// `trialing` / `active` / `past_due` / `canceled`, or null for all.
  final String? subscriptionStatus;

  final SubscriberSort sort;

  SubscriberQuery copyWith({
    int? limit,
    int? offset,
    Object? search = _unset,
    Object? organizationStatus = _unset,
    Object? planCode = _unset,
    Object? subscriptionStatus = _unset,
    SubscriberSort? sort,
  }) => SubscriberQuery(
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
    search: search == _unset ? this.search : search as String?,
    organizationStatus: organizationStatus == _unset
        ? this.organizationStatus
        : organizationStatus as String?,
    planCode: planCode == _unset ? this.planCode : planCode as String?,
    subscriptionStatus: subscriptionStatus == _unset
        ? this.subscriptionStatus
        : subscriptionStatus as String?,
    sort: sort ?? this.sort,
  );

  /// A query identical to this one but back on the FIRST page. Any filter or
  /// sort change must use this: keeping the old offset after narrowing the
  /// result set is how a console shows an empty page over non-empty data.
  SubscriberQuery resetToFirstPage() => copyWith(offset: 0);

  @override
  bool operator ==(Object other) =>
      other is SubscriberQuery &&
      other.limit == limit &&
      other.offset == offset &&
      other.search == search &&
      other.organizationStatus == organizationStatus &&
      other.planCode == planCode &&
      other.subscriptionStatus == subscriptionStatus &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    limit,
    offset,
    search,
    organizationStatus,
    planCode,
    subscriptionStatus,
    sort,
  );
}

/// One subscriber (= one Organization tenant) row.
class SubscriberRow {
  const SubscriberRow({
    required this.organizationId,
    required this.organizationName,
    required this.organizationStatus,
    required this.createdAtLabel,
    required this.defaultCurrency,
    required this.restaurantsCount,
    required this.branchesCount,
    required this.activeMembershipsCount,
    this.planCode,
    this.planDisplayName,
    this.subscriptionStatus,
    this.currentPeriodStartLabel,
    this.currentPeriodEndLabel,
  });

  /// The tenant id. The console REQUIRES this to open a detail page — the
  /// pre-125C.2 client mapped organizations without it, which is why no detail
  /// view could exist.
  final String organizationId;

  /// Tenant-entered display name — data, never translated.
  final String organizationName;

  /// Raw wire status (`active` / `suspended`); tone is derived, text is not.
  final String organizationStatus;

  final String createdAtLabel;
  final String defaultCurrency;
  final int restaurantsCount;
  final int branchesCount;
  final int activeMembershipsCount;

  final String? planCode;
  final String? planDisplayName;
  final String? subscriptionStatus;
  final String? currentPeriodStartLabel;
  final String? currentPeriodEndLabel;

  /// False for every production tenant today — `organization_subscriptions` is
  /// empty until a plan is assigned (a future WRITE phase).
  bool get hasSubscription => subscriptionStatus != null;
}

/// One page of subscribers plus the FILTERED total, so the console can show
/// "showing 1-50 of N" without a second request.
class SubscriberPage {
  const SubscriberPage({
    required this.rows,
    required this.totalCount,
    required this.limit,
    required this.offset,
  });

  final List<SubscriberRow> rows;

  /// Total matching the CURRENT filters (not the page length, not the platform
  /// total).
  final int totalCount;
  final int limit;
  final int offset;

  bool get isEmpty => rows.isEmpty;
  bool get hasPrevious => offset > 0;
  bool get hasNext => offset + rows.length < totalCount;

  /// 1-based index of the first row on this page (0 when the page is empty).
  int get firstRowNumber => rows.isEmpty ? 0 : offset + 1;
  int get lastRowNumber => offset + rows.length;
}

// ---------------------------------------------------------------------------
// Subscriber detail
// ---------------------------------------------------------------------------

/// The organization summary block of a subscriber detail.
class SubscriberOrganization {
  const SubscriberOrganization({
    required this.id,
    required this.name,
    required this.status,
    required this.defaultCurrency,
    required this.createdAtLabel,
  });

  final String id;
  final String name;
  final String status;
  final String defaultCurrency;
  final String createdAtLabel;
}

/// The three tenant counts shown on a subscriber detail.
class SubscriberCounts {
  const SubscriberCounts({
    required this.restaurantsCount,
    required this.branchesCount,
    required this.activeMembershipsCount,
  });

  final int restaurantsCount;
  final int branchesCount;
  final int activeMembershipsCount;
}

/// A tenant's subscription, when one exists.
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.planCode,
    required this.planDisplayName,
    required this.status,
    this.currentPeriodStartLabel,
    this.currentPeriodEndLabel,
  });

  final String planCode;
  final String planDisplayName;
  final String status;
  final String? currentPeriodStartLabel;
  final String? currentPeriodEndLabel;
}

/// One restaurant under a subscriber.
class SubscriberRestaurant {
  const SubscriberRestaurant({
    required this.id,
    required this.name,
    required this.status,
    required this.branchesCount,
  });

  final String id;
  final String name;
  final String status;
  final int branchesCount;
}

/// A subscriber (Organization) detail.
///
/// Deliberately ABSENT: `created_by_app_user_id`, `creation_request_id`, member
/// identities, and any order/payment figure. The server does not return the
/// first two at all, and this model has nowhere to put them if it ever did.
class SubscriberDetail {
  const SubscriberDetail({
    required this.organization,
    required this.counts,
    required this.restaurants,
    this.subscription,
  });

  final SubscriberOrganization organization;
  final SubscriberCounts counts;
  final List<SubscriberRestaurant> restaurants;

  /// Null when the tenant has no `organization_subscriptions` row.
  final SubscriptionInfo? subscription;

  bool get hasSubscription => subscription != null;
}

// ---------------------------------------------------------------------------
// Restaurants
// ---------------------------------------------------------------------------

/// How a restaurant page is ordered (fixed server-validated vocabulary).
enum RestaurantSort {
  nameAsc('name_asc'),
  nameDesc('name_desc'),
  createdAsc('created_asc'),
  createdDesc('created_desc'),
  organizationAsc('organization_asc'),
  organizationDesc('organization_desc');

  const RestaurantSort(this.wire);

  final String wire;
}

/// The platform-wide restaurant-list request (server-side filter + paging).
class RestaurantQuery {
  const RestaurantQuery({
    this.limit = kConsolePageSize,
    this.offset = 0,
    this.search,
    this.organizationStatus,
    this.sort = RestaurantSort.nameAsc,
  });

  final int limit;
  final int offset;

  /// Matches the RESTAURANT name or its ORGANIZATION name (server-side).
  final String? search;
  final String? organizationStatus;
  final RestaurantSort sort;

  RestaurantQuery copyWith({
    int? limit,
    int? offset,
    Object? search = _unset,
    Object? organizationStatus = _unset,
    RestaurantSort? sort,
  }) => RestaurantQuery(
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
    search: search == _unset ? this.search : search as String?,
    organizationStatus: organizationStatus == _unset
        ? this.organizationStatus
        : organizationStatus as String?,
    sort: sort ?? this.sort,
  );

  RestaurantQuery resetToFirstPage() => copyWith(offset: 0);

  @override
  bool operator ==(Object other) =>
      other is RestaurantQuery &&
      other.limit == limit &&
      other.offset == offset &&
      other.search == search &&
      other.organizationStatus == organizationStatus &&
      other.sort == sort;

  @override
  int get hashCode =>
      Object.hash(limit, offset, search, organizationStatus, sort);
}

/// One restaurant row on the platform-wide restaurant list.
class RestaurantRow {
  const RestaurantRow({
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantStatus,
    required this.organizationId,
    required this.organizationName,
    required this.organizationStatus,
    required this.branchesCount,
    required this.createdAtLabel,
    required this.effectiveCurrency,
    this.currencyOverride,
  });

  final String restaurantId;
  final String restaurantName;
  final String restaurantStatus;
  final String organizationId;
  final String organizationName;
  final String organizationStatus;
  final int branchesCount;
  final String createdAtLabel;

  /// `coalesce(restaurants.currency_override, organizations.default_currency)`
  /// — the SAME rule the POS and menu reads apply, so the console can never
  /// quote a currency the tills disagree with.
  final String effectiveCurrency;

  /// Non-null only when this restaurant overrides its organization's currency.
  final String? currencyOverride;

  bool get hasCurrencyOverride => currencyOverride != null;
}

/// One page of restaurants plus the filtered total.
class RestaurantPage {
  const RestaurantPage({
    required this.rows,
    required this.totalCount,
    required this.limit,
    required this.offset,
  });

  final List<RestaurantRow> rows;
  final int totalCount;
  final int limit;
  final int offset;

  bool get isEmpty => rows.isEmpty;
  bool get hasPrevious => offset > 0;
  bool get hasNext => offset + rows.length < totalCount;
  int get firstRowNumber => rows.isEmpty ? 0 : offset + 1;
  int get lastRowNumber => offset + rows.length;
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

/// A keyset position in the append-only audit log. BOTH parts travel together —
/// the server rejects half a cursor with SQLSTATE `22023`, because a partial
/// cursor would silently degrade into an unbounded scan and re-serve rows the
/// operator has already seen.
class AuditCursor {
  const AuditCursor({required this.occurredAt, required this.id});

  /// The RAW server timestamp, echoed back verbatim. Never a reformatted label:
  /// a lossy round-trip here would skip or repeat rows at the page boundary.
  final String occurredAt;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is AuditCursor && other.occurredAt == occurredAt && other.id == id;

  @override
  int get hashCode => Object.hash(occurredAt, id);
}

/// One platform-admin audit row, in the SAFE projection the server returns.
///
/// The `details` jsonb is NOT part of this model. The server never returns it,
/// and there is nowhere here to put it if it did — that column can carry
/// arbitrary operational context and is not fit for a console list.
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.actorAppUserId,
    required this.action,
    required this.reason,
    required this.occurredAtRaw,
    this.targetOrganizationId,
  });

  final String id;

  /// The acting operator's app-user id. NOT resolved to an email or name in this
  /// phase — resolving platform actors to people is a PII decision of its own.
  final String actorAppUserId;

  /// Raw wire action key (`platform.subscribers.list`), deliberately
  /// untranslated: it is an audit identifier, not UI chrome.
  final String action;

  /// The reason the caller supplied. Operator-authored text, shown as-is.
  final String reason;

  /// The raw server timestamp (kept verbatim so it can seed an [AuditCursor]).
  final String occurredAtRaw;

  /// Null for platform-wide reads that target no single tenant.
  final String? targetOrganizationId;

  String get occurredAtLabel => timestampLabelOf(occurredAtRaw);

  /// The actor id shortened for display.
  String get actorShortId => shortId(actorAppUserId);

  /// The target tenant id shortened for display, or null when platform-wide.
  String? get targetShortId {
    final target = targetOrganizationId;
    return target == null ? null : shortId(target);
  }
}

/// The audit-log request. Paging is KEYSET, not offset: an append-only log grows
/// under the reader, so an offset page would drift and could skip rows.
class AuditQuery {
  const AuditQuery({
    this.limit = kConsolePageSize,
    this.cursor,
    this.action,
    this.targetOrganizationId,
    this.from,
    this.to,
  });

  final int limit;

  /// Null for the first page; otherwise the cursor the PREVIOUS page returned.
  final AuditCursor? cursor;

  final String? action;
  final String? targetOrganizationId;

  /// Inclusive range bounds as ISO-8601 strings, or null for unbounded.
  final String? from;
  final String? to;

  AuditQuery copyWith({
    int? limit,
    Object? cursor = _unset,
    Object? action = _unset,
    Object? targetOrganizationId = _unset,
    Object? from = _unset,
    Object? to = _unset,
  }) => AuditQuery(
    limit: limit ?? this.limit,
    cursor: cursor == _unset ? this.cursor : cursor as AuditCursor?,
    action: action == _unset ? this.action : action as String?,
    targetOrganizationId: targetOrganizationId == _unset
        ? this.targetOrganizationId
        : targetOrganizationId as String?,
    from: from == _unset ? this.from : from as String?,
    to: to == _unset ? this.to : to as String?,
  );

  /// The same filters, rewound to the newest page. Every filter change uses
  /// this — carrying a cursor across a filter change would resume from a
  /// position that no longer exists in the new result set.
  AuditQuery resetToFirstPage() => copyWith(cursor: null);

  @override
  bool operator ==(Object other) =>
      other is AuditQuery &&
      other.limit == limit &&
      other.cursor == cursor &&
      other.action == action &&
      other.targetOrganizationId == targetOrganizationId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode =>
      Object.hash(limit, cursor, action, targetOrganizationId, from, to);
}

/// One keyset page of audit rows.
class AuditPage {
  const AuditPage({
    required this.rows,
    required this.hasMore,
    required this.limit,
    this.nextCursor,
  });

  final List<AuditEvent> rows;

  /// True when the server held back at least one more row (it fetches
  /// `limit + 1` to answer this without a second COUNT).
  final bool hasMore;

  final int limit;

  /// Non-null exactly when [hasMore] is true.
  final AuditCursor? nextCursor;

  bool get isEmpty => rows.isEmpty;
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

/// The console's page size. Well inside the server's `[1, 200]` clamp, and small
/// enough that a page stays readable on a 390-wide phone.
const int kConsolePageSize = 25;

/// The exact organization-status values the platform uses (`organizations`
/// carries a CHECK for these two).
const List<String> kOrganizationStatuses = <String>['active', 'suspended'];

/// The exact subscription-status values (`organization_subscriptions` CHECK).
const List<String> kSubscriptionStatuses = <String>[
  'trialing',
  'active',
  'past_due',
  'canceled',
];

/// Sentinel distinguishing "argument omitted" from "explicitly set to null" in
/// the `copyWith`s above — without it, clearing a filter would be impossible.
const Object _unset = Object();
