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
      DashboardAnalyticsScopeKind.singleBranch => option.branchId == branchId,
    };
  }

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
