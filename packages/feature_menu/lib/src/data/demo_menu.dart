import '../models/item_size.dart';
import '../models/item_variant.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import '../models/menu_scope.dart';
import '../models/modifier.dart';
import '../models/modifier_option.dart';
import 'in_memory_menu_store.dart';

/// FAKE demo data only (RF-111) — no Supabase, no real persistence. This backs
/// the owner menu UI in demo mode and the happy-path widget tests so the feature
/// is fully interactive while the real backend wiring is deferred (D1/D3). All
/// ids are stable demo strings; money is integer minor units (USD, exponent 2).
const String demoOrganizationId = 'demo-org';
const String demoRestaurantId = 'demo-restaurant';
const String demoBranchId = 'demo-branch';
const String demoCurrencyCode = 'USD';

/// The demo scope (a single branch of a single restaurant).
const MenuScope demoMenuScope = MenuScope(
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  currencyCode: demoCurrencyCode,
);

MenuCategory _category(
  String id,
  String name,
  int order, {
  String? branchId = demoBranchId,
  bool isActive = true,
}) {
  return MenuCategory(
    id: id,
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: branchId,
    name: name,
    displayOrder: order,
    isActive: isActive,
  );
}

MenuItem _item(
  String id,
  String categoryId,
  String name,
  int basePriceMinor,
  int order, {
  String? description,
  String? branchId = demoBranchId,
  bool isActive = true,
}) {
  return MenuItem(
    id: id,
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    branchId: branchId,
    menuCategoryId: categoryId,
    name: name,
    description: description,
    basePriceMinor: basePriceMinor,
    currencyCode: demoCurrencyCode,
    defaultStationId: null,
    displayOrder: order,
    isActive: isActive,
  );
}

ItemSize _size(
  String id,
  String itemId,
  String name,
  int deltaMinor,
  int order,
) => ItemSize(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  menuItemId: itemId,
  name: name,
  priceDeltaMinor: deltaMinor,
  displayOrder: order,
  isActive: true,
);

ItemVariant _variant(
  String id,
  String itemId,
  String name,
  int deltaMinor,
  int order,
) => ItemVariant(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  menuItemId: itemId,
  name: name,
  priceDeltaMinor: deltaMinor,
  displayOrder: order,
  isActive: true,
);

Modifier _modifier(String id, String itemId, String name, int order) =>
    Modifier(
      id: id,
      organizationId: demoOrganizationId,
      restaurantId: demoRestaurantId,
      branchId: demoBranchId,
      menuItemId: itemId,
      name: name,
      selectionType: 'multiple',
      minSelect: 0,
      maxSelect: 3,
      isRequired: false,
      displayOrder: order,
      isActive: true,
    );

ModifierOption _option(
  String id,
  String modifierId,
  String name,
  int deltaMinor,
  int order,
) => ModifierOption(
  id: id,
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  modifierId: modifierId,
  name: name,
  priceDeltaMinor: deltaMinor,
  displayOrder: order,
  isActive: true,
);

/// Builds a fresh, interactive demo store seeded with a small realistic menu.
/// A new instance per call keeps demo edits isolated between sessions/tests.
/// Set [readOnly] to model a member who lacks the write role.
InMemoryMenuStore buildDemoMenuStore({bool readOnly = false}) {
  return InMemoryMenuStore(
    readOnly: readOnly,
    categories: [
      _category('cat-hot', 'Hot Drinks', 0),
      _category('cat-cold', 'Cold Drinks', 1),
      // A restaurant-scoped (global) category, visible across branches.
      _category('cat-food', 'Food', 2, branchId: null),
    ],
    items: [
      _item(
        'item-espresso',
        'cat-hot',
        'Espresso',
        350,
        0,
        description: 'Double shot.',
      ),
      _item(
        'item-cappuccino',
        'cat-hot',
        'Cappuccino',
        450,
        1,
        description: 'Espresso with steamed milk.',
      ),
      // An inactive item (still listed, badged inactive).
      _item(
        'item-pumpkin',
        'cat-hot',
        'Seasonal Pumpkin Latte',
        550,
        2,
        isActive: false,
      ),
      _item('item-iced-latte', 'cat-cold', 'Iced Latte', 500, 0),
      // A restaurant-scoped (global) item.
      _item(
        'item-croissant',
        'cat-food',
        'Butter Croissant',
        400,
        0,
        branchId: null,
      ),
    ],
    sizes: [
      _size('size-cap-s', 'item-cappuccino', 'Small', 0, 0),
      _size('size-cap-l', 'item-cappuccino', 'Large', 150, 1),
    ],
    variants: [
      _variant('var-cap-oat', 'item-cappuccino', 'Oat milk', 80, 0),
      _variant('var-cap-decaf', 'item-cappuccino', 'Decaf', 0, 1),
    ],
    modifiers: [_modifier('mod-cap-extras', 'item-cappuccino', 'Extras', 0)],
    modifierOptions: [
      _option('opt-extra-shot', 'mod-cap-extras', 'Extra shot', 120, 0),
      _option('opt-caramel', 'mod-cap-extras', 'Caramel syrup', 90, 1),
    ],
  );
}
