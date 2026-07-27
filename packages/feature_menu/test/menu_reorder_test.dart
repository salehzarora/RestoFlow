import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_feature_menu/testing.dart' show menuReorderedIds;

/// MENU-ORDER-001: the drag-reorder index math + the in-memory store's reorder.

const _scope = MenuScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: null,
  currencyCode: 'USD',
);

MenuCategory _cat(String id, int order) => MenuCategory(
  id: id,
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: null,
  name: id,
  displayOrder: order,
  isActive: true,
);

ModifierOption _opt(String id, int order) => ModifierOption(
  id: id,
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: null,
  modifierId: 'mod-1',
  name: id,
  priceDeltaMinor: 0,
  displayOrder: order,
  isActive: true,
);

void main() {
  group('menuReorderedIds (classic onReorder semantics)', () {
    final ids = ['a', 'b', 'c', 'd'];

    test('moving an item DOWN adjusts newIndex (drop after the target)', () {
      // Drag 'a' (0) to land after 'c': ReorderableListView reports newIndex=3.
      expect(menuReorderedIds(ids, 0, 3), ['b', 'c', 'a', 'd']);
    });

    test('moving an item UP inserts before the target (no adjust)', () {
      // Drag 'd' (3) to the top: newIndex=0.
      expect(menuReorderedIds(ids, 3, 0), ['d', 'a', 'b', 'c']);
    });

    test('a no-op drag returns the same order', () {
      expect(menuReorderedIds(ids, 1, 2), ['a', 'b', 'c', 'd']);
    });

    test('is bounds-safe against a stale/out-of-range index', () {
      expect(menuReorderedIds(ids, 9, 0), ['a', 'b', 'c', 'd']);
      expect(menuReorderedIds(ids, 0, 99), ['b', 'c', 'd', 'a']);
    });

    test('does not mutate the input list', () {
      final input = ['a', 'b', 'c'];
      menuReorderedIds(input, 0, 2);
      expect(input, ['a', 'b', 'c']);
    });
  });

  group('InMemoryMenuStore.reorder', () {
    test('rewrites display_order to 1..N in the given order', () async {
      final store = InMemoryMenuStore(
        categories: [_cat('c1', 0), _cat('c2', 0), _cat('c3', 0)],
      );
      final outcome = await store.reorder(
        organizationId: 'org-1',
        entity: MenuEntityType.category,
        orderedIds: const ['c3', 'c1', 'c2'],
      );
      expect(outcome.fold((v) => v.action, (_) => null), isNotNull);

      final snapshot = await store.load(_scope);
      // visibleCategories sorts by (displayOrder, name); the new order wins.
      expect(snapshot.visibleCategories().map((c) => c.id).toList(), [
        'c3',
        'c1',
        'c2',
      ]);
      expect(
        {for (final c in snapshot.visibleCategories()) c.id: c.displayOrder},
        {'c3': 1, 'c1': 2, 'c2': 3},
      );
    });

    test('reorders modifier options too', () async {
      final store = InMemoryMenuStore(
        modifierOptions: [_opt('o1', 0), _opt('o2', 0), _opt('o3', 0)],
      );
      await store.reorder(
        organizationId: 'org-1',
        entity: MenuEntityType.modifierOption,
        orderedIds: const ['o2', 'o3', 'o1'],
      );
      final snapshot = await store.load(_scope);
      expect(snapshot.optionsForModifier('mod-1').map((o) => o.id).toList(), [
        'o2',
        'o3',
        'o1',
      ]);
    });

    test(
      'a read-only store denies reorder (server role-deny parity)',
      () async {
        final store = InMemoryMenuStore(
          categories: [_cat('c1', 1), _cat('c2', 2)],
          readOnly: true,
        );
        final outcome = await store.reorder(
          organizationId: 'org-1',
          entity: MenuEntityType.category,
          orderedIds: const ['c2', 'c1'],
        );
        expect(
          outcome.fold((_) => null, (f) => f),
          isA<MenuPermissionDenied>(),
        );
      },
    );

    test('empty ids are rejected', () async {
      final store = InMemoryMenuStore(categories: [_cat('c1', 1)]);
      final outcome = await store.reorder(
        organizationId: 'org-1',
        entity: MenuEntityType.category,
        orderedIds: const [],
      );
      expect(
        outcome.fold((_) => null, (f) => f),
        isA<MenuValidationRejected>(),
      );
    });
  });
}
