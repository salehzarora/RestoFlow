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
    this.iconKey,
    this.deletedAt,
  });

  final String id;
  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final String name;
  final int displayOrder;
  final bool isActive;

  /// OPS-044: the owner-chosen category icon, as an abstract registry key
  /// (`menu_categories.icon_key`). `null` = no explicit icon, which is the
  /// state every category has until an owner picks one.
  ///
  /// Held as the RAW server string, never resolved to an `IconData` here. A key
  /// this build does not recognise — one a NEWER dashboard chose — must survive
  /// a round trip untouched, so it is deliberately neither validated nor
  /// collapsed to null on decode: doing either would let an unrelated edit wipe
  /// a choice this binary simply cannot draw yet.
  final String? iconKey;
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
    // An absent key, a JSON null, or a non-string value all read as "not
    // chosen"; any other string is preserved verbatim (see [iconKey]).
    iconKey: optString(json, 'icon_key'),
    deletedAt: parseTimestamp(json['deleted_at']),
  );

  /// Rebuilds the row. Every field is carried explicitly — a reorder or a
  /// soft-delete that forgot [iconKey] would silently drop the owner's choice
  /// from the in-memory snapshot.
  MenuCategory copyWith({
    int? displayOrder,
    DateTime? deletedAt,
    String? iconKey,
  }) => MenuCategory(
    id: id,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    name: name,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive,
    iconKey: iconKey ?? this.iconKey,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
