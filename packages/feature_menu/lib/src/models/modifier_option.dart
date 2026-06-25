import 'json_helpers.dart';

/// A selectable option of a modifier (RF-109 `modifier_options`).
/// [priceDeltaMinor] is a SIGNED integer minor-unit delta (D-007).
class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.modifierId,
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
  final String modifierId;
  final String name;

  /// Signed integer minor-unit price delta (may be negative).
  final int priceDeltaMinor;
  final int displayOrder;
  final bool isActive;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory ModifierOption.fromJson(Map<String, dynamic> json) => ModifierOption(
    id: requireString(json, 'id'),
    organizationId: requireString(json, 'organization_id'),
    restaurantId: requireString(json, 'restaurant_id'),
    branchId: optString(json, 'branch_id'),
    modifierId: requireString(json, 'modifier_id'),
    name: requireString(json, 'name'),
    priceDeltaMinor: optInt(json, 'price_delta_minor', 0),
    displayOrder: optInt(json, 'display_order', 0),
    isActive: optBool(json, 'is_active', true),
    deletedAt: parseTimestamp(json['deleted_at']),
  );

  ModifierOption copyWith({DateTime? deletedAt}) => ModifierOption(
    id: id,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    modifierId: modifierId,
    name: name,
    priceDeltaMinor: priceDeltaMinor,
    displayOrder: displayOrder,
    isActive: isActive,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
