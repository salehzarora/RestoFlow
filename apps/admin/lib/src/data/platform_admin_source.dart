/// The STRUCTURED demo platform dataset the console pages are CALCULATED from
/// (RF-120, reshaped for the ADMIN-125C.2 console).
///
/// This is deliberately NOT a set of pre-baked cards. It is a realistic set of
/// organizations (tenants), their subscriptions, their restaurants and branch
/// counts, and a platform audit feed. Every console figure — the Overview
/// counts, the Subscribers page, a Subscriber detail, the Restaurants page and
/// the Audit log — is DERIVED from this dataset by `demo_console_calculator`.
/// Nothing is a hardcoded KPI.
///
/// The shapes mirror the ADMIN-125C.1 read contract exactly (org status +
/// default currency, restaurant/branch/membership counts, plan + subscription
/// status + period, `currency_override`, and safe-projection audit rows) so the
/// demo and real repositories return the SAME models and the pages cannot drift
/// apart. There is no Supabase, no RPC and no backend here.
///
/// The demo tenants deliberately cover every state the console must render:
/// an active tenant on an active plan, a trialing tenant, a past-due tenant, a
/// canceled tenant, a SUSPENDED tenant, a tenant with NO subscription at all,
/// a suspended restaurant, and a restaurant whose currency OVERRIDES its
/// organization's. Counts are plain integers; there is no money anywhere.
library;

/// One restaurant under a demo organization.
class PlatformRestaurant {
  const PlatformRestaurant({
    required this.id,
    required this.name,
    required this.status,
    required this.branchCount,
    required this.createdAtLabel,
    this.currencyOverride,
    this.todayOrdersCount = 0,
    this.todayRevenueMinor = 0,
  });

  final String id;

  /// Display name (data, not localized chrome).
  final String name;

  /// Raw wire status (`active` / `suspended`).
  final String status;
  final int branchCount;
  final String createdAtLabel;

  /// Set only when this restaurant overrides its organization's currency.
  final String? currencyOverride;

  /// ADMIN-126: today's trading, in this restaurant's EFFECTIVE currency and
  /// integer minor units. In real mode these come from the tenant's own
  /// reporting function; here they are demo figures, derived like everything
  /// else in this dataset.
  final int todayOrdersCount;
  final int todayRevenueMinor;
}

/// A demo tenant's subscription, when it has one.
class PlatformSubscription {
  const PlatformSubscription({
    required this.planCode,
    required this.planDisplayName,
    required this.status,
    this.currentPeriodStartLabel,
    this.currentPeriodEndLabel,
  });

  final String planCode;
  final String planDisplayName;

  /// `trialing` / `active` / `past_due` / `canceled`.
  final String status;
  final String? currentPeriodStartLabel;
  final String? currentPeriodEndLabel;
}

/// One organization (the tenant root, and the owner-facing "subscriber").
class PlatformOrganization {
  const PlatformOrganization({
    required this.id,
    required this.name,
    required this.status,
    required this.defaultCurrency,
    required this.createdAtLabel,
    required this.activeMembershipCount,
    required this.restaurants,
    this.subscription,
    this.ownerContacts = const <String>[],
  });

  final String id;

  /// Display name (data, not localized chrome).
  final String name;

  /// Raw wire status (`active` / `suspended`).
  final String status;
  final String defaultCurrency;
  final String createdAtLabel;
  final int activeMembershipCount;
  final List<PlatformRestaurant> restaurants;

  /// Null for a tenant with no `organization_subscriptions` row — the state
  /// EVERY production tenant is in today.
  final PlatformSubscription? subscription;

  /// ADMIN-126: the ACTIVE organization-owner email(s). Never other staff.
  final List<String> ownerContacts;

  bool get isActive => status == 'active';
  int get branchCount =>
      restaurants.fold<int>(0, (sum, r) => sum + r.branchCount);
}

/// One platform-admin audit row in the same SAFE projection the server returns
/// (no `details` jsonb, actor and target by id only).
class PlatformAuditSeed {
  const PlatformAuditSeed({
    required this.id,
    required this.actorAppUserId,
    required this.action,
    required this.reason,
    required this.occurredAtRaw,
    this.targetOrganizationId,
  });

  final String id;
  final String actorAppUserId;

  /// Raw wire action key, deliberately untranslated.
  final String action;
  final String reason;

  /// Raw ISO-8601 timestamp (zero-padded, so events sort lexicographically and
  /// the demo keyset cursor behaves exactly like the server's).
  final String occurredAtRaw;
  final String? targetOrganizationId;
}

/// The full structured demo platform dataset.
class PlatformDataset {
  const PlatformDataset({
    required this.serverDateLabel,
    required this.organizations,
    required this.auditEvents,
  });

  /// The platform "as of" day as a plain data string.
  final String serverDateLabel;
  final List<PlatformOrganization> organizations;
  final List<PlatformAuditSeed> auditEvents;
}

/// The demo platform operator's app-user id (a fixed, obviously-fake demo UUID).
const String kDemoOperatorId = 'd0000000-0000-4000-8000-000000000001';

/// The standard demo platform dataset: five organizations (four active, one
/// suspended), six restaurants, eight branches, twenty-three active memberships,
/// and one subscription in EACH of the four states plus one tenant with none.
/// Hand-tuned to clean, hand-verifiable counts (see the calculator tests).
PlatformDataset demoPlatformDataset() => PlatformDataset(
  serverDateLabel: '2026-06-28',
  organizations: const [
    PlatformOrganization(
      id: 'd0000000-0000-4000-8000-0000000000a1',
      name: 'Bistro Group',
      status: 'active',
      ownerContacts: ['amira@bistro.example', 'sam@bistro.example'],
      defaultCurrency: 'USD',
      createdAtLabel: '2026-03-12',
      activeMembershipCount: 9,
      subscription: PlatformSubscription(
        planCode: 'basic',
        planDisplayName: 'Basic',
        status: 'active',
        currentPeriodStartLabel: '2026-06-01',
        currentPeriodEndLabel: '2026-07-01',
      ),
      restaurants: [
        PlatformRestaurant(
          id: 'd0000000-0000-4000-8000-0000000000b1',
          name: 'Bistro Downtown',
          todayOrdersCount: 42,
          todayRevenueMinor: 18750,
          status: 'active',
          branchCount: 2,
          createdAtLabel: '2026-03-12',
        ),
        PlatformRestaurant(
          id: 'd0000000-0000-4000-8000-0000000000b2',
          name: 'Bistro Seaside',
          todayOrdersCount: 18,
          todayRevenueMinor: 9600,
          status: 'active',
          branchCount: 1,
          createdAtLabel: '2026-04-18',
        ),
      ],
    ),
    PlatformOrganization(
      id: 'd0000000-0000-4000-8000-0000000000a2',
      name: 'Cafe Noor',
      status: 'active',
      ownerContacts: ['noor@cafenoor.example'],
      defaultCurrency: 'ILS',
      createdAtLabel: '2026-04-02',
      activeMembershipCount: 5,
      subscription: PlatformSubscription(
        planCode: 'free',
        planDisplayName: 'Free',
        status: 'trialing',
        currentPeriodStartLabel: '2026-06-15',
        currentPeriodEndLabel: '2026-07-15',
      ),
      restaurants: [
        PlatformRestaurant(
          id: 'd0000000-0000-4000-8000-0000000000b3',
          name: 'Cafe Noor Central',
          todayOrdersCount: 27,
          todayRevenueMinor: 14320,
          status: 'active',
          branchCount: 2,
          createdAtLabel: '2026-04-02',
        ),
      ],
    ),
    PlatformOrganization(
      id: 'd0000000-0000-4000-8000-0000000000a3',
      name: 'Olive Tree',
      status: 'active',
      ownerContacts: ['olive@olivetree.example'],
      defaultCurrency: 'USD',
      createdAtLabel: '2026-02-10',
      activeMembershipCount: 2,
      subscription: PlatformSubscription(
        planCode: 'basic',
        planDisplayName: 'Basic',
        status: 'canceled',
        currentPeriodStartLabel: '2026-04-10',
        currentPeriodEndLabel: '2026-05-10',
      ),
      restaurants: [
        // A restaurant that OVERRIDES its organization's currency, and is
        // itself suspended while its organization is not.
        PlatformRestaurant(
          id: 'd0000000-0000-4000-8000-0000000000b4',
          name: 'Olive Tree Bistro',
          todayOrdersCount: 0,
          todayRevenueMinor: 0,
          status: 'suspended',
          branchCount: 1,
          createdAtLabel: '2026-02-10',
          currencyOverride: 'EUR',
        ),
      ],
    ),
    PlatformOrganization(
      id: 'd0000000-0000-4000-8000-0000000000a4',
      name: 'Sahara Grill',
      status: 'active',
      ownerContacts: ['sahara@sahara.example'],
      defaultCurrency: 'ILS',
      createdAtLabel: '2026-05-02',
      activeMembershipCount: 4,
      subscription: PlatformSubscription(
        planCode: 'basic',
        planDisplayName: 'Basic',
        status: 'past_due',
        currentPeriodStartLabel: '2026-05-02',
        currentPeriodEndLabel: '2026-06-02',
      ),
      restaurants: [
        PlatformRestaurant(
          id: 'd0000000-0000-4000-8000-0000000000b5',
          name: 'Sahara Grill Central',
          todayOrdersCount: 11,
          todayRevenueMinor: 6175,
          status: 'active',
          branchCount: 1,
          createdAtLabel: '2026-05-02',
        ),
      ],
    ),
    // A SUSPENDED tenant with NO subscription at all — the two states the
    // console must render honestly rather than hide.
    PlatformOrganization(
      id: 'd0000000-0000-4000-8000-0000000000a5',
      name: 'Pizza Plaza',
      status: 'suspended',
      // A tenant with no reachable owner: the console must say so rather than
      // render an empty cell that looks like a loading failure.
      ownerContacts: [],
      defaultCurrency: 'EUR',
      createdAtLabel: '2026-05-20',
      activeMembershipCount: 3,
      restaurants: [
        PlatformRestaurant(
          id: 'd0000000-0000-4000-8000-0000000000b6',
          name: 'Pizza Plaza HQ',
          todayOrdersCount: 0,
          todayRevenueMinor: 0,
          status: 'active',
          branchCount: 1,
          createdAtLabel: '2026-05-20',
        ),
      ],
    ),
  ],
  auditEvents: demoAuditFeed(),
);

/// The demo audit feed: a deterministic 30-row platform-read history built by
/// replaying a fixed set of console reads across three days. Thirty rows is
/// past one console page, so the demo exercises the SAME keyset "load more"
/// path the real audit log uses instead of a single short list that would hide
/// pagination bugs.
List<PlatformAuditSeed> demoAuditFeed() {
  const days = ['2026-06-28', '2026-06-27', '2026-06-26'];
  const reads = <(String action, String reason, String? target)>[
    (
      'platform.console.overview',
      'BIZBOT admin: platform overview (read-only)',
      null,
    ),
    (
      'platform.subscribers.list',
      'BIZBOT admin: subscriber list (read-only)',
      null,
    ),
    (
      'platform.subscriber.detail',
      'BIZBOT admin: subscriber detail (read-only)',
      'd0000000-0000-4000-8000-0000000000a1',
    ),
    (
      'platform.subscriber.detail',
      'BIZBOT admin: subscriber detail (read-only)',
      'd0000000-0000-4000-8000-0000000000a5',
    ),
    (
      'platform.restaurants.list',
      'BIZBOT admin: restaurant list (read-only)',
      null,
    ),
    ('platform.audit.search', 'BIZBOT admin: audit log (read-only)', null),
    (
      'platform.organizations.overview',
      'BIZBOT admin app: platform overview (read-only)',
      null,
    ),
    (
      'platform.organization.detail',
      'BIZBOT admin: subscriber detail (read-only)',
      'd0000000-0000-4000-8000-0000000000a2',
    ),
    (
      'platform.audit.read',
      'BIZBOT admin app: platform overview (read-only)',
      null,
    ),
    (
      'platform.subscribers.list',
      'BIZBOT admin: subscriber list (read-only)',
      null,
    ),
  ];

  final out = <PlatformAuditSeed>[];
  for (var d = 0; d < days.length; d++) {
    for (var i = 0; i < reads.length; i++) {
      final read = reads[i];
      // Descending minutes within the day, so the feed is already newest-first
      // and every timestamp is distinct (a keyset cursor needs a total order).
      final minute = (reads.length - i).toString().padLeft(2, '0');
      out.add(
        PlatformAuditSeed(
          id:
              'd0000000-0000-4000-8000-00000000'
              "${d.toString().padLeft(2, '0')}${i.toString().padLeft(2, '0')}",
          actorAppUserId: kDemoOperatorId,
          action: read.$1,
          reason: read.$2,
          occurredAtRaw: '${days[d]}T09:$minute:00Z',
          targetOrganizationId: read.$3,
        ),
      );
    }
  }
  return out;
}

/// An EMPTY platform (no organizations, no audit history), used to render and
/// test the empty states.
PlatformDataset emptyPlatformDataset() => const PlatformDataset(
  serverDateLabel: '2026-06-28',
  organizations: [],
  auditEvents: [],
);

/// A platform whose tenants exist but where NO subscription has been assigned —
/// the shape production is actually in today. Used to render and test the
/// honest "no subscriptions configured yet" notice.
PlatformDataset unsubscribedPlatformDataset() => PlatformDataset(
  serverDateLabel: '2026-06-28',
  organizations: [
    for (final org in demoPlatformDataset().organizations)
      PlatformOrganization(
        id: org.id,
        name: org.name,
        status: org.status,
        defaultCurrency: org.defaultCurrency,
        createdAtLabel: org.createdAtLabel,
        activeMembershipCount: org.activeMembershipCount,
        restaurants: org.restaurants,
      ),
  ],
  auditEvents: demoAuditFeed(),
);
