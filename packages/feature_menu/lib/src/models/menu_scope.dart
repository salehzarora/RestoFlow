import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The active tenant scope a menu management session operates in (RF-111).
///
/// Menu rows are organization + restaurant scoped, with a nullable branch
/// (`branchId == null` => restaurant-scoped / "global", visible across the
/// restaurant's branches — RF-109). The scope is derived from the RF-108 active
/// membership ([MenuScope.fromMembership]); [currencyCode] is the default
/// currency to prefill when creating a new priced item (the operator may still
/// set any valid ISO-4217 code).
class MenuScope {
  const MenuScope({
    required this.organizationId,
    required this.restaurantId,
    this.branchId,
    required this.currencyCode,
  });

  final String organizationId;
  final String restaurantId;

  /// `null` => restaurant-scoped / global (no branch override).
  final String? branchId;

  /// Default ISO-4217 currency for new items (uppercase, 3 letters).
  final String currencyCode;

  /// Whether this scope addresses restaurant-scoped ("global") menu rows.
  bool get isGlobal => branchId == null;

  /// The branch path segment used in an RF-110 image object key
  /// (`{branch_id}` or the literal `global`).
  String get branchSegment => branchId ?? 'global';

  /// Builds a scope from the RF-108 active membership. Returns `null` when the
  /// membership has no restaurant (an org-wide membership): a menu is always
  /// restaurant-scoped, so the UI must first resolve a restaurant in that case.
  static MenuScope? fromMembership(
    MembershipContext membership, {
    required String currencyCode,
  }) {
    final restaurantId = membership.restaurantId;
    if (restaurantId == null) return null;
    return MenuScope(
      organizationId: membership.organizationId,
      restaurantId: restaurantId,
      branchId: membership.branchId,
      currencyCode: currencyCode,
    );
  }

  MenuScope copyWith({
    String? branchId,
    bool clearBranch = false,
    String? currencyCode,
  }) {
    return MenuScope(
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: clearBranch ? null : (branchId ?? this.branchId),
      currencyCode: currencyCode ?? this.currencyCode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MenuScope &&
      other.organizationId == organizationId &&
      other.restaurantId == restaurantId &&
      other.branchId == branchId &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode =>
      Object.hash(organizationId, restaurantId, branchId, currencyCode);
}
