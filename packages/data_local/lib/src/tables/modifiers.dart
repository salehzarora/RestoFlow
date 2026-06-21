import 'package:drift/drift.dart';

import 'menu_items.dart';
import 'syncable_columns.dart';

/// A group of selectable options attached to a menu item (RF-030,
/// docs/DOMAIN_MODEL.md §4.5), e.g. "Toppings".
///
/// Modifiers attach directly to a menu item via `menu_item_id` (many-to-many
/// modifier groups are DEFERRED per the RF-030 decisions). RF-030 STORES the
/// selection rules (`min_select`, `max_select`, `is_required`) only — it does
/// NOT enforce them; cart enforcement is RF-031.
class Modifiers extends Table with SyncableColumns {
  TextColumn get restaurantId => text()();
  TextColumn get branchId => text().nullable()();

  TextColumn get menuItemId => text().references(MenuItems, #id)();
  TextColumn get name => text()();

  /// 'single' or 'multiple' (stored as text; not enforced in RF-030).
  TextColumn get selectionType => text()();
  IntColumn get minSelect => integer().withDefault(const Constant(0))();
  IntColumn get maxSelect => integer().withDefault(const Constant(1))();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();

  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
