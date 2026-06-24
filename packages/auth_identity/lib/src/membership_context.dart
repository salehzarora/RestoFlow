import 'membership_role.dart';

/// One membership from `public.get_my_context().memberships[]` (API_CONTRACT
/// section 4.22). Roles are PER-MEMBERSHIP (D-004) - there is no global role.
/// restaurant/branch ids and names are nullable for org-/restaurant-wide
/// memberships (the resolver LEFT-joins them, RF-124).
class MembershipContext {
  const MembershipContext({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.restaurantId,
    required this.restaurantName,
    required this.branchId,
    required this.branchName,
    required this.role,
    required this.status,
  });

  final String id;
  final String organizationId;
  final String organizationName;
  final String? restaurantId;
  final String? restaurantName;
  final String? branchId;
  final String? branchName;

  /// One of the six tenant roles. Never `platform_admin` (D-026).
  final MembershipRole role;

  /// The membership status wire value (e.g. `active`).
  final String status;

  /// Parses one membership object. Fail-closed: a missing/wrong-typed required
  /// field throws [FormatException]; an unrecognized [role] throws
  /// [UnknownRoleException] (the repository maps it to a fail-closed failure).
  factory MembershipContext.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final organizationId = json['organization_id'];
    final organizationName = json['organization_name'];
    final roleWire = json['role'];
    final status = json['status'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('membership.id missing or not a string');
    }
    if (organizationId is! String || organizationId.isEmpty) {
      throw const FormatException('membership.organization_id missing');
    }
    if (organizationName is! String) {
      throw const FormatException('membership.organization_name missing');
    }
    if (roleWire is! String) {
      throw const FormatException('membership.role missing or not a string');
    }
    if (status is! String) {
      throw const FormatException('membership.status missing or not a string');
    }
    final role = MembershipRole.tryFromWire(roleWire);
    if (role == null) {
      throw UnknownRoleException(roleWire); // fail-closed: never guess
    }
    return MembershipContext(
      id: id,
      organizationId: organizationId,
      organizationName: organizationName,
      restaurantId: _optString(json['restaurant_id'], 'restaurant_id'),
      restaurantName: _optString(json['restaurant_name'], 'restaurant_name'),
      branchId: _optString(json['branch_id'], 'branch_id'),
      branchName: _optString(json['branch_name'], 'branch_name'),
      role: role,
      status: status,
    );
  }
}

/// Reads an optional string: `null` stays null, a String passes through, and
/// any other type fails closed with a [FormatException].
String? _optString(Object? value, String field) {
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('membership.$field not a string or null');
}
