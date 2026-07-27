import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_feature_menu/testing.dart';

/// MENU-ORDER-001 (Codex, 4th pass — SAME-SCOPE WRITES ARE NOT GUARDED INSIDE THE
/// WRITE HANDLERS): the reorder-in-flight latch must be enforced at the CONTROLLER
/// boundary, before any repository/RPC call — not only by widget IgnorePointer /
/// onPressed:null. These tests invoke the REAL MenuWriteController methods directly
/// (the exact seam a stale dialog callback, keyboard action, or future control
/// reaches) with a spy MenuWriter, and prove:
///   * every user mutation of a sibling list issues ZERO repo/RPC calls while THAT
///     exact list is mid-reorder, returning a MenuReorderInProgress failure;
///   * unrelated scopes (another category's items, another group's options, another
///     branch) stay writable;
///   * the SAME write succeeds after the latch releases (post-reconcile);
///   * reorderScoped itself is never blocked by the guard (it owns the latch).

/// A [MenuWriter] that RECORDS every write it receives (so a blocked write is
/// provably zero repo/RPC calls) and returns a fixed success otherwise.
class _SpyMenuWriter extends ScriptedMenuWriter {
  _SpyMenuWriter()
    : super(
        const Success(
          MenuWriteResult(
            entity: MenuEntityType.category,
            id: 'x',
            action: MenuWriteAction.updated,
          ),
        ),
      );

  final List<String> ops = <String>[];
  int get count => ops.length;

  // The display_order carried by the LAST upsert of each kind (Codex #6: a normal
  // edit must send null so it never re-asserts a stale, pre-reorder order).
  int? lastCategoryDisplayOrder;
  int? lastItemDisplayOrder;
  int? lastModifierDisplayOrder;
  int? lastOptionDisplayOrder;
  MenuEntityType? lastSoftDeleteEntity;

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int? displayOrder,
    bool isActive = true,
  }) {
    ops.add('upsertCategory');
    lastCategoryDisplayOrder = displayOrder;
    return super.upsertCategory(
      scope: scope,
      id: id,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }

  @override
  Future<MenuWriteOutcome> upsertItem({
    required MenuScope scope,
    String? id,
    required String menuCategoryId,
    required String name,
    String? description,
    required int basePriceMinor,
    required String currencyCode,
    String? defaultStationId,
    int? displayOrder,
    bool isActive = true,
    String? imagePath,
    String? itemType,
    List<String> tags = const [],
    int? prepMinutes,
    String? sku,
    String? kitchenNote,
    Map<String, dynamic> attributes = const {},
  }) {
    ops.add('upsertItem');
    lastItemDisplayOrder = displayOrder;
    return super.upsertItem(
      scope: scope,
      id: id,
      menuCategoryId: menuCategoryId,
      name: name,
      basePriceMinor: basePriceMinor,
      currencyCode: currencyCode,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }

  @override
  Future<MenuWriteOutcome> upsertModifier({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    String selectionType = 'single',
    int minSelect = 0,
    int? maxSelect,
    bool isRequired = false,
    int? displayOrder,
    bool isActive = true,
    bool allowQuantity = false,
    int? maxQuantity,
  }) {
    ops.add('upsertModifier');
    lastModifierDisplayOrder = displayOrder;
    return super.upsertModifier(
      scope: scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }

  @override
  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int? displayOrder,
    bool isActive = true,
    Map<String, dynamic>? kitchenMeat,
  }) {
    ops.add('upsertModifierOption');
    lastOptionDisplayOrder = displayOrder;
    return super.upsertModifierOption(
      scope: scope,
      id: id,
      modifierId: modifierId,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }

  @override
  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int? displayOrder,
    bool isActive = true,
  }) {
    ops.add('upsertSize');
    return super.upsertSize(
      scope: scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }

  @override
  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  }) {
    ops.add('softDelete');
    lastSoftDeleteEntity = entity;
    return super.softDelete(
      organizationId: organizationId,
      entity: entity,
      id: id,
    );
  }

  @override
  Future<MenuWriteOutcome> setItemAvailability({
    required MenuScope scope,
    required String menuItemId,
    required String availability,
    String? reason,
  }) {
    ops.add('setItemAvailability');
    return super.setItemAvailability(
      scope: scope,
      menuItemId: menuItemId,
      availability: availability,
      reason: reason,
    );
  }
}

// The four reorder scopes exercised, all under the demo org/restaurant/branch.
MenuReorderScope _scope(MenuEntityType entity, String parentId) =>
    MenuReorderScope(
      organizationId: demoMenuScope.organizationId,
      restaurantId: demoMenuScope.restaurantId,
      branchId: demoMenuScope.branchId,
      entity: entity,
      parentId: parentId,
    );

final _categoryScope = _scope(
  MenuEntityType.category,
  demoMenuScope.restaurantId,
);
final _itemsOfCat1 = _scope(MenuEntityType.item, 'cat-1');
final _groupsOfItem1 = _scope(MenuEntityType.modifier, 'item-1');
final _optionsOfMod1 = _scope(MenuEntityType.modifierOption, 'mod-1');

/// A container wired to the spy writer; a real (unused) demo read source satisfies
/// the seam. Returns the container + controller + spy.
({
  ProviderContainer container,
  MenuWriteController controller,
  _SpyMenuWriter spy,
})
_wire() {
  final spy = _SpyMenuWriter();
  final container = ProviderContainer(
    overrides: menuFeatureOverrides(
      scope: demoMenuScope,
      readSource: buildDemoMenuStore(),
      writer: spy,
    ),
  );
  return (
    container: container,
    controller: container.read(menuWriteControllerProvider),
    spy: spy,
  );
}

void _setReordering(ProviderContainer c, MenuReorderScope scope, bool value) =>
    c.read(menuReorderInFlightProvider(scope).notifier).state = value;

void _expectBlocked(MenuWriteOutcome outcome) => outcome.fold(
  (_) => fail('expected the write to be REFUSED by the same-scope guard'),
  (failure) => expect(
    failure,
    isA<MenuReorderInProgress>(),
    reason:
        'a same-scope reorder-in-flight write must fail with '
        'MenuReorderInProgress (refused locally, zero repo/RPC calls)',
  ),
);

void main() {
  group('canWriteMenuScope reflects the exact per-scope latch', () {
    test('true when idle, false when THAT scope is reordering, true again '
        'after release; unrelated scopes stay writable', () {
      final w = _wire();
      addTearDown(w.container.dispose);
      expect(w.controller.canWriteMenuScope(_categoryScope), isTrue);

      _setReordering(w.container, _categoryScope, true);
      expect(w.controller.canWriteMenuScope(_categoryScope), isFalse);
      // A different list (items of cat-1) is unaffected.
      expect(w.controller.canWriteMenuScope(_itemsOfCat1), isTrue);

      _setReordering(w.container, _categoryScope, false);
      expect(w.controller.canWriteMenuScope(_categoryScope), isTrue);
    });
  });

  group('every same-scope user write is REFUSED mid-reorder (zero repo/RPC)', () {
    test(
      'CATEGORY: add, edit, active-toggle, and soft-delete are all blocked',
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);
        _setReordering(w.container, _categoryScope, true);

        _expectBlocked(await w.controller.upsertCategory(name: 'New')); // add
        _expectBlocked(
          await w.controller.upsertCategory(id: 'c1', name: 'Renamed'),
        ); // edit
        _expectBlocked(
          await w.controller.upsertCategory(
            id: 'c1',
            name: 'c1',
            isActive: false,
          ),
        ); // active toggle rides upsert
        _expectBlocked(
          await w.controller.softDelete(
            entity: MenuEntityType.category,
            id: 'c1',
            parentId: demoMenuScope.restaurantId,
          ),
        );
        expect(
          w.spy.count,
          0,
          reason: 'not one category write reached the writer',
        );
      },
    );

    test(
      'ITEM: add/edit, active + availability toggle, and soft-delete are blocked',
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);
        _setReordering(w.container, _itemsOfCat1, true);

        _expectBlocked(
          await w.controller.upsertItem(
            menuCategoryId: 'cat-1',
            name: 'New',
            basePriceMinor: 500,
            currencyCode: 'ILS',
          ),
        );
        _expectBlocked(
          await w.controller.upsertItem(
            id: 'item-1',
            menuCategoryId: 'cat-1',
            name: 'Renamed',
            basePriceMinor: 900,
            currencyCode: 'ILS',
          ),
        );
        _expectBlocked(
          await w.controller.softDelete(
            entity: MenuEntityType.item,
            id: 'item-1',
            parentId: 'cat-1',
          ),
        );
        _expectBlocked(
          await w.controller.setItemAvailability(
            menuItemId: 'item-1',
            menuCategoryId: 'cat-1',
            availability: 'unavailable',
            reason: 'sold_out',
          ),
        );
        // Active toggle rides the same guarded upsert (isActive:false).
        _expectBlocked(
          await w.controller.upsertItem(
            id: 'item-1',
            menuCategoryId: 'cat-1',
            name: 'item-1',
            basePriceMinor: 500,
            currencyCode: 'ILS',
            isActive: false,
          ),
        );
        expect(w.spy.count, 0, reason: 'not one item write reached the writer');
      },
    );

    test(
      'MODIFIER GROUP: add/edit, active-toggle, and soft-delete are blocked',
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);
        _setReordering(w.container, _groupsOfItem1, true);

        _expectBlocked(
          await w.controller.upsertModifier(
            menuItemId: 'item-1',
            name: 'Extras',
          ),
        );
        _expectBlocked(
          await w.controller.upsertModifier(
            id: 'mod-1',
            menuItemId: 'item-1',
            name: 'Renamed',
          ),
        );
        _expectBlocked(
          await w.controller.softDelete(
            entity: MenuEntityType.modifier,
            id: 'mod-1',
            parentId: 'item-1',
          ),
        );
        // Active toggle rides the same guarded upsert (isActive:false).
        _expectBlocked(
          await w.controller.upsertModifier(
            id: 'mod-1',
            menuItemId: 'item-1',
            name: 'mod-1',
            isActive: false,
          ),
        );
        expect(
          w.spy.count,
          0,
          reason: 'not one group write reached the writer',
        );
      },
    );

    test(
      'MODIFIER OPTION: add/edit, active-toggle, and soft-delete are blocked',
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);
        _setReordering(w.container, _optionsOfMod1, true);

        _expectBlocked(
          await w.controller.upsertModifierOption(
            modifierId: 'mod-1',
            name: 'Extra',
          ),
        );
        _expectBlocked(
          await w.controller.upsertModifierOption(
            id: 'opt-1',
            modifierId: 'mod-1',
            name: 'Renamed',
          ),
        );
        _expectBlocked(
          await w.controller.softDelete(
            entity: MenuEntityType.modifierOption,
            id: 'opt-1',
            parentId: 'mod-1',
          ),
        );
        // Active toggle rides the same guarded upsert (isActive:false).
        _expectBlocked(
          await w.controller.upsertModifierOption(
            id: 'opt-1',
            modifierId: 'mod-1',
            name: 'opt-1',
            isActive: false,
          ),
        );
        expect(
          w.spy.count,
          0,
          reason: 'not one option write reached the writer',
        );
      },
    );
  });

  group('unrelated scopes stay writable while one list reorders', () {
    test(
      "a DIFFERENT category's items are writable while categories reorder",
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);
        _setReordering(w.container, _categoryScope, true);

        final outcome = await w.controller.upsertItem(
          menuCategoryId: 'cat-1',
          name: 'Still writable',
          basePriceMinor: 500,
          currencyCode: 'ILS',
        );
        expect(outcome.isSuccess, isTrue);
        expect(w.spy.ops, ['upsertItem']);
      },
    );

    test(
      "another group's options are writable while a different group's options "
      'reorder',
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);
        _setReordering(w.container, _optionsOfMod1, true);

        final outcome = await w.controller.upsertModifierOption(
          modifierId: 'mod-2', // a DIFFERENT group
          name: 'Free',
        );
        expect(outcome.isSuccess, isTrue);
        expect(w.spy.ops, ['upsertModifierOption']);
      },
    );

    test(
      'another BRANCH is writable while this branch reorders categories',
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);
        // Hold the latch for a DIFFERENT branch's category scope.
        _setReordering(
          w.container,
          MenuReorderScope(
            organizationId: demoMenuScope.organizationId,
            restaurantId: demoMenuScope.restaurantId,
            branchId: 'other-branch',
            entity: MenuEntityType.category,
            parentId: demoMenuScope.restaurantId,
          ),
          true,
        );
        // The active scope's category write is NOT blocked (different branch key).
        final outcome = await w.controller.upsertCategory(name: 'Fine');
        expect(outcome.isSuccess, isTrue);
        expect(w.spy.ops, ['upsertCategory']);
      },
    );
  });

  group('stale-edit-during-reorder: refused mid-flight, persists after release '
      'with an unchanged (null) order', () {
    Future<void> staleEdit({
      required MenuReorderScope scope,
      required Future<MenuWriteOutcome> Function(MenuWriteController c) save,
      required int? Function(_SpyMenuWriter s) sentOrder,
    }) async {
      final w = _wire();
      addTearDown(w.container.dispose);

      // 2) a reorder of the SAME scope begins.
      _setReordering(w.container, scope, true);
      // 3) the (stale) save handler is invoked directly -> 4) zero writes.
      _expectBlocked(await save(w.controller));
      expect(w.spy.count, 0);

      // 5) reorder completes + authoritative refresh -> latch releases.
      _setReordering(w.container, scope, false);
      // 6) the SAME save now persists -> 7) it reached the writer once, and
      // 8) it carried NO display_order (null) so it cannot move the row.
      final outcome = await save(w.controller);
      expect(outcome.isSuccess, isTrue);
      expect(w.spy.count, 1);
      expect(
        sentOrder(w.spy),
        isNull,
        reason:
            'a normal edit sends null display_order (Codex #6) — the '
            'committed drag order is preserved by the DB guard trigger',
      );
    }

    test(
      'category',
      () => staleEdit(
        scope: _categoryScope,
        save: (c) => c.upsertCategory(id: 'c1', name: 'Renamed'),
        sentOrder: (s) => s.lastCategoryDisplayOrder,
      ),
    );
    test(
      'item',
      () => staleEdit(
        scope: _itemsOfCat1,
        save: (c) => c.upsertItem(
          id: 'item-1',
          menuCategoryId: 'cat-1',
          name: 'Renamed',
          basePriceMinor: 900,
          currencyCode: 'ILS',
          displayOrder: null,
        ),
        sentOrder: (s) => s.lastItemDisplayOrder,
      ),
    );
    test(
      'modifier group',
      () => staleEdit(
        scope: _groupsOfItem1,
        save: (c) => c.upsertModifier(
          id: 'mod-1',
          menuItemId: 'item-1',
          name: 'Renamed',
        ),
        sentOrder: (s) => s.lastModifierDisplayOrder,
      ),
    );
    test(
      'modifier option',
      () => staleEdit(
        scope: _optionsOfMod1,
        save: (c) => c.upsertModifierOption(
          id: 'opt-1',
          modifierId: 'mod-1',
          name: 'Renamed',
        ),
        sentOrder: (s) => s.lastOptionDisplayOrder,
      ),
    );
  });

  group('the reorder itself is never blocked by the guard', () {
    test(
      'reorderScoped writes even though it holds its own scope latch',
      () async {
        final w = _wire();
        addTearDown(w.container.dispose);

        final outcome = await w.controller.reorderScoped(
          scope: _categoryScope,
          orderedIds: const ['c2', 'c1'],
        );
        expect(outcome, isNotNull);
        expect(outcome!.isSuccess, isTrue);
        expect(
          w.spy.lastReorderEntity,
          MenuEntityType.category,
          reason:
              'the reorder RPC ran — the guard did not block the reorder itself',
        );
        // And after it completes, the latch is released (a normal write is allowed).
        expect(w.controller.canWriteMenuScope(_categoryScope), isTrue);
      },
    );
  });
}
