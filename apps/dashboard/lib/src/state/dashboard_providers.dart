import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../analytics/analytics_range.dart';
import '../analytics/dashboard_analytics_scope.dart';
import '../analytics/owner_report_query_key.dart';
import '../analytics/owner_sales_series_query_key.dart';
import '../data/audit_log_models.dart' show AuditBranchOption;
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

/// CLIENT-E1 — the BROADEST scope the current membership is authorized to
/// report on. Null when no membership is resolved (demo mode, or before the
/// shell publishes one).
///
/// Derived from the ROLE, never from the resolved membership's ids: those have
/// already been narrowed to a concrete first-restaurant / first-branch by
/// `resolveTenantContext`, so they cannot say what the membership covers. This
/// is the same recovery the Activity branch filter has always used.
final dashboardCoveredScopeProvider = Provider<DashboardAnalyticsScope?>((ref) {
  final membership = ref.watch(dashboardMembershipProvider);
  if (membership == null) return null;
  return DashboardAnalyticsScope.coveredBy(membership);
}, dependencies: [dashboardMembershipProvider]);

/// CLIENT-E1 — the owner's explicit branch choice, or null for "all permitted".
///
/// Written ONLY by the Overview scope selector. Null is not "unknown"; it is
/// the deliberate broad default, which is the whole point of this slice — an
/// org owner now starts at their organization rather than at whichever branch
/// happened to be created first.
///
/// Session-lived and in-memory. No persistence is introduced here: a remembered
/// selection would have to be re-authorized on every membership change, and
/// that is a larger contract than this slice owns.
final selectedAnalyticsBranchProvider = StateProvider<AuditBranchOption?>(
  (ref) => null,
);

/// CODEX F-1 — the selection AFTER coverage sanitisation, or null.
///
/// This is the ONE place a raw selection becomes an effective one, and it is a
/// separate provider so the invariant is observable rather than implied: the
/// scope selector renders THIS value, so a control can never sit on an option
/// that is not in its own item list.
///
/// WHY SANITISE RATHER THAN RESET THE RAW STATE. The obvious fix — have
/// [selectedAnalyticsBranchProvider] watch the membership so it re-initialises
/// — would give it a `dependencies` entry on a provider the shell OVERRIDES per
/// surface. Riverpod then instantiates the selection in each overriding
/// container (`container.dart` places a provider in the deepest container that
/// overrides any of its transitive dependencies), so Overview and Orders would
/// each get their OWN selection and CLIENT-E2's cross-surface synchronisation
/// would silently break. Keeping the raw state dependency-free keeps it at the
/// root, shared, and sanitising on read gives the same guarantee without that
/// fragility.
///
/// A selection that becomes valid again — the owner switches back to the
/// organization they made it in — simply starts applying again, which is the
/// behaviour an owner expects from their own last choice.
final effectiveAnalyticsBranchProvider = Provider<AuditBranchOption?>(
  (ref) {
    final covered = ref.watch(dashboardCoveredScopeProvider);
    final selected = ref.watch(selectedAnalyticsBranchProvider);
    if (covered == null || selected == null) return null;
    return covered.covers(selected) ? selected : null;
  },
  dependencies: [
    dashboardCoveredScopeProvider,
    selectedAnalyticsBranchProvider,
  ],
);

/// CLIENT-E1 — the scope every Overview analytic actually reads.
///
/// The selection is applied ONLY when the current coverage still contains it —
/// including its ORGANIZATION (CODEX F-1). That check is the fail-closed guard
/// for a membership that changed underneath a stale selection: an owner
/// demoted to one branch, moved to another restaurant, or signed out and
/// replaced by a different organization's owner falls back to their real
/// coverage rather than keeping an id they may no longer read. Coverage is
/// role-derived, so this is true the instant the membership changes — it does
/// not wait for an option list.
final dashboardAnalyticsScopeProvider = Provider<DashboardAnalyticsScope?>(
  (ref) {
    final covered = ref.watch(dashboardCoveredScopeProvider);
    if (covered == null) return null;
    final selected = ref.watch(effectiveAnalyticsBranchProvider);
    if (selected == null) return covered;
    return DashboardAnalyticsScope.branch(
      organizationId: covered.organizationId,
      option: selected,
    );
  },
  dependencies: [
    dashboardCoveredScopeProvider,
    effectiveAnalyticsBranchProvider,
  ],
);

/// F0.6 / CLIENT-E1 — the identity of the report the Overview is asking for.
///
/// Derived, never written by a screen: it reads the same scope the repository
/// posts (`p_organization_id` / `p_restaurant_id` / `p_branch_id` / `p_range`)
/// plus the demo-vs-real source. Drill-down state deliberately cannot reach it,
/// so a business filter can never rewrite tenant identity.
///
/// CLIENT-E1 swaps the membership's NARROWED ids for the selected analytics
/// scope. The key space is unchanged — same three ids, same cache — so two
/// branches, or a branch and "all permitted", remain two entries that can never
/// satisfy each other.
final currentOwnerReportKeyProvider = Provider<OwnerReportQueryKey>((ref) {
  final scope = ref.watch(dashboardAnalyticsScopeProvider);
  return OwnerReportQueryKey(
    organizationId: scope?.organizationId,
    restaurantId: scope?.restaurantId,
    branchId: scope?.branchId,
    range: ref.watch(reportRangeProvider),
    isDemoMode: ref.watch(runtimeConfigProvider).isDemoMode,
  );
}, dependencies: [dashboardAnalyticsScopeProvider, reportRangeProvider]);

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
/// Scope is read from the SAME selected analytics scope the report key uses
/// (CLIENT-E1), so the KPIs and every trend on the page describe one window of
/// one scope — there is no arrangement in which the headline figures show one
/// branch while the charts below them show all of them. Drill-down and filter
/// state deliberately cannot reach it.
///
/// The single-day gate still comes FIRST: changing the selected branch on
/// today or yesterday still produces no key, and therefore still issues no
/// `owner_sales_series` request at all.
final currentOwnerSalesSeriesKeyProvider = Provider<OwnerSalesSeriesQueryKey?>((
  ref,
) {
  final range = AnalyticsRange.fromReportRange(ref.watch(reportRangeProvider));
  if (range.isSingleDay) return null;
  final scope = ref.watch(dashboardAnalyticsScopeProvider);
  return OwnerSalesSeriesQueryKey(
    organizationId: scope?.organizationId,
    restaurantId: scope?.restaurantId,
    branchId: scope?.branchId,
    range: range,
    isDemoMode: ref.watch(runtimeConfigProvider).isDemoMode,
  );
}, dependencies: [dashboardAnalyticsScopeProvider, reportRangeProvider]);

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
