/// MENU-CATEGORY-ICON-PICKER-OPS-044 (Phase 1) — the shared, owner-pickable
/// category icon library.
///
/// WHY A REGISTRY AND NOT A STORED ICON. Today a POS category's icon is decided
/// by its POSITION in the fetched list (`kPosCategoryPalette[index % 6]`), so
/// drag-reordering categories silently reassigns every icon. OPS-044 lets the
/// owner pick one explicitly. What gets persisted (from Phase 2 onward) is the
/// abstract [MenuCategoryIconDefinition.key] — never a Material codepoint, an
/// [IconData], a widget/class name, or a numeric glyph id. The key is the
/// contract; this map is an implementation detail, so a future custom icon
/// family can replace today's approximations with NO database migration and no
/// re-picking by the owner.
///
/// RELEASE SAFETY — READ BEFORE EDITING. Release builds tree-shake the icon
/// font (`flutter_tools/.../icon_tree_shaker.dart`). Two rules follow, and both
/// fail ONLY in a release build — never in `flutter test` and never in debug:
///
///  1. Every icon here MUST be a compile-time `const` reference to an
///     `Icons.*` constant. A dynamically constructed `IconData(codePoint)`
///     makes the tool `throwToolExit` with "This application cannot tree shake
///     icons fonts. It has non-constant instances of IconData", i.e. the
///     release build FAILS. `menu_category_icons_test.dart` scans this source
///     for a raw `IconData(` and fails if one ever appears.
///  2. This class must NOT carry `@staticIconProvider`. That annotation tells
///     the shaker to IGNORE a class's constants — it is how `Icons` itself
///     avoids retaining all ~8,800 glyphs — so annotating THIS registry would
///     strip our 49 glyphs out of the bundled font and render blanks in
///     release only.
///
/// SCOPE (Phase 1). This file is inert: nothing consumes it yet. The POS keeps
/// its positional palette and the Dashboard keeps its fixed tile icon until the
/// later phases wire them up.
library;

import 'package:flutter/material.dart';

/// The owner-facing grouping of the icon library, in picker display order.
///
/// Groups exist so the picker can present ~49 icons as browsable sections
/// rather than one undifferentiated grid. The enum is the stable identity; its
/// localized heading is looked up per-locale by the picker (Phase 3).
enum MenuCategoryIconGroup {
  /// Plated/served food: the restaurant's main dishes.
  mains,

  /// Counter and quick-service food, plus the service styles that go with it.
  fastFood,

  /// Baked goods, breakfast and everything sweet.
  bakerySweets,

  /// Cold and alcoholic drinks.
  coldDrinks,

  /// Hot drinks and the coffee bar.
  hotDrinks,

  /// Produce, condiments and non-food catch-alls.
  other,
}

/// One entry in the built-in category icon library.
///
/// [key] is the ONLY part that is ever persisted or transmitted. [icon] and
/// [group] are presentation, free to change between releases.
@immutable
class MenuCategoryIconDefinition {
  const MenuCategoryIconDefinition({
    required this.key,
    required this.icon,
    required this.group,
    this.searchTokens = const <String>[],
  });

  /// The stable wire key, `^[a-z][a-z0-9_]{0,39}$` — the same shape the Phase-2
  /// `menu_categories.icon_key` CHECK constraint will enforce server-side.
  final String key;

  /// The rendered glyph. Always a `const Icons.*` reference (see the library
  /// doc: a non-const [IconData] breaks the release build).
  final IconData icon;

  /// Which picker section this icon belongs to.
  final MenuCategoryIconGroup group;

  /// Extra lowercase ASCII match terms for the picker's search box.
  ///
  /// These are a MATCHING AID, never displayed: the picker shows the localized
  /// label (Phase 3) and matches against that label, the [key], and these. They
  /// let an owner typing "sandwich" or "patty" find the burger icon even though
  /// neither word is its key. Deliberately not localized — the localized label
  /// is what covers ar/he search.
  final List<String> searchTokens;

  @override
  String toString() => 'MenuCategoryIconDefinition($key)';
}

/// The built-in category icon library: 49 Material glyphs in six groups.
///
/// MATERIAL-ONLY, ONE FAMILY. Every entry is a FILLED Material icon — the same
/// family the POS category chips already use — so the picker can never produce
/// a mixed-weight rail. No `_outlined` / `_rounded` / `_sharp` variants.
///
/// NO BRANDS. Material ships trademarked marks (`Icons.apple`, `Icons.facebook`
/// and friends). None is in this allow-list, and a test asserts that.
///
/// KNOWN APPROXIMATIONS. Material has no burger, fries, chicken, salad,
/// seafood, sauce, fruit, snack or dessert glyph, so a few keys carry the
/// nearest neutral pictogram (`salad` -> eco, `sauces` -> local_dining,
/// `produce` -> agriculture). Because the KEY is what persists, swapping in a
/// dedicated food-icon family later changes only this file.
abstract final class MenuCategoryIcons {
  /// Every definition, in picker order: by [MenuCategoryIconGroup] declaration
  /// order, then a curated order within each group.
  ///
  /// This list is the SINGLE source of truth. The lookup index below is derived
  /// from it rather than hand-maintained, so the two can never drift apart.
  static const List<MenuCategoryIconDefinition> all =
      <MenuCategoryIconDefinition>[
        // --- Mains ---------------------------------------------------------
        MenuCategoryIconDefinition(
          key: 'meals',
          icon: Icons.restaurant,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['food', 'dish', 'plate', 'cutlery'],
        ),
        MenuCategoryIconDefinition(
          key: 'dinner',
          icon: Icons.dinner_dining,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['pasta', 'evening', 'main'],
        ),
        MenuCategoryIconDefinition(
          key: 'grill',
          icon: Icons.outdoor_grill,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['bbq', 'barbecue', 'charcoal', 'meat'],
        ),
        MenuCategoryIconDefinition(
          key: 'rice',
          icon: Icons.rice_bowl,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['bowl', 'grain'],
        ),
        MenuCategoryIconDefinition(
          key: 'noodles',
          icon: Icons.ramen_dining,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['ramen', 'pasta', 'soup'],
        ),
        MenuCategoryIconDefinition(
          key: 'soup',
          icon: Icons.soup_kitchen,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['broth', 'stew', 'pot'],
        ),
        MenuCategoryIconDefinition(
          key: 'set_meal',
          icon: Icons.set_meal,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['combo', 'platter', 'seafood', 'fish'],
        ),
        MenuCategoryIconDefinition(
          key: 'bento',
          icon: Icons.bento,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['box', 'lunchbox', 'combo'],
        ),
        MenuCategoryIconDefinition(
          key: 'skewers',
          icon: Icons.kebab_dining,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['kebab', 'shawarma', 'chicken', 'grill'],
        ),
        MenuCategoryIconDefinition(
          key: 'tapas',
          icon: Icons.tapas,
          group: MenuCategoryIconGroup.mains,
          searchTokens: <String>['mezze', 'appetizer', 'starter', 'small'],
        ),
        // --- Fast food -----------------------------------------------------
        MenuCategoryIconDefinition(
          key: 'burger',
          icon: Icons.lunch_dining,
          group: MenuCategoryIconGroup.fastFood,
          searchTokens: <String>['sandwich', 'patty', 'bun', 'lunch'],
        ),
        MenuCategoryIconDefinition(
          key: 'fast_food',
          icon: Icons.fastfood,
          group: MenuCategoryIconGroup.fastFood,
          searchTokens: <String>['fries', 'snack', 'quick', 'counter'],
        ),
        MenuCategoryIconDefinition(
          key: 'pizza',
          icon: Icons.local_pizza,
          group: MenuCategoryIconGroup.fastFood,
          searchTokens: <String>['slice', 'italian'],
        ),
        MenuCategoryIconDefinition(
          key: 'takeaway',
          icon: Icons.takeout_dining,
          group: MenuCategoryIconGroup.fastFood,
          searchTokens: <String>['takeout', 'togo', 'box'],
        ),
        MenuCategoryIconDefinition(
          key: 'delivery',
          icon: Icons.delivery_dining,
          group: MenuCategoryIconGroup.fastFood,
          searchTokens: <String>['scooter', 'courier', 'dispatch'],
        ),
        MenuCategoryIconDefinition(
          key: 'room_service',
          icon: Icons.room_service,
          group: MenuCategoryIconGroup.fastFood,
          searchTokens: <String>['tray', 'cloche', 'service'],
        ),
        MenuCategoryIconDefinition(
          key: 'kids_meal',
          icon: Icons.child_care,
          group: MenuCategoryIconGroup.fastFood,
          searchTokens: <String>['kids', 'children', 'family'],
        ),
        // --- Bakery & sweets -----------------------------------------------
        MenuCategoryIconDefinition(
          key: 'bakery',
          icon: Icons.bakery_dining,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['bread', 'croissant', 'pastry'],
        ),
        MenuCategoryIconDefinition(
          key: 'breakfast',
          icon: Icons.breakfast_dining,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['toast', 'morning'],
        ),
        MenuCategoryIconDefinition(
          key: 'brunch',
          icon: Icons.brunch_dining,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['latebreakfast', 'morning'],
        ),
        MenuCategoryIconDefinition(
          key: 'eggs',
          icon: Icons.egg_alt,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['omelette', 'egg'],
        ),
        MenuCategoryIconDefinition(
          key: 'cake',
          icon: Icons.cake,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['dessert', 'birthday', 'gateau'],
        ),
        MenuCategoryIconDefinition(
          key: 'cookie',
          icon: Icons.cookie,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['biscuit', 'snack', 'sweet'],
        ),
        MenuCategoryIconDefinition(
          key: 'donut',
          icon: Icons.donut_large,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['doughnut', 'ring', 'sweet'],
        ),
        MenuCategoryIconDefinition(
          key: 'ice_cream',
          icon: Icons.icecream,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['gelato', 'cone', 'frozen', 'dessert'],
        ),
        MenuCategoryIconDefinition(
          key: 'celebration',
          icon: Icons.celebration,
          group: MenuCategoryIconGroup.bakerySweets,
          searchTokens: <String>['party', 'event', 'special'],
        ),
        // --- Cold drinks ---------------------------------------------------
        MenuCategoryIconDefinition(
          key: 'drinks',
          icon: Icons.local_drink,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['juice', 'soda', 'cup', 'beverage'],
        ),
        MenuCategoryIconDefinition(
          key: 'bar',
          icon: Icons.local_bar,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['cocktail', 'martini', 'mixed'],
        ),
        MenuCategoryIconDefinition(
          key: 'wine',
          icon: Icons.wine_bar,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['glass', 'red', 'white'],
        ),
        MenuCategoryIconDefinition(
          key: 'spirits',
          icon: Icons.liquor,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['bottle', 'alcohol', 'whisky'],
        ),
        MenuCategoryIconDefinition(
          key: 'beer',
          icon: Icons.sports_bar,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['pint', 'draft', 'lager'],
        ),
        MenuCategoryIconDefinition(
          key: 'nightlife',
          icon: Icons.nightlife,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['evening', 'club', 'late'],
        ),
        MenuCategoryIconDefinition(
          key: 'water',
          icon: Icons.water_drop,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['still', 'sparkling', 'bottle'],
        ),
        MenuCategoryIconDefinition(
          key: 'cold',
          icon: Icons.ac_unit,
          group: MenuCategoryIconGroup.coldDrinks,
          searchTokens: <String>['iced', 'chilled', 'frozen'],
        ),
        // --- Hot drinks ----------------------------------------------------
        MenuCategoryIconDefinition(
          key: 'coffee',
          icon: Icons.local_cafe,
          group: MenuCategoryIconGroup.hotDrinks,
          searchTokens: <String>['cafe', 'cup', 'latte'],
        ),
        MenuCategoryIconDefinition(
          key: 'espresso',
          icon: Icons.coffee,
          group: MenuCategoryIconGroup.hotDrinks,
          searchTokens: <String>['mug', 'americano', 'short'],
        ),
        MenuCategoryIconDefinition(
          key: 'tea',
          icon: Icons.emoji_food_beverage,
          group: MenuCategoryIconGroup.hotDrinks,
          searchTokens: <String>['teapot', 'herbal', 'infusion'],
        ),
        MenuCategoryIconDefinition(
          key: 'hot_drinks',
          icon: Icons.free_breakfast,
          group: MenuCategoryIconGroup.hotDrinks,
          searchTokens: <String>['hot', 'steam', 'cup'],
        ),
        MenuCategoryIconDefinition(
          key: 'coffee_maker',
          icon: Icons.coffee_maker,
          group: MenuCategoryIconGroup.hotDrinks,
          searchTokens: <String>['machine', 'brewer', 'barista'],
        ),
        // --- Other ---------------------------------------------------------
        MenuCategoryIconDefinition(
          key: 'salad',
          icon: Icons.eco,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['green', 'leaf', 'vegan', 'vegetarian'],
        ),
        MenuCategoryIconDefinition(
          key: 'produce',
          icon: Icons.agriculture,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['fruit', 'vegetable', 'farm', 'fresh'],
        ),
        MenuCategoryIconDefinition(
          key: 'herbs',
          icon: Icons.grass,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['spice', 'seasoning', 'fresh'],
        ),
        MenuCategoryIconDefinition(
          key: 'sauces',
          icon: Icons.local_dining,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['dip', 'dressing', 'condiment', 'extra'],
        ),
        MenuCategoryIconDefinition(
          key: 'spicy',
          icon: Icons.local_fire_department,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['hot', 'chilli', 'flame'],
        ),
        MenuCategoryIconDefinition(
          key: 'kitchen',
          icon: Icons.kitchen,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['fridge', 'prep', 'backofhouse'],
        ),
        MenuCategoryIconDefinition(
          key: 'sides',
          icon: Icons.inventory_2,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['extras', 'addons', 'box'],
        ),
        MenuCategoryIconDefinition(
          key: 'offers',
          icon: Icons.local_offer,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['deal', 'promo', 'discount', 'tag'],
        ),
        MenuCategoryIconDefinition(
          key: 'general',
          icon: Icons.category,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['misc', 'other', 'default'],
        ),
        MenuCategoryIconDefinition(
          key: 'menu',
          icon: Icons.restaurant_menu,
          group: MenuCategoryIconGroup.other,
          searchTokens: <String>['list', 'card', 'all'],
        ),
      ];

  /// Derived lookup index — see [all] for why this is not hand-written.
  static final Map<String, MenuCategoryIconDefinition> _byKey = {
    for (final definition in all) definition.key: definition,
  };

  /// Every known key. Useful for validation and for tests.
  static Set<String> get keys => _byKey.keys.toSet();

  /// Whether [key] is a key THIS build knows how to render.
  ///
  /// False for null, for the empty string, and for a key added by a newer
  /// Dashboard than this binary — which is exactly why the consuming surfaces
  /// keep a fallback (a newer picker must never blank out an older POS).
  static bool isKnownCategoryIconKey(String? key) =>
      key != null && _byKey.containsKey(key);

  /// The full definition for [key], or null when unknown. Prefer this over
  /// [iconForCategoryKey] when the caller also needs the group or the search
  /// tokens (the picker does).
  static MenuCategoryIconDefinition? definitionFor(String? key) =>
      key == null ? null : _byKey[key];

  /// The glyph for [key], or null when the key is absent, empty or unknown.
  ///
  /// Returning null rather than a default is deliberate: the registry does not
  /// get to decide the fallback. Each surface keeps its own — the POS its
  /// positional `kPosCategoryPalette` entry, the Dashboard its tile default —
  /// so "no icon chosen" keeps rendering exactly as it does today.
  static IconData? iconForCategoryKey(String? key) => definitionFor(key)?.icon;

  /// The definitions in [group], in picker order.
  static List<MenuCategoryIconDefinition> definitionsFor(
    MenuCategoryIconGroup group,
  ) => <MenuCategoryIconDefinition>[
    for (final definition in all)
      if (definition.group == group) definition,
  ];
}
