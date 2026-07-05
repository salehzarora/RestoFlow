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
/// limited); the Overview's data-gated chart simply does not render.
///
/// COMPATIBILITY FALLBACK (LIVE-DASHBOARD-001): the RF-REPORT-001 migration is
/// merged but intentionally NOT applied to the live database until R-003 sign-off,
/// so on production `owner_daily_report` does not exist yet and PostgREST answers
/// with a "could not find the function" error (PGRST202/404). ONLY for that
/// missing-RPC signature this repository falls back to the already-deployed
/// `public.sales_summary` and maps the LIMITED figures it provides (orders +
/// completed-payment gross), leaving everything else at honest zero/empty (still
/// the RF-140 "live · limited" report). The fallback NEVER fires on a permission /
/// tenant-isolation / auth error (42501) — those stay FAIL-CLOSED so a denied
/// caller never silently sees fallback data.
///
/// FAIL-CLOSED: with no transport/scope (or any non-missing transport failure, or
/// a rejected `ok != true` body) it throws — never fabricated data, never a
/// silent demo fallback.
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
    } on SyncTransportException catch (e) {
      // LIVE-DASHBOARD-001: on production `owner_daily_report` is not deployed
      // yet, so PostgREST returns a "could not find the function" error. ONLY
      // that missing-RPC signature falls back to the deployed `sales_summary`;
      // an auth/permission denial (42501) stays fail-closed below.
      if (_isMissingRpc(e)) return _loadFromSalesSummary(t, m);
      throw const OwnerReportsException('owner_daily_report transport failure');
    }
    if (raw is! Map || raw['ok'] != true) {
      // A deployed RPC that REJECTED the caller (e.g. {ok:false,
      // error:'permission_denied'}) is NOT a missing-RPC case — fail closed,
      // never fall back and never fabricate.
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
      // RF-REPORT-002: TODAY's REAL sales-by-hour (billed net, integer minor). A
      // day with no sales / a malformed payload maps to empty, so the chart stays
      // hidden — never a fabricated or flat-zero curve.
      hourlyNetSales: _hourly(raw['hourly']),
    );
  }

  /// Maps the RPC's `hourly: [{hour, net_minor}]` (RF-REPORT-002 — TODAY's
  /// branch-local sales-by-hour, integer minor) to the chart's [HourlyNetSales]
  /// rows (label `HH:00`). Non-list / malformed input, or a day with NO net sales
  /// in ANY hour, yields an EMPTY list so the data-gated chart stays hidden — the
  /// live-limited report never shows a fabricated or flat-zero curve.
  static List<HourlyNetSales> _hourly(Object? raw) {
    if (raw is! List) return const [];
    final rows = <HourlyNetSales>[];
    var anyNonZero = false;
    for (final row in raw) {
      if (row is! Map) continue;
      final hour = _int(row['hour']);
      if (hour < 0 || hour > 23) continue;
      final net = _int(row['net_minor']);
      if (net != 0) anyNonZero = true;
      rows.add(
        HourlyNetSales(
          hourLabel: '${hour.toString().padLeft(2, '0')}:00',
          netSalesMinor: net,
        ),
      );
    }
    return anyNonZero ? rows : const [];
  }

  /// Whether [e] means the `owner_daily_report` FUNCTION does not exist yet (so
  /// the deployed `sales_summary` is a safe compatibility fallback), as opposed
  /// to a permission / tenant / auth denial (which must stay fail-closed).
  ///
  /// NEVER treats an auth denial (SQLSTATE 42501 -> [SyncTransportErrorKind.auth])
  /// as missing — a denied caller must never be handed fallback data. Otherwise a
  /// PostgREST "could not find the function ... in the schema cache" (PGRST202, or
  /// the 404 some SDK versions surface) or a Postgres undefined-function message
  /// counts as missing.
  static bool _isMissingRpc(SyncTransportException e) {
    if (e.kind == SyncTransportErrorKind.auth) return false;
    final code = (e.code ?? '').toUpperCase();
    if (code == 'PGRST202' || code == '404') return true;
    final message = (e.message ?? '').toLowerCase();
    return message.contains('could not find the function') ||
        (message.contains('function') && message.contains('does not exist'));
  }

  /// Compatibility fallback (LIVE-DASHBOARD-001): reads the deployed
  /// `public.sales_summary` and maps the LIMITED figures it exposes (orders +
  /// completed-payment gross) into a [DashboardReport], PLUS a safe "vs yesterday"
  /// comparison derived from `last_7_days` (LIVE-UX-001, see [_priorDayComparison])
  /// so the Overview KPI deltas render instead of looking bare. Everything the
  /// summary does not carry — the billed/collected split, tender breakdown, voids,
  /// shift/cash, per-branch, top items, recent orders, and the hourly curve —
  /// stays at honest zero/empty (still the RF-140 "live · limited" report). Money
  /// is integer minor throughout (D-007). FAIL-CLOSED: a rejected body or a
  /// transport failure (including a permission denial on the summary itself)
  /// throws — the fallback never fabricates and never chains onward.
  Future<DashboardReport> _loadFromSalesSummary(
    SyncRpcTransport t,
    MembershipContext m,
  ) async {
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
    final ordersCount = today is Map ? _int(today['orders_count']) : 0;
    final paymentsCount = today is Map ? _int(today['payments_count']) : 0;
    final grossMinor = today is Map ? _int(today['gross_minor']) : 0;
    final days = raw['last_7_days'];
    final dateLabel = days is List && days.isNotEmpty && days.last is Map
        ? ((days.last as Map)['day'] ?? '').toString()
        : '';
    // sales_summary reports only completed-payment gross; with no discount engine
    // and cash-only payments in this build, net/collected/cash MIRROR it (they
    // MUST split once tenders/discounts land). openOrders is the honest
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
      // LIVE-UX-001: a SAFE "vs yesterday" comparison from last_7_days (lights up
      // the Overview KPI deltas so the live-limited report no longer looks bare).
      // Still no hourly curve (sales_summary has no hourly granularity) so the
      // sales-by-hour chart stays hidden — never fabricated.
      comparison: _priorDayComparison(days),
    );
  }

  /// A SAFE prior-day ("vs yesterday") comparison from `sales_summary.last_7_days`
  /// (LIVE-UX-001). The array is 6 prior days + today ascending, so `[len-2]` is
  /// yesterday; it carries ONLY `{day, orders_count, gross_minor}`. So ONLY these
  /// are honest and NOTHING is invented: gross/net/cash all map to yesterday's
  /// completed-payment `gross_minor` (the SAME identity the today-block uses in
  /// this limited build — net/cash MIRROR gross), and `orderCount` maps to
  /// yesterday's `orders_count` (same per-day definition as today's). A short or
  /// malformed array yields `null` (no delta — never a fabricated one), and
  /// `deltaPercent` already guards a zero prior. It is deliberately NOT used to
  /// synthesize a completed/unpaid comparison (last_7_days has no per-day
  /// payments_count) — that would be fabrication.
  static ReportComparison? _priorDayComparison(Object? sevenDays) {
    if (sevenDays is! List || sevenDays.length < 2) return null;
    final prior = sevenDays[sevenDays.length - 2];
    if (prior is! Map) return null;
    final priorGross = _int(prior['gross_minor']);
    return ReportComparison(
      grossSalesMinor: priorGross,
      netSalesMinor: priorGross,
      cashSalesMinor: priorGross,
      orderCount: _int(prior['orders_count']),
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
