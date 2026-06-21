import 'package:drift/drift.dart';

import 'menu_items.dart';
import 'syncable_columns.dart';

/// Size variant of a menu item (RF-030, docs/DOMAIN_MODEL.md §4.3), e.g.
/// Small/Medium/Large, with a price delta in integer MINOR units (DECISION
/// D-007). The delta is relative to the item base price; currency is inherited
/// from the menu item.
class ItemSizes extends Table with SyncableColumns {
  TextColumn get restaurantId => text()();
  TextColumn get branchId => text().nullable()();

  TextColumn get menuItemId => text().references(MenuItems, #id)();
  TextColumn get name => text()();

  /// Price delta vs the item base price, integer MINOR units (DECISION D-007).
  IntColumn get priceDeltaMinor => integer().withDefault(const Constant(0))();

  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
