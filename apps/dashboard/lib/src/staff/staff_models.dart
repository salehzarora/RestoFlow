import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// A staff member (an `employee_profiles` row + its authoritative membership
/// role). Pure Dart. NEVER carries PIN material — only the boolean fact that a
/// PIN credential is set (`has_pin`); the backend stores a bcrypt hash and the
/// raw PIN exists nowhere.
class StaffMember {
  const StaffMember({
    required this.employeeProfileId,
    required this.displayName,
    required this.role,
    required this.hasPin,
    required this.employmentStatus,
    this.employeeNumber,
  });

  final String employeeProfileId;
  final String displayName;
  final MembershipRole role;

  /// True when a PIN credential reference is set (boolean only — never the ref).
  final bool hasPin;

  /// `active` / `suspended` / `terminated`.
  final String employmentStatus;
  final String? employeeNumber;

  bool get isActive => employmentStatus == 'active';
}

/// The staff roles a dashboard owner/manager can provision from this surface —
/// PIN-operated tenant roles only. Owner roles are granted via Users/RF-112
/// (`grant_membership`), never here; `platform_admin` is not a tenant role
/// (D-026).
const List<MembershipRole> kProvisionableStaffRoles = [
  MembershipRole.cashier,
  MembershipRole.kitchenStaff,
  MembershipRole.manager,
];
