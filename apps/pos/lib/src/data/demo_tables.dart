import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
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
  const DemoTable({required this.table, required this.status});

  final DiningTable table;
  final TableStatusKind status;

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
        .map((t) => DemoTable(table: t, status: _statusFor(t, occupied)))
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

/// REAL tables repository skeleton (M7). Selected by `runtimeConfigProvider` in
/// real mode. NOT YET WIRED: the production path is an RLS-scoped
/// `SELECT ... FROM public.tables` for the active branch. The exact
/// column -> [DemoTable] mapping and the branch-scope binding are not ratified
/// yet, so rather than guess the row shape this throws [RealRepoNotWiredError].
/// It can be upgraded to a thin authenticated read once the column contract and
/// branch scope are confirmed; no backend is contacted today.
class RealTablesRepository implements TablesRepository {
  const RealTablesRepository(this.config);

  /// The validated anon-key Supabase config (or null - fail-closed). Held for the
  /// future RLS-scoped read; no client is constructed yet.
  final SupabaseBootstrapConfig? config;

  @override
  Future<List<DemoTable>> loadTables() async =>
      throw const RealRepoNotWiredError(
        'tables: RLS-scoped public.tables read not wired yet',
      );
}
