/// The platform-admin overview OUTPUT models (RF-120).
///
/// These are the immutable shapes the UI renders. They are PRODUCED by
/// `computePlatformOverview` from a structured demo dataset
/// (`platform_admin_source`) — nothing here holds hardcoded KPI numbers. The
/// shapes mirror the real RF-091 platform-admin RPC returns (org status +
/// restaurant/branch counts, branch health, audit events) so a future
/// Supabase-backed repository can fill the same model without touching the UI.
/// Counts are plain integers — there is no money on the platform overview.
library;

/// One organization summary row (name, counts, status, plan, created date).
class OrgSummary {
  const OrgSummary({
    required this.organizationName,
    required this.restaurantCount,
    required this.branchCount,
    required this.status,
    required this.plan,
    required this.createdAtLabel,
  });

  /// Display name (data, not localized chrome).
  final String organizationName;
  final int restaurantCount;
  final int branchCount;

  /// Status as a plain data string (e.g. `active` / `suspended`).
  final String status;

  /// Plan/tier as a plain data string (e.g. `pro`).
  final String plan;

  /// Created date as a plain data string (e.g. `2026-03-12`).
  final String createdAtLabel;
}

/// One branch-health row (branch, org, status, devices, activity, today orders
/// and a derived warning flag).
class BranchHealth {
  const BranchHealth({
    required this.branchName,
    required this.organizationName,
    required this.status,
    required this.deviceCount,
    required this.lastActivityLabel,
    required this.todayOrderCount,
    required this.hasWarning,
  });

  /// Display name (data, not localized chrome).
  final String branchName;
  final String organizationName;

  /// Branch status as a plain data string (e.g. `active`).
  final String status;
  final int deviceCount;

  /// Last activity as a plain data string.
  final String lastActivityLabel;
  final int todayOrderCount;

  /// True when the branch needs attention (inactive branch or suspended org).
  final bool hasWarning;
}

/// One recent-activity row (time, action, summary).
class ActivityEvent {
  const ActivityEvent({
    required this.timestampLabel,
    required this.action,
    required this.summary,
  });

  /// Plain `YYYY-MM-DD HH:mm` data string.
  final String timestampLabel;

  /// Canonical action as a plain data string (e.g. `sync_warning`).
  final String action;

  /// A readable one-line description (data).
  final String summary;

  /// Whether this event is a warning (drives the warning tone on its chip).
  bool get isWarning => action.contains('warning');
}

/// An immutable, computed platform-admin overview. Every count is DERIVED from
/// the source dataset by `computePlatformOverview`. Counts are plain integers.
class PlatformOverview {
  const PlatformOverview({
    required this.generatedDateLabel,
    required this.organizationCount,
    required this.activeOrganizationCount,
    required this.restaurantCount,
    required this.branchCount,
    required this.activeBranchCount,
    required this.deviceCount,
    required this.warningCount,
    required this.todayOrderCount,
    required this.organizations,
    required this.branchHealth,
    required this.activity,
  });

  /// The platform "as of" day as a plain data string.
  final String generatedDateLabel;

  final int organizationCount;
  final int activeOrganizationCount;
  final int restaurantCount;
  final int branchCount;
  final int activeBranchCount;
  final int deviceCount;
  final int warningCount;
  final int todayOrderCount;

  final List<OrgSummary> organizations;
  final List<BranchHealth> branchHealth;
  final List<ActivityEvent> activity;

  /// True when there is nothing to show (drives the empty state).
  bool get isEmpty => organizationCount == 0 && activity.isEmpty;
}
