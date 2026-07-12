/// Order-history state seam (ORDERS-HISTORY-001).
///
/// Picks the demo vs real repository from [runtimeConfigProvider] (the one
/// audited mode switch) exactly like the owner-reports seam, scoped to the
/// active membership + authenticated transport (both overridden by the shell's
/// Orders surface). A [StateNotifier] holds the paginated list so "load more"
/// accumulates rows; a family provider loads one order's detail lazily.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/demo_order_store.dart';
import '../data/order_history_models.dart';
import '../data/order_history_repository.dart';
import '../data/real_order_history_repository.dart';
import 'dashboard_providers.dart';

/// The ONE mutable demo order dataset (ORDER-COMPLETION-001), shared by the demo
/// order-history, active-orders and completion repositories — so a demo
/// completion really moves an order OUT of Active Orders and INTO History instead
/// of mutating a private copy nobody else can see.
final demoOrderStoreProvider = Provider<DemoOrderStore>(
  (ref) => DemoOrderStore(),
);

/// The order-history data seam. Demo mode (the DEFAULT) uses the computed
/// [DemoOrderHistoryRepository]; real mode returns [RealOrderHistoryRepository]
/// reading `owner_order_history` / `owner_order_detail` over the authenticated
/// transport, scoped to the active membership (fails closed with no
/// transport/scope).
final orderHistoryRepositoryProvider = Provider<OrderHistoryRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return DemoOrderHistoryRepository(store: ref.watch(demoOrderStoreProvider));
  }
  return RealOrderHistoryRepository(
    config.supabase,
    scope: ref.watch(dashboardMembershipProvider),
    transport: ref.watch(dashboardAuthTransportProvider),
  );
}, dependencies: [dashboardMembershipProvider, dashboardAuthTransportProvider]);

/// The active list controls (range + filters + search). The screen's chips /
/// dropdowns / search box write this; changing it rebuilds the controller,
/// which reloads the first page for the new window.
final orderHistoryQueryProvider = StateProvider<OrderHistoryQuery>(
  (ref) => const OrderHistoryQuery(),
);

/// One order's detail (header + items + payments), loaded lazily when a row is
/// opened. Family-keyed by order id; scoped through the repository provider.
final orderDetailProvider = FutureProvider.family<OrderDetail, String>(
  (ref, orderId) =>
      ref.watch(orderHistoryRepositoryProvider).loadDetail(orderId),
  dependencies: [orderHistoryRepositoryProvider],
);

/// The paginated history list state: the initial load status, the accumulated
/// rows, and the keyset continuation.
class OrderHistoryState {
  const OrderHistoryState({
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.rows = const [],
    this.hasMore = false,
    this.cursor,
  });

  /// The first page is loading (no rows yet).
  final bool loading;

  /// A "load more" page is in flight (rows already shown).
  final bool loadingMore;

  /// The initial-load failure, if any (a load-more failure keeps the rows).
  final Object? error;

  final List<OrderHistoryRow> rows;
  final bool hasMore;
  final String? cursor;

  bool get isEmpty => !loading && error == null && rows.isEmpty;

  OrderHistoryState copyWith({
    bool? loading,
    bool? loadingMore,
    Object? error,
    List<OrderHistoryRow>? rows,
    bool? hasMore,
    String? cursor,
  }) => OrderHistoryState(
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
    rows: rows ?? this.rows,
    hasMore: hasMore ?? this.hasMore,
    cursor: cursor,
  );
}

/// Drives the paginated history list for a fixed [OrderHistoryQuery]. Recreated
/// whenever the query changes (so a filter change reloads the first page).
class OrderHistoryController extends StateNotifier<OrderHistoryState> {
  OrderHistoryController(this._repo, this._query)
    : super(const OrderHistoryState(loading: true)) {
    _loadInitial();
  }

  final OrderHistoryRepository _repo;
  final OrderHistoryQuery _query;

  Future<void> _loadInitial() async {
    state = const OrderHistoryState(loading: true);
    try {
      final page = await _repo.loadHistory(_query);
      if (!mounted) return;
      state = OrderHistoryState(
        loading: false,
        rows: page.rows,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } catch (e) {
      if (!mounted) return;
      state = OrderHistoryState(loading: false, error: e);
    }
  }

  /// Re-runs the first-page load (the refresh button).
  Future<void> refresh() => _loadInitial();

  /// Appends the next keyset page. A load-more failure keeps the existing rows
  /// (it just stops paging) rather than wiping the list.
  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (state.loading ||
        state.loadingMore ||
        !state.hasMore ||
        cursor == null) {
      return;
    }
    state = state.copyWith(loadingMore: true, cursor: cursor);
    try {
      final page = await _repo.loadHistory(_query, cursor: cursor);
      if (!mounted) return;
      state = state.copyWith(
        loadingMore: false,
        rows: [...state.rows, ...page.rows],
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false, hasMore: false, cursor: null);
    }
  }
}

/// The history list controller for the current query.
final orderHistoryControllerProvider =
    StateNotifierProvider<OrderHistoryController, OrderHistoryState>(
      (ref) {
        final repo = ref.watch(orderHistoryRepositoryProvider);
        final query = ref.watch(orderHistoryQueryProvider);
        return OrderHistoryController(repo, query);
      },
      dependencies: [orderHistoryRepositoryProvider, orderHistoryQueryProvider],
    );
