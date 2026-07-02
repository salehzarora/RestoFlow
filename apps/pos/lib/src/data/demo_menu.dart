import 'package:flutter/material.dart';
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
class DemoMenuItem {
  const DemoMenuItem({
    required this.id,
    required this.name,
    required this.priceMinor,
    required this.categoryId,
    required this.categoryName,
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
  DemoMenuItem(
    id: 'cheeseburger',
    name: 'Cheeseburger',
    priceMinor: 4800,
    categoryId: 'burgers',
    categoryName: 'Burgers',
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
  DemoMenuItem(
    id: 'onion-rings',
    name: 'Onion Rings',
    priceMinor: 1900,
    categoryId: 'sides',
    categoryName: 'Sides',
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
  DemoMenuItem(
    id: 'fresh-lemonade',
    name: 'Fresh Lemonade',
    priceMinor: 1400,
    categoryId: 'drinks',
    categoryName: 'Drinks',
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
