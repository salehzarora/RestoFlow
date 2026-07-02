import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_menu.dart';

/// Sentinel category id meaning "show every item".
const String kAllCategoriesId = 'all';

/// The currently selected menu category id (defaults to all). UI-only demo
/// state — no backend, no persistence.
final selectedCategoryProvider = StateProvider<String>(
  (ref) => kAllCategoriesId,
);

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
