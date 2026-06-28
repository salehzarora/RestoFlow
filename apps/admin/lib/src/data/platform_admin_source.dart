/// The STRUCTURED demo platform dataset the admin overview is CALCULATED from
/// (RF-120).
///
/// This is deliberately NOT a pre-baked set of KPI cards: it is a realistic set
/// of organizations, their restaurants/branches, branch device counts and
/// activity, and a platform activity feed. Every platform KPI and list is
/// DERIVED from it by `computePlatformOverview` — nothing is a random or
/// hardcoded card. There is no Supabase, no RPC, no backend: the real RF-091
/// platform-admin RPCs (`platform_admin_organization_overview` /
/// `get_organization` / `recent_audit`) exist server-side but are not wired here
/// (real platform admin data wiring is deferred). The demo shapes intentionally
/// mirror those RPC returns (org status + restaurant/branch counts, audit
/// events) so a future Supabase-backed repository can fill the same models.
/// Counts are plain integers (no money); timestamps are plain data strings
/// (zero-padded, so the overview is deterministic and testable).
library;

/// One branch under an organization, with its device count and activity. Status
/// is a plain data string (e.g. `active` / `inactive`).
class PlatformBranch {
  const PlatformBranch({
    required this.name,
    required this.restaurantName,
    required this.status,
    required this.deviceCount,
    required this.lastActivityLabel,
    required this.todayOrderCount,
  });

  /// Display name (data, not localized chrome).
  final String name;
  final String restaurantName;

  /// Branch status as a plain data string (e.g. `active`).
  final String status;
  final int deviceCount;

  /// Last activity as a plain data string (e.g. `2026-06-28 14:02`).
  final String lastActivityLabel;
  final int todayOrderCount;

  bool get isActive => status == 'active';
}

/// One organization (tenant root) with its restaurant count and branches.
class PlatformOrganization {
  const PlatformOrganization({
    required this.name,
    required this.status,
    required this.plan,
    required this.createdAtLabel,
    required this.restaurantCount,
    required this.branches,
  });

  /// Display name (data, not localized chrome).
  final String name;

  /// Organization status as a plain data string (e.g. `active` / `suspended`).
  final String status;

  /// Plan/tier as a plain data string (e.g. `pro` / `standard` / `trial`).
  final String plan;

  /// Created date as a plain data string (e.g. `2026-03-12`).
  final String createdAtLabel;
  final int restaurantCount;
  final List<PlatformBranch> branches;

  bool get isActive => status == 'active';
}

/// One platform activity event (e.g. organization created, device paired, sync
/// warning). Action + summary are plain data strings; the timestamp is a plain
/// zero-padded data string so events sort lexicographically.
class PlatformActivity {
  const PlatformActivity({
    required this.timestampLabel,
    required this.action,
    required this.summary,
  });

  /// Plain `YYYY-MM-DD HH:mm` data string.
  final String timestampLabel;

  /// Canonical action as a plain data string (e.g. `sync_warning`).
  final String action;

  /// A readable one-line description (data, e.g. `Pizza Plaza · device offline`).
  final String summary;
}

/// The full structured platform dataset an overview is computed from.
class PlatformDataset {
  const PlatformDataset({
    required this.generatedDateLabel,
    required this.organizations,
    required this.activity,
  });

  /// The platform "as of" day as a plain data string (e.g. `2026-06-28`).
  final String generatedDateLabel;
  final List<PlatformOrganization> organizations;
  final List<PlatformActivity> activity;
}

/// The standard demo platform dataset: three organizations (two active, one
/// suspended), four restaurants, six branches, ten devices, and a recent
/// activity feed. Hand-tuned to clean, hand-verifiable counts (see the
/// platform-overview-calculator tests). No money — counts only.
PlatformDataset demoPlatformDataset() => const PlatformDataset(
  generatedDateLabel: '2026-06-28',
  organizations: [
    PlatformOrganization(
      name: 'Bistro Group',
      status: 'active',
      plan: 'pro',
      createdAtLabel: '2026-03-12',
      restaurantCount: 2, // Bistro Downtown, Bistro Seaside
      branches: [
        PlatformBranch(
          name: 'Downtown Main',
          restaurantName: 'Bistro Downtown',
          status: 'active',
          deviceCount: 3,
          lastActivityLabel: '2026-06-28 14:02',
          todayOrderCount: 87,
        ),
        PlatformBranch(
          name: 'Downtown Express',
          restaurantName: 'Bistro Downtown',
          status: 'active',
          deviceCount: 2,
          lastActivityLabel: '2026-06-28 13:50',
          todayOrderCount: 41,
        ),
        PlatformBranch(
          name: 'Seaside',
          restaurantName: 'Bistro Seaside',
          status: 'active',
          deviceCount: 2,
          lastActivityLabel: '2026-06-28 13:40',
          todayOrderCount: 33,
        ),
      ],
    ),
    PlatformOrganization(
      name: 'Cafe Noor',
      status: 'active',
      plan: 'standard',
      createdAtLabel: '2026-04-02',
      restaurantCount: 1, // Cafe Noor Central
      branches: [
        PlatformBranch(
          name: 'Noor Central',
          restaurantName: 'Cafe Noor Central',
          status: 'active',
          deviceCount: 2,
          lastActivityLabel: '2026-06-28 12:15',
          todayOrderCount: 54,
        ),
        PlatformBranch(
          name: 'Noor Airport',
          restaurantName: 'Cafe Noor Central',
          status: 'inactive',
          deviceCount: 0,
          lastActivityLabel: '2026-06-20 09:30',
          todayOrderCount: 0,
        ),
      ],
    ),
    PlatformOrganization(
      name: 'Pizza Plaza',
      status: 'suspended',
      plan: 'trial',
      createdAtLabel: '2026-05-20',
      restaurantCount: 1, // Pizza Plaza HQ
      branches: [
        PlatformBranch(
          name: 'Plaza HQ',
          restaurantName: 'Pizza Plaza HQ',
          status: 'active',
          deviceCount: 1,
          lastActivityLabel: '2026-06-25 18:00',
          todayOrderCount: 0,
        ),
      ],
    ),
  ],
  activity: [
    PlatformActivity(
      timestampLabel: '2026-06-28 14:05',
      action: 'sync_warning',
      summary: 'Pizza Plaza · Plaza HQ device offline',
    ),
    PlatformActivity(
      timestampLabel: '2026-06-28 13:20',
      action: 'report_generated',
      summary: 'Bistro Group · daily sales report',
    ),
    PlatformActivity(
      timestampLabel: '2026-06-28 10:12',
      action: 'device_paired',
      summary: 'Bistro Group · Downtown Main',
    ),
    PlatformActivity(
      timestampLabel: '2026-06-27 16:40',
      action: 'branch_opened',
      summary: 'Cafe Noor · Noor Central',
    ),
    PlatformActivity(
      timestampLabel: '2026-05-20 11:30',
      action: 'organization_created',
      summary: 'Pizza Plaza',
    ),
  ],
);

/// An EMPTY platform (no organizations, no activity), used to render and test
/// the empty state.
PlatformDataset emptyPlatformDataset() => const PlatformDataset(
  generatedDateLabel: '2026-06-28',
  organizations: [],
  activity: [],
);
