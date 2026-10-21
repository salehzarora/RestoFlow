import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show MenuReadSource, MenuScope, MenuCategory;

import 'storefront_models.dart';

/// Presentation choices only: no private image key, price or publication write.
class StorefrontFeaturedOption {
  const StorefrontFeaturedOption({
    required this.id,
    required this.name,
    required this.categoryName,
  });

  final String id;
  final String name;
  final String categoryName;
}

abstract interface class StorefrontFeaturedCatalog {
  /// The SAVED profile branch, never a membership-derived/global substitute.
  /// Null means unavailable; empty means an authoritative empty eligible menu.
  Future<List<StorefrontFeaturedOption>?> load(String storefrontBranchId);
}

class DashboardStorefrontFeaturedCatalog implements StorefrontFeaturedCatalog {
  const DashboardStorefrontFeaturedCatalog({
    required this.menuReadSource,
    required this.organizationId,
    required this.restaurantId,
    required this.currencyCode,
  });

  final MenuReadSource? menuReadSource;
  final String organizationId;
  final String restaurantId;
  final String currencyCode;

  @override
  Future<List<StorefrontFeaturedOption>?> load(
    String storefrontBranchId,
  ) async {
    final source = menuReadSource;
    if (source == null ||
        storefrontBranchId.length != 36 ||
        !isCanonicalUuid(storefrontBranchId.toLowerCase())) {
      return null;
    }
    bool same(String a, String b) => a.toLowerCase() == b.toLowerCase();
    bool visible(String org, String restaurant, String? branch) =>
        same(org, organizationId) &&
        same(restaurant, restaurantId) &&
        (branch == null || same(branch, storefrontBranchId));
    try {
      final snapshot = await source.load(
        MenuScope(
          organizationId: organizationId,
          restaurantId: restaurantId,
          branchId: storefrontBranchId,
          currencyCode: currencyCode,
        ),
      );
      final categories = <String, MenuCategory>{};
      for (final category in snapshot.categories) {
        if (category.isDeleted ||
            !category.isActive ||
            !visible(
              category.organizationId,
              category.restaurantId,
              category.branchId,
            ))
          continue;
        final id = category.id.toLowerCase();
        if (id.length != 36 ||
            !isCanonicalUuid(id) ||
            categories.containsKey(id))
          return null;
        categories[id] = category;
      }
      final seen = <String>{};
      final eligible = snapshot.items.where((item) {
        final category = categories[item.menuCategoryId.toLowerCase()];
        return !item.isDeleted &&
            item.isActive &&
            visible(item.organizationId, item.restaurantId, item.branchId) &&
            category != null;
      }).toList();
      for (final item in eligible) {
        if (item.id.length != 36 ||
            !isCanonicalUuid(item.id.toLowerCase()) ||
            !seen.add(item.id.toLowerCase())) {
          return null;
        }
      }
      eligible.sort((a, b) {
        final ac = categories[a.menuCategoryId.toLowerCase()]!;
        final bc = categories[b.menuCategoryId.toLowerCase()]!;
        var order = ac.displayOrder.compareTo(bc.displayOrder);
        if (order == 0) order = ac.name.compareTo(bc.name);
        if (order == 0) order = a.displayOrder.compareTo(b.displayOrder);
        if (order == 0) order = a.name.compareTo(b.name);
        if (order == 0) order = a.id.compareTo(b.id);
        return order;
      });
      return List.unmodifiable([
        for (final item in eligible)
          StorefrontFeaturedOption(
            id: item.id.toLowerCase(),
            name: item.name,
            categoryName: categories[item.menuCategoryId.toLowerCase()]!.name,
          ),
      ]);
    } catch (_) {
      // A failed management read never becomes an invented/demo selection.
      return null;
    }
  }
}
