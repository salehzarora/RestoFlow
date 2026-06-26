import 'json_helpers.dart';

/// A sellable menu item (RF-109 `menu_items`). Money is integer minor units
/// only ([basePriceMinor], DECISION D-007); never a floating-point type.
class MenuItem {
  const MenuItem({
    required this.id,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.menuCategoryId,
    required this.name,
    required this.description,
    required this.basePriceMinor,
    required this.currencyCode,
    required this.defaultStationId,
    required this.displayOrder,
    required this.isActive,
    this.deletedAt,
  });

  final String id;
  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final String menuCategoryId;
  final String name;
  final String? description;

  /// Absolute base price in integer minor units (`>= 0`).
  final int basePriceMinor;

  /// ISO-4217 currency code (uppercase, 3 letters).
  final String currencyCode;
  final String? defaultStationId;
  final int displayOrder;
  final bool isActive;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: requireString(json, 'id'),
    organizationId: requireString(json, 'organization_id'),
    restaurantId: requireString(json, 'restaurant_id'),
    branchId: optString(json, 'branch_id'),
    menuCategoryId: requireString(json, 'menu_category_id'),
    name: requireString(json, 'name'),
    description: optString(json, 'description'),
    basePriceMinor: requireInt(json, 'base_price_minor'),
    currencyCode: requireString(json, 'currency_code'),
    defaultStationId: optString(json, 'default_station_id'),
    displayOrder: optInt(json, 'display_order', 0),
    isActive: optBool(json, 'is_active', true),
    deletedAt: parseTimestamp(json['deleted_at']),
  );

  MenuItem copyWith({DateTime? deletedAt}) => MenuItem(
    id: id,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    menuCategoryId: menuCategoryId,
    name: name,
    description: description,
    basePriceMinor: basePriceMinor,
    currencyCode: currencyCode,
    defaultStationId: defaultStationId,
    displayOrder: displayOrder,
    isActive: isActive,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
