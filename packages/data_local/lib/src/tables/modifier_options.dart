import 'package:drift/drift.dart';

import 'modifiers.dart';
import 'syncable_columns.dart';

/// An individual choice within a modifier (RF-030, docs/DOMAIN_MODEL.md §4.6),
/// e.g. "Extra cheese", with a price delta in integer MINOR units (DECISION
/// D-007). No separate currency — it inherits the menu item's `currency_code`.
class ModifierOptions extends Table with SyncableColumns {
  TextColumn get restaurantId => text()();
  TextColumn get branchId => text().nullable()();

  TextColumn get modifierId => text().references(Modifiers, #id)();
  TextColumn get name => text()();

  /// Price delta in integer MINOR units (DECISION D-007).
  IntColumn get priceDeltaMinor => integer().withDefault(const Constant(0))();

  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
