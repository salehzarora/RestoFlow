import 'app_surface.dart';
import 'membership_role.dart';

/// The outcome of evaluating whether a principal may enter a surface.
enum EntryDecision {
  /// Permitted to enter the surface.
  allowed,

  /// Not permitted (wrong role for the surface, not a platform admin, or no
  /// active role).
  denied,

  /// A KNOWN role that RF-108 defers (currently `accountant`). The UI must show
  /// a "not available yet" state - never crash, never silently grant.
  deferred,
}

/// The pure, testable role -> surface entry policy for RF-108.
///
/// Tenant surfaces (pos/kds/dashboard) are decided by the SELECTED membership's
/// [role] (D-004 - never a global role). The admin surface is decided ONLY by
/// [isPlatformAdmin] (D-026 - a separate boolean, never a tenant membership).
/// `accountant` is a known-but-deferred role in RF-108 (Q-017).
class RoleEntryPolicy {
  const RoleEntryPolicy();

  static const Set<MembershipRole> _posRoles = {
    MembershipRole.orgOwner,
    MembershipRole.restaurantOwner,
    MembershipRole.manager,
    MembershipRole.cashier,
  };

  static const Set<MembershipRole> _kdsRoles = {
    MembershipRole.orgOwner,
    MembershipRole.restaurantOwner,
    MembershipRole.manager,
    MembershipRole.kitchenStaff,
  };

  static const Set<MembershipRole> _dashboardRoles = {
    MembershipRole.orgOwner,
    MembershipRole.restaurantOwner,
    MembershipRole.manager,
  };

  /// Decides entry for [surface] given the active membership [role] (null when
  /// there is no selected/active membership) and the [isPlatformAdmin] flag.
  EntryDecision evaluate({
    required AppSurface surface,
    required MembershipRole? role,
    required bool isPlatformAdmin,
  }) {
    // Admin is gated ONLY by the platform-admin flag (D-026) - a tenant role
    // (even org_owner) can never enter admin, and a platform admin needs no
    // membership.
    if (surface == AppSurface.admin) {
      return isPlatformAdmin ? EntryDecision.allowed : EntryDecision.denied;
    }
    // Tenant surfaces require an active membership role.
    if (role == null) return EntryDecision.denied;
    // accountant is a known role deferred in RF-108 - acknowledged, not crashed.
    if (role == MembershipRole.accountant) return EntryDecision.deferred;
    final allowedRoles = switch (surface) {
      AppSurface.pos => _posRoles,
      AppSurface.kds => _kdsRoles,
      AppSurface.dashboard => _dashboardRoles,
      AppSurface.admin =>
        const <MembershipRole>{}, // unreachable (handled above)
    };
    return allowedRoles.contains(role)
        ? EntryDecision.allowed
        : EntryDecision.denied;
  }
}
