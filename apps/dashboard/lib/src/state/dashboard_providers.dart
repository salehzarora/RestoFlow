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
// CODEX F-1B-3. The import graph between this file and the analytics-branch
// lifecycle is cyclic (that file needs the coverage and effective-selection
// providers defined here). The PROVIDER graph is not: it runs scope -> resolved
// live -> sanitised options -> raw options -> membership, and terminates. Dart
// initialises top-level finals lazily, so the cycle is a file-layout detail,
// not an initialisation order hazard.
import 'analytics_branch_providers.dart'
    show analyticsBranchAnswerProvider, resolvedLiveAnalyticsBranchProvider;
import 'audit_log_providers.dart' show auditBranchOptionsProvider;
import 'dashboard_membership_identity.dart';
import '../analytics/analytics_window.dart';
import '../analytics/custom_range_draft.dart';

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

/// CODEX R1A-01 — the membership as TRANSPORT/AUTHORIZATION identity.
///
/// Every provider that builds a request depends on THIS rather than on
/// [dashboardMembershipProvider]. `MembershipContext` has no `==`, so watching
/// it meant any new instance rebuilt the repositories — new financial RPCs, a
/// discarded Orders History page, pagination restarted — even when the only
/// difference was a display name. This value compares on the fields that decide
/// what is asked and what is permitted, and on nothing else, so a rename is a
/// no-op here and an authorization change is not.
///
/// Surfaces that render the membership keep watching the labelled provider.
final dashboardMembershipIdentityProvider =
    Provider<DashboardMembershipIdentity?>((ref) {
      final membership = ref.watch(dashboardMembershipProvider);
      return membership == null
          ? null
          : DashboardMembershipIdentity.of(membership);
    }, dependencies: [dashboardMembershipProvider]);

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
final ownerReportsRepositoryProvider = Provider<OwnerReportsRepository>(
  (ref) {
    final config = ref.watch(runtimeConfigProvider);
    if (config.isDemoMode) {
      return const DemoOwnerReportsRepository();
    }
    return RealOwnerReportsRepository(
      config.supabase,
      // R1A-01: identity, not the labelled membership.
      scope: ref.watch(dashboardMembershipIdentityProvider)?.membership,
      transport: ref.watch(dashboardAuthTransportProvider),
    );
  },
  dependencies: [
    dashboardMembershipIdentityProvider,
    dashboardAuthTransportProvider,
  ],
);

/// The selected reporting date range (RF-REPORT-004). The Overview's range chips
/// write this; the report provider watches it, so changing the range re-runs
/// `loadReport` for the new window. Defaults to today.
final reportRangeProvider = StateProvider<ReportRange>(
  (ref) => ReportRange.today,
);

/// DASHBOARD-VISUAL-RANGE-REFRESH-F1 — the committed CUSTOM window, or null when
/// a preset is selected.
///
/// ONLY EVER HOLDS A VALID WINDOW. [CustomAnalyticsWindow] cannot be constructed
/// out of range, so an incomplete or reversed draft is unrepresentable here and
/// therefore can never become query state. Draft dates live in F2's picker,
/// never in this provider.
final customAnalyticsWindowProvider = StateProvider<CustomAnalyticsWindow?>(
  (ref) => null,
);

/// The ONE committed analytics window — the canonical selection every analytics
/// request is built from.
///
/// DERIVED, not a third source of truth: a custom window wins when one is
/// committed, otherwise the preset does. [reportRangeProvider] stays the preset
/// channel so the existing chips and the thirteen suites that drive them keep
/// working unchanged, and this reads DOWNSTREAM of it — one direction only.
///
/// Commit through [commitAnalyticsPreset] / [commitCustomAnalyticsWindow] rather
/// than writing either channel directly; selecting a preset must also clear a
/// committed custom window, and doing that in one place is what stops the two
/// channels from disagreeing about what is selected.
final analyticsWindowProvider = Provider<AnalyticsWindow>((ref) {
  final custom = ref.watch(customAnalyticsWindowProvider);
  if (custom != null) return custom;
  return AnalyticsWindow.preset(
    AnalyticsRange.fromReportRange(ref.watch(reportRangeProvider)),
  );
}, dependencies: [reportRangeProvider, customAnalyticsWindowProvider]);

/// Commits a PRESET, clearing any committed custom window.
void commitAnalyticsPreset(WidgetRef ref, ReportRange range) {
  ref.read(customAnalyticsWindowProvider.notifier).state = null;
  ref.read(reportRangeProvider.notifier).state = range;
}

/// Commits a validated CUSTOM window. [window] is already valid by construction.
///
/// Also remembers it in [lastCustomAnalyticsWindowProvider] so reopening the
/// sheet after a detour through a preset starts from what the owner last chose.
void commitCustomAnalyticsWindow(WidgetRef ref, CustomAnalyticsWindow window) {
  ref.read(lastCustomAnalyticsWindowProvider.notifier).state = window;
  ref.read(customAnalyticsWindowProvider.notifier).state = window;
}

/// DASHBOARD-VISUAL-RANGE-REFRESH-F2 — the custom-range DRAFT.
///
/// Deliberately NOT part of any query key, and deliberately not the committed
/// window: this is what the owner is typing, and typing a From date must not
/// issue a request. It reaches [customAnalyticsWindowProvider] only through
/// Apply.
final customRangeDraftProvider = StateProvider<CustomRangeDraft>(
  (ref) => CustomRangeDraft.empty,
);

/// The last custom window committed THIS SESSION, for reopening the sheet.
///
/// Memory, not truth: selecting a preset clears the committed custom window but
/// leaves this alone, so returning to Custom offers the previous dates instead
/// of an empty sheet. Nothing reads it to build a request, which is what keeps
/// it from becoming a second source of truth.
final lastCustomAnalyticsWindowProvider = StateProvider<CustomAnalyticsWindow?>(
  (ref) => null,
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

/// CODEX R1A-01 — the covered scope as a LABEL-FREE identity.
///
/// [dashboardCoveredScopeProvider] keeps its label because the selector renders
/// it for a branch-fixed membership. But the branch-option chain hangs off
/// coverage, and for that membership `coveredBy` copies `branchName` into the
/// scope — so a rename produced an unequal coverage and RE-ENUMERATED the
/// branches, discarding and re-fetching the very answer the omission machinery
/// depends on. Everything downstream of coverage that only needs ids reads this.
final dashboardCoveredScopeIdentityProvider =
    Provider<DashboardAnalyticsScope?>(
      (ref) => ref.watch(dashboardCoveredScopeProvider)?.transportIdentity,
      dependencies: [dashboardCoveredScopeProvider],
    );

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
///
/// CODEX F-1B-3 — it now reads [resolvedLiveAnalyticsBranchProvider], which
/// adds the second question coverage cannot answer: does this branch still
/// EXIST. A branch a successful option list omits stops applying here, so a
/// deleted or tombstoned branch can no longer remain a hidden financial scope
/// while the selector shows "All permitted branches". A LOADING or FAILED list
/// changes nothing, so a flaky fetch never widens the figures.
///
/// THE FALLBACK IS [covered], AND THAT IS THE WHOLE OMISSION RULE. Coverage is
/// the authorized PARENT of whatever was selected, so an omitted branch lands
/// on org/null/null for an org-wide owner, on org/rest/null for a
/// restaurant-wide owner — never on a sibling restaurant — and, for a
/// branch-FIXED membership whose coverage IS one branch, on that same branch.
/// A fixed membership therefore cannot be widened by an option list that fails
/// to enumerate its branch, because its authorization never came from the list
/// in the first place.
final dashboardAnalyticsScopeProvider = Provider<DashboardAnalyticsScope?>(
  (ref) {
    final covered = ref.watch(dashboardCoveredScopeProvider);
    if (covered == null) return null;
    final selected = ref.watch(resolvedLiveAnalyticsBranchProvider);
    if (selected == null) return covered;
    return DashboardAnalyticsScope.branch(
      organizationId: covered.organizationId,
      option: selected,
    );
  },
  dependencies: [
    dashboardCoveredScopeProvider,
    resolvedLiveAnalyticsBranchProvider,
  ],
);

/// CODEX F-1B-1-R1 — the analytics scope as a REQUEST identity: the same ids
/// and kind, with the display label stripped.
///
/// Providers that build a request watch THIS, so a branch rename cannot rebuild
/// them. [dashboardAnalyticsScopeProvider] keeps the label, because the Overview
/// selector and the Orders scope indicator have to render the branch's current
/// name — the two consumers genuinely want different things, and the split says
/// so rather than leaving each caller to remember.
final analyticsTransportScopeProvider = Provider<DashboardAnalyticsScope?>(
  (ref) => ref.watch(dashboardAnalyticsScopeProvider)?.transportIdentity,
  dependencies: [dashboardAnalyticsScopeProvider],
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
final currentOwnerReportKeyProvider = Provider<OwnerReportQueryKey>(
  (ref) {
    final scope = ref.watch(dashboardAnalyticsScopeProvider);
    return OwnerReportQueryKey(
      organizationId: scope?.organizationId,
      restaurantId: scope?.restaurantId,
      branchId: scope?.branchId,
      range: ref.watch(reportRangeProvider),
      customWindow: ref.watch(customAnalyticsWindowProvider),
      isDemoMode: ref.watch(runtimeConfigProvider).isDemoMode,
    );
  },
  dependencies: [
    dashboardAnalyticsScopeProvider,
    reportRangeProvider,
    customAnalyticsWindowProvider,
  ],
);

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
      // CODEX F-1A: the key's OWN scope goes to the request the key identifies,
      // so the ids on the wire and the ids the result is filed under cannot
      // drift apart — including for a retained entry re-run after a rebuild.
      return ref
          .watch(ownerReportsRepositoryProvider)
          .loadReport(
            range: key.range,
            analyticsScope: key.analyticsScope,
            customWindow: key.customWindow,
          );
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
      // R1A-01: identity, not the labelled membership.
      scope: ref.watch(dashboardMembershipIdentityProvider)?.membership,
      transport: ref.watch(dashboardAuthTransportProvider),
    );
  },
  dependencies: [
    dashboardMembershipIdentityProvider,
    dashboardAuthTransportProvider,
  ],
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
final currentOwnerSalesSeriesKeyProvider = Provider<OwnerSalesSeriesQueryKey?>(
  (ref) {
    final custom = ref.watch(customAnalyticsWindowProvider);
    final range = AnalyticsRange.fromReportRange(
      ref.watch(reportRangeProvider),
    );
    // A custom window ALWAYS has a series: it is a date range, not a single-day
    // view, so the hourly-curve shortcut that suppresses the trend for
    // today/yesterday must not suppress it here.
    if (custom == null && range.isSingleDay) return null;
    final scope = ref.watch(dashboardAnalyticsScopeProvider);
    return OwnerSalesSeriesQueryKey(
      organizationId: scope?.organizationId,
      restaurantId: scope?.restaurantId,
      branchId: scope?.branchId,
      range: range,
      customWindow: custom,
      isDemoMode: ref.watch(runtimeConfigProvider).isDemoMode,
    );
  },
  dependencies: [
    dashboardAnalyticsScopeProvider,
    reportRangeProvider,
    customAnalyticsWindowProvider,
  ],
);

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
      // CODEX F-1A: same invariant as the report family — the key carries its
      // scope into its own request.
      return ref
          .watch(ownerSalesSeriesRepositoryProvider)
          .loadSeries(
            range: key.range,
            analyticsScope: key.analyticsScope,
            customWindow: key.customWindow,
          );
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
/// CODEX F-1B-3-R1C — THE BRANCH LIST IS REFRESHED HERE TOO, AND FIRST.
///
/// Until now nothing in production ever re-ran `list_org_structure`. The
/// authoritative-omission machinery was therefore only reachable in tests: a
/// branch deleted mid-session stayed selectable, and stayed the financial
/// scope, for the life of the session. The refresh the owner already has is the
/// right place for it — no polling, no second button, no refresh on tab
/// changes, and the SAME shared container, so one enumeration serves every
/// surface.
///
/// ORDER MATTERS. Invalidating the report first would refetch branch B, and
/// only then would the enumeration report B gone and refetch the parent — one
/// avoidable request for a scope the owner is no longer in, with its result
/// briefly on screen. Settling the branch answer first means the financial
/// invalidation reads the key the answer produced, so exactly one report
/// request goes out and it is for the right scope.
///
/// A FAILED enumeration does not block the refresh: the last authoritative
/// answer still stands (F-1B-3-R1), so the financial half re-runs against the
/// retained scope. Refreshing must never be able to widen the figures.
/// CODEX R1C-03 — the refresh SEQUENCE, owned by the shared container.
///
/// It used to run on the Overview's `WidgetRef`, awaiting the branch
/// enumeration and then checking `ref.context.mounted` before touching the
/// financial families. Crossing the responsive breakpoint mid-flight remounts
/// that widget, so the check failed and the second half was simply skipped: the
/// branch authority updated while every figure on the page stayed stale, and
/// nothing said so. Whether a data refresh COMPLETES must not depend on whether
/// a particular widget survived.
///
/// Living in a [StateNotifierProvider] moves the continuation onto a `Ref` with
/// the container's lifetime — the same hoisted container the branch answer and
/// the report families live in — so a remount, a tab change or a resize cannot
/// cancel it.
///
/// The state is whether a refresh is in flight, and it is also the single-flight
/// gate: a second tap joins the running refresh instead of starting a rival one,
/// so two sequences can never interleave their invalidations or land their
/// results out of order.
class DashboardRefreshController extends StateNotifier<bool> {
  DashboardRefreshController(this._ref) : super(false);

  final Ref _ref;
  Future<void>? _inFlight;

  /// Runs the refresh, or joins the one already running.
  Future<void> refresh() => _inFlight ??= _run().whenComplete(() {
    _inFlight = null;
    if (mounted) state = false;
  });

  Future<void> _run() async {
    state = true;
    // ORDER MATTERS (F-1B-3-R1C). Invalidating the report first would refetch
    // the current branch, and only then would the enumeration report it gone
    // and refetch the parent — one avoidable request for a scope the owner is
    // no longer in, with its result briefly on screen. Settling the branch
    // answer first means the financial invalidation reads the key that answer
    // produced.
    //
    // No membership (demo mode) means there is no branch list to re-read.
    if (_ref.read(dashboardCoveredScopeIdentityProvider) != null) {
      _ref.invalidate(auditBranchOptionsProvider);
      try {
        await _ref.read(analyticsBranchAnswerProvider.future);
      } catch (_) {
        // Technical failure: the last authoritative answer stands, and the
        // figures refresh against it. Refreshing must never widen the scope.
      }
      // CODEX FINDING 5 - the container may be GONE by now.
      //
      // Surviving a widget remount was the point of moving here (R1C-03), but
      // sign-out disposes the whole shell container, and a continuation that
      // then reads or invalidates a disposed `Ref` throws where nobody is
      // waiting to catch it. `mounted` is the notifier's own lifetime, which is
      // exactly the container's, so it answers the only question that matters:
      // is there still an authorization context to refresh for. Nothing is
      // requested after it says no.
      if (!mounted) return;
    }
    _ref.invalidate(
      ownerReportForKeyProvider(_ref.read(currentOwnerReportKeyProvider)),
    );
    final seriesKey = _ref.read(currentOwnerSalesSeriesKeyProvider);
    if (seriesKey != null) {
      _ref.invalidate(ownerSalesSeriesForKeyProvider(seriesKey));
    }
  }
}

/// True while a refresh is in flight.
final dashboardRefreshControllerProvider =
    StateNotifierProvider<DashboardRefreshController, bool>(
      DashboardRefreshController.new,
      dependencies: [
        dashboardCoveredScopeIdentityProvider,
        auditBranchOptionsProvider,
        analyticsBranchAnswerProvider,
        currentOwnerReportKeyProvider,
        currentOwnerSalesSeriesKeyProvider,
        ownerReportForKeyProvider,
        ownerSalesSeriesForKeyProvider,
      ],
    );

/// The Overview's refresh action. A thin call into the controller above, kept
/// under its original name so every existing call site and test is unchanged.
Future<void> refreshOwnerReport(WidgetRef ref) =>
    ref.read(dashboardRefreshControllerProvider.notifier).refresh();
