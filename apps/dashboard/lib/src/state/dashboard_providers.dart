import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../analytics/analytics_range.dart';
import '../analytics/owner_report_query_key.dart';
import '../analytics/owner_sales_series_query_key.dart';
import '../data/demo_report.dart';
import '../data/owner_reports_repository.dart';
import '../data/owner_sales_series.dart';
import '../data/owner_sales_series_repository.dart';
import '../data/real_owner_reports_repository.dart';
import '../data/real_owner_sales_series_repository.dart';

/// The active dashboard membership scope (org/restaurant/branch), overridden by
/// the shell's Overview scope for real mode (sprint). Null in demo mode (the
/// DEFAULT) or before a membership is selected; the real repo treats null as
/// unscoped and fails closed.
final dashboardMembershipProvider = Provider<MembershipContext?>(
  (ref) => null,
  dependencies: const [],
);

/// The AUTHENTICATED dashboard RPC transport (the session-carrying
/// supabase_flutter client), overridden by the shell for real mode (sprint).
/// Null => real reads fail closed (never a fresh, session-less client).
final dashboardAuthTransportProvider = Provider<SyncRpcTransport?>(
  (ref) => null,
  dependencies: const [],
);

/// The owner-reports data seam (RF-119).
///
/// SINGLE swap point. The demo/real choice is decided by [runtimeConfigProvider]
/// (the one audited mode switch): demo mode - the DEFAULT (RESTOFLOW_DEMO_MODE
/// defaults to true) - keeps the verbatim [DemoOwnerReportsRepository] computing
/// from the structured demo dataset; real mode returns the
/// [RealOwnerReportsRepository] reading `public.sales_summary` (sprint) over the
/// authenticated transport, scoped to the active membership. With no
/// transport/scope it fails closed (see [RealRepoNotWiredError]) and the
/// existing error state surfaces it.
final ownerReportsRepositoryProvider = Provider<OwnerReportsRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return const DemoOwnerReportsRepository();
  }
  return RealOwnerReportsRepository(
    config.supabase,
    scope: ref.watch(dashboardMembershipProvider),
    transport: ref.watch(dashboardAuthTransportProvider),
  );
}, dependencies: [dashboardMembershipProvider, dashboardAuthTransportProvider]);

/// The selected reporting date range (RF-REPORT-004). The Overview's range chips
/// write this; the report provider watches it, so changing the range re-runs
/// `loadReport` for the new window. Defaults to today.
final reportRangeProvider = StateProvider<ReportRange>(
  (ref) => ReportRange.today,
);

/// F0.6 — the identity of the report the Overview is currently asking for.
///
/// Derived, never written by a screen: it reads the same scope the repository
/// posts (`p_organization_id` / `p_restaurant_id` / `p_branch_id` / `p_range`)
/// plus the demo-vs-real source. Drill-down state deliberately cannot reach it,
/// so a business filter can never rewrite tenant identity.
final currentOwnerReportKeyProvider = Provider<OwnerReportQueryKey>((ref) {
  final membership = ref.watch(dashboardMembershipProvider);
  return OwnerReportQueryKey(
    organizationId: membership?.organizationId,
    restaurantId: membership?.restaurantId,
    branchId: membership?.branchId,
    range: ref.watch(reportRangeProvider),
    isDemoMode: ref.watch(runtimeConfigProvider).isDemoMode,
  );
}, dependencies: [dashboardMembershipProvider, reportRangeProvider]);

/// F0.6 — the owner report FOR ONE EXACT REQUEST IDENTITY.
///
/// Keyed by [OwnerReportQueryKey] so two scopes, or two ranges, are two
/// entries that can never satisfy each other. Not `autoDispose`: an entry
/// outlives the Overview subtree, which is the whole point — the shell rebuilds
/// each tab under a keyed subtree, so leaving and returning used to throw the
/// result away and refetch.
///
/// Retention is bounded by the key space, not by a timer. A session's keys are
/// (ranges the owner picked) x (scopes they are authorized for) — a handful,
/// each a small report. No eviction timer is introduced, because a flaky
/// time-based test is a worse problem than holding four reports.
///
/// A FAILED entry is not sticky: the family still throws for that key, and the
/// refresh action re-runs it, so an error is always retryable.
final ownerReportForKeyProvider =
    FutureProvider.family<DashboardReport, OwnerReportQueryKey>((ref, key) {
      return ref
          .watch(ownerReportsRepositoryProvider)
          .loadReport(range: key.range);
    }, dependencies: [ownerReportsRepositoryProvider]);

/// The owner dashboard report for the CURRENT key.
///
/// Kept under its original name and type so every existing consumer compiles
/// unchanged; it is now a thin projection of [ownerReportForKeyProvider]. The
/// grouped single-request shape is unchanged — this is still one call per key,
/// never one per KPI.
///
/// Refresh through [refreshOwnerReport], which targets ONLY the current key.
/// Stays a [FutureProvider] so every existing consumer — including
/// `.future` in tests — keeps working unchanged. It delegates to the keyed
/// entry rather than loading anything itself: when that entry has already
/// resolved, awaiting its future returns the cached report WITHOUT a second
/// repository call, which is precisely the tab-return behaviour F0.6 needed.
final dashboardReportProvider = FutureProvider<DashboardReport>((ref) {
  final key = ref.watch(currentOwnerReportKeyProvider);
  return ref.watch(ownerReportForKeyProvider(key).future);
}, dependencies: [ownerReportForKeyProvider, currentOwnerReportKeyProvider]);

/// CLIENT-A — the daily sales-series data seam (`owner_sales_series`).
///
/// The same demo/real switch [ownerReportsRepositoryProvider] uses, so the two
/// owner surfaces can never end up reading different data sources at once. Demo
/// is the DEFAULT; real mode fails closed with no transport/scope.
final ownerSalesSeriesRepositoryProvider = Provider<OwnerSalesSeriesRepository>(
  (ref) {
    if (ref.watch(runtimeConfigProvider).isDemoMode) {
      return const DemoOwnerSalesSeriesRepository();
    }
    return RealOwnerSalesSeriesRepository(
      scope: ref.watch(dashboardMembershipProvider),
      transport: ref.watch(dashboardAuthTransportProvider),
    );
  },
  dependencies: [dashboardMembershipProvider, dashboardAuthTransportProvider],
);

/// CLIENT-A — the identity of the sales series the Overview currently needs, or
/// NULL when it needs none.
///
/// Null is the load gate, and it is a provider rather than a rule the UI has to
/// remember: `today` and `yesterday` keep their existing sales-by-HOUR curve,
/// which already answers "how did this day go", so asking the server to break a
/// single day into one daily bucket would be a second round trip for a chart
/// with one point. Only the multi-day ranges produce a key, and a family entry
/// with no key is never watched, so no request is issued at all.
///
/// Scope is read from the resolved membership, exactly like the report key —
/// drill-down and filter state deliberately cannot reach it.
final currentOwnerSalesSeriesKeyProvider = Provider<OwnerSalesSeriesQueryKey?>((
  ref,
) {
  final range = AnalyticsRange.fromReportRange(ref.watch(reportRangeProvider));
  if (range.isSingleDay) return null;
  final membership = ref.watch(dashboardMembershipProvider);
  return OwnerSalesSeriesQueryKey(
    organizationId: membership?.organizationId,
    restaurantId: membership?.restaurantId,
    branchId: membership?.branchId,
    range: range,
    isDemoMode: ref.watch(runtimeConfigProvider).isDemoMode,
  );
}, dependencies: [dashboardMembershipProvider, reportRangeProvider]);

/// CLIENT-A — the sales series FOR ONE EXACT REQUEST IDENTITY.
///
/// Keyed like [ownerReportForKeyProvider] and for the same reason: two scopes,
/// or two ranges, are two entries that can never satisfy each other. Not
/// `autoDispose` — the shell rebuilds each tab under a keyed subtree, so an
/// auto-disposing entry would refetch every time the owner left Overview and
/// came back, which is the exact defect F0.6 fixed for the report.
final ownerSalesSeriesForKeyProvider =
    FutureProvider.family<OwnerSalesSeries, OwnerSalesSeriesQueryKey>((
      ref,
      key,
    ) {
      return ref
          .watch(ownerSalesSeriesRepositoryProvider)
          .loadSeries(range: key.range);
    }, dependencies: [ownerSalesSeriesRepositoryProvider]);

/// Refreshes ONLY the currently selected report entry — and the daily series
/// beside it, when the selected range has one.
///
/// `invalidate` rather than `refresh`: the caller does not want the Future, and
/// invalidate re-runs the entry lazily for the widgets already watching it,
/// which is exactly one new repository call. `refresh` would additionally
/// return a Future nobody awaits. Other ranges and other scopes keep their
/// cached results — a refresh is "re-read what I am looking at", not "throw
/// away everything the dashboard knows".
///
/// The series is included because the refresh button sits above BOTH: leaving
/// the trend stale while the KPIs above it updated would make the page
/// self-contradictory, and an owner would have no way to tell which half was
/// current.
void refreshOwnerReport(WidgetRef ref) {
  ref.invalidate(
    ownerReportForKeyProvider(ref.read(currentOwnerReportKeyProvider)),
  );
  final seriesKey = ref.read(currentOwnerSalesSeriesKeyProvider);
  if (seriesKey != null) {
    ref.invalidate(ownerSalesSeriesForKeyProvider(seriesKey));
  }
}
