import 'json_helpers.dart';

/// A modifier group of a menu item (RF-109 `modifiers`). Carries selection rules
/// (no price of its own; its options carry the price deltas).
class Modifier {
  const Modifier({
    required this.id,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.menuItemId,
    required this.name,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.isRequired,
    required this.displayOrder,
    required this.isActive,
    this.allowQuantity = false,
    this.maxQuantity,
    this.deletedAt,
  });

  final String id;
  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final String menuItemId;
  final String name;

  /// `single` or `multiple`.
  final String selectionType;
  final int minSelect;
  final int? maxSelect;
  final bool isRequired;
  final int displayOrder;
  final bool isActive;

  /// Whether the POS may add the SAME option more than once (quantity
  /// stepper). Only meaningful for `multiple` selection — the server rejects
  /// `single` + allow_quantity (product-rescue quantity settings).
  final bool allowQuantity;

  /// Per-option units cap while [allowQuantity] is on; null = no cap.
  final int? maxQuantity;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory Modifier.fromJson(Map<String, dynamic> json) => Modifier(
    id: requireString(json, 'id'),
    organizationId: requireString(json, 'organization_id'),
    restaurantId: requireString(json, 'restaurant_id'),
    branchId: optString(json, 'branch_id'),
    menuItemId: requireString(json, 'menu_item_id'),
    name: requireString(json, 'name'),
    selectionType: optString(json, 'selection_type') ?? 'single',
    minSelect: optInt(json, 'min_select', 0),
    maxSelect: optIntOrNull(json, 'max_select'),
    isRequired: optBool(json, 'is_required', false),
    displayOrder: optInt(json, 'display_order', 0),
    isActive: optBool(json, 'is_active', true),
    allowQuantity: optBool(json, 'allow_quantity', false),
    maxQuantity: optIntOrNull(json, 'max_quantity'),
    deletedAt: parseTimestamp(json['deleted_at']),
  );

  Modifier copyWith({DateTime? deletedAt}) => Modifier(
    id: id,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    menuItemId: menuItemId,
    name: name,
    selectionType: selectionType,
    minSelect: minSelect,
    maxSelect: maxSelect,
    isRequired: isRequired,
    displayOrder: displayOrder,
    isActive: isActive,
    allowQuantity: allowQuantity,
    maxQuantity: maxQuantity,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
