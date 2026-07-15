/// Dining-table models for the dashboard Tables surface (sprint backend:
/// `dining_tables` behind `list_tables` / `upsert_table` / `set_table_status`
/// / `soft_delete_table`). Pure Dart, no Flutter.
///
/// Money never appears here (tables carry no money). A table row is branch
/// operational data only (label/seats/area/status) — never a secret.
library;

/// `dining_tables.status` (CHECK: available | occupied | reserved |
/// out_of_service).
enum DiningTableStatus {
  available('available'),
  occupied('occupied'),
  reserved('reserved'),
  outOfService('out_of_service');

  const DiningTableStatus(this.wire);
  final String wire;

  static DiningTableStatus? fromWire(String? wire) => switch (wire) {
    'available' => DiningTableStatus.available,
    'occupied' => DiningTableStatus.occupied,
    'reserved' => DiningTableStatus.reserved,
    'out_of_service' => DiningTableStatus.outOfService,
    _ => null,
  };
}

/// One configured dining table (a row of `dining_tables`). Inactive tables are
/// still listed (the dashboard manages them); tombstoned tables never are.
class DashboardTable {
  const DashboardTable({
    required this.id,
    required this.label,
    required this.status,
    required this.isActive,
    required this.branchId,
    this.seats,
    this.area,
    this.activeOrderCount = 0,
  });

  final String id;

  /// The table's name or number as printed on tickets (e.g. "T1", "Window 2").
  final String label;

  /// Seat count (optional; null when the owner didn't set one).
  final int? seats;

  /// Dining area / section (optional; e.g. "Main hall", "Terrace").
  final String? area;

  final DiningTableStatus status;

  /// Inactive tables stay listed here but are hidden from the POS table picker.
  final bool isActive;

  final String branchId;

  /// RESTAURANT-OPERATIONS-V1-001: DERIVED occupancy — live active-status
  /// orders currently on this table, as the SERVER counted them
  /// (`list_tables.active_order_count`). Multiple active orders per table are
  /// valid; the stored manual [status] is a separate, manual floor control.
  final int activeOrderCount;
}
