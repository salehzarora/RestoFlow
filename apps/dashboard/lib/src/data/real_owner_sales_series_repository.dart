/// Real-mode daily sales series (DASHBOARD-OWNER-ANALYTICS-PHASE-A CLIENT-A).
///
/// Reads the SERVER-A `public.owner_sales_series` RPC over the SAME authenticated
/// anon-key transport the rest of the real dashboard uses — the GoTrue session
/// rides the client and identity is server-derived, so nothing here decides who
/// the caller is. The RPC is financial-read gated, RLS-safe, branch-local and
/// integer-minor (D-007); this class only maps it.
///
/// SCOPE COMES FROM THE MEMBERSHIP, never from a filter. The three ids posted are
/// the resolved `MembershipContext`'s, exactly as `RealOwnerReportsRepository`
/// posts them. No drill-down or UI filter state can reach this call, so a
/// business filter can never widen a tenant boundary (D-001 / RISK R-003).
///
/// `p_start` / `p_end` are NOT sent. The RPC accepts a custom window, but there
/// is no custom-range control yet, and sending a client-computed window would
/// reintroduce the device-timezone bug the server owns the answer to.
///
/// NOT-DEPLOYED-YET vs FAILED, kept distinct (the convention
/// `RealOwnerReportsRepository` already set): the SERVER-A migration is merged but
/// not applied to the hosted database, so PostgREST answers "could not find the
/// function" (PGRST202/404) there. ONLY that signature degrades to an honest
/// [OwnerSalesSeries.unavailable]. An auth denial (42501) is NEVER treated as
/// missing — a denied caller must never be handed a softer story than the truth.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../analytics/analytics_range.dart';
import '../analytics/dashboard_analytics_scope.dart';
import 'owner_sales_series.dart';
import 'owner_sales_series_repository.dart';

/// Reads [OwnerSalesSeries] from `public.owner_sales_series`.
class RealOwnerSalesSeriesRepository implements OwnerSalesSeriesRepository {
  const RealOwnerSalesSeriesRepository({this.scope, this.transport});

  /// The active membership (org/restaurant/branch) the series is scoped to.
  /// Null in demo mode or before a membership is selected.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport. Null => not wired (fail-closed).
  final SyncRpcTransport? transport;

  @override
  Future<OwnerSalesSeries> loadSeries({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
  }) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'owner-sales-series: no authenticated transport/scope - real read not wired',
      );
    }
    // CODEX F-1A — the scope on the wire is the scope in the KEY.
    //
    // These params used to come off the resolved membership, whose restaurant
    // and branch `resolveTenantContext` has already pinned to the FIRST of
    // each. The family key carried the owner's real selection while the
    // request carried the pin, so a broad owner's analytics stayed narrowed and
    // branch A's data could be cached under a branch B key.
    //
    // The ORGANIZATION remains the authenticated membership's — it is the
    // authorization anchor, never a filter. A key claiming a different
    // organization is a client bug, and fails closed HERE rather than becoming
    // a cross-org tuple on the wire.
    final selected = analyticsScope ?? DashboardAnalyticsScope.coveredBy(m);
    if (selected.organizationId != m.organizationId) {
      throw const OwnerSalesSeriesException(
        'owner_sales_series: analytics scope organization does not match the membership',
      );
    }

    final Object? raw;
    try {
      raw = await t.invoke('owner_sales_series', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': selected.restaurantId,
        'p_branch_id': selected.branchId,
        'p_range': range.wire,
      });
    } on SyncTransportException catch (e) {
      if (_isMissingRpc(e)) return OwnerSalesSeries.unavailable(range.wire);
      throw const OwnerSalesSeriesException(
        'owner_sales_series transport failure',
      );
    }
    if (raw is! Map || raw['ok'] != true) {
      // A DEPLOYED RPC that rejected the caller (`{ok:false,
      // error:'permission_denied'}`) is not a missing-RPC case — fail closed,
      // never soften it into "unavailable", never fabricate.
      throw const OwnerSalesSeriesException('owner_sales_series rejected');
    }
    return OwnerSalesSeries.fromPayload(raw);
  }

  /// Whether [e] means the FUNCTION does not exist yet, as opposed to a
  /// permission / tenant / auth denial. Same rule, same order of checks as
  /// `RealOwnerReportsRepository._isMissingRpc` — one definition of "missing"
  /// across the owner RPCs.
  static bool _isMissingRpc(SyncTransportException e) {
    if (e.kind == SyncTransportErrorKind.auth) return false;
    final code = (e.code ?? '').toUpperCase();
    if (code == 'PGRST202' || code == '404') return true;
    final message = (e.message ?? '').toLowerCase();
    return message.contains('could not find the function') ||
        (message.contains('function') && message.contains('does not exist'));
  }
}
