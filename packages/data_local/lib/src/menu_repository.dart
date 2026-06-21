import 'package:drift/drift.dart';

import 'local_database.dart';

/// Concrete Drift-backed local menu/catalog repository (RF-030).
///
/// CRUD round-trips through the local [LocalDatabase] for the six menu tables.
/// Deletes are **tombstones**: `tombstone*` sets `deleted_at` (never a hard
/// delete), is idempotent, and the row stays in the DB. All live-only operations
/// — `get*`, `list*`, and `update*` — exclude tombstoned rows (so a tombstoned
/// row can never be edited/resurrected here; `list*` also excludes inactive
/// rows). RF-030 is persistence only — no cart, pricing totals, tax, kitchen
/// routing, or sync-engine behavior.
class MenuRepository {
  MenuRepository(this._db);

  final LocalDatabase _db;

  // ===== menu_categories ====================================================
  Future<void> createCategory(MenuCategoriesCompanion category) =>
      _db.into(_db.menuCategories).insert(category);

  Future<MenuCategory?> getCategory(String id) => (_db.select(
    _db.menuCategories,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<List<MenuCategory>> listCategories({
    required String organizationId,
    required String restaurantId,
  }) =>
      (_db.select(_db.menuCategories)
            ..where(
              (t) =>
                  t.organizationId.equals(organizationId) &
                  t.restaurantId.equals(restaurantId) &
                  t.deletedAt.isNull() &
                  t.isActive.equals(true),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.displayOrder)]))
          .get();

  Future<int> updateCategory(MenuCategoriesCompanion category) =>
      (_db.update(_db.menuCategories)..where(
            (t) => t.id.equals(category.id.value) & t.deletedAt.isNull(),
          ))
          .write(category);

  Future<int> tombstoneCategory(String id, DateTime at) =>
      (_db.update(
        _db.menuCategories,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        MenuCategoriesCompanion(deletedAt: Value(at), updatedAt: Value(at)),
      );

  // ===== menu_items =========================================================
  Future<void> createItem(MenuItemsCompanion item) =>
      _db.into(_db.menuItems).insert(item);

  Future<MenuItem?> getItem(String id) => (_db.select(
    _db.menuItems,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<List<MenuItem>> listItemsByCategory(String menuCategoryId) =>
      (_db.select(_db.menuItems)
            ..where(
              (t) =>
                  t.menuCategoryId.equals(menuCategoryId) &
                  t.deletedAt.isNull() &
                  t.isActive.equals(true),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<int> updateItem(MenuItemsCompanion item) =>
      (_db.update(_db.menuItems)
            ..where((t) => t.id.equals(item.id.value) & t.deletedAt.isNull()))
          .write(item);

  Future<int> tombstoneItem(String id, DateTime at) =>
      (_db.update(
        _db.menuItems,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        MenuItemsCompanion(deletedAt: Value(at), updatedAt: Value(at)),
      );

  // ===== item_sizes =========================================================
  Future<void> createSize(ItemSizesCompanion size) =>
      _db.into(_db.itemSizes).insert(size);

  Future<ItemSize?> getSize(String id) => (_db.select(
    _db.itemSizes,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<List<ItemSize>> listSizesByItem(String menuItemId) =>
      (_db.select(_db.itemSizes)
            ..where(
              (t) =>
                  t.menuItemId.equals(menuItemId) &
                  t.deletedAt.isNull() &
                  t.isActive.equals(true),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.displayOrder)]))
          .get();

  Future<int> updateSize(ItemSizesCompanion size) =>
      (_db.update(_db.itemSizes)
            ..where((t) => t.id.equals(size.id.value) & t.deletedAt.isNull()))
          .write(size);

  Future<int> tombstoneSize(String id, DateTime at) =>
      (_db.update(
        _db.itemSizes,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        ItemSizesCompanion(deletedAt: Value(at), updatedAt: Value(at)),
      );

  // ===== item_variants ======================================================
  Future<void> createVariant(ItemVariantsCompanion variant) =>
      _db.into(_db.itemVariants).insert(variant);

  Future<ItemVariant?> getVariant(String id) => (_db.select(
    _db.itemVariants,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<List<ItemVariant>> listVariantsByItem(String menuItemId) =>
      (_db.select(_db.itemVariants)
            ..where(
              (t) =>
                  t.menuItemId.equals(menuItemId) &
                  t.deletedAt.isNull() &
                  t.isActive.equals(true),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.displayOrder)]))
          .get();

  Future<int> updateVariant(ItemVariantsCompanion variant) =>
      (_db.update(
            _db.itemVariants,
          )..where((t) => t.id.equals(variant.id.value) & t.deletedAt.isNull()))
          .write(variant);

  Future<int> tombstoneVariant(String id, DateTime at) =>
      (_db.update(
        _db.itemVariants,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        ItemVariantsCompanion(deletedAt: Value(at), updatedAt: Value(at)),
      );

  // ===== modifiers ==========================================================
  Future<void> createModifier(ModifiersCompanion modifier) =>
      _db.into(_db.modifiers).insert(modifier);

  Future<Modifier?> getModifier(String id) => (_db.select(
    _db.modifiers,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<List<Modifier>> listModifiersByItem(String menuItemId) =>
      (_db.select(_db.modifiers)
            ..where(
              (t) =>
                  t.menuItemId.equals(menuItemId) &
                  t.deletedAt.isNull() &
                  t.isActive.equals(true),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.displayOrder)]))
          .get();

  Future<int> updateModifier(ModifiersCompanion modifier) =>
      (_db.update(_db.modifiers)..where(
            (t) => t.id.equals(modifier.id.value) & t.deletedAt.isNull(),
          ))
          .write(modifier);

  Future<int> tombstoneModifier(String id, DateTime at) =>
      (_db.update(
        _db.modifiers,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        ModifiersCompanion(deletedAt: Value(at), updatedAt: Value(at)),
      );

  // ===== modifier_options ===================================================
  Future<void> createOption(ModifierOptionsCompanion option) =>
      _db.into(_db.modifierOptions).insert(option);

  Future<ModifierOption?> getOption(String id) => (_db.select(
    _db.modifierOptions,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<List<ModifierOption>> listOptionsByModifier(String modifierId) =>
      (_db.select(_db.modifierOptions)
            ..where(
              (t) =>
                  t.modifierId.equals(modifierId) &
                  t.deletedAt.isNull() &
                  t.isActive.equals(true),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.displayOrder)]))
          .get();

  Future<int> updateOption(ModifierOptionsCompanion option) =>
      (_db.update(_db.modifierOptions)
            ..where((t) => t.id.equals(option.id.value) & t.deletedAt.isNull()))
          .write(option);

  Future<int> tombstoneOption(String id, DateTime at) =>
      (_db.update(
        _db.modifierOptions,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        ModifierOptionsCompanion(deletedAt: Value(at), updatedAt: Value(at)),
      );
}
