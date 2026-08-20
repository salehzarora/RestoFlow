/// POS-OFFLINE-OPERATIONS-002 — the JSON codec for the operational snapshot's
/// MENU payload.
///
/// [PosMenuData] and its model types ([DemoCategory], [DemoMenuItem],
/// [PosModifierGroup], [PosModifierOption]) are deliberately NOT modified —
/// they are order-time pricing inputs shared by every POS surface, and this
/// ticket may not change their shape. The serializers live here, beside the
/// snapshot store, and round-trip EVERY field the POS renders or prices from:
/// ids, names, descriptions, integer minor prices and deltas (D-007),
/// availability + reason, tags, display orders, the attributes bag (which
/// carries the per-item prep components), kitchen meat, and image paths/urls.
///
/// Decoding FAILS CLOSED: a record missing an identity or a price throws
/// [FormatException], which the store surfaces as an UNREADABLE envelope.
/// Selling from a half-menu (an item without its paid modifier group, a group
/// without its options) is exactly the silent under-charge the menu source
/// boundary exists to prevent, so a snapshot this build cannot fully read is
/// never served at all — unlike the parked-carts store, where one bad record
/// can be quarantined, a menu is ONE pricing document and is all-or-nothing.
library;

import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;

import '../state/pos_menu_provider.dart'
    show
        PosMenuData,
        PosModifierGroup,
        PosModifierOption,
        resolvePosCategoryStyle;
import 'demo_menu.dart' show DemoCategory, DemoMenuItem;

/// Encodes the FULL menu the POS sells from. The category icon/colour are NOT
/// stored as styling: they are presentation, re-derived from list position by
/// the decoder exactly how the live `pos_menu` parse assigns them, instead of
/// trusting stored styling bytes.
///
/// OPS-044 adds ONE optional field, `icon_key` — the owner's abstract choice,
/// never a codepoint, an [IconData] or a Material name. It is DATA, not
/// styling: without it a till that reboots offline would silently revert to
/// positional icons. It is optional in both directions, so `schemaVersion`
/// deliberately does NOT change: a snapshot written before this build decodes
/// with the key absent, and an older build reading a newer snapshot ignores it.
/// Bumping the version would discard every cached menu, stranding any till that
/// happened to be offline during the upgrade.
Map<String, Object?> encodePosMenuData(PosMenuData menu) => <String, Object?>{
  'currency_code': menu.currencyCode,
  'categories': <Object?>[
    for (final category in menu.categories)
      <String, Object?>{
        'id': category.id,
        'name': category.name,
        if (category.iconKey != null) 'icon_key': category.iconKey,
      },
  ],
  'items': <Object?>[for (final item in menu.items) _encodeItem(item)],
  'modifier_groups': <Object?>[
    for (final group in menu.modifierGroups) _encodeGroup(group),
  ],
};

/// Decodes a stored menu payload, throwing [FormatException] when ANY record
/// is structurally unusable (see the library doc for why this is
/// all-or-nothing). Tolerances mirror the live `pos_menu` parsing boundary:
/// identity and money fields are STRICT; optional display fields degrade to
/// unset; availability fails open to 'available' because the server re-refuses
/// an unavailable item at acceptance either way.
PosMenuData decodePosMenuData(Map<String, Object?> json) {
  final currency = json['currency_code'];
  if (currency is! String || currency.length != 3) {
    throw const FormatException('menu payload has no usable currency code');
  }

  final rawCategories = json['categories'];
  if (rawCategories is! List) {
    throw const FormatException('menu payload has no category list');
  }
  final categories = <DemoCategory>[];
  for (final raw in rawCategories) {
    if (raw is! Map) {
      throw const FormatException('menu category record is malformed');
    }
    categories.add(
      _decodeCategory(raw.cast<String, Object?>(), categories.length),
    );
  }

  final rawItems = json['items'];
  if (rawItems is! List) {
    throw const FormatException('menu payload has no item list');
  }
  final items = <DemoMenuItem>[];
  for (final raw in rawItems) {
    if (raw is! Map) {
      throw const FormatException('menu item record is malformed');
    }
    items.add(_decodeItem(raw.cast<String, Object?>()));
  }

  final rawGroups = json['modifier_groups'];
  if (rawGroups is! List) {
    throw const FormatException('menu payload has no modifier group list');
  }
  final groups = <PosModifierGroup>[];
  for (final raw in rawGroups) {
    if (raw is! Map) {
      throw const FormatException('modifier group record is malformed');
    }
    groups.add(_decodeGroup(raw.cast<String, Object?>()));
  }

  return PosMenuData(
    categories: categories,
    items: items,
    currencyCode: currency,
    modifierGroups: groups,
  );
}

DemoCategory _decodeCategory(Map<String, Object?> json, int index) {
  final id = json['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('menu category record has no id');
  }
  final name = json['name'];
  if (name is! String) {
    throw const FormatException('menu category record has no name');
  }
  // Presentation is re-derived, never stored (see [encodePosMenuData]).
  // OPS-044: the owner's KEY is the one thing that is stored, and it is kept
  // verbatim — including a key this build cannot draw, which resolves to the
  // legacy positional glyph rather than a blank. A non-string is not a key, so
  // it degrades to unset like every other optional field here.
  final rawIconKey = json['icon_key'];
  final iconKey = rawIconKey is String && rawIconKey.isNotEmpty
      ? rawIconKey
      : null;
  final style = resolvePosCategoryStyle(index: index, iconKey: iconKey);
  return DemoCategory(
    id: id,
    name: name,
    icon: style.icon,
    color: style.color,
    iconKey: iconKey,
  );
}

Map<String, Object?> _encodeItem(DemoMenuItem item) => <String, Object?>{
  'id': item.id,
  'name': item.name,
  'price_minor': item.priceMinor,
  'category_id': item.categoryId,
  'category_name': item.categoryName,
  'category_display_order': item.categoryDisplayOrder,
  'item_display_order': item.itemDisplayOrder,
  if (item.imagePath != null) 'image_path': item.imagePath,
  if (item.imageUrl != null) 'image_url': item.imageUrl,
  if (item.itemType != null) 'item_type': item.itemType,
  if (item.tags.isNotEmpty) 'tags': item.tags,
  if (item.prepMinutes != null) 'prep_minutes': item.prepMinutes,
  if (item.kitchenNote != null) 'kitchen_note': item.kitchenNote,
  if (item.attributes.isNotEmpty) 'attributes': item.attributes,
  'availability': item.availability,
  if (item.availabilityReason != null)
    'availability_reason': item.availabilityReason,
  if (item.description != null) 'description': item.description,
};

DemoMenuItem _decodeItem(Map<String, Object?> json) {
  final id = json['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('menu item record has no id');
  }
  final name = json['name'];
  if (name is! String) {
    throw const FormatException('menu item record has no name');
  }
  // STRICT (D-007): a price we cannot read is a price we must not invent.
  final priceMinor = json['price_minor'];
  if (priceMinor is! int) {
    throw FormatException('menu item $id has no integer minor price');
  }
  final categoryId = json['category_id'];
  final categoryName = json['category_name'];
  if (categoryId is! String || categoryName is! String) {
    throw FormatException('menu item $id has no category identity');
  }
  final imagePath = json['image_path'];
  final imageUrl = json['image_url'];
  final itemType = json['item_type'];
  final rawTags = json['tags'];
  final prepMinutes = json['prep_minutes'];
  final kitchenNote = json['kitchen_note'];
  final rawAttributes = json['attributes'];
  final availabilityReason = json['availability_reason'];
  final description = json['description'];
  return DemoMenuItem(
    id: id,
    name: name,
    priceMinor: priceMinor,
    categoryId: categoryId,
    categoryName: categoryName,
    categoryDisplayOrder: _intOrZero(json['category_display_order']),
    itemDisplayOrder: _intOrZero(json['item_display_order']),
    imagePath: imagePath is String && imagePath.isNotEmpty ? imagePath : null,
    imageUrl: imageUrl is String && imageUrl.isNotEmpty ? imageUrl : null,
    itemType: itemType is String && itemType.isNotEmpty ? itemType : null,
    tags: rawTags is List
        ? <String>[
            for (final tag in rawTags)
              if (tag is String && tag.isNotEmpty) tag,
          ]
        : const <String>[],
    prepMinutes: prepMinutes is int && prepMinutes >= 0 ? prepMinutes : null,
    kitchenNote: kitchenNote is String && kitchenNote.isNotEmpty
        ? kitchenNote
        : null,
    attributes: rawAttributes is Map
        ? Map<String, dynamic>.from(rawAttributes)
        : const <String, dynamic>{},
    // Fails open to 'available' exactly like the live parse boundary: the
    // gate is display-only and the SERVER re-refuses at acceptance.
    availability: json['availability'] == 'unavailable'
        ? 'unavailable'
        : 'available',
    availabilityReason:
        availabilityReason is String && availabilityReason.isNotEmpty
        ? availabilityReason
        : null,
    description: description is String && description.trim().isNotEmpty
        ? description
        : null,
  );
}

Map<String, Object?> _encodeGroup(PosModifierGroup group) => <String, Object?>{
  'id': group.id,
  'menu_item_id': group.menuItemId,
  'name': group.name,
  'single_select': group.singleSelect,
  'min_select': group.minSelect,
  if (group.maxSelect != null) 'max_select': group.maxSelect,
  'is_required': group.isRequired,
  'allow_quantity': group.allowQuantity,
  if (group.maxQuantity != null) 'max_quantity': group.maxQuantity,
  'options': <Object?>[
    for (final option in group.options)
      <String, Object?>{
        'id': option.id,
        'name': option.name,
        'price_delta_minor': option.priceDeltaMinor,
        if (option.kitchenMeat != null)
          'kitchen_meat': option.kitchenMeat!.toJson(),
      },
  ],
};

PosModifierGroup _decodeGroup(Map<String, Object?> json) {
  final id = json['id'];
  final menuItemId = json['menu_item_id'];
  final name = json['name'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('modifier group record has no id');
  }
  if (menuItemId is! String || menuItemId.isEmpty) {
    throw FormatException('modifier group $id names no menu item');
  }
  if (name is! String || name.trim().isEmpty) {
    throw FormatException('modifier group $id has no name');
  }
  final rawOptions = json['options'];
  if (rawOptions is! List) {
    throw FormatException('modifier group $id has no option list');
  }
  final options = <PosModifierOption>[];
  for (final raw in rawOptions) {
    if (raw is! Map) {
      throw FormatException('modifier group $id has a malformed option');
    }
    final option = raw.cast<String, Object?>();
    final optionId = option['id'];
    final optionName = option['name'];
    // STRICT (D-007): a lost delta is the silent under-charge this codec's
    // fail-closed contract exists to prevent.
    final delta = option['price_delta_minor'];
    if (optionId is! String || optionId.isEmpty) {
      throw FormatException('modifier group $id has an option with no id');
    }
    if (optionName is! String) {
      throw FormatException('modifier option $optionId has no name');
    }
    if (delta is! int) {
      throw FormatException('modifier option $optionId has no integer delta');
    }
    options.add(
      PosModifierOption(
        id: optionId,
        name: optionName,
        priceDeltaMinor: delta,
        // Tolerant like the live boundary: malformed meat metadata degrades to
        // "no contribution" (money-free), never to a lost option.
        kitchenMeat: KitchenMeat.tryFromJson(option['kitchen_meat']),
      ),
    );
  }
  final minSelect = json['min_select'];
  final maxSelect = json['max_select'];
  final maxQuantity = json['max_quantity'];
  return PosModifierGroup(
    id: id,
    menuItemId: menuItemId,
    name: name,
    options: options,
    singleSelect: json['single_select'] == true,
    minSelect: minSelect is int ? minSelect : 0,
    maxSelect: maxSelect is int ? maxSelect : null,
    isRequired: json['is_required'] == true,
    allowQuantity: json['allow_quantity'] == true,
    maxQuantity: maxQuantity is int && maxQuantity > 0 ? maxQuantity : null,
  );
}

int _intOrZero(Object? raw) => raw is int ? raw : 0;
