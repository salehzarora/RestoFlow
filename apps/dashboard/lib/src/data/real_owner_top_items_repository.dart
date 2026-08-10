/// Real-mode top-selling items (DASHBOARD-VISUAL-RANGE-REFRESH-F3).
///
/// Reads the S0 `public.owner_top_items` RPC over the SAME authenticated
/// transport the rest of the real dashboard uses. The RPC is financial-read
/// gated, RLS-safe, branch-local and integer-minor (D-007); this class only maps
/// it.
///
/// THE RANKING IS NOT RECOMPUTED HERE. The server orders by revenue desc,
/// quantity desc, name asc, menu_item_id asc — a TOTAL order — and it groups by
/// the stable `menu_item_id` while reporting the most recently captured name
/// snapshot. Re-sorting or re-grouping client-side could only disagree with
/// that, and disagreeing about "the top seller" is worse than not showing one.
///
/// NOT-DEPLOYED-YET vs FAILED, kept distinct (the convention every other real
/// owner repository follows): only a PGRST202/404 "could not find the function"
/// degrades to an honest [OwnerTopItems.unavailable]. An auth denial (42501) and
/// an argument rejection (22023) are NEVER softened into "unavailable", and a
/// successful empty list is EMPTY DATA — the server's real answer that this
/// window sold nothing — never a capability problem.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../analytics/analytics_range.dart';
import '../analytics/analytics_window.dart';
import '../analytics/dashboard_analytics_scope.dart';
import '../analytics/owner_top_items_query_key.dart';
import 'demo_report.dart' show TopItem;
import 'owner_top_items.dart';
import 'owner_top_items_repository.dart';

/// Reads [OwnerTopItems] from `public.owner_top_items`.
class RealOwnerTopItemsRepository implements OwnerTopItemsRepository {
  const RealOwnerTopItemsRepository({this.scope, this.transport});

  /// The active membership. Null in demo mode or before one is selected.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport. Null => not wired (fail-closed).
  final SyncRpcTransport? transport;

  @override
  Future<OwnerTopItems> loadTopItems({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    int limit = kOverviewTopItemsLimit,
  }) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'owner-top-items: no authenticated transport/scope - real read not wired',
      );
    }
    // The scope on the wire is the scope in the KEY (CODEX F-1A), so an
    // org-wide owner is never silently narrowed to the membership's pinned
    // first branch. The ORGANIZATION stays the membership's — it is the
    // authorization anchor, never a filter — and a key claiming a different one
    // fails closed here rather than becoming a cross-org tuple on the wire.
    final selected = analyticsScope ?? DashboardAnalyticsScope.coveredBy(m);
    if (selected.organizationId != m.organizationId) {
      throw const OwnerTopItemsException(
        'owner_top_items: analytics scope organization does not match the membership',
      );
    }

    final window = customWindow ?? AnalyticsWindow.preset(range);
    final Object? raw;
    try {
      raw = await t.invoke('owner_top_items', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': selected.restaurantId,
        'p_branch_id': selected.branchId,
        // ONE mapper for every owner RPC: a preset sends only p_range, a custom
        // window sends only the two dates. 60/90 travel as real tokens so the
        // server resolves them per branch.
        ...analyticsWindowParams(window),
        'p_limit': limit,
      });
    } on SyncTransportException catch (e) {
      if (_isMissingRpc(e)) return OwnerTopItems.unavailable(window.wire);
      throw const OwnerTopItemsException('owner_top_items transport failure');
    }
    if (raw is! Map || raw['ok'] != true) {
      // A DEPLOYED RPC that rejected the caller — permission_denied, or a 22023
      // argument error — is not a missing-RPC case. Fail closed; never soften
      // it into "unavailable" and never fabricate rows.
      throw const OwnerTopItemsException('owner_top_items rejected');
    }
    return _fromPayload(raw, window.wire);
  }

  static OwnerTopItems _fromPayload(
    Map<Object?, Object?> raw,
    String fallbackWire,
  ) {
    final currency = (raw['currency_code'] ?? '').toString();
    final itemsRaw = raw['items'];
    final items = <TopItem>[];
    if (itemsRaw is List) {
      for (final entry in itemsRaw) {
        if (entry is! Map) continue;
        final id = entry['menu_item_id']?.toString();
        final name = entry['name']?.toString();
        // A row without an identity or a name is unrenderable; skipping it is
        // honest, whereas inventing "Unknown item" would put a product on the
        // owner's best-sellers list that does not exist.
        if (id == null || name == null) continue;
        items.add(
          TopItem(
            menuItemId: id,
            name: name,
            quantity: _int(entry['quantity']),
            lineRevenueMinor: _int(entry['revenue_minor']),
            currencyCode: currency,
            orderCount: entry['order_count'] == null
                ? null
                : _int(entry['order_count']),
          ),
        );
      }
    }
    return OwnerTopItems(
      currencyCode: currency,
      // The server's own echo when present — it answers `custom` for a custom
      // window, which no enum can represent.
      rangeWire: (raw['range'] ?? fallbackWire).toString(),
      items: List.unmodifiable(items),
    );
  }

  /// Integer minor units, defensively. Money never becomes a double (D-007);
  /// a malformed value reads as zero rather than throwing away the whole card.
  static int _int(Object? v) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    _ => int.tryParse('$v') ?? 0,
  };

  /// Whether [e] means the FUNCTION does not exist yet, as opposed to a
  /// permission / tenant / auth denial. Same rule and same order of checks as
  /// the sibling owner repositories — one definition of "missing".
  static bool _isMissingRpc(SyncTransportException e) {
    if (e.kind == SyncTransportErrorKind.auth) return false;
    final code = (e.code ?? '').toUpperCase();
    if (code == 'PGRST202' || code == '404') return true;
    final message = (e.message ?? '').toLowerCase();
    return message.contains('could not find the function') ||
        (message.contains('function') && message.contains('does not exist'));
  }
}
