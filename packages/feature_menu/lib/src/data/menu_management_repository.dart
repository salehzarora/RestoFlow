import 'package:restoflow_core/restoflow_core.dart';

import '../models/menu_entity_type.dart';
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
    int displayOrder = 0,
    bool isActive = true,
  }) => _writer.upsertCategory(
    scope: scope,
    id: id,
    name: name,
    displayOrder: displayOrder,
    isActive: isActive,
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
    int displayOrder = 0,
    bool isActive = true,
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
  );

  @override
  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
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
    int displayOrder = 0,
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
    int displayOrder = 0,
    bool isActive = true,
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
  );

  @override
  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) => _writer.upsertModifierOption(
    scope: scope,
    id: id,
    modifierId: modifierId,
    name: name,
    priceDeltaMinor: priceDeltaMinor,
    displayOrder: displayOrder,
    isActive: isActive,
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
}

/// Convenience to keep the success type explicit at call sites.
typedef MenuWriteSuccess = Success<MenuWriteResult, MenuWriteFailure>;
