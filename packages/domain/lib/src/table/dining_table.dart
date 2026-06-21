/// An immutable dining table (RF-035, DOMAIN_MODEL.md §5.1): a physical table /
/// seating spot at a branch, for dine-in orders. Pure-Dart value object — NOT
/// persisted (no Drift), and it carries NO occupancy `status` (occupancy is
/// derived by [TableAssignmentService], not stored on the table).
library;

import 'table_exceptions.dart';

class DiningTable {
  DiningTable({
    required this.tableId,
    required this.label,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    this.seats,
    this.area,
    this.isActive = true,
  }) {
    _requireNonEmpty(tableId, 'tableId');
    _requireNonEmpty(label, 'label');
    _requireNonEmpty(organizationId, 'organizationId');
    _requireNonEmpty(restaurantId, 'restaurantId');
    _requireNonEmpty(branchId, 'branchId');
  }

  final String tableId;
  final String label;

  // Tenant scope (DECISION D-001/D-002) — all required (RF-035 AC#2).
  final String organizationId;
  final String restaurantId;
  final String branchId;

  /// Optional seating capacity.
  final int? seats;

  /// Optional area/zone label.
  final String? area;

  /// Whether the table is in service (default true).
  final bool isActive;

  static void _requireNonEmpty(String value, String field) {
    if (value.trim().isEmpty) {
      throw InvalidDiningTableException('$field must not be empty');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DiningTable &&
      other.tableId == tableId &&
      other.label == label &&
      other.organizationId == organizationId &&
      other.restaurantId == restaurantId &&
      other.branchId == branchId &&
      other.seats == seats &&
      other.area == area &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(
    tableId,
    label,
    organizationId,
    restaurantId,
    branchId,
    seats,
    area,
    isActive,
  );
}
