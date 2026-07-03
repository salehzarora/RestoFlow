import 'package:restoflow_core/restoflow_core.dart';

import '../models/item_size.dart';
import '../models/item_variant.dart';
import '../models/menu_category.dart';
import '../models/menu_entity_type.dart';
import '../models/menu_item.dart';
import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../models/menu_write_failure.dart';
import '../models/menu_write_result.dart';
import '../models/modifier.dart';
import '../models/modifier_option.dart';
import 'menu_image_path.dart';
import 'menu_read_source.dart';
import 'menu_writer.dart';

/// An in-memory [MenuReadSource] + [MenuWriter] backing the demo experience and
/// happy-path widget tests (RF-111). It is NOT a production backend: there is no
/// network, no auth, and no real persistence — it exists so the owner menu UI is
/// fully interactive and testable while the real backend wiring is deferred
/// (D1/D3). Set [readOnly] to simulate a member who lacks the write role
/// (returns [MenuPermissionDenied], mirroring the server's `{ok:false}` envelope).
class InMemoryMenuStore implements MenuReadSource, MenuWriter {
  InMemoryMenuStore({
    List<MenuCategory> categories = const [],
    List<MenuItem> items = const [],
    List<ItemSize> sizes = const [],
    List<ItemVariant> variants = const [],
    List<Modifier> modifiers = const [],
    List<ModifierOption> modifierOptions = const [],
    this.readOnly = false,
    String Function()? newId,
  }) : _categories = List.of(categories),
       _items = List.of(items),
       _sizes = List.of(sizes),
       _variants = List.of(variants),
       _modifiers = List.of(modifiers),
       _options = List.of(modifierOptions),
       _newId = newId ?? RandomImageIdGenerator().newImageId;

  final List<MenuCategory> _categories;
  final List<MenuItem> _items;
  final List<ItemSize> _sizes;
  final List<ItemVariant> _variants;
  final List<Modifier> _modifiers;
  final List<ModifierOption> _options;
  final bool readOnly;
  final String Function() _newId;

  bool _inScope(
    MenuScope scope,
    String organizationId,
    String restaurantId,
    String? branchId,
  ) {
    return organizationId == scope.organizationId &&
        restaurantId == scope.restaurantId &&
        (branchId == null || branchId == scope.branchId);
  }

  @override
  Future<MenuSnapshot> load(MenuScope scope) async {
    return MenuSnapshot(
      categories: _categories
          .where(
            (c) =>
                _inScope(scope, c.organizationId, c.restaurantId, c.branchId),
          )
          .toList(),
      items: _items
          .where(
            (i) =>
                _inScope(scope, i.organizationId, i.restaurantId, i.branchId),
          )
          .toList(),
      sizes: _sizes
          .where(
            (s) =>
                _inScope(scope, s.organizationId, s.restaurantId, s.branchId),
          )
          .toList(),
      variants: _variants
          .where(
            (v) =>
                _inScope(scope, v.organizationId, v.restaurantId, v.branchId),
          )
          .toList(),
      modifiers: _modifiers
          .where(
            (m) =>
                _inScope(scope, m.organizationId, m.restaurantId, m.branchId),
          )
          .toList(),
      modifierOptions: _options
          .where(
            (o) =>
                _inScope(scope, o.organizationId, o.restaurantId, o.branchId),
          )
          .toList(),
    );
  }

  Failure<MenuWriteResult, MenuWriteFailure> _denied(MenuEntityType entity) =>
      Failure(MenuPermissionDenied(entity));

  Success<MenuWriteResult, MenuWriteFailure> _ok(
    MenuEntityType entity,
    String id,
    bool created,
  ) => Success(
    MenuWriteResult(
      entity: entity,
      id: id,
      action: created ? MenuWriteAction.created : MenuWriteAction.updated,
    ),
  );

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    if (readOnly) return _denied(MenuEntityType.category);
    final created = id == null;
    final rowId = id ?? _newId();
    final existing = _findById(_categories, rowId, (c) => c.id);
    final row = MenuCategory(
      id: rowId,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
      deletedAt: existing?.deletedAt,
    );
    _upsert(_categories, row, (c) => c.id);
    return _ok(MenuEntityType.category, rowId, created);
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
    int displayOrder = 0,
    bool isActive = true,
    String? imagePath,
    String? itemType,
    List<String> tags = const [],
    int? prepMinutes,
    String? sku,
    String? kitchenNote,
    Map<String, dynamic> attributes = const {},
  }) async {
    if (readOnly) return _denied(MenuEntityType.item);
    final created = id == null;
    final rowId = id ?? _newId();
    final existing = _findById(_items, rowId, (i) => i.id);
    final row = MenuItem(
      id: rowId,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      menuCategoryId: menuCategoryId,
      name: name,
      description: description,
      basePriceMinor: basePriceMinor,
      currencyCode: currencyCode,
      defaultStationId: defaultStationId,
      displayOrder: displayOrder,
      isActive: isActive,
      // Mirrors the server: null/blank = clear (full-state upsert).
      imagePath: (imagePath == null || imagePath.trim().isEmpty)
          ? null
          : imagePath,
      itemType: itemType,
      tags: List.unmodifiable(tags),
      prepMinutes: prepMinutes,
      // Mirrors the server normalization: blank text = unset.
      sku: (sku == null || sku.trim().isEmpty) ? null : sku.trim(),
      kitchenNote: (kitchenNote == null || kitchenNote.trim().isEmpty)
          ? null
          : kitchenNote.trim(),
      attributes: Map.unmodifiable(attributes),
      deletedAt: existing?.deletedAt,
    );
    _upsert(_items, row, (i) => i.id);
    return _ok(MenuEntityType.item, rowId, created);
  }

  @override
  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    if (readOnly) return _denied(MenuEntityType.size);
    final created = id == null;
    final rowId = id ?? _newId();
    final existing = _findById(_sizes, rowId, (s) => s.id);
    final row = ItemSize(
      id: rowId,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      menuItemId: menuItemId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
      deletedAt: existing?.deletedAt,
    );
    _upsert(_sizes, row, (s) => s.id);
    return _ok(MenuEntityType.size, rowId, created);
  }

  @override
  Future<MenuWriteOutcome> upsertVariant({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    if (readOnly) return _denied(MenuEntityType.variant);
    final created = id == null;
    final rowId = id ?? _newId();
    final existing = _findById(_variants, rowId, (v) => v.id);
    final row = ItemVariant(
      id: rowId,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      menuItemId: menuItemId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
      deletedAt: existing?.deletedAt,
    );
    _upsert(_variants, row, (v) => v.id);
    return _ok(MenuEntityType.variant, rowId, created);
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
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    if (readOnly) return _denied(MenuEntityType.modifier);
    final created = id == null;
    final rowId = id ?? _newId();
    final existing = _findById(_modifiers, rowId, (m) => m.id);
    final row = Modifier(
      id: rowId,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      menuItemId: menuItemId,
      name: name,
      selectionType: selectionType,
      minSelect: minSelect,
      maxSelect: maxSelect,
      isRequired: isRequired,
      displayOrder: displayOrder,
      isActive: isActive,
      deletedAt: existing?.deletedAt,
    );
    _upsert(_modifiers, row, (m) => m.id);
    return _ok(MenuEntityType.modifier, rowId, created);
  }

  @override
  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    if (readOnly) return _denied(MenuEntityType.modifierOption);
    final created = id == null;
    final rowId = id ?? _newId();
    final existing = _findById(_options, rowId, (o) => o.id);
    final row = ModifierOption(
      id: rowId,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      modifierId: modifierId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
      deletedAt: existing?.deletedAt,
    );
    _upsert(_options, row, (o) => o.id);
    return _ok(MenuEntityType.modifierOption, rowId, created);
  }

  @override
  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  }) async {
    if (readOnly) return _denied(entity);
    final now = DateTime.now();
    final deleted = switch (entity) {
      MenuEntityType.category => _tombstone(
        _categories,
        id,
        (c) => c.id,
        (c) => c.copyWith(deletedAt: now),
      ),
      MenuEntityType.item => _tombstone(
        _items,
        id,
        (i) => i.id,
        (i) => i.copyWith(deletedAt: now),
      ),
      MenuEntityType.size => _tombstone(
        _sizes,
        id,
        (s) => s.id,
        (s) => s.copyWith(deletedAt: now),
      ),
      MenuEntityType.variant => _tombstone(
        _variants,
        id,
        (v) => v.id,
        (v) => v.copyWith(deletedAt: now),
      ),
      MenuEntityType.modifier => _tombstone(
        _modifiers,
        id,
        (m) => m.id,
        (m) => m.copyWith(deletedAt: now),
      ),
      MenuEntityType.modifierOption => _tombstone(
        _options,
        id,
        (o) => o.id,
        (o) => o.copyWith(deletedAt: now),
      ),
    };
    if (!deleted) {
      return const Failure(MenuValidationRejected('row not found'));
    }
    return Success(
      MenuWriteResult(
        entity: entity,
        id: id,
        action: MenuWriteAction.softDeleted,
      ),
    );
  }

  static T? _findById<T>(List<T> rows, String id, String Function(T) idOf) {
    for (final row in rows) {
      if (idOf(row) == id) return row;
    }
    return null;
  }

  static void _upsert<T>(List<T> rows, T row, String Function(T) idOf) {
    final id = idOf(row);
    final index = rows.indexWhere((r) => idOf(r) == id);
    if (index >= 0) {
      rows[index] = row;
    } else {
      rows.add(row);
    }
  }

  static bool _tombstone<T>(
    List<T> rows,
    String id,
    String Function(T) idOf,
    T Function(T) tombstone,
  ) {
    final index = rows.indexWhere((r) => idOf(r) == id);
    if (index < 0) return false;
    rows[index] = tombstone(rows[index]);
    return true;
  }
}
