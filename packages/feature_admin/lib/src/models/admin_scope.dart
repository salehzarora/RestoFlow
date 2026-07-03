import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The active administration scope (RF-108 membership): the organization plus the
/// optional restaurant/branch the owner/manager is acting in. Mirrors the
/// `MenuScope` pattern of RF-111 — auth mode uses the membership's EXACT ids;
/// demo mode uses [AdminScope.demo].
class AdminScope {
  const AdminScope({
    required this.organizationId,
    required this.organizationName,
    required this.restaurantId,
    required this.restaurantName,
    required this.branchId,
    required this.branchName,
    required this.currencyCode,
    required this.actingRole,
  });

  final String organizationId;
  final String organizationName;
  final String? restaurantId;
  final String? restaurantName;
  final String? branchId;
  final String? branchName;
  final String currencyCode;

  /// The acting member's role — drives the role-rank guard + permission states.
  final MembershipRole actingRole;

  /// A short human label for the active scope (branch, else restaurant, else org).
  String get scopeLabel => branchName ?? restaurantName ?? organizationName;

  AdminScope copyWith({MembershipRole? actingRole}) => AdminScope(
    organizationId: organizationId,
    organizationName: organizationName,
    restaurantId: restaurantId,
    restaurantName: restaurantName,
    branchId: branchId,
    branchName: branchName,
    currencyCode: currencyCode,
    actingRole: actingRole ?? this.actingRole,
  );

  /// Derives the scope from the active RF-108 membership (auth mode).
  factory AdminScope.fromMembership(
    MembershipContext m, {
    required String currencyCode,
  }) => AdminScope(
    organizationId: m.organizationId,
    organizationName: m.organizationName,
    restaurantId: m.restaurantId,
    restaurantName: m.restaurantName,
    branchId: m.branchId,
    branchName: m.branchName,
    currencyCode: currencyCode,
    actingRole: m.role,
  );

  /// The demo scope (a single restaurant + branch), acting as the org owner so the
  /// full happy path is visible. Ids/names are stable demo data.
  static const AdminScope demo = AdminScope(
    organizationId: 'demo-org',
    organizationName: 'Olive & Thyme Group',
    restaurantId: 'demo-restaurant',
    restaurantName: 'Olive & Thyme — Downtown',
    branchId: 'demo-branch',
    branchName: 'Main Street',
    // ILS-only for the pilot (demo mirrors the real default; Q-007 interim).
    currencyCode: 'ILS',
    actingRole: MembershipRole.orgOwner,
  );
}
