import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_menu.dart';

/// Sentinel category id meaning "show every item".
const String kAllCategoriesId = 'all';

/// The currently selected menu category id (defaults to all). UI-only demo
/// state — no backend, no persistence.
final selectedCategoryProvider = StateProvider<String>(
  (ref) => kAllCategoriesId,
);

/// The live menu search query (DESIGN-004). A lightweight, client-side filter
/// over the ALREADY-LOADED menu items — no backend call, no repository, no
/// schema. Empty = no search filter. UI-only state.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// [items] filtered by [categoryId]; [kAllCategoriesId] returns all items.
/// Pure over the ACTIVE menu (demo consts or the real backend menu).
List<DemoMenuItem> menuItemsForCategory(
  List<DemoMenuItem> items,
  String categoryId,
) {
  if (categoryId == kAllCategoriesId) return items;
  return items
      .where((item) => item.categoryId == categoryId)
      .toList(growable: false);
}

/// [items] filtered by BOTH the selected [categoryId] and the search [query]
/// (case-insensitive substring over the item's displayed name — the name in
/// whatever language the active menu supplies). Pure; presentation-only.
List<DemoMenuItem> filterMenuItems(
  List<DemoMenuItem> items,
  String categoryId,
  String query,
) {
  final byCategory = menuItemsForCategory(items, categoryId);
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return byCategory;
  return byCategory
      .where((item) => item.name.toLowerCase().contains(q))
      .toList(growable: false);
}
