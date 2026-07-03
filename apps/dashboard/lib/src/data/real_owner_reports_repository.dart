/// Real-mode owner-reports repository (M7 skeleton RF-119, wired in the
/// product-rescue sprint).
///
/// Reads the sprint's `public.sales_summary` RPC (manager+, GUC-free, RLS-safe,
/// integer-minor money — D-007) over the SAME authenticated anon-key transport
/// the rest of the real dashboard uses (the GoTrue session rides the client;
/// identity is server-derived). It maps ONLY the figures the backend actually
/// provides — orders today + completed payments + gross — and leaves the rest
/// at honest zero/empty; the RF-140 real-mode banner tells the owner the live
/// report is limited. FAIL-CLOSED: with no transport/scope (or any transport
/// failure) it throws — never fabricated data, never a silent demo fallback.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'demo_report.dart';
import 'owner_reports_repository.dart';

/// Reads the owner [DashboardReport] from `public.sales_summary`.
class RealOwnerReportsRepository implements OwnerReportsRepository {
  const RealOwnerReportsRepository(this.config, {this.scope, this.transport});

  /// The validated client runtime config (anon key only). Null when real mode
  /// was selected but the Supabase config was missing/invalid (fail-closed
  /// upstream in `RuntimeConfig`).
  final SupabaseBootstrapConfig? config;

  /// The active membership (org/restaurant/branch) the report is scoped to.
  /// Null in demo mode or before a membership is selected.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport (the session-carrying dashboard client). Null
  /// => not wired (fail-closed).
  final SyncRpcTransport? transport;

  @override
  Future<DashboardReport> loadReport() async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'owner-reports: no authenticated transport/scope - real read not wired',
      );
    }
    final Object? raw;
    try {
      raw = await t.invoke('sales_summary', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': m.restaurantId,
        'p_branch_id': m.branchId,
      });
    } on SyncTransportException {
      throw const OwnerReportsException('sales_summary transport failure');
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const OwnerReportsException('sales_summary rejected');
    }
    final today = raw['today'];
    final ordersCount = today is Map ? _asInt(today['orders_count']) : 0;
    final paymentsCount = today is Map ? _asInt(today['payments_count']) : 0;
    final grossMinor = today is Map ? _asInt(today['gross_minor']) : 0;
    final days = raw['last_7_days'];
    final dateLabel = days is List && days.isNotEmpty && days.last is Map
        ? ((days.last as Map)['day'] ?? '').toString()
        : '';

    // Only backend-provided figures populate the report; the RF-140 real-mode
    // banner says the live report is limited. gross = the completed-payments
    // sum; net/collected/cash mirror it because THIS build records no
    // discounts and payment.create is CASH-ONLY (RF-130) — when other tenders
    // or a discount engine land, these must split. openOrders is the honest
    // orders-without-a-completed-payment approximation.
    final openOrders = ordersCount - paymentsCount;
    return DashboardReport(
      currencyCode: (raw['currency_code'] ?? '').toString(),
      businessDateLabel: dateLabel,
      grossSalesMinor: grossMinor,
      netSalesMinor: grossMinor,
      discountTotalMinor: 0,
      collectedMinor: grossMinor,
      cashSalesMinor: grossMinor,
      lastCashPaymentMinor: 0,
      orderCount: ordersCount,
      completedOrderCount: paymentsCount,
      openOrderCount: openOrders < 0 ? 0 : openOrders,
      unpaidOrderCount: openOrders < 0 ? 0 : openOrders,
      voidCount: 0,
      voidTotalMinor: 0,
      openingFloatMinor: 0,
      expectedCashMinor: 0,
      countedCashMinor: 0,
      shiftStatus: 'none',
      branches: const [],
      topItems: const [],
      recentOrders: const [],
      paymentMethods: const [],
    );
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}
