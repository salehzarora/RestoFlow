/// The six tenant membership role keys (D-004 / D-026), matching the exact wire
/// values returned by `public.get_my_context().memberships[].role`
/// (API_CONTRACT section 4.22).
///
/// `platform_admin` is intentionally NOT a member of this enum: it is a separate
/// platform-plane grant surfaced only via `MyContext.isPlatformAdmin` (D-026),
/// never a membership role. There is NO global user role (D-004) — roles are
/// always per-membership.
enum MembershipRole {
  orgOwner('org_owner'),
  restaurantOwner('restaurant_owner'),
  manager('manager'),
  cashier('cashier'),
  kitchenStaff('kitchen_staff'),
  accountant('accountant');

  const MembershipRole(this.wire);

  /// The exact server wire key (e.g. `org_owner`).
  final String wire;

  /// Maps a wire key to a role, or returns `null` for ANY unknown/unsupported
  /// value (fail-closed: callers MUST deny rather than guess). `platform_admin`
  /// is not in this enum, so it resolves to `null` here.
  static MembershipRole? tryFromWire(String value) {
    for (final role in MembershipRole.values) {
      if (role.wire == value) return role;
    }
    return null;
  }
}

/// Thrown when a membership carries a role string outside the six tenant keys.
/// The repository maps this to a fail-closed `AuthUnknownRoleFailure`.
class UnknownRoleException implements Exception {
  UnknownRoleException(this.role);

  /// The offending wire value. This is a role label (not PII or a secret), so it
  /// is safe to surface in diagnostics.
  final String role;

  @override
  String toString() => 'UnknownRoleException($role)';
}
