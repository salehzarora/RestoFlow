import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// One membership row shown on the Users/Roles screen. Mirrors a RF-112
/// membership: an existing app_user granted a role at a scope, with a status.
class AdminUser {
  const AdminUser({
    required this.id,
    String? membershipId,
    required this.displayName,
    required this.email,
    required this.role,
    required this.scopeLabel,
    required this.status,
    this.isSelf = false,
  }) : membershipId = membershipId ?? id;

  final String id;

  /// The real `membership_id` (RF-116) that role-change and revoke target — never
  /// the display id. Defaults to [id] when omitted (the demo store, where [id] is
  /// already the row key). The real repository sets both to the membership id.
  final String membershipId;

  final String displayName;
  final String email;

  /// One of the six tenant roles (never platform_admin — D-026).
  final MembershipRole role;

  /// A human label for the membership scope (org-wide / a restaurant / a branch).
  final String scopeLabel;

  /// `active` or `revoked` (the interim RF-112 set; no invite/pending).
  final String status;

  /// True for the acting user's own membership (self-grant/self-escalation are
  /// denied by RF-112, so the UI hides destructive self actions).
  final bool isSelf;

  AdminUser copyWith({MembershipRole? role, String? status}) => AdminUser(
    id: id,
    membershipId: membershipId,
    displayName: displayName,
    email: email,
    role: role ?? this.role,
    scopeLabel: scopeLabel,
    status: status ?? this.status,
    isSelf: isSelf,
  );
}
