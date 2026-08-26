import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// Demo tenant scope for the in-memory tables. It only needs to be
/// self-consistent so the domain [TableAssignmentService] tenant check passes
/// for the seeded occupancy orders — it is NOT wired to real auth/org context.
const String _demoOrgId = 'demo-org';
const String _demoRestaurantId = 'demo-restaurant';
const String _demoBranchId = 'demo-branch';
const String _demoCurrencyCode = 'ILS';

/// UI/demo occupancy status for a [DiningTable] (RF-114).
///
/// The domain [DiningTable] stores NO status — occupancy is DERIVED, never
/// stored (DOMAIN_MODEL.md §5.1). These values are derived here for the
/// POS table picker:
///  * [blocked]   — the table is inactive (`!isActive`); out of service.
///  * [occupied]  — an OPEN (non-terminal) dine-in order is assigned to it per
///                  [TableAssignmentService]; it cannot take another (the
///                  one-open-dine-in-per-table rule, RF-035).
///  * [reserved]  — TABLE-FLOOR-LAYOUT-021 (owner decision 3): the manual
///                  `reserved` floor flag, DISPLAY-ONLY distinct. It behaves
///                  exactly like [occupied] for every business rule (never
///                  assignable, same gating) — it merely stops LYING about
///                  WHY the table is unavailable.
///  * [available] — active and free; assignable to a dine-in order.
enum TableStatusKind { available, reserved, occupied, blocked }

/// Immutable UI view of a [DiningTable] plus its derived [TableStatusKind].
class DemoTable {
  const DemoTable({
    required this.table,
    required this.status,
    this.activeOrderCount = 0,
    this.manualStatus = 'available',
    this.effectiveState = 'available',
    this.groupId,
    this.sectionId,
    this.sectionName,
    this.sectionDisplayOrder,
    this.layoutX,
    this.layoutY,
    this.visualPreset = TableVisualPreset.classicRectTable,
    this.visualMaterial,
    this.sectionFloorPreset = FloorPreset.plainLight,
    String? memberEffectiveState,
    int? memberActiveOrderCount,
  }) : _memberEffectiveState = memberEffectiveState,
       _memberActiveOrderCount = memberActiveOrderCount;

  final DiningTable table;
  final TableStatusKind status;

  /// TABLE-FLOOR-LAYOUT-021: the first-class dining section this table sits in
  /// (null = legacy/unsectioned — the picker keeps its area-text fallback
  /// zone), plus the owner's section ordering and the NORMALIZED placement
  /// (0..[kFloorLayoutMax] integers; both-or-neither; physical — never
  /// RTL-mirrored). All display plumbing: no business rule reads them.
  final String? sectionId;
  final String? sectionName;
  final int? sectionDisplayOrder;
  final int? layoutX;
  final int? layoutY;

  /// TABLE-VISUAL-LAYOUT-118: how this table is DRAWN (`visual_preset`) and
  /// how its section's floor is painted (`section_floor_preset` — the owning
  /// section's key rides on every row because `pos_tables` ships no section
  /// catalog). Presentation plumbing only: absent/unknown keys decode to the
  /// defaults, no business rule reads them, and neither changes the footprint
  /// or the saved placement.
  final TableVisualPreset visualPreset;
  final FloorPreset sectionFloorPreset;

  /// TABLE-VISUAL-CONFIGURATION-120: the persisted surface material
  /// (`visual_material`; null = Auto — the deterministic 119D mapping).
  final TableVisualMaterial? visualMaterial;

  /// RESTAURANT-OPERATIONS-V1-001: DERIVED occupancy — how many live
  /// active-status orders currently sit on this table, as the SERVER counted
  /// them (`pos_tables.active_order_count`). Multiple active orders per table
  /// are VALID (second rounds); the count is shown honestly and does NOT by
  /// itself block selection. Demo mode derives it from its seeded orders.
  final int activeOrderCount;

  /// PILOT-OPERATIONS-CORRECTIONS-001: the raw MANUAL floor status the operator
  /// set (`available` | `reserved` | `occupied` | `out_of_service`). Distinct
  /// from [effectiveState] — a table manually `available` can still be
  /// effectively `occupied` because a live dine-in order sits on it.
  final String manualStatus;

  /// PILOT-OPERATIONS-CORRECTIONS-001: the SERVER-authoritative effective state
  /// (`app.table_effective_state` — manual status fused with derived occupancy):
  /// out_of_service > active dine-in occupancy > reserved > occupied > available.
  final String effectiveState;

  /// PILOT-OPERATIONS-CORRECTIONS-001: the active link-group id, or null when the
  /// table is not part of a group. Client renders same-group tables as one unit.
  final String? groupId;

  /// PSC-001B: this member's OWN (pre-group-projection) truth, preserved through
  /// [withGroupAggregation] so the group-detail sheet can honestly show which
  /// physical table owns which state/activity while [effectiveState] and
  /// [activeOrderCount] carry the group-wide projection. For an ungrouped (or
  /// never-projected) row they fall back to the row's own values.
  final String? _memberEffectiveState;
  final int? _memberActiveOrderCount;

  /// This physical table's OWN effective state (never the group projection).
  String get memberEffectiveState => _memberEffectiveState ?? effectiveState;

  /// This physical table's OWN active dine-in order count (never the group sum).
  int get memberActiveOrderCount => _memberActiveOrderCount ?? activeOrderCount;

  String get tableId => table.tableId;
  String get label => table.label;
  int? get seats => table.seats;
  String? get area => table.area;

  bool get isGrouped => groupId != null;
  bool get isOutOfService => effectiveState == 'out_of_service';
  bool get isReserved => manualStatus == 'reserved' && activeOrderCount == 0;

  /// A table can be assigned to a dine-in order only when it is available.
  bool get isAssignable => status == TableStatusKind.available;

  /// MENU-ORDER-001 (Codex #8/#9): a MINIMAL durable identity so a captured
  /// draft's assigned table survives an app restart. Only the display essentials
  /// are persisted; group/occupancy state is re-derived when the picker reloads.
  Map<String, Object?> toJson() => <String, Object?>{
    'table_id': tableId,
    'label': label,
    if (seats != null) 'seats': seats,
    if (area != null) 'area': area,
  };

  static DemoTable fromJson(Map<String, Object?> json) {
    final rawSeats = json['seats'];
    final rawArea = json['area'];
    return DemoTable(
      table: DiningTable(
        tableId: (json['table_id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        organizationId: _demoOrgId,
        restaurantId: _demoRestaurantId,
        branchId: _demoBranchId,
        seats: rawSeats is int ? rawSeats : int.tryParse('${rawSeats ?? ''}'),
        area: rawArea is String && rawArea.isNotEmpty ? rawArea : null,
      ),
      status: TableStatusKind.available,
    );
  }

  /// PILOT-OPERATIONS-CORRECTIONS-001 (A4): a copy with the GROUP-WIDE effective
  /// state, count and derived status projected onto this member. Used only by
  /// [withGroupAggregation]; every other field is preserved.
  ///
  /// PSC-001B: the member's OWN truth survives the projection. When the optional
  /// member values are omitted the copy keeps this row's current member truth
  /// (the group-projection step); the dedup merge passes them explicitly so a
  /// duplicate physical row's merged state/count becomes the member truth.
  DemoTable copyWithGroupState({
    required String effectiveState,
    required int activeOrderCount,
    required TableStatusKind status,
    String? memberEffectiveState,
    int? memberActiveOrderCount,
  }) => DemoTable(
    table: table,
    status: status,
    activeOrderCount: activeOrderCount,
    manualStatus: manualStatus,
    effectiveState: effectiveState,
    groupId: groupId,
    sectionId: sectionId,
    sectionName: sectionName,
    sectionDisplayOrder: sectionDisplayOrder,
    layoutX: layoutX,
    layoutY: layoutY,
    visualPreset: visualPreset,
    sectionFloorPreset: sectionFloorPreset,
    memberEffectiveState: memberEffectiveState ?? this.memberEffectiveState,
    memberActiveOrderCount:
        memberActiveOrderCount ?? this.memberActiveOrderCount,
  );
}

/// Maps a GROUP-WIDE effective state to the picker's assignability model. NORMALIZES
/// first (Finding 6): available -> available; reserved/occupied -> occupied (non-
/// assignable); out_of_service AND unknown -> blocked (non-assignable, fail-closed —
/// an unknown/unrecognized state never presents as selectable capacity).
TableStatusKind tableStatusKindFor(String effectiveState) =>
    switch (normalizeTableEffectiveState(effectiveState)) {
      'available' => TableStatusKind.available,
      // TABLE-FLOOR-LAYOUT-021: reserved is DISPLAY-distinct now; it stays
      // non-assignable exactly like occupied (business rules unchanged).
      'reserved' => TableStatusKind.reserved,
      'occupied' => TableStatusKind.occupied,
      _ => TableStatusKind.blocked, // out_of_service + unknown
    };

/// PILOT-OPERATIONS-CORRECTIONS-001 (A4 + Finding 5): projects the ONE canonical group
/// aggregation ([aggregateTableGroup]) onto every table, so a linked group presents as
/// one operational unit — every member shows the SAME group-wide effective state and
/// active dine-in count. It ALSO deduplicates the projected list by physical table id:
/// a table id duplicated upstream yields exactly ONE tile/option (stable first-occurrence
/// order), so the floor, the picker, and the table-operations sheet never render a
/// physical table twice. This is the SINGLE place the POS applies both.
List<DemoTable> withGroupAggregation(List<DemoTable> tables) {
  // Finding 5: collapse duplicate physical-table rows FIRST — one row per table id,
  // stable first-occurrence order, merged deterministically (MAX count, most RESTRICTIVE
  // effective state). A LinkedHashMap preserves insertion order.
  final byId = <String, DemoTable>{};
  for (final t in tables) {
    final existing = byId[t.tableId];
    if (existing == null) {
      byId[t.tableId] = t;
    } else {
      final effective = mostRestrictiveTableState(
        t.effectiveState,
        existing.effectiveState,
      );
      final count = t.activeOrderCount > existing.activeOrderCount
          ? t.activeOrderCount
          : existing.activeOrderCount;
      // Keep the FIRST row's identity fields (label/manual/group); merge state + count.
      // PSC-001B: the merged values are ALSO this physical table's member truth,
      // so a later group projection cannot resurrect a stale duplicate's state.
      byId[t.tableId] = existing.copyWithGroupState(
        effectiveState: effective,
        activeOrderCount: count,
        status: tableStatusKindFor(effective),
        memberEffectiveState: effective,
        memberActiveOrderCount: count,
      );
    }
  }
  final deduped = byId.values.toList(growable: false);

  final byGroup = <String, List<TableGroupMember>>{};
  for (final t in deduped) {
    final g = t.groupId;
    if (g == null) continue;
    // Finding 4: carry the PHYSICAL table id so aggregateTableGroup deduplicates by
    // table — a row duplicated upstream cannot double a table's occupancy.
    (byGroup[g] ??= []).add((
      tableId: t.tableId,
      effectiveState: t.effectiveState,
      activeOrderCount: t.activeOrderCount,
    ));
  }
  if (byGroup.isEmpty) return deduped;
  final aggByGroup = <String, TableGroupAggregate>{
    for (final e in byGroup.entries) e.key: aggregateTableGroup(e.value),
  };
  return <DemoTable>[
    for (final t in deduped)
      if (t.groupId case final g? when aggByGroup[g] != null)
        t.copyWithGroupState(
          effectiveState: aggByGroup[g]!.effectiveState,
          activeOrderCount: aggByGroup[g]!.activeOrderCount,
          status: tableStatusKindFor(aggByGroup[g]!.effectiveState),
        )
      else
        t,
  ];
}

/// TABLE-FLOOR-MAP-POLISH-027: one VISUAL-ONLY floor fixture from the
/// `pos_tables` `floor_elements` envelope catalog — wall/door/window/cashier/
/// plant decoration on a section canvas. Read-only on every POS surface;
/// never a table (no status, no occupancy, no assignability).
class PosFloorElement {
  const PosFloorElement({
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
  final String kind;
  final int layoutX;
  final int layoutY;
  final int widthNorm;
  final int heightNorm;
  final int orientationQuarterTurns;
  final String? label;

  /// TABLE-VISUAL-CONFIGURATION-120: the persisted artwork variant
  /// (`visual_style`; null = the kind's default look).
  final String? visualStyle;
}

/// 027: one tables read — the rows plus the fixture catalog that rides the
/// same envelope (a single `pos_tables` invoke, never two).
class PosFloorSnapshot {
  const PosFloorSnapshot({required this.tables, this.floorElements = const []});

  final List<DemoTable> tables;
  final List<PosFloorElement> floorElements;
}

/// The repository seam for tables (RF-114). Its method maps 1:1 to the future
/// backend read — an RLS-scoped `tables` query for the active branch — and the
/// derived occupancy mirrors what a server `assign_table` RPC would enforce.
/// Implemented here ONLY by the in-memory [DemoTablesStore]; the real
/// Supabase-backed implementation is deferred to the data/sync tickets.
abstract class TablesRepository {
  /// Loads the branch's tables with their derived occupancy [TableStatusKind].
  Future<List<DemoTable>> loadTables();

  /// 027: tables + visual fixtures in ONE read. The default keeps older
  /// implementations honest with an empty fixture catalog; the real
  /// repository overrides this to parse both from the same envelope.
  Future<PosFloorSnapshot> loadFloorSnapshot() async =>
      PosFloorSnapshot(tables: await loadTables());
}

/// In-memory, clearly-labelled DEMO tables store (RF-114). It seeds a fixed set
/// of [DiningTable]s and a couple of OPEN dine-in orders, then derives each
/// table's [TableStatusKind] through the real domain [TableAssignmentService]
/// (so "occupied" follows the one-open-dine-in-per-table rule — not a fake
/// flag).
///
/// NO backend, NO Supabase, NO persistence. Nothing here is synced or audited.
class DemoTablesStore extends TablesRepository {
  DemoTablesStore({
    TablePolicy policy = const TablePolicy(),
    Map<String, String> manualOverrides = const {},
    Map<String, String> groupOverrides = const {},
  }) : _service = TableAssignmentService(policy: policy),
       _manualOverrides = manualOverrides,
       _groupOverrides = groupOverrides;

  final TableAssignmentService _service;

  /// PILOT-OPERATIONS-CORRECTIONS-001: the demo table-ops overlay (tableId ->
  /// manual status / group id) so a demo cashier's floor control is honestly
  /// reflected. Empty in a plain demo; supplied by the repository seam otherwise.
  final Map<String, String> _manualOverrides;
  final Map<String, String> _groupOverrides;

  @override
  Future<List<DemoTable>> loadTables() async {
    final tables = _seedTables();
    final occupied = _seedOccupancy(tables);
    return tables
        .map((t) {
          final active = occupied.contains(t.tableId) ? 1 : 0;
          final manual =
              _manualOverrides[t.tableId] ??
              (t.isActive ? 'available' : 'out_of_service');
          final effective = _effectiveState(manual, active);
          return DemoTable(
            table: t,
            status: _kindFor(effective),
            activeOrderCount: active,
            manualStatus: manual,
            effectiveState: effective,
            groupId: _groupOverrides[t.tableId],
          );
        })
        .toList(growable: false);
  }

  /// The SAME precedence as `app.table_effective_state`.
  String _effectiveState(String manual, int activeCount) {
    if (manual == 'out_of_service') return 'out_of_service';
    if (activeCount > 0) return 'occupied';
    if (manual == 'reserved') return 'reserved';
    if (manual == 'occupied') return 'occupied';
    return 'available';
  }

  TableStatusKind _kindFor(String effective) => switch (effective) {
    'available' => TableStatusKind.available,
    'reserved' => TableStatusKind.reserved, // display-distinct, non-assignable
    'out_of_service' => TableStatusKind.blocked,
    _ => TableStatusKind.occupied, // occupied -> non-assignable visual
  };

  /// Ten tables across two areas, one out of service — a realistic mix so the
  /// picker shows available, occupied (seeded below), and blocked states.
  List<DiningTable> _seedTables() => <DiningTable>[
    _table('t1', 'T1', seats: 2),
    _table('t2', 'T2', seats: 2),
    _table('t3', 'T3', seats: 4),
    _table('t4', 'T4', seats: 4),
    _table('t5', 'T5', seats: 4),
    _table('t6', 'T6', seats: 6),
    _table('t7', 'T7', seats: 6, area: 'Patio'),
    _table('t8', 'T8', seats: 8, area: 'Patio'),
    _table('t9', 'T9', seats: 4, area: 'Patio'),
    _table('t10', 'T10', seats: 4, area: 'Patio', isActive: false),
  ];

  /// Seeds OPEN dine-in orders on two tables via the domain service and returns
  /// the occupied table-id set. Using the real [TableAssignmentService] proves
  /// occupancy follows the RF-035 rule rather than a hard-coded flag.
  Set<String> _seedOccupancy(List<DiningTable> tables) {
    final occupied = <String>{};
    for (final tableId in <String>['t3', 't6']) {
      final table = tables.firstWhere((t) => t.tableId == tableId);
      _service.assignDineIn(
        order: _openDineInOrder('seed-$tableId'),
        table: table,
      );
      occupied.add(tableId);
    }
    return occupied;
  }

  DiningTable _table(
    String id,
    String label, {
    int? seats,
    String area = 'Main',
    bool isActive = true,
  }) => DiningTable(
    tableId: id,
    label: label,
    organizationId: _demoOrgId,
    restaurantId: _demoRestaurantId,
    branchId: _demoBranchId,
    seats: seats,
    area: area,
    isActive: isActive,
  );

  /// A minimal OPEN dine-in [LocalOrder] used only to seed table occupancy.
  LocalOrder _openDineInOrder(String orderId) {
    final cart = Cart(
      orderId: orderId,
      organizationId: _demoOrgId,
      restaurantId: _demoRestaurantId,
      branchId: _demoBranchId,
      currencyCode: _demoCurrencyCode,
    );
    cart.addLine(
      CartLine.snapshot(
        lineId: '$orderId-l1',
        menuItemId: 'seed-item',
        itemNameSnapshot: 'Seed item',
        basePriceMinorSnapshot: 1000,
        currencyCodeSnapshot: _demoCurrencyCode,
      ),
    );
    return LocalOrder.submitFromCart(cart, orderType: OrderType.dineIn);
  }
}

/// REAL tables repository (demo-readiness sprint): `public.pos_tables` over the
/// paired device's authenticated transport + PIN session — the device-side
/// read the dashboard Tables page feeds. The backend derives the branch from
/// the SESSION (never the payload) and returns ACTIVE, non-deleted tables:
/// `{id, label, seats, area, status}` with status
/// available|occupied|reserved|out_of_service. Fail-closed: no
/// transport/session (or a rejected response) throws — the picker shows its
/// honest error/empty state, never demo tables.
class RealTablesRepository extends TablesRepository {
  RealTablesRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  /// Placeholder for [DiningTable]'s required tenant fields: `pos_tables`
  /// rows deliberately carry NO tenant ids (scope lives server-side, derived
  /// from the session). Only `tableId`/`label`/`seats`/`area` leave this view
  /// model — the tenant fields are never transmitted anywhere.
  static const String _serverScope = 'server-scoped';

  @override
  Future<List<DemoTable>> loadTables() async =>
      (await loadFloorSnapshot()).tables;

  /// 027: the SAME single `pos_tables` invoke now also yields the visual
  /// fixture catalog (`floor_elements` envelope key; absent on an older
  /// backend -> empty).
  @override
  Future<PosFloorSnapshot> loadFloorSnapshot() async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const RealRepoNotWiredError(
        'tables: no authenticated transport/PIN session',
      );
    }
    final raw = await transport.invoke('pos_tables', <String, dynamic>{
      'p_pin_session_id': session.pinSessionId,
      'p_device_id': session.deviceId,
    });
    if (raw is! Map || raw['ok'] != true) {
      throw const RealRepoNotWiredError('tables: pos_tables rejected');
    }
    final rows = raw['tables'];
    if (rows is! List) return const PosFloorSnapshot(tables: []);
    final tables = <DemoTable>[];
    for (final row in rows.whereType<Map>()) {
      final id = row['id'];
      final label = row['label'];
      if (id is! String || label is! String) continue;
      final seats = row['seats'];
      final area = row['area'];
      // RESTAURANT-OPERATIONS-V1-001: honest server-derived occupancy. Missing/
      // malformed degrades to 0 — the count is display truth, never a gate.
      final activeOrders = row['active_order_count'];
      // PILOT-OPERATIONS-CORRECTIONS-001: the raw manual status + server-computed
      // effective_state + active link group id.
      final manual = row['status'] is String
          ? row['status'] as String
          : 'available';
      final effective = row['effective_state'] is String
          ? row['effective_state'] as String
          : manual;
      final groupId = row['group_id'] is String
          ? row['group_id'] as String
          : null;
      // TABLE-FLOOR-LAYOUT-021: the section + normalized placement keys. All
      // nullable — a legacy row simply has none and falls back to the
      // area-text zone. Malformed values degrade to null (display plumbing;
      // never a gate).
      final sectionId = row['section_id'] is String
          ? row['section_id'] as String
          : null;
      final sectionName = row['section_name'] is String
          ? row['section_name'] as String
          : null;
      final rawSectionOrder = row['section_display_order'];
      final rawX = row['layout_x'];
      final rawY = row['layout_y'];
      final layoutX = rawX is int ? rawX : null;
      final layoutY = rawY is int ? rawY : null;
      tables.add(
        DemoTable(
          table: DiningTable(
            tableId: id,
            label: label,
            organizationId: _serverScope,
            restaurantId: _serverScope,
            branchId: _serverScope,
            seats: seats is int ? seats : int.tryParse('$seats'),
            area: area is String && area.isNotEmpty ? area : null,
          ),
          // The picker's assignability model derives from the EFFECTIVE state
          // (the honest fusion), not the raw manual status.
          status: _statusFor(effective),
          activeOrderCount: activeOrders is int && activeOrders > 0
              ? activeOrders
              : 0,
          manualStatus: manual,
          effectiveState: effective,
          groupId: groupId,
          sectionId: sectionId,
          sectionName: sectionId == null ? null : sectionName,
          sectionDisplayOrder: rawSectionOrder is int ? rawSectionOrder : null,
          // Defensive both-or-neither (the DB forbids halves; never trust one).
          layoutX: layoutX != null && layoutY != null ? layoutX : null,
          layoutY: layoutX != null && layoutY != null ? layoutY : null,
          // 118: tolerant decode — absent/NULL/unknown => the defaults.
          visualPreset: TableVisualPreset.fromWire(row['visual_preset']),
          visualMaterial: TableVisualMaterial.tryParse(row['visual_material']),
          sectionFloorPreset: FloorPreset.fromWire(row['section_floor_preset']),
        ),
      );
    }
    return PosFloorSnapshot(
      tables: tables,
      floorElements: _elementsFrom(raw['floor_elements']),
    );
  }

  /// 027: the fixture catalog rows. Malformed rows degrade to nothing —
  /// decoration is never worth failing a tables load.
  static List<PosFloorElement> _elementsFrom(Object? rows) {
    if (rows is! List) return const <PosFloorElement>[];
    final out = <PosFloorElement>[];
    for (final row in rows.whereType<Map>()) {
      final id = row['id'];
      final sectionId = row['section_id'];
      final kind = row['kind'];
      final x = row['layout_x'];
      final y = row['layout_y'];
      final w = row['width_norm'];
      final h = row['height_norm'];
      if (id is! String ||
          id.isEmpty ||
          sectionId is! String ||
          sectionId.isEmpty ||
          kind is! String ||
          kind.isEmpty ||
          x is! int ||
          y is! int ||
          w is! int ||
          h is! int) {
        continue;
      }
      final orient = row['orientation_quarter_turns'];
      final label = row['label'];
      out.add(
        PosFloorElement(
          id: id,
          sectionId: sectionId,
          kind: kind,
          layoutX: x,
          layoutY: y,
          widthNorm: w,
          heightNorm: h,
          orientationQuarterTurns: orient is int && orient >= 0 && orient <= 3
              ? orient
              : 0,
          label: label is String && label.isNotEmpty ? label : null,
          // 120: tolerant + registry-sanitized.
          visualStyle:
              row['visual_style'] is String &&
                  isFloorElementStyleAllowed(
                    kind,
                    row['visual_style'] as String,
                  )
              ? row['visual_style'] as String
              : null,
        ),
      );
    }
    return out;
  }

  /// Maps the backend status to the picker's assignability model: reserved is
  /// display-distinct but non-assignable exactly like occupied
  /// (TABLE-FLOOR-LAYOUT-021); out_of_service is blocked; anything unknown
  /// fails closed to blocked.
  static TableStatusKind _statusFor(Object? status) => switch (status) {
    'available' => TableStatusKind.available,
    'reserved' => TableStatusKind.reserved,
    'occupied' => TableStatusKind.occupied,
    'out_of_service' => TableStatusKind.blocked,
    _ => TableStatusKind.blocked,
  };
}
