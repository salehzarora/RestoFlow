import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('InMemoryMenuStore (demo seed)', () {
    test('loads categories incl. the restaurant-scoped/global one', () async {
      final store = buildDemoMenuStore();
      final snapshot = await store.load(demoMenuScope);
      final categories = snapshot.visibleCategories();
      expect(
        categories.map((c) => c.name),
        containsAll(['Hot Drinks', 'Cold Drinks', 'Food']),
      );
      // The global (branch-null) category is visible in a branch scope.
      expect(
        categories.any((c) => c.branchId == null && c.name == 'Food'),
        isTrue,
      );
    });

    test('items list keeps inactive rows (badged, not filtered)', () async {
      final store = buildDemoMenuStore();
      final snapshot = await store.load(demoMenuScope);
      final hot = snapshot.itemsForCategory('cat-hot');
      expect(hot.map((i) => i.name), contains('Seasonal Pumpkin Latte'));
      expect(hot.firstWhere((i) => i.id == 'item-pumpkin').isActive, isFalse);
    });

    test('create category is reflected on reload', () async {
      final store = buildDemoMenuStore();
      final outcome = await store.upsertCategory(
        scope: demoMenuScope,
        name: 'Desserts',
        displayOrder: 9,
      );
      expect(
        outcome.fold((v) => v.action, (_) => null),
        MenuWriteAction.created,
      );

      final snapshot = await store.load(demoMenuScope);
      expect(
        snapshot.visibleCategories().any((c) => c.name == 'Desserts'),
        isTrue,
      );
    });

    test('update item (existing id) replaces fields', () async {
      final store = buildDemoMenuStore();
      final outcome = await store.upsertItem(
        scope: demoMenuScope,
        id: 'item-cappuccino',
        menuCategoryId: 'cat-hot',
        name: 'Flat White',
        basePriceMinor: 475,
        currencyCode: 'USD',
      );
      expect(
        outcome.fold((v) => v.action, (_) => null),
        MenuWriteAction.updated,
      );

      final snapshot = await store.load(demoMenuScope);
      final updated = snapshot
          .itemsForCategory('cat-hot')
          .firstWhere((i) => i.id == 'item-cappuccino');
      expect(updated.name, 'Flat White');
      expect(updated.basePriceMinor, 475);
    });

    test(
      'soft-delete tombstones the row (hidden by default, visible with includeDeleted)',
      () async {
        final store = buildDemoMenuStore();
        final outcome = await store.softDelete(
          organizationId: demoOrganizationId,
          entity: MenuEntityType.item,
          id: 'item-espresso',
        );
        expect(
          outcome.fold((v) => v.action, (_) => null),
          MenuWriteAction.softDeleted,
        );

        final snapshot = await store.load(demoMenuScope);
        expect(
          snapshot
              .itemsForCategory('cat-hot')
              .any((i) => i.id == 'item-espresso'),
          isFalse,
        );
        expect(
          snapshot
              .itemsForCategory('cat-hot', includeDeleted: true)
              .any((i) => i.id == 'item-espresso'),
          isTrue,
        );
      },
    );

    test(
      'readOnly store denies writes (mirrors {ok:false, permission_denied})',
      () async {
        final store = buildDemoMenuStore(readOnly: true);
        final outcome = await store.upsertCategory(
          scope: demoMenuScope,
          name: 'Nope',
        );
        expect(
          outcome.fold((_) => null, (f) => f),
          isA<MenuPermissionDenied>(),
        );
      },
    );
  });
}
