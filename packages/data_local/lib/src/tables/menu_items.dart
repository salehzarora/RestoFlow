import 'package:drift/drift.dart';

import 'menu_categories.dart';
import 'syncable_columns.dart';

/// A sellable menu product (RF-030, docs/DOMAIN_MODEL.md §4.2).
///
/// Money is integer MINOR units only (DECISION D-007) — `base_price_minor`,
/// never floating point. The item's currency is `currency_code` (ISO 4217);
/// child price deltas (sizes/variants/options) inherit it. RF-030 carries raw
/// prices only — no money engine/totals/snapshots (those are RF-036/RF-031).
class MenuItems extends Table with SyncableColumns {
  TextColumn get restaurantId => text()();
  TextColumn get branchId => text().nullable()();

  /// Owning category (DECISION D-017 FK).
  TextColumn get menuCategoryId => text().references(MenuCategories, #id)();

  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// Base price in integer MINOR units (DECISION D-007). No floating point.
  IntColumn get basePriceMinor => integer()();

  /// ISO 4217 currency code (e.g. ILS / USD). Child price deltas inherit it.
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
