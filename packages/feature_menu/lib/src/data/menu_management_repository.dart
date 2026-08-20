import 'package:restoflow_core/restoflow_core.dart';

import '../models/menu_entity_type.dart';
import '../models/menu_icon_key_write.dart';
import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../models/menu_write_failure.dart';
import '../models/menu_write_result.dart';
import 'menu_read_source.dart';
import 'menu_writer.dart';

/// The owner menu management repository (RF-111): a thin façade over a
/// [MenuReadSource] (load the tree) and a [MenuWriter] (the seven RF-109 write
/// operations). Writes are NON-OPTIMISTIC — the caller reloads via [load] after
/// a successful write rather than mutating local state speculatively.
class MenuManagementRepository implements MenuWriter {
  const MenuManagementRepository({
    required MenuReadSource readSource,
    required MenuWriter writer,
  }) : _readSource = readSource,
       _writer = writer;

  final MenuReadSource _readSource;
  final MenuWriter _writer;

  Future<MenuSnapshot> load(MenuScope scope) => _readSource.load(scope);

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int? displayOrder,
    bool isActive = true,
    MenuIconKeyWrite iconKey = const MenuIconKeyWrite.preserve(),
  }) => _writer.upsertCategory(
    scope: scope,
    id: id,
    name: name,
    displayOrder: displayOrder,
    isActive: isActive,
    iconKey: iconKey,
  );

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
  }) => _writer.upsertItem(
    scope: scope,
    id: id,
    menuCategoryId: menuCategoryId,
    name: name,
    description: description,
    basePriceMinor: basePriceMinor,
    currencyCode: currencyCode,
    defaultStationId: defaultStationId,
    displayOrder: displayOrder,
    isActive: isActive,
    imagePath: imagePath,
    itemType: itemType,
    tags: tags,
    prepMinutes: prepMinutes,
    sku: sku,
    kitchenNote: kitchenNote,
    attributes: attributes,
  );

  @override
  Future<MenuWriteOutcome> setItemAvailability({
    required MenuScope scope,
    required String menuItemId,
    required String availability,
    String? reason,
  }) => _writer.setItemAvailability(
    scope: scope,
    menuItemId: menuItemId,
    availability: availability,
    reason: reason,
  );

  @override
  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int? displayOrder,
    bool isActive = true,
  }) => _writer.upsertSize(
    scope: scope,
    id: id,
    menuItemId: menuItemId,
    name: name,
    priceDeltaMinor: priceDeltaMinor,
    displayOrder: displayOrder,
    isActive: isActive,
  );

  @override
  Future<MenuWriteOutcome> upsertVariant({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int? displayOrder,
    bool isActive = true,
  }) => _writer.upsertVariant(
    scope: scope,
    id: id,
    menuItemId: menuItemId,
    name: name,
    priceDeltaMinor: priceDeltaMinor,
    displayOrder: displayOrder,
    isActive: isActive,
  );

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
  }) => _writer.upsertModifier(
    scope: scope,
    id: id,
    menuItemId: menuItemId,
    name: name,
    selectionType: selectionType,
    minSelect: minSelect,
    maxSelect: maxSelect,
    isRequired: isRequired,
    displayOrder: displayOrder,
    isActive: isActive,
    allowQuantity: allowQuantity,
    maxQuantity: maxQuantity,
  );

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
  }) => _writer.upsertModifierOption(
    scope: scope,
    id: id,
    modifierId: modifierId,
    name: name,
    priceDeltaMinor: priceDeltaMinor,
    displayOrder: displayOrder,
    isActive: isActive,
    kitchenMeat: kitchenMeat,
  );

  @override
  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  }) => _writer.softDelete(
    organizationId: organizationId,
    entity: entity,
    id: id,
  );

  @override
  Future<MenuWriteOutcome> reorder({
    required String organizationId,
    required String restaurantId,
    required String? branchId,
    required MenuEntityType entity,
    required List<String> orderedIds,
  }) => _writer.reorder(
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    entity: entity,
    orderedIds: orderedIds,
  );
}

/// Convenience to keep the success type explicit at call sites.
typedef MenuWriteSuccess = Success<MenuWriteResult, MenuWriteFailure>;
