/// ORDER-EDIT-001G — the identity of one Overview "Order edits" request.
///
/// A sibling of [OwnerTopItemsQueryKey], built the same way and for the same
/// reason: from what the repository ACTUALLY sends. The real repository posts
/// `p_organization_id`, `p_restaurant_id`, `p_branch_id`, the window
/// parameters and `p_limit` to `owner_order_edits` (API_CONTRACT §4.47), so
/// those are the truth-bearing inputs, and [isDemoMode] joins them because demo
/// and real are different data sources on one provider path.
///
/// A SEPARATE type rather than reusing the top-items key: the two identify
/// requests to DIFFERENT RPCs, and a field added for one endpoint must not
/// silently redefine the other's cache identity.
library;

import 'analytics_range.dart';
import 'analytics_window.dart';
import 'dashboard_analytics_scope.dart';

/// How many of the newest edits the Overview card lists before "Load more".
/// The block is a summary first; the list is a pointer to the details.
const int kOverviewOrderEditsLimit = 5;

/// The page size of every "Load more" page after the first. The server clamps
/// `p_limit` to 1..100 (API_CONTRACT §4.47).
const int kOrderEditsPageSize = 25;

/// A value-equal, hash-stable identity for one `owner_order_edits` request.
class OwnerOrderEditsQueryKey {
  const OwnerOrderEditsQueryKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.range,
    required this.isDemoMode,
    this.customWindow,
    this.limit = kOverviewOrderEditsLimit,
  });

  /// Null when no membership is resolved yet — a valid, distinct identity whose
  /// result is an honest failure rather than a silent empty block.
  final String? organizationId;
  final String? restaurantId;

  /// Null for an org- or restaurant-wide scope ("every branch I may see").
  final String? branchId;

  final AnalyticsRange range;

  /// The committed CUSTOM window, or null when [range] is the selection. A
  /// preset key holds null here, so a preset can never equal a custom window.
  final CustomAnalyticsWindow? customWindow;

  /// On the wire, so part of identity: a 5-row answer cannot satisfy a larger
  /// request.
  final int limit;

  final bool isDemoMode;

  /// This key's selection as the canonical domain type.
  AnalyticsWindow get window => customWindow ?? AnalyticsWindow.preset(range);

  /// The exact scope this key identifies, handed to the repository so the ids
  /// on the wire are the ids in the key.
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
      other is OwnerOrderEditsQueryKey &&
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
      'OwnerOrderEditsQueryKey(org: $organizationId, restaurant: $restaurantId, '
      'branch: $branchId, window: $window, limit: $limit, demo: $isDemoMode)';
}
