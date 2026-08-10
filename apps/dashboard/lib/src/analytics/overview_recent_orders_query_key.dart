/// DASHBOARD-VISUAL-RANGE-REFRESH-F3 — the identity of the Overview's
/// Recent Orders request.
///
/// A SEPARATE key from the Orders screen's own state, deliberately. The two ask
/// the same RPC very different questions: the Overview wants the newest eight
/// rows of the committed analytics window with no filters, while the Orders
/// screen wants a filtered, searchable, cursor-paginated 25-row page. Sharing
/// one cache entry would let a filtered page satisfy the card — or the card's
/// eight rows satisfy the screen's first page — and neither is the answer that
/// was asked for.
///
/// [OrderHistoryQuery] itself cannot be the family key: it is a plain mutable-
/// shaped value object with no `==`/`hashCode`, so Riverpod would compare it by
/// identity, rebuild a fresh instance every build, and refetch forever.
library;

import '../data/order_history_models.dart';
import 'analytics_range.dart';
import 'analytics_window.dart';
import 'dashboard_analytics_scope.dart';

/// A value-equal, hash-stable identity for the Overview's Recent Orders card.
class OverviewRecentOrdersQueryKey {
  const OverviewRecentOrdersQueryKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.range,
    required this.isDemoMode,
    this.customWindow,
    this.limit = kOverviewRecentOrdersLimit,
  });

  final String? organizationId;
  final String? restaurantId;

  /// Null for an org- or restaurant-wide scope — "every branch I may see",
  /// never a missing value.
  final String? branchId;

  final AnalyticsRange range;

  /// The committed CUSTOM window, or null when [range] is the selection.
  final CustomAnalyticsWindow? customWindow;

  /// Eight for the card. On the wire as `p_limit`, so it belongs to identity.
  final int limit;

  final bool isDemoMode;

  /// This key's selection as the canonical domain type.
  AnalyticsWindow get window => customWindow ?? AnalyticsWindow.preset(range);

  /// The request this key stands for.
  ///
  /// NO filters: the card shows the window's newest orders, full stop. Adding a
  /// status or payment filter here would make "recent orders" quietly mean
  /// "recent SOME orders", and the count would stop matching the KPIs above it.
  OrderHistoryQuery get query => OrderHistoryQuery(
    range: range.asOrderHistoryRange,
    customWindow: customWindow,
    limit: limit,
  );

  /// The exact scope this key identifies.
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
      other is OverviewRecentOrdersQueryKey &&
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
      'OverviewRecentOrdersQueryKey(org: $organizationId, restaurant: '
      '$restaurantId, branch: $branchId, window: $window, limit: $limit, '
      'demo: $isDemoMode)';
}
