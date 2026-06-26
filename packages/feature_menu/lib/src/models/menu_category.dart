import 'json_helpers.dart';

/// A menu category (RF-109 `menu_categories`). Organization + restaurant scoped
/// with a nullable [branchId] (`null` => restaurant-scoped / global).
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.name,
    required this.displayOrder,
    required this.isActive,
    this.deletedAt,
  });

  final String id;
  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final String name;
  final int displayOrder;
  final bool isActive;
  final DateTime? deletedAt;

  /// Whether this row is a tombstone (soft-deleted, D-020).
  bool get isDeleted => deletedAt != null;

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
    id: requireString(json, 'id'),
    organizationId: requireString(json, 'organization_id'),
    restaurantId: requireString(json, 'restaurant_id'),
    branchId: optString(json, 'branch_id'),
    name: requireString(json, 'name'),
    displayOrder: optInt(json, 'display_order', 0),
    isActive: optBool(json, 'is_active', true),
    deletedAt: parseTimestamp(json['deleted_at']),
  );

  MenuCategory copyWith({DateTime? deletedAt}) => MenuCategory(
    id: id,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    name: name,
    displayOrder: displayOrder,
    isActive: isActive,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
