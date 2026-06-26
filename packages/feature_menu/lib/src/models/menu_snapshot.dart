import 'item_size.dart';
import 'item_variant.dart';
import 'menu_category.dart';
import 'menu_item.dart';
import 'modifier.dart';
import 'modifier_option.dart';

/// An immutable read of the full menu tree for one scope (RF-111).
///
/// Lists may include tombstones (`deletedAt != null`) — RF-109 SELECT/sync_pull
/// do not filter them (D-020). Query helpers return non-deleted rows ordered by
/// `displayOrder` then `name`; pass `includeDeleted: true` for an archive view.
class MenuSnapshot {
  const MenuSnapshot({
    this.categories = const [],
    this.items = const [],
    this.sizes = const [],
    this.variants = const [],
    this.modifiers = const [],
    this.modifierOptions = const [],
  });

  final List<MenuCategory> categories;
  final List<MenuItem> items;
  final List<ItemSize> sizes;
  final List<ItemVariant> variants;
  final List<Modifier> modifiers;
  final List<ModifierOption> modifierOptions;

  bool get isEmpty =>
      categories.where((c) => !c.isDeleted).isEmpty &&
      items.where((i) => !i.isDeleted).isEmpty;

  List<MenuCategory> visibleCategories({bool includeDeleted = false}) {
    final rows = categories
        .where((c) => includeDeleted || !c.isDeleted)
        .toList();
    rows.sort(_byOrderThenName((c) => c.displayOrder, (c) => c.name));
    return rows;
  }

  List<MenuItem> itemsForCategory(
    String categoryId, {
    bool includeDeleted = false,
  }) {
    final rows = items
        .where(
          (i) =>
              i.menuCategoryId == categoryId &&
              (includeDeleted || !i.isDeleted),
        )
        .toList();
    rows.sort(_byOrderThenName((i) => i.displayOrder, (i) => i.name));
    return rows;
  }

  List<ItemSize> sizesForItem(String itemId, {bool includeDeleted = false}) {
    final rows = sizes
        .where(
          (s) => s.menuItemId == itemId && (includeDeleted || !s.isDeleted),
        )
        .toList();
    rows.sort(_byOrderThenName((s) => s.displayOrder, (s) => s.name));
    return rows;
  }

  List<ItemVariant> variantsForItem(
    String itemId, {
    bool includeDeleted = false,
  }) {
    final rows = variants
        .where(
          (v) => v.menuItemId == itemId && (includeDeleted || !v.isDeleted),
        )
        .toList();
    rows.sort(_byOrderThenName((v) => v.displayOrder, (v) => v.name));
    return rows;
  }

  List<Modifier> modifiersForItem(
    String itemId, {
    bool includeDeleted = false,
  }) {
    final rows = modifiers
        .where(
          (m) => m.menuItemId == itemId && (includeDeleted || !m.isDeleted),
        )
        .toList();
    rows.sort(_byOrderThenName((m) => m.displayOrder, (m) => m.name));
    return rows;
  }

  List<ModifierOption> optionsForModifier(
    String modifierId, {
    bool includeDeleted = false,
  }) {
    final rows = modifierOptions
        .where(
          (o) => o.modifierId == modifierId && (includeDeleted || !o.isDeleted),
        )
        .toList();
    rows.sort(_byOrderThenName((o) => o.displayOrder, (o) => o.name));
    return rows;
  }
}

int Function(T, T) _byOrderThenName<T>(
  int Function(T) order,
  String Function(T) name,
) {
  return (a, b) {
    final byOrder = order(a).compareTo(order(b));
    if (byOrder != 0) return byOrder;
    return name(a).toLowerCase().compareTo(name(b).toLowerCase());
  };
}
