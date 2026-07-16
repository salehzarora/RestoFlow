/// Dining-table models for the dashboard Tables surface (sprint backend:
/// `dining_tables` behind `list_tables` / `upsert_table` / `set_table_status`
/// / `soft_delete_table`). Pure Dart, no Flutter.
///
/// Money never appears here (tables carry no money). A table row is branch
/// operational data only (label/seats/area/status) — never a secret.
library;

import 'package:restoflow_domain/restoflow_domain.dart'
    show aggregateTableGroup, TableGroupAggregate, TableGroupMember;

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
    this.effectiveState,
    this.groupId,
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

  /// PILOT-OPERATIONS-CORRECTIONS-001: the SERVER-authoritative effective state
  /// (`app.table_effective_state` — manual [status] fused with derived
  /// occupancy). Null when an older server did not supply it (falls back to the
  /// manual status for display).
  final String? effectiveState;

  /// PILOT-OPERATIONS-CORRECTIONS-001: the active link-group id, or null when the
  /// table is not part of a group. The Dashboard shows linked members read-only;
  /// the POS remains the operational link/unlink surface for this phase.
  final String? groupId;

  bool get isGrouped => groupId != null;

  /// PILOT-OPERATIONS-CORRECTIONS-001 (A4): a copy carrying the GROUP-WIDE effective
  /// state + active dine-in count projected onto this member. Only these two fields
  /// change (the manual [status] the owner set is a separate, per-table axis).
  DashboardTable copyWithGroupState({
    required String effectiveState,
    required int activeOrderCount,
  }) => DashboardTable(
    id: id,
    label: label,
    status: status,
    isActive: isActive,
    branchId: branchId,
    seats: seats,
    area: area,
    activeOrderCount: activeOrderCount,
    effectiveState: effectiveState,
    groupId: groupId,
  );
}

/// PILOT-OPERATIONS-CORRECTIONS-001 (A4): projects the ONE canonical group aggregation
/// ([aggregateTableGroup]) onto every grouped table, so the Dashboard presents a linked
/// group as one coherent operational unit — every member showing the SAME group-wide
/// effective state and active dine-in count. Ungrouped tables are unchanged; a member
/// with no server effective state (older backend) is left as-is.
List<DashboardTable> withDashboardGroupAggregation(
  List<DashboardTable> tables,
) {
  final byGroup = <String, List<TableGroupMember>>{};
  for (final t in tables) {
    final g = t.groupId;
    final e = t.effectiveState;
    if (g == null || e == null) continue;
    // Finding 4: carry the PHYSICAL table id so a duplicate row cannot double a
    // group's count.
    (byGroup[g] ??= []).add((
      tableId: t.id,
      effectiveState: e,
      activeOrderCount: t.activeOrderCount,
    ));
  }
  if (byGroup.isEmpty) return tables;
  final aggByGroup = <String, TableGroupAggregate>{
    for (final e in byGroup.entries) e.key: aggregateTableGroup(e.value),
  };
  return <DashboardTable>[
    for (final t in tables)
      if (t.groupId case final g? when aggByGroup[g] != null)
        t.copyWithGroupState(
          effectiveState: aggByGroup[g]!.effectiveState,
          activeOrderCount: aggByGroup[g]!.activeOrderCount,
        )
      else
        t,
  ];
}
