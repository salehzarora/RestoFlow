import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('buildDemoMenuStore(scope:)', () {
    test('default scope is the demo scope', () async {
      final store = buildDemoMenuStore();
      final snapshot = await store.load(demoMenuScope);
      final item = snapshot.itemsForCategory('cat-hot').first;
      expect(item.organizationId, demoOrganizationId);
      expect(item.restaurantId, demoRestaurantId);
      expect(item.branchId, demoBranchId);
    });

    test(
      'seeds rows at a supplied scope (so RF-110 image paths use it)',
      () async {
        const scope = MenuScope(
          organizationId: 'org-9',
          restaurantId: 'rest-9',
          branchId: 'branch-9',
          currencyCode: 'EUR',
        );
        final store = buildDemoMenuStore(scope: scope);
        final snapshot = await store.load(scope);

        final item = snapshot.itemsForCategory('cat-hot').first;
        expect(item.organizationId, 'org-9');
        expect(item.restaurantId, 'rest-9');
        expect(item.branchId, 'branch-9');
        expect(item.currencyCode, 'EUR');

        // The RF-110 object key the image panel previews therefore carries the
        // real scope, not the demo scope.
        final key = buildMenuImageObjectKey(
          organizationId: item.organizationId,
          restaurantId: item.restaurantId,
          branchId: item.branchId,
          menuItemId: item.id,
          imageId: 'img-1',
          extension: 'png',
        );
        expect(key, startsWith('org-9/rest-9/branch-9/menu_item/'));
      },
    );

    test(
      'a restaurant-scoped (branch-null) scope keeps branch-specific rows null',
      () async {
        const scope = MenuScope(
          organizationId: 'org-9',
          restaurantId: 'rest-9',
          branchId: null,
          currencyCode: 'USD',
        );
        final store = buildDemoMenuStore(scope: scope);
        final snapshot = await store.load(scope);
        final item = snapshot.itemsForCategory('cat-hot').first;
        expect(item.branchId, isNull);
      },
    );
  });
}
