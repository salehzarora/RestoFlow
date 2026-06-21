import 'package:drift/drift.dart';

import 'syncable_columns.dart';

/// Menu category (RF-030): grouping of menu items for display/ordering
/// (docs/DOMAIN_MODEL.md §4.1).
///
/// Mixes in [SyncableColumns] (id, organization_id, device_id,
/// local_operation_id, revision, client/server timestamps, created/updated_at,
/// tombstone deleted_at) and adds the operational tenant scope
/// (`restaurant_id`, nullable `branch_id`) per DECISION D-001/D-002.
class MenuCategories extends Table with SyncableColumns {
  /// Operational tenant scope (DECISION D-001/D-002); organization_id is on the
  /// mixin. `branch_id` is nullable for branch-specific overrides.
  TextColumn get restaurantId => text()();
  TextColumn get branchId => text().nullable()();

  TextColumn get name => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
