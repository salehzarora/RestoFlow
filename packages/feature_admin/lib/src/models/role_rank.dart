import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The RF-112 role-rank ladder (DECISION D-033), mirrored client-side so the UI
/// can disable disallowed assignments BEFORE calling the backend (which is the
/// authoritative guard): `org_owner > restaurant_owner > manager >
/// {cashier, kitchen_staff, accountant}`.
int roleRank(MembershipRole role) => switch (role) {
  MembershipRole.orgOwner => 4,
  MembershipRole.restaurantOwner => 3,
  MembershipRole.manager => 2,
  MembershipRole.cashier => 1,
  MembershipRole.kitchenStaff => 1,
  MembershipRole.accountant => 1,
};

/// True iff an [actor] may grant/assign the [assigned] role: the actor must be a
/// managing role (rank ≥ manager) AND strictly outrank the assigned role
/// (D-033). So a manager can assign only cashier/kitchen_staff/accountant, a
/// restaurant_owner up to manager, and an org_owner up to restaurant_owner.
bool canAssignRole(MembershipRole actor, MembershipRole assigned) =>
    roleRank(actor) >= roleRank(MembershipRole.manager) &&
    roleRank(actor) > roleRank(assigned);

/// The roles [actor] may assign, in descending rank (empty when the actor cannot
/// manage at all).
List<MembershipRole> assignableRoles(MembershipRole actor) => const [
  MembershipRole.restaurantOwner,
  MembershipRole.manager,
  MembershipRole.cashier,
  MembershipRole.kitchenStaff,
  MembershipRole.accountant,
].where((r) => canAssignRole(actor, r)).toList();

/// True iff the actor may manage memberships/devices at all (rank ≥ manager).
bool canManage(MembershipRole actor) =>
    roleRank(actor) >= roleRank(MembershipRole.manager);

/// True iff the actor may edit settings (rank ≥ restaurant_owner) — managers are
/// denied settings edits in RF-112 (the conservative D-033 reading).
bool canEditSettings(MembershipRole actor) =>
    roleRank(actor) >= roleRank(MembershipRole.restaurantOwner);
