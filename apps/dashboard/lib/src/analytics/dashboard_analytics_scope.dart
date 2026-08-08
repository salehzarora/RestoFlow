/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-E1) — the Overview's explicit
/// analytics scope.
///
/// THE DEFECT THIS EXISTS TO FIX. `resolveTenantContext` deliberately pins a
/// CONCRETE restaurant and branch onto every resolved membership — when the
/// membership is org- or restaurant-wide it takes the FIRST of each from
/// `list_org_structure` — because the menu, printer and staff surfaces cannot
/// function without one. The Dashboard shell then publishes that narrowed
/// membership, and the owner reports read their scope straight off it. So an
/// org owner asking for "sales" was shown ONE branch's sales, with nothing on
/// screen saying which, or that a choice had been made at all. Every figure was
/// individually correct and the page as a whole was misleading.
///
/// The fix is NOT to widen anything. Coverage is recovered the way the Activity
/// log already recovers it — from the ROLE, via `auditCoveredScope`, because the
/// pinned ids can no longer tell you what the membership actually covers. The
/// owner then chooses within that coverage. The selector is a FILTER over
/// already-authorized scope: it mints no membership, changes no role, and can
/// only ever narrow.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import '../data/audit_filter_options_repository.dart' show auditCoveredScope;
import '../data/audit_log_models.dart' show AuditBranchOption;

/// What breadth an analytics scope represents.
enum DashboardAnalyticsScopeKind {
  /// Every permitted branch in the organization. Only an org-wide membership
  /// reaches this.
  orgWide,

  /// Every permitted branch in one restaurant.
  restaurantWide,

  /// Exactly one branch — either chosen by a broader owner, or the only branch
  /// a scope-limited membership covers.
  singleBranch,
}

/// One analytics scope: exactly the three ids the owner RPCs take, plus what to
/// call it on screen.
///
/// Deliberately NOT a `MembershipContext`. Fabricating a membership to express
/// a selection would put a business filter and an authorization claim in the
/// same object, and the next reader would have no way to tell which fields were
/// authority and which were preference.
class DashboardAnalyticsScope {
  const DashboardAnalyticsScope({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.kind,
    this.branchLabel,
  });

  /// The BROADEST scope [membership] is authorized to report on.
  ///
  /// Reads coverage from the role through [auditCoveredScope] — the same
  /// function the Activity branch filter uses — precisely because the resolved
  /// membership's ids have already been narrowed and cannot be trusted to say
  /// what it covers.
  factory DashboardAnalyticsScope.coveredBy(MembershipContext membership) {
    final covered = auditCoveredScope(membership);
    final kind = covered.restaurantId == null
        ? DashboardAnalyticsScopeKind.orgWide
        : covered.branchId == null
        ? DashboardAnalyticsScopeKind.restaurantWide
        : DashboardAnalyticsScopeKind.singleBranch;
    return DashboardAnalyticsScope(
      organizationId: membership.organizationId,
      restaurantId: covered.restaurantId,
      branchId: covered.branchId,
      kind: kind,
      // A scope-limited membership names its own branch; the broad kinds have
      // no single branch to name.
      branchLabel: kind == DashboardAnalyticsScopeKind.singleBranch
          ? membership.branchName
          : null,
    );
  }

  /// One authorized branch, carrying BOTH ids.
  ///
  /// `restaurantId` comes from the option, not from the membership: an org
  /// owner selecting a branch of their second restaurant must send that
  /// restaurant's id, and the narrowed membership only ever knows the first.
  factory DashboardAnalyticsScope.branch({
    required String organizationId,
    required AuditBranchOption option,
  }) => DashboardAnalyticsScope(
    organizationId: organizationId,
    restaurantId: option.restaurantId,
    branchId: option.branchId,
    kind: DashboardAnalyticsScopeKind.singleBranch,
    branchLabel: option.label,
  );

  /// CODEX F-1A — the scope implied by an explicit id triple.
  ///
  /// Exists so a family KEY can hand its exact scope to the request that key
  /// identifies. The kind is derived from which ids are present, by the same
  /// rule [coveredBy] uses, so a reconstructed scope and a derived one are the
  /// same value for the same ids.
  factory DashboardAnalyticsScope.ofIds({
    required String organizationId,
    String? restaurantId,
    String? branchId,
    String? branchLabel,
  }) => DashboardAnalyticsScope(
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    kind: restaurantId == null
        ? DashboardAnalyticsScopeKind.orgWide
        : branchId == null
        ? DashboardAnalyticsScopeKind.restaurantWide
        : DashboardAnalyticsScopeKind.singleBranch,
    branchLabel: branchLabel,
  );

  final String organizationId;

  /// Null means EVERY permitted restaurant — which the owner RPCs already
  /// express as a null `p_restaurant_id`, intersected server-side with the
  /// caller's real membership.
  final String? restaurantId;

  /// Null means every permitted branch within [restaurantId].
  final String? branchId;

  final DashboardAnalyticsScopeKind kind;

  /// Display name for a single-branch scope; null for the broad kinds, which
  /// the UI labels with the existing "All permitted branches" wording.
  final String? branchLabel;

  /// True when this scope covers more than one branch.
  bool get isAllPermitted => branchId == null;

  /// Whether [option] falls inside this coverage.
  ///
  /// The check a selection must pass before it is allowed to take effect. It is
  /// deliberately about COVERAGE rather than about a loaded option list: the
  /// list is a convenience that can be stale or still loading, while coverage
  /// is derived from the role and is true the instant the membership changes.
  ///
  /// CODEX F-1 — ORGANIZATION EQUALITY IS MANDATORY, and is checked FIRST for
  /// every kind. The org-wide arm previously returned true unconditionally,
  /// which was only ever safe while a selection could not outlive its
  /// membership. It can: the selection lives in the root provider container,
  /// and signing out does not rebuild it (`main.dart` creates it once in
  /// `runApp`, and `DashboardAuthFlow` clears widget state only). So a branch
  /// picked in one organization survived into the next session and, under a
  /// different org, was still accepted — sending that org's id together with
  /// another org's restaurant and branch.
  ///
  /// The server always refused those (`actor_rank_in_scope` -> 42501), so no
  /// data ever crossed; what leaked was a request the client should never have
  /// formed, and a selector holding a value absent from its own item list.
  ///
  /// Branch ids are NOT treated as globally unique here. Even if they are in
  /// practice, leaning on that would make a uniqueness property load-bearing
  /// for tenant scoping, which is not what it is for.
  bool covers(AuditBranchOption option) {
    if (option.organizationId != organizationId) return false;
    return switch (kind) {
      DashboardAnalyticsScopeKind.orgWide => true,
      DashboardAnalyticsScopeKind.restaurantWide =>
        option.restaurantId == restaurantId,
      // CODEX F-1C — the branch check alone was not enough. A stale or
      // malformed option carrying the right branch id under a DIFFERENT
      // restaurant would have matched, which again leans on branch ids being
      // globally unique. The full triple is required.
      DashboardAnalyticsScopeKind.singleBranch =>
        option.restaurantId == restaurantId && option.branchId == branchId,
    };
  }

  /// CODEX F-1B-1-R1 — this scope as TRANSPORT IDENTITY: the same ids and kind
  /// with the display label dropped.
  ///
  /// [branchLabel] is part of `==` and `hashCode`, and rightly so for a value
  /// the UI renders. But a provider that watches the whole scope in order to
  /// build a REQUEST inherits that: renaming a branch produced an unequal
  /// scope, which rebuilt `orderHistoryRepositoryProvider`, which rebuilt the
  /// controller, which discarded the loaded page and re-issued
  /// `owner_order_history` from a null cursor. The owner's list jumped back to
  /// the top because someone had edited a branch's NAME.
  ///
  /// The report and series keys never had this problem — they are built from
  /// ids and compare equal across a rename. This gives the transport-bearing
  /// providers the same property without asking every one of them to remember
  /// to strip the label.
  DashboardAnalyticsScope get transportIdentity => branchLabel == null
      ? this
      : DashboardAnalyticsScope(
          organizationId: organizationId,
          restaurantId: restaurantId,
          branchId: branchId,
          kind: kind,
        );

  /// Whether [option] is this exact scope — all three ids.
  ///
  /// Used by the selector to decide whether a loaded option is THE selected
  /// one. Deliberately stricter than [covers]: coverage answers "may I read
  /// this", identity answers "is this the row I am sitting on".
  bool isExactly(AuditBranchOption option) =>
      option.organizationId == organizationId &&
      option.restaurantId == restaurantId &&
      option.branchId == branchId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardAnalyticsScope &&
          other.organizationId == organizationId &&
          other.restaurantId == restaurantId &&
          other.branchId == branchId &&
          other.kind == kind &&
          other.branchLabel == branchLabel;

  @override
  int get hashCode =>
      Object.hash(organizationId, restaurantId, branchId, kind, branchLabel);

  @override
  String toString() =>
      'DashboardAnalyticsScope(${kind.name}, org: $organizationId, '
      'restaurant: $restaurantId, branch: $branchId)';
}

/// CODEX F-1B-1 — analytics branch IDENTITY, which the display label is NOT
/// part of.
///
/// `AuditBranchOption.==` includes `label`, and legitimately so: the Activity
/// and Active Orders filters use an option as a DISPLAY value, where a renamed
/// branch really is a different thing to show. But an analytics scope is three
/// ids — the owner RPCs take no label at all — so for scope purposes a label is
/// metadata ABOUT a branch, never a way of naming one.
///
/// Using value equality to answer "is this the branch I selected" therefore
/// made a RENAME look like a different branch. A branch selected as "Old name"
/// and re-delivered as "New name" is the same `org/restaurant/branch` triple:
/// transport stayed on it, while the selector — finding no *equal* option —
/// fell back to "All permitted branches". Scope and screen disagreed until the
/// owner picked again, and nothing on screen said which was right.
///
/// `AuditBranchOption.==` is deliberately left ALONE (CODEX F-1B §22).
/// Redefining model equality to fix one selector would quietly change every
/// other consumer that treats an option as a display value.
bool sameAnalyticsBranchIdentity(AuditBranchOption a, AuditBranchOption b) =>
    a.organizationId == b.organizationId &&
    a.restaurantId == b.restaurantId &&
    a.branchId == b.branchId;

/// CODEX F-1B-2 — the branch options an analytics selector may offer, given the
/// list as delivered and the caller's [coverage].
///
/// Three rules, in this order:
///
///  1. **Conflicting composites are excluded ENTIRELY.** Two rows sharing a
///     `branchId` under different restaurants (or organizations) cannot both be
///     true. The previous de-duplication kept the FIRST and dropped the rest,
///     which made list ORDER load-bearing for tenant scoping: put the wrong
///     tuple first and the wrong tuple won. Branch ids are UUID primary keys in
///     a valid schema, so this only happens with stale or malformed decoded
///     data — exactly when guessing is least defensible. The branch id is
///     therefore dropped, not repaired: not first, not last, and never by
///     substituting a restaurant or organization the client invented.
///
///     The check runs over the list AS DELIVERED, BEFORE coverage narrowing, so
///     a conflict cannot be hidden by one of its two rows happening to fall
///     outside coverage. It is symmetric and whole-list, so the answer does not
///     depend on which conflicting row arrives first.
///
///  2. **Coverage still filters.** A branch the role does not cover is never
///     offered, as before.
///
///  3. **One entry per surviving identity.** Rows that agree on all three ids
///     are ONE branch; differing labels are a cosmetic metadata conflict, not a
///     scope conflict, so they collapse to a single selectable entry. First
///     occurrence wins, which is deterministic because the option source orders
///     stably (created_at, then name) — and safe, because after rule 1 every
///     remaining row with a given branch id carries the SAME composite.
///
/// Rule 3 is where the old first-wins behaviour survives; rule 1 is what makes
/// it sound.
List<AuditBranchOption> sanitizeAnalyticsBranchOptions(
  Iterable<AuditBranchOption> options, {
  DashboardAnalyticsScope? coverage,
}) {
  final firstByBranchId = <String, AuditBranchOption>{};
  final conflicting = <String>{};
  for (final option in options) {
    final seen = firstByBranchId[option.branchId];
    if (seen == null) {
      firstByBranchId[option.branchId] = option;
    } else if (!sameAnalyticsBranchIdentity(seen, option)) {
      conflicting.add(option.branchId);
    }
  }

  final selectable = <AuditBranchOption>[];
  final taken = <String>{};
  for (final option in options) {
    if (conflicting.contains(option.branchId)) continue;
    if (coverage != null && !coverage.covers(option)) continue;
    if (!taken.add(option.branchId)) continue;
    selectable.add(option);
  }
  return selectable;
}
