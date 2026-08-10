/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — the identity of one daily
/// sales-series request.
///
/// The sibling of F0.6's [OwnerReportQueryKey], built the same way: from what the
/// repository ACTUALLY sends. `RealOwnerSalesSeriesRepository` posts exactly
/// `p_organization_id`, `p_restaurant_id`, `p_branch_id` and `p_range`, and
/// [isDemoMode] joins them because demo and real are different data sources on
/// one provider path — a demo series must never satisfy a real request.
///
/// A SEPARATE type rather than reusing [OwnerReportQueryKey], for two reasons:
///
///  * they identify requests to DIFFERENT RPCs. One type would mean a field
///    added for one endpoint silently redefines the other's cache identity —
///    and this one will grow `p_start`/`p_end` when a custom range lands, which
///    `owner_report_range` does not have;
///  * the range here is [AnalyticsRange], F0's canonical type, not the legacy
///    `ReportRange`. Keying on the canonical type is what stops this new surface
///    from adding yet another enum translation at a boundary — which is the
///    exact drift F0 existed to end.
///
/// Nothing decorative is included, and role/membership id is deliberately
/// ABSENT: it does not change the rows the RPC returns for a given scope, only
/// whether the call is authorized at all, and an unauthorized caller gets an
/// error rather than a cacheable series.
library;

import 'analytics_range.dart';
import 'analytics_window.dart';
import 'dashboard_analytics_scope.dart';

/// A value-equal, hash-stable identity for one sales-series request.
class OwnerSalesSeriesQueryKey {
  const OwnerSalesSeriesQueryKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.range,
    required this.isDemoMode,
    this.customWindow,
  });

  /// Null when no membership is resolved yet. A null-scope key is still a valid,
  /// distinct identity — the "not wired" request whose result is an honest
  /// failure.
  final String? organizationId;
  final String? restaurantId;

  /// Null for an org- or restaurant-wide membership, which sends a null
  /// `p_branch_id`. Not a missing value — a deliberate all-branches scope, and
  /// already the shape explicit branch selection will need.
  final String? branchId;

  /// Only ever a MULTI-DAY range in practice: the single-day ranges keep their
  /// hourly curve and never build a key at all. The type still admits them so
  /// this stays a plain identity rather than a validator.
  final AnalyticsRange range;

  /// DASHBOARD-VISUAL-RANGE-REFRESH-F1 — the committed CUSTOM window, or null
  /// when [range] is the selection. This is the `p_start`/`p_end` growth this
  /// key's header predicted, and it is part of identity: two different custom
  /// windows must never share one cache entry.
  final CustomAnalyticsWindow? customWindow;

  final bool isDemoMode;

  /// This key's selection as the canonical domain type.
  AnalyticsWindow get window => customWindow ?? AnalyticsWindow.preset(range);

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
      other is OwnerSalesSeriesQueryKey &&
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
      'OwnerSalesSeriesQueryKey(org: $organizationId, restaurant: '
      '$restaurantId, branch: $branchId, window: $window, '
      'demo: $isDemoMode)';
}
