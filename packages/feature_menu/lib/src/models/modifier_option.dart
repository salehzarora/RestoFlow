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
    this.kitchenMeat,
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

  /// KITCHEN-MEAT-001: the OPTIONAL configured meat contribution of one
  /// selection (`modifier_options.kitchen_meat` = `{quantity, unit}`). Non-money
  /// (D-007); null when the option contributes no meat.
  final Map<String, dynamic>? kitchenMeat;

  bool get isDeleted => deletedAt != null;

  /// KITCHEN-MEAT-001: true when this option counts toward the KDS meat total.
  bool get hasKitchenMeat => kitchenMeat != null;

  /// The configured meat quantity, or null. A count, never money.
  num? get kitchenMeatQuantity {
    final value = kitchenMeat?['quantity'];
    return value is num ? value : num.tryParse('${value ?? ''}');
  }

  /// The configured meat unit (e.g. "patties", "g"), or '' when unset.
  String get kitchenMeatUnit => (kitchenMeat?['unit'] ?? '').toString();

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
    kitchenMeat: optJsonMapOrNull(json, 'kitchen_meat'),
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
    // Preserve meat across a soft-delete tombstone copyWith.
    kitchenMeat: kitchenMeat,
  );
}
