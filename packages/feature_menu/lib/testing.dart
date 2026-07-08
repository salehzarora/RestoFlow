/// Test-only helpers for feature_menu (RF-111). Import only from tests. The
/// demo store + scope (used at runtime by the dashboard demo) live in the main
/// barrel; this file holds doubles that are only useful for tests.
library;

import 'restoflow_feature_menu.dart';

// Test-only access to the form dialogs (used to drive validation in widget
// tests without going through the full editor flow).
export 'src/widgets/menu_entity_forms.dart'
    show
        PricedChildKind,
        showCategoryFormDialog,
        showMenuDeleteConfirm,
        showModifierFormDialog,
        showPricedChildFormDialog;

/// A [MenuWriter] that returns a preset [outcome] for every operation and
/// records the last operation name. Lets a widget test drive a specific
/// success/failure (e.g. a `MenuPermissionDenied`) without a backend.
class ScriptedMenuWriter implements MenuWriter {
  ScriptedMenuWriter(this.outcome);

  /// The outcome returned by every write.
  MenuWriteOutcome outcome;

  /// The name of the most recent operation invoked (for assertions).
  String? lastOperation;

  /// The quantity settings of the most recent [upsertModifier] call (for
  /// assertions; product-rescue quantity settings). Null until it runs.
  bool? lastAllowQuantity;
  int? lastMaxQuantity;

  Future<MenuWriteOutcome> _record(String operation) async {
    lastOperation = operation;
    return outcome;
  }

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int displayOrder = 0,
    bool isActive = true,
  }) => _record('upsertCategory');

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
  }) => _record('upsertItem');

  @override
  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) => _record('upsertSize');

  @override
  Future<MenuWriteOutcome> upsertVariant({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) => _record('upsertVariant');

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
    bool allowQuantity = false,
    int? maxQuantity,
  }) {
    lastAllowQuantity = allowQuantity;
    lastMaxQuantity = maxQuantity;
    return _record('upsertModifier');
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
    Map<String, dynamic>? kitchenMeat,
  }) => _record('upsertModifierOption');

  @override
  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  }) => _record('softDelete');
}
