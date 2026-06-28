/// The platform-admin overview CALCULATOR (RF-120): derives a [PlatformOverview]
/// from a structured [PlatformDataset]. Pure + deterministic — every count and
/// list is computed from the dataset's organizations / branches / activity;
/// nothing is hardcoded. Counts are plain integers (no money).
library;

import 'platform_admin_source.dart';
import 'platform_overview.dart';

/// Computes the [PlatformOverview] for [data].
PlatformOverview computePlatformOverview(PlatformDataset data) {
  final orgs = data.organizations;
  final allBranches = [
    for (final org in orgs)
      for (final branch in org.branches) (org, branch),
  ];

  final organizationCount = orgs.length;
  final activeOrganizationCount = orgs.where((o) => o.isActive).length;
  final restaurantCount = orgs.fold<int>(0, (s, o) => s + o.restaurantCount);
  final branchCount = allBranches.length;
  final activeBranchCount = allBranches.where((b) => b.$2.isActive).length;
  final deviceCount = allBranches.fold<int>(0, (s, b) => s + b.$2.deviceCount);
  final todayOrderCount = allBranches.fold<int>(
    0,
    (s, b) => s + b.$2.todayOrderCount,
  );

  // A branch needs attention when it is inactive OR its organization is
  // suspended (a deterministic, testable rule).
  bool warns((PlatformOrganization, PlatformBranch) ob) =>
      !ob.$2.isActive || !ob.$1.isActive;
  final warningCount = allBranches.where(warns).length;

  // Organization summaries, sorted by name (deterministic).
  final organizations = [
    for (final org in orgs)
      OrgSummary(
        organizationName: org.name,
        restaurantCount: org.restaurantCount,
        branchCount: org.branches.length,
        status: org.status,
        plan: org.plan,
        createdAtLabel: org.createdAtLabel,
      ),
  ]..sort((a, b) => a.organizationName.compareTo(b.organizationName));

  // Branch health, sorted by name (deterministic), with the derived warning.
  final branchHealth = [
    for (final ob in allBranches)
      BranchHealth(
        branchName: ob.$2.name,
        organizationName: ob.$1.name,
        status: ob.$2.status,
        deviceCount: ob.$2.deviceCount,
        lastActivityLabel: ob.$2.lastActivityLabel,
        todayOrderCount: ob.$2.todayOrderCount,
        hasWarning: warns(ob),
      ),
  ]..sort((a, b) => a.branchName.compareTo(b.branchName));

  // Recent activity, newest first (zero-padded timestamps sort lexically).
  final activity = [
    for (final event in data.activity)
      ActivityEvent(
        timestampLabel: event.timestampLabel,
        action: event.action,
        summary: event.summary,
      ),
  ]..sort((a, b) => b.timestampLabel.compareTo(a.timestampLabel));

  return PlatformOverview(
    generatedDateLabel: data.generatedDateLabel,
    organizationCount: organizationCount,
    activeOrganizationCount: activeOrganizationCount,
    restaurantCount: restaurantCount,
    branchCount: branchCount,
    activeBranchCount: activeBranchCount,
    deviceCount: deviceCount,
    warningCount: warningCount,
    todayOrderCount: todayOrderCount,
    organizations: organizations,
    branchHealth: branchHealth,
    activity: activity,
  );
}

/// Convenience: the standard computed demo overview (used by tests and as the
/// default repository result). Built from the structured demo dataset — not a
/// hardcoded snapshot.
PlatformOverview demoPlatformOverview() =>
    computePlatformOverview(demoPlatformDataset());
