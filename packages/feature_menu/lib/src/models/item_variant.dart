import 'json_helpers.dart';

/// A variant option of a menu item (RF-109 `item_variants`). [priceDeltaMinor]
/// is a SIGNED integer minor-unit delta on the item base price (D-007).
class ItemVariant {
  const ItemVariant({
    required this.id,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.menuItemId,
    required this.name,
    required this.priceDeltaMinor,
    required this.displayOrder,
    required this.isActive,
    this.deletedAt,
  });

  final String id;
  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final String menuItemId;
  final String name;

  /// Signed integer minor-unit price delta (may be negative).
  final int priceDeltaMinor;
  final int displayOrder;
  final bool isActive;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory ItemVariant.fromJson(Map<String, dynamic> json) => ItemVariant(
    id: requireString(json, 'id'),
    organizationId: requireString(json, 'organization_id'),
    restaurantId: requireString(json, 'restaurant_id'),
    branchId: optString(json, 'branch_id'),
    menuItemId: requireString(json, 'menu_item_id'),
    name: requireString(json, 'name'),
    priceDeltaMinor: optInt(json, 'price_delta_minor', 0),
    displayOrder: optInt(json, 'display_order', 0),
    isActive: optBool(json, 'is_active', true),
    deletedAt: parseTimestamp(json['deleted_at']),
  );

  ItemVariant copyWith({DateTime? deletedAt}) => ItemVariant(
    id: id,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    menuItemId: menuItemId,
    name: name,
    priceDeltaMinor: priceDeltaMinor,
    displayOrder: displayOrder,
    isActive: isActive,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
