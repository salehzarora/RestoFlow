import 'package:flutter/material.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// In-memory demo menu data for the RF-100 POS demo screen.
///
/// This is FAKE local data only — no Supabase, no repository, no persistence.
/// Real menu data lands in a later ticket. Prices are integer MINOR units
/// (agorot for ILS) per DECISION D-007 — there is no floating-point money.
///
/// Item and category NAMES are data (rendered via `Text(identifier)`), so they
/// stay here rather than in l10n; only POS chrome (buttons/labels) is localized.

/// ISO 4217 currency for the demo, locked to ILS / ₪ for RF-100.
const String kDemoCurrencyCode = 'ILS';

/// Sentinel distinguishing "argument omitted" from an explicit `null` in
/// [DemoMenuItem.copyWith] (so a nullable field can be cleared, not only kept).
const Object _unset = Object();

/// A menu category used for the filter chips and per-item iconography.
class DemoCategory {
  const DemoCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  final String id;

  /// Display name (data, not localized chrome).
  final String name;

  /// Material icon for the chip and item cards (bundled font — not unicode).
  final IconData icon;

  /// Accent colour used to tint the item card's icon band.
  final Color color;
}

/// A single demo menu item rendered as a card on the POS menu grid.
///
/// Also the POS view model for the REAL backend menu (`pos_menu` rows are
/// parsed into it), so real-only fields ([imagePath], [imageUrl]) and the
/// rich attributes (menu/media sprint) are OPTIONAL.
class DemoMenuItem {
  const DemoMenuItem({
    required this.id,
    required this.name,
    required this.priceMinor,
    required this.categoryId,
    required this.categoryName,
    this.imagePath,
    this.imageUrl,
    this.itemType,
    this.tags = const <String>[],
    this.prepMinutes,
    this.kitchenNote,
    this.attributes = const <String, dynamic>{},
    this.availability = 'available',
    this.availabilityReason,
  });

  /// Stable demo identifier; also used as the cart line's menu item id.
  final String id;

  /// Display name (data, not localized chrome).
  final String name;

  /// Unit price in integer MINOR units (e.g. 4200 = ₪42.00). Never a float.
  final int priceMinor;

  /// Owning category id/name (data).
  final String categoryId;
  final String categoryName;

  /// The RF-110 storage object key of the item's image (real menu only; the
  /// backend `pos_menu` serves it as `image_path`). Null = no image.
  final String? imagePath;

  /// The resolved short-lived signed URL for [imagePath] (real menu only,
  /// batch-resolved once per menu load; fail-soft — resolution failures leave
  /// it null and the card renders its tinted icon band).
  final String? imageUrl;

  /// Rich attributes (menu/media sprint) — STORAGE ONLY for now; card/sheet
  /// display lands in later parts. All NON-MONEY (D-007): [itemType] is the
  /// coarse kind wire value (food/drink/side/combo/other), [tags] are fixed-
  /// vocabulary wire strings (never localized in data), [prepMinutes] is time,
  /// [kitchenNote] is the standing prep note, and [attributes] is the generic
  /// bag (portion_label / patty_count / patty_weight_grams — weight is grams).
  final String? itemType;
  final List<String> tags;
  final int? prepMinutes;
  final String? kitchenNote;
  final Map<String, dynamic> attributes;

  /// RESTAURANT-OPERATIONS-V1-001: the item's availability in THIS branch, as
  /// the server reported it ('available' | 'unavailable'; absence of an
  /// override row is 'available'). The POS keeps unavailable items VISIBLE —
  /// greyed, with [availabilityReason] ('sold_out' | 'paused') explaining why —
  /// and refuses to add them to the cart; the server refuses the sale again at
  /// acceptance (item_unavailable), so a stale menu can never oversell.
  final String availability;
  final String? availabilityReason;

  bool get isUnavailable => availability == 'unavailable';

  /// PILOT-OPERATIONS-CORRECTIONS-001: a field-preserving copy. Every field is
  /// carried through unless explicitly overridden — so a partial rebuild (e.g.
  /// attaching a resolved signed image URL) can NEVER silently drop an
  /// authoritative field such as [availability]/[availabilityReason] and turn a
  /// Sold-out/Paused item back into a normally-sellable one. New fields added to
  /// this model are preserved automatically; keep this method exhaustive.
  ///
  /// [availabilityReason] uses a sentinel so it can be explicitly cleared to
  /// null (returning an item to available) — omitting it preserves the current
  /// value, passing `null` clears it.
  DemoMenuItem copyWith({
    String? id,
    String? name,
    int? priceMinor,
    String? categoryId,
    String? categoryName,
    String? imagePath,
    String? imageUrl,
    String? itemType,
    List<String>? tags,
    int? prepMinutes,
    String? kitchenNote,
    Map<String, dynamic>? attributes,
    String? availability,
    Object? availabilityReason = _unset,
  }) => DemoMenuItem(
    id: id ?? this.id,
    name: name ?? this.name,
    priceMinor: priceMinor ?? this.priceMinor,
    categoryId: categoryId ?? this.categoryId,
    categoryName: categoryName ?? this.categoryName,
    imagePath: imagePath ?? this.imagePath,
    imageUrl: imageUrl ?? this.imageUrl,
    itemType: itemType ?? this.itemType,
    tags: tags ?? this.tags,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    kitchenNote: kitchenNote ?? this.kitchenNote,
    attributes: attributes ?? this.attributes,
    availability: availability ?? this.availability,
    availabilityReason: identical(availabilityReason, _unset)
        ? this.availabilityReason
        : availabilityReason as String?,
  );

  /// PILOT-OPERATIONS-CORRECTIONS-001: a copy with only the branch availability
  /// changed (used by the demo availability overlay and by real-mode optimistic
  /// tile reconciliation before the authoritative menu re-fetch lands). Clears
  /// the reason when returning to available.
  DemoMenuItem withAvailability(String availability, String? reason) =>
      copyWith(
        availability: availability,
        availabilityReason: availability == 'unavailable' ? reason : null,
      );

  /// KITCHEN-PREP-001: the item's configured PER-UNIT kitchen prep components,
  /// parsed from the generic [attributes] bag (`prep_components`). Non-money;
  /// empty when unconfigured. Snapshotted into the order at submit time so the
  /// KDS can aggregate a prep summary for the chef.
  List<KitchenPrepComponent> get prepComponents =>
      parseKitchenPrepComponents(attributes['prep_components']);
}

/// The demo categories (order drives the filter-chip order).
const List<DemoCategory> kDemoCategories = <DemoCategory>[
  DemoCategory(
    id: 'burgers',
    name: 'Burgers',
    icon: Icons.lunch_dining,
    color: RestoflowCategoryPalette.terracotta,
  ),
  DemoCategory(
    id: 'mains',
    name: 'Mains',
    icon: Icons.dinner_dining,
    color: RestoflowCategoryPalette.teal,
  ),
  DemoCategory(
    id: 'sides',
    name: 'Sides',
    icon: Icons.fastfood,
    color: RestoflowCategoryPalette.amber,
  ),
  DemoCategory(
    id: 'drinks',
    name: 'Drinks',
    icon: Icons.local_bar,
    color: RestoflowCategoryPalette.blue,
  ),
  DemoCategory(
    id: 'coffee',
    name: 'Coffee',
    icon: Icons.local_cafe,
    color: RestoflowCategoryPalette.coffee,
  ),
];

/// Looks up a category by id; falls back to the first category if unknown.
DemoCategory categoryById(String categoryId) {
  for (final category in kDemoCategories) {
    if (category.id == categoryId) return category;
  }
  return kDemoCategories.first;
}

/// Fake demo menu: 16 items across the five categories. In-memory only.
const List<DemoMenuItem> kDemoMenu = <DemoMenuItem>[
  // Burgers
  DemoMenuItem(
    id: 'classic-burger',
    name: 'Classic Burger',
    priceMinor: 4200,
    categoryId: 'burgers',
    categoryName: 'Burgers',
  ),
  // The rich-attribute showcase item (menu/media sprint): sensible demo
  // values so later parts can demo type/tags/prep/kitchen-note/attributes.
  // Names/notes are demo DATA, not chrome; weight is grams, never money.
  DemoMenuItem(
    id: 'cheeseburger',
    name: 'Cheeseburger',
    priceMinor: 4800,
    categoryId: 'burgers',
    categoryName: 'Burgers',
    itemType: 'food',
    tags: <String>['popular'],
    prepMinutes: 12,
    kitchenNote: 'Toast the bun; cheese on the patty.',
    attributes: <String, dynamic>{
      'portion_label': 'Single',
      'patty_count': 1,
      'patty_weight_grams': 160,
      // KITCHEN-PREP-001 demo: what the chef assembles for ONE cheeseburger.
      // Names/units are demo DATA (a real restaurant configures its own, in any
      // language). Counts, never money (D-007).
      'prep_components': <Map<String, dynamic>>[
        {'name': 'Beef patty', 'quantity': 1, 'unit': 'pcs'},
        {'name': 'Burger bun', 'quantity': 1, 'unit': ''},
        {'name': 'Cheese slice', 'quantity': 1, 'unit': ''},
      ],
    },
  ),
  DemoMenuItem(
    id: 'double-bacon-burger',
    name: 'Double Bacon Burger',
    priceMinor: 5900,
    categoryId: 'burgers',
    categoryName: 'Burgers',
  ),
  DemoMenuItem(
    id: 'veggie-burger',
    name: 'Veggie Burger',
    priceMinor: 4400,
    categoryId: 'burgers',
    categoryName: 'Burgers',
  ),
  // Mains
  DemoMenuItem(
    id: 'grilled-chicken',
    name: 'Grilled Chicken',
    priceMinor: 5200,
    categoryId: 'mains',
    categoryName: 'Mains',
  ),
  DemoMenuItem(
    id: 'margherita-pizza',
    name: 'Margherita Pizza',
    priceMinor: 5600,
    categoryId: 'mains',
    categoryName: 'Mains',
  ),
  DemoMenuItem(
    id: 'falafel-plate',
    name: 'Falafel Plate',
    priceMinor: 3800,
    categoryId: 'mains',
    categoryName: 'Mains',
  ),
  DemoMenuItem(
    id: 'lamb-shawarma',
    name: 'Lamb Shawarma',
    priceMinor: 5400,
    categoryId: 'mains',
    categoryName: 'Mains',
  ),
  // Sides
  DemoMenuItem(
    id: 'french-fries',
    name: 'French Fries',
    priceMinor: 1600,
    categoryId: 'sides',
    categoryName: 'Sides',
  ),
  // RESTAURANT-OPERATIONS-V1-001: a SOLD-OUT demo item — visible, greyed, not
  // sellable, so the availability treatment has a live example.
  DemoMenuItem(
    id: 'onion-rings',
    name: 'Onion Rings',
    priceMinor: 1900,
    categoryId: 'sides',
    categoryName: 'Sides',
    availability: 'unavailable',
    availabilityReason: 'sold_out',
  ),
  DemoMenuItem(
    id: 'garden-salad',
    name: 'Garden Salad',
    priceMinor: 2400,
    categoryId: 'sides',
    categoryName: 'Sides',
  ),
  // Drinks
  DemoMenuItem(
    id: 'cola',
    name: 'Cola',
    priceMinor: 900,
    categoryId: 'drinks',
    categoryName: 'Drinks',
  ),
  // RESTAURANT-OPERATIONS-V1-001: a PAUSED demo item (temporarily unavailable).
  DemoMenuItem(
    id: 'fresh-lemonade',
    name: 'Fresh Lemonade',
    priceMinor: 1400,
    categoryId: 'drinks',
    categoryName: 'Drinks',
    availability: 'unavailable',
    availabilityReason: 'paused',
  ),
  DemoMenuItem(
    id: 'mineral-water',
    name: 'Mineral Water',
    priceMinor: 700,
    categoryId: 'drinks',
    categoryName: 'Drinks',
  ),
  // Coffee
  DemoMenuItem(
    id: 'espresso',
    name: 'Espresso',
    priceMinor: 1200,
    categoryId: 'coffee',
    categoryName: 'Coffee',
  ),
  DemoMenuItem(
    id: 'cappuccino',
    name: 'Cappuccino',
    priceMinor: 1500,
    categoryId: 'coffee',
    categoryName: 'Coffee',
  ),
];
