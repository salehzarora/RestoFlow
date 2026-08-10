/// DASHBOARD-VISUAL-RANGE-REFRESH-F3 — the identity of one top-items request.
///
/// The third sibling of [OwnerReportQueryKey] and [OwnerSalesSeriesQueryKey],
/// built the same way and for the same reason: from what the repository
/// ACTUALLY sends. `RealOwnerTopItemsRepository` posts `p_organization_id`,
/// `p_restaurant_id`, `p_branch_id`, the window parameters and `p_limit`, so
/// those are the truth-bearing inputs, and [isDemoMode] joins them because demo
/// and real are different data sources on one provider path.
///
/// A SEPARATE type rather than reusing either sibling: they identify requests to
/// DIFFERENT RPCs, and a field added for one endpoint must not silently redefine
/// another's cache identity. This one additionally carries [limit], which the
/// other two have no concept of.
library;

import 'analytics_range.dart';
import 'analytics_window.dart';
import 'dashboard_analytics_scope.dart';

/// The Overview card's page size. The server clamps to 1..50; ten is what the
/// card can show without becoming a second Orders screen.
const int kOverviewTopItemsLimit = 10;

/// A value-equal, hash-stable identity for one top-items request.
class OwnerTopItemsQueryKey {
  const OwnerTopItemsQueryKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.range,
    required this.isDemoMode,
    this.customWindow,
    this.limit = kOverviewTopItemsLimit,
  });

  /// Null when no membership is resolved yet — a valid, distinct identity whose
  /// result is an honest failure rather than a silent empty list.
  final String? organizationId;
  final String? restaurantId;

  /// Null for an org- or restaurant-wide scope, which sends a null
  /// `p_branch_id`. NOT a missing value: it is "every branch I may see", and
  /// narrowing it to one branch is the exact defect CLIENT-E1 removed.
  final String? branchId;

  final AnalyticsRange range;

  /// The committed CUSTOM window, or null when [range] is the selection. Part of
  /// identity: two different custom windows are two different requests, and a
  /// preset can never equal a custom window because a preset key holds null here.
  final CustomAnalyticsWindow? customWindow;

  /// In the key because it is on the wire. A 10-row answer cannot satisfy a
  /// 50-row request.
  final int limit;

  final bool isDemoMode;

  /// This key's selection as the canonical domain type.
  AnalyticsWindow get window => customWindow ?? AnalyticsWindow.preset(range);

  /// The exact scope this key identifies, handed to the repository by the family
  /// loader so the ids on the wire are the ids in the key structurally, rather
  /// than because two providers happen to agree.
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
      other is OwnerTopItemsQueryKey &&
          other.organizationId == organizationId &&
          other.restaurantId == restaurantId &&
          other.branchId == branchId &&
          other.range == range &&
          other.customWindow == customWindow &&
          other.limit == limit &&
          other.isDemoMode == isDemoMode;

  @override
  int get hashCode => Object.hash(
    organizationId,
    restaurantId,
    branchId,
    range,
    customWindow,
    limit,
    isDemoMode,
  );

  @override
  String toString() =>
      'OwnerTopItemsQueryKey(org: $organizationId, restaurant: $restaurantId, '
      'branch: $branchId, window: $window, limit: $limit, demo: $isDemoMode)';
}
