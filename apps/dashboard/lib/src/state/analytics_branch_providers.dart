/// CODEX F-1B — the analytics branch selection LIFECYCLE.
///
/// Two questions were being answered by one provider, and they are not the same
/// question:
///
///  * **May I report on this branch?** Role coverage answers it, immediately
///    and without a network call. That is `effectiveAnalyticsBranchProvider`,
///    and it is the security sanitiser — it must never wait for a list, because
///    a membership change has to take effect at once.
///
///  * **Does this branch still exist?** Only the authoritative branch-option
///    list answers it, and only once it has actually LOADED.
///
/// Collapsing the second into the first is what left a deleted, tombstoned or
/// otherwise authoritatively-omitted branch as a HIDDEN financial scope: the
/// selector could not offer it, so it showed "All permitted branches", while
/// `owner_report_range` and `owner_sales_series` kept querying it — forever,
/// and usually to an empty result. Not a tenant leak (the ids stayed
/// authorized) but a lie about what the numbers on screen describe.
///
/// The distinction is load-bearing in BOTH directions:
///
///  * while the list is LOADING or FAILED, nothing has been learned, so the
///    selection stands. A flaky `list_org_structure` must not silently widen an
///    owner's financial scope;
///  * once the list has SUCCEEDED it is authoritative about existence, so a
///    selection it omits stops applying.
///
/// The raw selection is left in place rather than reset. Resetting it would
/// mean writing a provider from inside another provider's build — the
/// side-effect-in-build hazard — or giving the raw `StateProvider` a
/// `dependencies` entry, which Riverpod uses to place it in the deepest
/// container that overrides any transitive dependency; the shell overrides
/// `dashboardMembershipProvider` per surface, so Overview and Orders would each
/// get their OWN selection and CLIENT-E2's cross-surface synchronisation would
/// break silently. Resolving on READ keeps the raw state dependency-free at the
/// root and makes the stale value INERT everywhere that matters: the selector
/// renders the resolved value, the analytics scope reads the resolved value,
/// and the family cache keys read the scope.
///
/// One consequence is deliberate and documented: if the omitted branch REAPPEARS
/// in a later successful list and is still covered, it resumes. Both gates must
/// hold — authorization AND live presence — so resumption cannot revive a branch
/// the owner may no longer read, and it matches what an owner expects of their
/// own last choice when a transient server-side omission ends.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/dashboard_analytics_scope.dart';
import '../data/audit_log_models.dart' show AuditBranchOption;
import 'audit_log_providers.dart' show auditBranchOptionsProvider;
import 'dashboard_providers.dart'
    show
        dashboardCoveredScopeIdentityProvider,
        effectiveAnalyticsBranchProvider;

/// One real answer about which branches exist, STAMPED with the authorization
/// context it was loaded for.
///
/// The stamp is the point. Riverpod keeps a provider's previous value across a
/// rebuild — including a rebuild caused by a DEPENDENCY CHANGE, and including
/// one whose reload then fails. Verified, not assumed: switching the membership
/// leaves `AsyncLoading(value: <previous>)`, and if the new load then throws it
/// leaves `AsyncError(value: <previous>)`. Both report `hasValue == true`. So
/// "the last successful answer" is not by itself a safe question — organization
/// A's answer is still sitting there while organization B is asking.
///
/// Neither `isRefreshing` nor `isReloading` separates the two cases (the
/// dependency-change-then-failure state is not "loading" at all), so the
/// context is recorded here, at the moment the answer is produced, and checked
/// on the way out. `list_org_structure` is NOT re-issued: this awaits the
/// existing [auditBranchOptionsProvider] future, so Activity, Active Orders and
/// the analytics scope still share one request.
class AnalyticsBranchAnswer {
  const AnalyticsBranchAnswer({required this.context, required this.options});

  /// The coverage this answer describes, as a LABEL-FREE identity. An answer
  /// whose context is not the current one answers a question nobody is asking
  /// any more.
  ///
  /// CODEX F-1B-3-R1A — label-free, because the stamp decides whether a
  /// remembered answer still applies and a display name has no business in that
  /// decision. `DashboardAnalyticsScope.coveredBy` copies `membership.branchName`
  /// into `branchLabel` for a branch-fixed membership, and scope equality
  /// includes it, so RENAMING that branch changed the stamp: the answer was
  /// discarded, the context read as "never answered", and the resolution fell
  /// back to the raw selection — the same resurrection F-1B-3-R1 exists to
  /// prevent, reached through a rename instead of a failure.
  ///
  /// Null only where there is no membership at all (demo mode), which is also a
  /// context: it matches the current null coverage and mismatches any real one.
  final DashboardAnalyticsScope? context;

  /// Conflict-sanitised, coverage-filtered branches. Empty is an ANSWER.
  final List<AuditBranchOption> options;
}

final analyticsBranchAnswerProvider = FutureProvider<AnalyticsBranchAnswer>(
  (ref) async {
    // R1A-01: the LABEL-FREE coverage, so renaming a branch cannot re-enumerate.
    final covered = ref.watch(dashboardCoveredScopeIdentityProvider);
    final raw = await ref.watch(auditBranchOptionsProvider.future);
    return AnalyticsBranchAnswer(
      // The IDS this answer was loaded under, never the name they had at the time.
      context: covered,
      options: sanitizeAnalyticsBranchOptions(raw, coverage: covered),
    );
  },
  dependencies: [
    dashboardCoveredScopeIdentityProvider,
    auditBranchOptionsProvider,
  ],
);

/// CODEX F-1B-2 / F-1B-3-R1 — the LAST REAL ANSWER for the CURRENT
/// authorization context, or null if there has not been one.
///
/// One provider so the CONTROL and the SCOPE can never disagree about which
/// branches are real. Computing the selectable list inside the widget is
/// precisely how a rule applied in one place and not the other went unnoticed.
///
/// WHY "LAST REAL ANSWER" AND NOT "CURRENTLY SUCCESSFUL". The first version
/// asked whether the CURRENT state is `AsyncData` and fell back to the raw
/// selection otherwise. That has a hole with a memory: once a successful list
/// has authoritatively omitted branch B and the scope has moved to the parent,
/// a later FAILED refresh is not `AsyncData` — so the rule fell back to the
/// still-stored raw B and RESURRECTED it, moving the money back to a branch no
/// successful response had reintroduced. Nothing had said B was back; the
/// client had merely stopped knowing, and treated that as permission.
///
/// So: resolve against the last real answer when there is one for THIS context,
/// and fall back to the raw selection only when the question has never been
/// answered here. Ignorance never restores a branch; only another real answer
/// containing it can.
final analyticsBranchOptionsProvider = Provider<List<AuditBranchOption>?>(
  (ref) {
    // CODEX FINDING 3 — a null coverage is DEMO MODE, not "no branches".
    // Returning an empty list here made every demo branch selection reconcile
    // to "All", which silently disabled branch filtering on Activity and the
    // active board in the one mode where nothing is authorized at all. The
    // answer stands on its own: it is stamped with the null context and matches
    // it, so the demo option list is a real answer like any other.
    final covered = ref.watch(dashboardCoveredScopeIdentityProvider);
    final async = ref.watch(analyticsBranchAnswerProvider);
    // Never answered at all — which is not "answered: none".
    if (!async.hasValue) return null;
    final answer = async.requireValue;
    // Answered, but for a membership/coverage we have since left. Compared on
    // IDS ONLY (F-1B-3-R1A) so a branch rename cannot look like a new context.
    if (answer.context != covered) return null;
    return answer.options;
  },
  dependencies: [
    dashboardCoveredScopeIdentityProvider,
    analyticsBranchAnswerProvider,
  ],
);

/// CODEX R1C-02 — whether [branch] is still a usable filter, given what is
/// authorized and what the last real answer said.
///
/// The SAME question the analytics scope asks, exposed for the operational
/// surfaces so Activity and Active Orders cannot answer it differently. They
/// each own their own branch filter (that is deliberate — the F-6 product
/// decision about unifying them is still open), but "does this branch still
/// apply" is not a matter of opinion.
///
///  * outside current coverage -> no, immediately. A membership change makes a
///    foreign branch inert before any list is consulted;
///  * never answered here -> yes. Ignorance is not removal;
///  * answered, and the answer contains it exactly once -> yes;
///  * answered, and it is absent — deleted, tombstoned, or dropped as a
///    conflicting composite -> no.
/// [coverageRequired] is REAL MODE. There, an authorized coverage is mandatory
/// and a missing one fails closed — a request must never escape the coverage
/// check merely because the check had nothing to say. Demo mode has no
/// membership and therefore no coverage at all, so validity comes from the demo
/// option list instead; treating its null coverage as "not covered" is what
/// disabled demo branch filtering (CODEX FINDING 3).
bool analyticsBranchStillApplies(
  AuditBranchOption branch, {
  required DashboardAnalyticsScope? coverage,
  required List<AuditBranchOption>? answer,
  required bool coverageRequired,
}) {
  if (coverage != null) {
    if (!coverage.covers(branch)) return false;
  } else if (coverageRequired) {
    return false;
  }
  if (answer == null) return true;
  return answer.where((o) => sameAnalyticsBranchIdentity(o, branch)).length ==
      1;
}

/// CODEX FINDINGS 1 & 2 — the branch options an operational filter must OFFER,
/// given the last real answer and the branch it is actually querying.
///
/// A `DropdownButtonFormField` asserts on a value with no item, and both
/// operational surfaces built their items from the RAW async option list: a
/// technical failure emptied it while the effective query — and the wire —
/// still carried branch B. Activity therefore ASSERTED, and the active board
/// silently showed "All" while filtering to B.
///
/// The same rule the analytics selector already uses: when there is no answer
/// to offer, offer exactly the branch being queried, so the control is both
/// assertion-safe and truthful. Never a first-branch fallback, and never a
/// value the list does not contain.
List<AuditBranchOption> operationalBranchItems({
  required List<AuditBranchOption>? answer,
  required AuditBranchOption? effective,
}) {
  final items = <AuditBranchOption>[];
  final taken = <String>{};
  for (final option in answer ?? const <AuditBranchOption>[]) {
    if (taken.add(option.branchId)) items.add(option);
  }
  if (effective != null && taken.add(effective.branchId)) items.add(effective);
  return items;
}

/// CODEX F-1B — the selection that the UI and the financial transport BOTH use.
///
/// [effectiveAnalyticsBranchProvider] answers authorization; this answers
/// usability, and it is the only value a surface should act on.
///
///  * no authorized selection -> null;
///  * NEVER ANSWERED here (a first load in flight, or a first load that failed)
///    -> the authorized selection stands. Ignorance is not evidence of removal,
///    and widening the scope on a failed fetch would silently change what every
///    figure on the page means;
///  * ANSWERED -> the last real answer decides, even while a refresh is in
///    flight or after one has failed. Exactly one match on branch IDENTITY
///    (organization + restaurant + branch, never the label — F-1B-1) returns
///    that option, so a renamed branch keeps its scope and shows its new name.
///    Zero matches — deleted, tombstoned, or dropped as a conflicting composite
///    — returns null, and the scope falls back to the authorized parent rather
///    than staying on a branch that is no longer there.
///
/// F-1B-3-R1: the second bullet is what stops an omission from being undone by
/// a later failure. Once a real answer has said branch B is gone, no amount of
/// subsequent not-knowing brings it back; only another real answer containing
/// it can.
///
/// Returning the ANSWER'S option rather than the stored one is what makes a
/// rename free: the ids are identical, so the family keys do not change and no
/// analytics request is re-issued for a change of display text.
final resolvedLiveAnalyticsBranchProvider = Provider<AuditBranchOption?>(
  (ref) {
    final effective = ref.watch(effectiveAnalyticsBranchProvider);
    if (effective == null) return null;

    final answered = ref.watch(analyticsBranchOptionsProvider);
    // Never answered here: nothing authoritative has been said about existence.
    if (answered == null) return effective;

    final matches = [
      for (final option in answered)
        if (sameAnalyticsBranchIdentity(option, effective)) option,
    ];
    // Sanitised options hold at most one row per identity, so more than one
    // match cannot occur; refusing to guess is still the right answer if it
    // ever does.
    return matches.length == 1 ? matches.single : null;
  },
  dependencies: [
    effectiveAnalyticsBranchProvider,
    analyticsBranchOptionsProvider,
  ],
);
