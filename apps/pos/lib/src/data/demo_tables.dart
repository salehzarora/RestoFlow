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
/// stored (DOMAIN_MODEL.md §5.1). These three values are derived here for the
/// POS table picker:
///  * [blocked]   — the table is inactive (`!isActive`); out of service.
///  * [occupied]  — an OPEN (non-terminal) dine-in order is assigned to it per
///                  [TableAssignmentService]; it cannot take another (the
///                  one-open-dine-in-per-table rule, RF-035).
///  * [available] — active and free; assignable to a dine-in order.
enum TableStatusKind { available, occupied, blocked }

/// Immutable UI view of a [DiningTable] plus its derived [TableStatusKind].
class DemoTable {
  const DemoTable({
    required this.table,
    required this.status,
    this.activeOrderCount = 0,
  });

  final DiningTable table;
  final TableStatusKind status;

  /// RESTAURANT-OPERATIONS-V1-001: DERIVED occupancy — how many live
  /// active-status orders currently sit on this table, as the SERVER counted
  /// them (`pos_tables.active_order_count`). Multiple active orders per table
  /// are VALID (second rounds); the count is shown honestly and does NOT by
  /// itself block selection. Demo mode derives it from its seeded orders.
  final int activeOrderCount;

  String get tableId => table.tableId;
  String get label => table.label;
  int? get seats => table.seats;
  String? get area => table.area;

  /// A table can be assigned to a dine-in order only when it is available.
  bool get isAssignable => status == TableStatusKind.available;
}

/// The repository seam for tables (RF-114). Its method maps 1:1 to the future
/// backend read — an RLS-scoped `tables` query for the active branch — and the
/// derived occupancy mirrors what a server `assign_table` RPC would enforce.
/// Implemented here ONLY by the in-memory [DemoTablesStore]; the real
/// Supabase-backed implementation is deferred to the data/sync tickets.
abstract class TablesRepository {
  /// Loads the branch's tables with their derived occupancy [TableStatusKind].
  Future<List<DemoTable>> loadTables();
}

/// In-memory, clearly-labelled DEMO tables store (RF-114). It seeds a fixed set
/// of [DiningTable]s and a couple of OPEN dine-in orders, then derives each
/// table's [TableStatusKind] through the real domain [TableAssignmentService]
/// (so "occupied" follows the one-open-dine-in-per-table rule — not a fake
/// flag).
///
/// NO backend, NO Supabase, NO persistence. Nothing here is synced or audited.
class DemoTablesStore implements TablesRepository {
  DemoTablesStore({TablePolicy policy = const TablePolicy()})
    : _service = TableAssignmentService(policy: policy);

  final TableAssignmentService _service;

  @override
  Future<List<DemoTable>> loadTables() async {
    final tables = _seedTables();
    final occupied = _seedOccupancy(tables);
    return tables
        .map(
          (t) => DemoTable(
            table: t,
            status: _statusFor(t, occupied),
            activeOrderCount: occupied.contains(t.tableId) ? 1 : 0,
          ),
        )
        .toList(growable: false);
  }

  TableStatusKind _statusFor(DiningTable t, Set<String> occupiedTableIds) {
    if (!t.isActive) return TableStatusKind.blocked;
    if (occupiedTableIds.contains(t.tableId)) return TableStatusKind.occupied;
    return TableStatusKind.available;
  }

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
class RealTablesRepository implements TablesRepository {
  const RealTablesRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  /// Placeholder for [DiningTable]'s required tenant fields: `pos_tables`
  /// rows deliberately carry NO tenant ids (scope lives server-side, derived
  /// from the session). Only `tableId`/`label`/`seats`/`area` leave this view
  /// model — the tenant fields are never transmitted anywhere.
  static const String _serverScope = 'server-scoped';

  @override
  Future<List<DemoTable>> loadTables() async {
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
    if (rows is! List) return const <DemoTable>[];
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
          status: _statusFor(row['status']),
          activeOrderCount: activeOrders is int && activeOrders > 0
              ? activeOrders
              : 0,
        ),
      );
    }
    return tables;
  }

  /// Maps the backend status to the picker's assignability model: reserved
  /// and occupied are both non-assignable ("occupied" visual); out_of_service
  /// is blocked; anything unknown fails closed to blocked.
  static TableStatusKind _statusFor(Object? status) => switch (status) {
    'available' => TableStatusKind.available,
    'occupied' || 'reserved' => TableStatusKind.occupied,
    'out_of_service' => TableStatusKind.blocked,
    _ => TableStatusKind.blocked,
  };
}
