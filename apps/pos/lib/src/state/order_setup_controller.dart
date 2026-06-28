import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/demo_tables.dart';

/// Immutable selection state for the active order's service mode (RF-114): the
/// chosen [OrderType] and, for dine-in, the assigned [DemoTable].
///
/// In-memory only — this is the UI draft selection. Real persistence and the
/// server `assign_table` RPC are deferred (see [TablesRepository]).
class OrderSetupState {
  const OrderSetupState({required this.orderType, this.assignedTable});

  final OrderType orderType;
  final DemoTable? assignedTable;

  /// Dine-in orders must carry a table before they can be submitted (RF-035).
  bool get requiresTable => orderType == OrderType.dineIn;

  bool get hasTable => assignedTable != null;

  /// True when the selection is complete enough to submit: takeaway always,
  /// dine-in only once a table is assigned.
  bool get isReadyToSubmit => !requiresTable || hasTable;

  /// True when the cashier must still be warned that a dine-in order needs a
  /// table.
  bool get needsTableWarning => requiresTable && !hasTable;
}

/// Holds the active order's [OrderSetupState] (RF-114). Switching to takeaway
/// clears any assigned table (takeaway never carries one — RF-035); switching
/// to dine-in leaves the table unassigned until the cashier picks one.
///
/// In-memory demo only — no backend, no persistence, no sync.
class OrderSetupController extends Notifier<OrderSetupState> {
  @override
  OrderSetupState build() =>
      const OrderSetupState(orderType: OrderType.takeaway);

  void setOrderType(OrderType orderType) {
    if (orderType == state.orderType) return;
    // Takeaway must not carry a table; dine-in starts unassigned.
    state = OrderSetupState(orderType: orderType);
  }

  /// Assigns [table] to a dine-in order. No-op unless the order is dine-in and
  /// the table is assignable (available) — occupied/blocked tables are rejected.
  void assignTable(DemoTable table) {
    if (state.orderType != OrderType.dineIn) return;
    if (!table.isAssignable) return;
    state = OrderSetupState(orderType: OrderType.dineIn, assignedTable: table);
  }

  void clearTable() {
    if (!state.hasTable) return;
    state = OrderSetupState(orderType: state.orderType);
  }

  /// Resets to the default (takeaway, no table) — used after submit / new order.
  void reset() => state = build();
}

final orderSetupControllerProvider =
    NotifierProvider<OrderSetupController, OrderSetupState>(
      OrderSetupController.new,
    );

/// The tables repository (RF-114). Selects by client runtime mode (M7): the
/// in-memory [DemoTablesStore] in demo mode (the DEFAULT), or the
/// [RealTablesRepository] skeleton in real mode. Tests can override either this
/// provider or [runtimeConfigProvider] to force a mode.
final tablesRepositoryProvider = Provider<TablesRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return DemoTablesStore();
  return RealTablesRepository(cfg.supabase);
});

/// Loads the branch's tables for the picker. Async to mirror the future backend
/// read; resolves immediately for the demo store.
final tablesProvider = FutureProvider.autoDispose<List<DemoTable>>(
  (ref) => ref.watch(tablesRepositoryProvider).loadTables(),
);
