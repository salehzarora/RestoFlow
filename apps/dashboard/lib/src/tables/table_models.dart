/// Dining-table models for the dashboard Tables surface (sprint backend:
/// `dining_tables` behind `list_tables` / `upsert_table` / `set_table_status`
/// / `soft_delete_table`). Pure Dart, no Flutter.
///
/// Money never appears here (tables carry no money). A table row is branch
/// operational data only (label/seats/area/status) — never a secret.
library;

import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPreset,
        TableSectionRoomFramePreset,
        TableVisualMaterial,
        TableVisualPreset,
        aggregateTableGroup,
        TableGroupAggregate,
        TableGroupMember,
        mostRestrictiveTableState;

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

/// TABLE-FLOOR-LAYOUT-021: one first-class dining section (a row of
/// `table_sections`) — owner-named, owner-ordered, branch-scoped. The floor
/// editor renders one white canvas per ACTIVE section; inactive sections stay
/// listed (management) but draw no canvas.
class DashboardTableSection {
  const DashboardTableSection({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.isActive,
    required this.branchId,
    this.floorPreset = FloorPreset.plainLight,
    this.roomFramePreset,
  });

  final String id;
  final String name;
  final int displayOrder;
  final bool isActive;
  final String branchId;

  /// TABLE-VISUAL-LAYOUT-118: how this section's floor is painted (a
  /// presentation-only key; `table_sections.floor_preset`, NULL = plain
  /// light). Written only through the dedicated setter.
  final FloorPreset floorPreset;

  /// TABLE-ROOM-FRAME-121: the section's room size/shape
  /// (`table_sections.room_frame_preset`, NULL = Standard = the legacy
  /// room). Written only through the dedicated setter.
  final TableSectionRoomFramePreset? roomFramePreset;

  DashboardTableSection copyWith({
    String? name,
    int? displayOrder,
    bool? isActive,
    FloorPreset? floorPreset,
    TableSectionRoomFramePreset? roomFramePreset,
    bool clearRoomFramePreset = false,
  }) => DashboardTableSection(
    id: id,
    name: name ?? this.name,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive ?? this.isActive,
    branchId: branchId,
    floorPreset: floorPreset ?? this.floorPreset,
    roomFramePreset: clearRoomFramePreset
        ? null
        : (roomFramePreset ?? this.roomFramePreset),
  );
}

/// TABLE-FLOOR-MAP-POLISH-027: one VISUAL-ONLY floor fixture (a row of
/// `table_floor_elements`) — wall/door/window/cashier/plant decoration on a
/// section canvas. Never a table: no status, no occupancy, no orders.
class DashboardFloorElement {
  const DashboardFloorElement({
    required this.id,
    required this.sectionId,
    required this.kind,
    required this.layoutX,
    required this.layoutY,
    required this.widthNorm,
    required this.heightNorm,
    this.orientationQuarterTurns = 0,
    this.label,
    this.visualStyle,
  });

  final String id;
  final String sectionId;

  /// `wall` / `door` / `window` / `cashier` / `plant` (wire values).
  final String kind;

  /// Normalized anchor (0..10000 each; PHYSICAL — never RTL-mirrored).
  final int layoutX;
  final int layoutY;

  /// Stored (unrotated) footprint in room units.
  final int widthNorm;
  final int heightNorm;

  /// Clockwise quarter turns (0..3) applied at render time.
  final int orientationQuarterTurns;

  /// Caption (cashier/door only by contract).
  final String? label;

  /// TABLE-VISUAL-CONFIGURATION-120: the persisted artwork variant
  /// (`table_floor_elements.visual_style`; null = the kind's default look).
  /// Written only through the dedicated setter.
  final String? visualStyle;

  DashboardFloorElement copyWith({
    int? layoutX,
    int? layoutY,
    int? widthNorm,
    int? heightNorm,
    int? orientationQuarterTurns,
    String? label,
    bool clearLabel = false,
    String? visualStyle,
    bool clearVisualStyle = false,
  }) => DashboardFloorElement(
    id: id,
    sectionId: sectionId,
    kind: kind,
    layoutX: layoutX ?? this.layoutX,
    layoutY: layoutY ?? this.layoutY,
    widthNorm: widthNorm ?? this.widthNorm,
    heightNorm: heightNorm ?? this.heightNorm,
    orientationQuarterTurns:
        orientationQuarterTurns ?? this.orientationQuarterTurns,
    label: clearLabel ? null : (label ?? this.label),
    visualStyle: clearVisualStyle ? null : (visualStyle ?? this.visualStyle),
  );
}

/// TABLE-FLOOR-LAYOUT-021: one load of the Tables surface — the table rows
/// PLUS the section catalog (empty sections must render as empty canvases, so
/// a per-row join can never carry them). TABLE-FLOOR-MAP-POLISH-027 adds the
/// visual fixture catalog (absent on an older backend -> empty).
class TablesFloorSnapshot {
  const TablesFloorSnapshot({
    required this.tables,
    required this.sections,
    this.floorElements = const [],
  });

  final List<DashboardTable> tables;
  final List<DashboardTableSection> sections;
  final List<DashboardFloorElement> floorElements;
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
    this.sectionId,
    this.sectionName,
    this.sectionDisplayOrder,
    this.layoutX,
    this.layoutY,
    this.visualPreset = TableVisualPreset.classicRectTable,
    this.visualMaterial,
  });

  final String id;

  /// TABLE-VISUAL-LAYOUT-118: how the table is DRAWN on the floor map (a
  /// presentation-only key; `tables.visual_preset`, NULL = classic). Never
  /// changes the footprint or the saved placement; written only through the
  /// dedicated setter, so the full-replace upsert can never erase it.
  final TableVisualPreset visualPreset;

  /// TABLE-VISUAL-CONFIGURATION-120: the persisted surface material
  /// (`tables.visual_material`; null = Auto — the deterministic 119D
  /// preset+floor mapping). Written only through the dedicated setter.
  final TableVisualMaterial? visualMaterial;

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

  /// TABLE-FLOOR-LAYOUT-021: the first-class section this table sits in (null
  /// = unassigned/legacy) plus the NORMALIZED placement inside its canvas
  /// (0..10000 integers, both-or-neither, PHYSICAL — never RTL-mirrored).
  final String? sectionId;
  final String? sectionName;
  final int? sectionDisplayOrder;
  final int? layoutX;
  final int? layoutY;

  bool get isGrouped => groupId != null;

  /// Whether the table has a complete saved placement on its section canvas.
  bool get isPlaced => sectionId != null && layoutX != null && layoutY != null;

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
    sectionId: sectionId,
    sectionName: sectionName,
    sectionDisplayOrder: sectionDisplayOrder,
    layoutX: layoutX,
    layoutY: layoutY,
    visualPreset: visualPreset,
    visualMaterial: visualMaterial,
  );

  /// TABLE-VISUAL-LAYOUT-118: a copy with a different visual preset (the
  /// in-memory demo store + the dialog's optimistic apply). 121 review: also
  /// the status, so the demo store's setStatus preserves every other field.
  DashboardTable copyWith({
    DiningTableStatus? status,
    TableVisualPreset? visualPreset,
    TableVisualMaterial? visualMaterial,
    bool clearVisualMaterial = false,
  }) => DashboardTable(
    id: id,
    label: label,
    status: status ?? this.status,
    isActive: isActive,
    branchId: branchId,
    seats: seats,
    area: area,
    activeOrderCount: activeOrderCount,
    effectiveState: effectiveState,
    groupId: groupId,
    sectionId: sectionId,
    sectionName: sectionName,
    sectionDisplayOrder: sectionDisplayOrder,
    layoutX: layoutX,
    layoutY: layoutY,
    visualPreset: visualPreset ?? this.visualPreset,
    visualMaterial: clearVisualMaterial
        ? null
        : (visualMaterial ?? this.visualMaterial),
  );

  /// TABLE-FLOOR-LAYOUT-021: a copy with a different section/placement (the
  /// in-memory demo store + optimistic arrange moves).
  DashboardTable copyWithPlacement({
    String? sectionId,
    String? sectionName,
    int? sectionDisplayOrder,
    int? layoutX,
    int? layoutY,
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
    sectionId: sectionId,
    sectionName: sectionName,
    sectionDisplayOrder: sectionDisplayOrder,
    layoutX: layoutX,
    layoutY: layoutY,
    visualPreset: visualPreset,
    visualMaterial: visualMaterial,
  );
}

/// PILOT-OPERATIONS-CORRECTIONS-001 (A4 + Finding 5): projects the ONE canonical group
/// aggregation ([aggregateTableGroup]) onto every table AND deduplicates the projected
/// list by physical table id, so the Dashboard presents a linked group as one coherent
/// unit AND renders each physical table exactly once (a table id duplicated upstream
/// yields ONE tile). Ungrouped tables keep their own (deduplicated) state; a table with
/// no server effective state (older backend) is left as-is.
List<DashboardTable> withDashboardGroupAggregation(
  List<DashboardTable> tables,
) {
  // Finding 5: one row per physical table id (stable first-occurrence order), merging
  // duplicates deterministically (MAX count, most RESTRICTIVE effective state).
  final byId = <String, DashboardTable>{};
  for (final t in tables) {
    final existing = byId[t.id];
    if (existing == null) {
      byId[t.id] = t;
      continue;
    }
    final ee = existing.effectiveState;
    final te = t.effectiveState;
    final merged = ee == null
        ? te
        : (te == null ? ee : mostRestrictiveTableState(ee, te));
    final count = t.activeOrderCount > existing.activeOrderCount
        ? t.activeOrderCount
        : existing.activeOrderCount;
    byId[t.id] = merged == null
        // Both rows are older-backend (no effective state): keep the first as-is.
        ? existing
        : existing.copyWithGroupState(
            effectiveState: merged,
            activeOrderCount: count,
          );
  }
  final deduped = byId.values.toList(growable: false);

  final byGroup = <String, List<TableGroupMember>>{};
  for (final t in deduped) {
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
  if (byGroup.isEmpty) return deduped;
  final aggByGroup = <String, TableGroupAggregate>{
    for (final e in byGroup.entries) e.key: aggregateTableGroup(e.value),
  };
  return <DashboardTable>[
    for (final t in deduped)
      if (t.groupId case final g? when aggByGroup[g] != null)
        t.copyWithGroupState(
          effectiveState: aggByGroup[g]!.effectiveState,
          activeOrderCount: aggByGroup[g]!.activeOrderCount,
        )
      else
        t,
  ];
}
