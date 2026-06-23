import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_menu.dart';

/// Sentinel category id meaning "show every item".
const String kAllCategoriesId = 'all';

/// The currently selected menu category id (defaults to all). UI-only demo
/// state — no backend, no persistence.
final selectedCategoryProvider = StateProvider<String>(
  (ref) => kAllCategoriesId,
);

/// The demo menu filtered by [categoryId]; [kAllCategoriesId] returns all items.
List<DemoMenuItem> menuItemsForCategory(String categoryId) {
  if (categoryId == kAllCategoriesId) return kDemoMenu;
  return kDemoMenu
      .where((item) => item.categoryId == categoryId)
      .toList(growable: false);
}
