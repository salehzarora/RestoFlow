/// DASHBOARD-OWNER-ANALYTICS-F0.6 — the identity of one owner-report request.
///
/// The report provider previously had no request identity at all: it watched a
/// range and a repository and produced "the report". That is fine while a
/// container lives, but it makes the cached value impossible to reason about
/// the moment scope can change — two different branches would look like the
/// same request.
///
/// [OwnerReportQueryKey] is that identity, taken from what the repository
/// ACTUALLY sends. `RealOwnerReportsRepository` posts exactly
/// `p_organization_id`, `p_restaurant_id`, `p_branch_id` and `p_range`, so
/// those four are the truth-bearing inputs; [isDemoMode] joins them because the
/// demo and real repositories are different data sources reachable from the
/// same provider path, and a demo result must never satisfy a real request.
///
/// Nothing decorative is included. Role/membership id is deliberately ABSENT:
/// it does not change the rows the RPC returns for a given org/restaurant/
/// branch — it only decides whether the call is authorized at all, and an
/// unauthorized caller gets an error rather than a cacheable report.
///
/// Branch is nullable today because an org- or restaurant-wide membership sends
/// a null `p_branch_id`. That is exactly the shape explicit branch selection
/// will need later, so this key is already structurally ready for it without
/// implementing any selection now.
library;

import '../data/demo_report.dart' show ReportRange;

import 'analytics_range.dart';
import 'analytics_window.dart';
import 'dashboard_analytics_scope.dart';

/// A value-equal, hash-stable identity for one owner-report request.
class OwnerReportQueryKey {
  const OwnerReportQueryKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.range,
    required this.isDemoMode,
    this.customWindow,
  });

  /// Null when no membership is resolved yet (demo mode, or before the shell
  /// publishes one). A null-scope key is still a valid, distinct identity — it
  /// is the "not wired" request whose result is an honest failure.
  final String? organizationId;
  final String? restaurantId;

  /// Null for an org- or restaurant-wide membership, which sends a null
  /// `p_branch_id`. Not a missing value — a deliberate all-branches scope.
  final String? branchId;

  final ReportRange range;

  /// DASHBOARD-VISUAL-RANGE-REFRESH-F1 — the committed CUSTOM window, or null
  /// when [range] is the selection.
  ///
  /// PART OF IDENTITY, which is the whole point. Two different custom windows
  /// are two different requests; without this they would be the same key and one
  /// would be served from the other's cache under the wrong dates. And because a
  /// preset key carries null here, `last60` can never equal a hand-picked 60-day
  /// window — they are genuinely different requests, since the preset is
  /// re-resolved per branch at midnight and the custom window is not.
  final CustomAnalyticsWindow? customWindow;

  /// Demo and real are different data sources on the same provider path; a
  /// demo result must never satisfy a real request.
  final bool isDemoMode;

  /// This key's selection as the canonical domain type.
  AnalyticsWindow get window =>
      customWindow ??
      AnalyticsWindow.preset(AnalyticsRange.fromReportRange(range));

  /// CODEX F-1A — the exact scope this key identifies, for the REQUEST it
  /// identifies.
  ///
  /// The family loader hands this to the repository so the ids on the wire are
  /// the ids in the key, structurally, rather than because two providers happen
  /// to agree. Null only when no membership is resolved (demo / not wired),
  /// where the real repository fails closed anyway.
  DashboardAnalyticsScope? get analyticsScope {
    final org = organizationId;
    if (org == null) return null;
    return DashboardAnalyticsScope.ofIds(
      organizationId: org,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OwnerReportQueryKey &&
          other.organizationId == organizationId &&
          other.restaurantId == restaurantId &&
          other.branchId == branchId &&
          other.range == range &&
          other.customWindow == customWindow &&
          other.isDemoMode == isDemoMode;

  @override
  int get hashCode => Object.hash(
    organizationId,
    restaurantId,
    branchId,
    range,
    customWindow,
    isDemoMode,
  );

  @override
  String toString() =>
      'OwnerReportQueryKey(org: $organizationId, restaurant: $restaurantId, '
      'branch: $branchId, window: $window, demo: $isDemoMode)';
}
