import 'package:restoflow_domain/restoflow_domain.dart';

import 'json_helpers.dart';

/// The fixed menu item tag vocabulary (menu/media sprint). These are stable
/// WIRE strings — stored verbatim in `menu_items.tags`, NEVER localized in
/// data (the UI localizes only the display label). Generic across cuisines.
const List<String> kMenuItemTags = ['spicy', 'vegetarian', 'popular', 'new'];

/// The `menu_items.item_type` vocabulary (CHECK-pinned server-side). Stable
/// wire strings; null/absent = unspecified.
const List<String> kMenuItemTypes = ['food', 'drink', 'side', 'combo', 'other'];

/// Wire keys inside the generic [MenuItem.attributes] bag (snake_case, matching
/// the stored JSON). NON-MONEY only (DECISION D-007): a weight is grams, a
/// count is pieces — money lives exclusively in integer `*_minor` columns.
const String kMenuAttrPortionLabel = 'portion_label';
const String kMenuAttrPattyCount = 'patty_count';
const String kMenuAttrPattyWeightGrams = 'patty_weight_grams';

/// KITCHEN-PREP-001: the [MenuItem.attributes] key holding the configurable
/// kitchen prep component list (`[{name, quantity, unit}]`). Non-money (D-007):
/// quantity is a count, unit is text.
const String kMenuAttrPrepComponents = 'prep_components';

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
    this.imagePath,
    this.itemType,
    this.tags = const [],
    this.prepMinutes,
    this.sku,
    this.kitchenNote,
    this.attributes = const {},
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

  /// The RF-110 `menu-images` object key of the item's current image
  /// (`{org}/{rest}/{branch|global}/menu_item/{item}/{image}.{ext}`), or null
  /// for no image. Bytes are always fetched via a short-lived signed URL
  /// (private bucket — DECISION D-032); this is a pointer, never a URL.
  final String? imagePath;

  /// Coarse item kind — one of [kMenuItemTypes], or null for unspecified.
  final String? itemType;

  /// Tags from the fixed [kMenuItemTags] vocabulary (stable wire strings,
  /// never localized in data). Empty = no tags.
  final List<String> tags;

  /// Expected preparation time in MINUTES (`>= 0`), or null. Time, not money.
  final int? prepMinutes;

  /// Internal stock/product code. Back-office only — the server never serves
  /// it to devices (`pos_menu` omits it).
  final String? sku;

  /// A standing preparation note for the kitchen (passes through to the KDS).
  final String? kitchenNote;

  /// The generic NON-MONEY attribute bag (`menu_items.attributes`): snake_case
  /// keys like [kMenuAttrPortionLabel], [kMenuAttrPattyCount],
  /// [kMenuAttrPattyWeightGrams]. HARD RULE (D-007): money never lives here.
  final Map<String, dynamic> attributes;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// Typed accessor over [attributes]: the portion label (e.g. a size wording
  /// the kitchen prints), or null.
  String? get portionLabel => _attrString(kMenuAttrPortionLabel);

  /// Typed accessor over [attributes]: how many patties/pieces make up the
  /// item, or null. A count, never money.
  int? get pattyCount => _attrInt(kMenuAttrPattyCount);

  /// Typed accessor over [attributes]: weight per patty/piece in GRAMS, or
  /// null. A weight, never money (D-007).
  int? get pattyWeightGrams => _attrInt(kMenuAttrPattyWeightGrams);

  /// KITCHEN-PREP-001: the configured kitchen prep components (what the chef
  /// assembles for ONE unit), parsed from [attributes]. Empty when unset.
  /// Non-money ({name,quantity,unit}); shared parser drops blank/invalid rows.
  List<KitchenPrepComponent> get prepComponents =>
      parseKitchenPrepComponents(attributes[kMenuAttrPrepComponents]);

  String? _attrString(String key) {
    final value = attributes[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  int? _attrInt(String key) {
    final value = attributes[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Builds a wire-shaped [attributes] map from the typed fields, omitting
  /// unset values (so an untouched pizza/cafe item stores NO burger keys).
  static Map<String, dynamic> buildAttributes({
    String? portionLabel,
    int? pattyCount,
    int? pattyWeightGrams,
  }) => {
    if (portionLabel != null && portionLabel.trim().isNotEmpty)
      kMenuAttrPortionLabel: portionLabel.trim(),
    if (pattyCount != null) kMenuAttrPattyCount: pattyCount,
    if (pattyWeightGrams != null) kMenuAttrPattyWeightGrams: pattyWeightGrams,
  };

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
    imagePath: optString(json, 'image_path'),
    itemType: optString(json, 'item_type'),
    tags: optStringList(json, 'tags'),
    prepMinutes: optIntOrNull(json, 'prep_minutes'),
    sku: optString(json, 'sku'),
    kitchenNote: optString(json, 'kitchen_note'),
    attributes: optJsonMap(json, 'attributes'),
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
    imagePath: imagePath,
    itemType: itemType,
    tags: tags,
    prepMinutes: prepMinutes,
    sku: sku,
    kitchenNote: kitchenNote,
    attributes: attributes,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
