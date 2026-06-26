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
/// is fully interactive while the real backend wiring is deferred (D1/D3).
///
/// [buildDemoMenuStore] seeds the demo rows at a supplied [MenuScope] so the
/// dashboard can wire the menu feature to the REAL active-membership scope
/// (org/restaurant/branch + currency) in auth mode — only the data is demo, not
/// the scope. Ids/names/prices are stable; money is integer minor units.
const String demoOrganizationId = 'demo-org';
const String demoRestaurantId = 'demo-restaurant';
const String demoBranchId = 'demo-branch';
const String demoCurrencyCode = 'USD';

/// The default demo scope (a single branch of a single restaurant).
const MenuScope demoMenuScope = MenuScope(
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  currencyCode: demoCurrencyCode,
);

/// Builds a fresh, interactive demo store seeded with a small realistic menu,
/// scoped to [scope] (org/restaurant/branch + currency). Branch-specific rows
/// use `scope.branchId`; restaurant-scoped ("global") rows use a null branch. A
/// new instance per call keeps demo edits isolated between sessions/tests. Set
/// [readOnly] to model a member who lacks the write role.
InMemoryMenuStore buildDemoMenuStore({
  MenuScope scope = demoMenuScope,
  bool readOnly = false,
}) {
  final org = scope.organizationId;
  final restaurant = scope.restaurantId;
  final branch = scope.branchId;
  final currency = scope.currencyCode;

  MenuCategory category(
    String id,
    String name,
    int order, {
    bool global = false,
    bool isActive = true,
  }) => MenuCategory(
    id: id,
    organizationId: org,
    restaurantId: restaurant,
    branchId: global ? null : branch,
    name: name,
    displayOrder: order,
    isActive: isActive,
  );

  MenuItem item(
    String id,
    String categoryId,
    String name,
    int basePriceMinor,
    int order, {
    String? description,
    bool global = false,
    bool isActive = true,
  }) => MenuItem(
    id: id,
    organizationId: org,
    restaurantId: restaurant,
    branchId: global ? null : branch,
    menuCategoryId: categoryId,
    name: name,
    description: description,
    basePriceMinor: basePriceMinor,
    currencyCode: currency,
    defaultStationId: null,
    displayOrder: order,
    isActive: isActive,
  );

  ItemSize size(
    String id,
    String itemId,
    String name,
    int deltaMinor,
    int order,
  ) => ItemSize(
    id: id,
    organizationId: org,
    restaurantId: restaurant,
    branchId: branch,
    menuItemId: itemId,
    name: name,
    priceDeltaMinor: deltaMinor,
    displayOrder: order,
    isActive: true,
  );

  ItemVariant variant(
    String id,
    String itemId,
    String name,
    int deltaMinor,
    int order,
  ) => ItemVariant(
    id: id,
    organizationId: org,
    restaurantId: restaurant,
    branchId: branch,
    menuItemId: itemId,
    name: name,
    priceDeltaMinor: deltaMinor,
    displayOrder: order,
    isActive: true,
  );

  Modifier modifier(String id, String itemId, String name, int order) =>
      Modifier(
        id: id,
        organizationId: org,
        restaurantId: restaurant,
        branchId: branch,
        menuItemId: itemId,
        name: name,
        selectionType: 'multiple',
        minSelect: 0,
        maxSelect: 3,
        isRequired: false,
        displayOrder: order,
        isActive: true,
      );

  ModifierOption option(
    String id,
    String modifierId,
    String name,
    int deltaMinor,
    int order,
  ) => ModifierOption(
    id: id,
    organizationId: org,
    restaurantId: restaurant,
    branchId: branch,
    modifierId: modifierId,
    name: name,
    priceDeltaMinor: deltaMinor,
    displayOrder: order,
    isActive: true,
  );

  return InMemoryMenuStore(
    readOnly: readOnly,
    categories: [
      category('cat-hot', 'Hot Drinks', 0),
      category('cat-cold', 'Cold Drinks', 1),
      // A restaurant-scoped (global) category, visible across branches.
      category('cat-food', 'Food', 2, global: true),
    ],
    items: [
      item(
        'item-espresso',
        'cat-hot',
        'Espresso',
        350,
        0,
        description: 'Double shot.',
      ),
      item(
        'item-cappuccino',
        'cat-hot',
        'Cappuccino',
        450,
        1,
        description: 'Espresso with steamed milk.',
      ),
      // An inactive item (still listed, badged inactive).
      item(
        'item-pumpkin',
        'cat-hot',
        'Seasonal Pumpkin Latte',
        550,
        2,
        isActive: false,
      ),
      item('item-iced-latte', 'cat-cold', 'Iced Latte', 500, 0),
      // A restaurant-scoped (global) item.
      item(
        'item-croissant',
        'cat-food',
        'Butter Croissant',
        400,
        0,
        global: true,
      ),
    ],
    sizes: [
      size('size-cap-s', 'item-cappuccino', 'Small', 0, 0),
      size('size-cap-l', 'item-cappuccino', 'Large', 150, 1),
    ],
    variants: [
      variant('var-cap-oat', 'item-cappuccino', 'Oat milk', 80, 0),
      variant('var-cap-decaf', 'item-cappuccino', 'Decaf', 0, 1),
    ],
    modifiers: [modifier('mod-cap-extras', 'item-cappuccino', 'Extras', 0)],
    modifierOptions: [
      option('opt-extra-shot', 'mod-cap-extras', 'Extra shot', 120, 0),
      option('opt-caramel', 'mod-cap-extras', 'Caramel syrup', 90, 1),
    ],
  );
}
