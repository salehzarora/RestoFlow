/// CODEX R1A-01 — the part of a membership that decides what is REQUESTED and
/// what is ALLOWED.
///
/// `MembershipContext` carries display text (`organizationName`,
/// `restaurantName`, `branchName`) alongside the ids and the role, and it has no
/// `==` at all — so every provider that watched it rebuilt whenever a new
/// instance arrived, even one identical in every field that matters. Renaming a
/// branch therefore rebuilt the owner-report repository, the sales-series
/// repository and the Orders History repository AND its controller: fresh
/// financial RPCs, the loaded page discarded, and pagination restarted from a
/// null cursor, because someone had edited a name.
///
/// This is the value those providers should depend on instead. Two identities
/// are equal when every field that reaches the wire or the authorization checks
/// is equal; display text is deliberately absent from both the fields and the
/// equality.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

@immutable
class DashboardMembershipIdentity {
  const DashboardMembershipIdentity._(
    this.membership, {
    required this.membershipId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.role,
    required this.status,
  });

  factory DashboardMembershipIdentity.of(MembershipContext membership) =>
      DashboardMembershipIdentity._(
        membership,
        membershipId: membership.id,
        organizationId: membership.organizationId,
        restaurantId: membership.restaurantId,
        branchId: membership.branchId,
        role: membership.role,
        status: membership.status,
      );

  /// The membership this identity was derived from, for the repositories that
  /// still take one.
  ///
  /// DELIBERATELY OUTSIDE [==]. Two equal identities may carry different
  /// instances differing only in display text — which is the whole point: no
  /// transport parameter and no authorization check reads a name, so a provider
  /// holding the previous instance is holding the same ANSWER to every question
  /// it will ask. Anything that could change an answer is a field below, and
  /// changing one rebuilds the dependents.
  final MembershipContext membership;

  /// The membership row itself: a different grant is a different authorization,
  /// even at identical ids.
  final String membershipId;

  /// The tenant anchor (D-001). Never a filter.
  final String organizationId;
  final String? restaurantId;
  final String? branchId;

  /// Coverage is derived from the ROLE (`auditCoveredScope`), so a role change
  /// changes which branches may be read even when every id stays put.
  final MembershipRole role;

  /// An inactive/suspended membership is not the same authorization as an
  /// active one.
  final String status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardMembershipIdentity &&
          other.membershipId == membershipId &&
          other.organizationId == organizationId &&
          other.restaurantId == restaurantId &&
          other.branchId == branchId &&
          other.role == role &&
          other.status == status;

  @override
  int get hashCode => Object.hash(
    membershipId,
    organizationId,
    restaurantId,
    branchId,
    role,
    status,
  );

  @override
  String toString() =>
      'DashboardMembershipIdentity(org: $organizationId, '
      'restaurant: $restaurantId, branch: $branchId, role: ${role.name})';
}
