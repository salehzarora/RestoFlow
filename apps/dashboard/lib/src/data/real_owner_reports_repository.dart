/// Real-mode owner-reports repository (RF-REPORT-001 Slice 1).
///
/// Reads the `public.owner_daily_report` RPC (financial-read gated, GUC-free,
/// RLS-safe, integer-minor money — D-007) over the SAME authenticated anon-key
/// transport the rest of the real dashboard uses (the GoTrue session rides the
/// client; identity is server-derived). Unlike the earlier `sales_summary`
/// headline it SPLITS billed sales (gross/discount/net, voids) from collected
/// payments (collected/cash/last-cash + a per-method tender breakdown), and
/// carries a prior-day block that lights up the Overview's "vs yesterday" KPI
/// deltas. Fields not yet sourced server-side in Slice 1 — sales-by-hour, shift/
/// cash reconciliation, per-branch, top items, recent orders — stay at honest
/// zero/empty (the RF-140 real-mode banner tells the owner the live report is
/// limited); the Overview's data-gated chart simply does not render. FAIL-CLOSED:
/// with no transport/scope (or any transport failure) it throws — never
/// fabricated data, never a silent demo fallback.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'demo_report.dart';
import 'owner_reports_repository.dart';

/// Reads the owner [DashboardReport] from `public.owner_daily_report`.
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
      raw = await t.invoke('owner_daily_report', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': m.restaurantId,
        'p_branch_id': m.branchId,
      });
    } on SyncTransportException {
      throw const OwnerReportsException('owner_daily_report transport failure');
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const OwnerReportsException('owner_daily_report rejected');
    }

    final currency = (raw['currency_code'] ?? '').toString();
    final today = raw['today'] is Map
        ? (raw['today'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final prior = raw['prior_day'] is Map
        ? (raw['prior_day'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return DashboardReport(
      currencyCode: currency,
      businessDateLabel: (raw['business_date'] ?? '').toString(),
      // BILLED sales (orders + order_items) — split from collected payments.
      grossSalesMinor: _int(today['gross_minor']),
      netSalesMinor: _int(today['net_minor']),
      discountTotalMinor: _int(today['discount_minor']),
      voidCount: _int(today['void_count']),
      voidTotalMinor: _int(today['void_total_minor']),
      // COLLECTED payments — the real cash/tender figures (never = billed sales).
      collectedMinor: _int(today['collected_minor']),
      cashSalesMinor: _int(today['cash_minor']),
      lastCashPaymentMinor: _int(today['last_cash_payment_minor']),
      // Counts (feed the KPI cards + client-side avg-ticket = net // orderCount).
      orderCount: _int(today['order_count']),
      completedOrderCount: _int(today['completed_count']),
      openOrderCount: _int(today['open_count']),
      unpaidOrderCount: _int(today['unpaid_count']),
      // Per-method tender breakdown (cash-only today, but real when card/bit land).
      paymentMethods: _tenders(today['tenders'], currency),
      // Prior-day block -> KPI "vs yesterday" deltas (deltaPercent guards prior 0).
      comparison: ReportComparison(
        grossSalesMinor: _int(prior['gross_minor']),
        netSalesMinor: _int(prior['net_minor']),
        orderCount: _int(prior['order_count']),
        cashSalesMinor: _int(prior['cash_minor']),
      ),
      // NOT sourced in Slice 1 — honest zero/empty (never fabricated). The RF-140
      // banner flags the live report as limited; the data-gated chart/cards hide.
      openingFloatMinor: 0,
      expectedCashMinor: 0,
      countedCashMinor: 0,
      shiftStatus: 'none',
      branches: const [],
      topItems: const [],
      recentOrders: const [],
      // No fabricated hourly curve in real mode (sales-by-hour is a later slice).
      hourlyNetSales: const [],
    );
  }

  /// Maps the RPC's `tenders: [{method, count, total_minor}]` to the report's
  /// payment-method rows. Non-list / malformed input yields an empty breakdown
  /// (honest, never fabricated).
  static List<PaymentMethodLine> _tenders(Object? raw, String currency) {
    if (raw is! List) return const [];
    final rows = <PaymentMethodLine>[];
    for (final row in raw) {
      if (row is! Map) continue;
      rows.add(
        PaymentMethodLine(
          method: (row['method'] ?? '').toString(),
          count: _int(row['count']),
          totalMinor: _int(row['total_minor']),
          currencyCode: currency,
        ),
      );
    }
    return rows;
  }

  static int _int(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}
