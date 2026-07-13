/// Active-orders state seam (ACTIVE-ORDERS-001, reworked by ACTIVE-ORDERS-002).
///
/// Picks the demo vs real repository from [runtimeConfigProvider] (the one
/// audited mode switch), scoped to the active membership + authenticated
/// transport.
///
/// FRESHNESS (ACTIVE-ORDERS-002) — simplified. The opt-in auto-refresh SWITCH is
/// gone: it added chrome without operational value, and an operations board that
/// only updates when you remember to flip a toggle is worse than useless. Now:
///   * the board auto-refreshes on ONE coarse interval
///     ([kActiveOrdersRefreshInterval]) WHILE IT IS VISIBLE, and only then;
///   * switching to History (or disposing the view) CANCELS the timer — the
///     Dashboard never polls a surface nobody is looking at;
///   * a MANUAL refresh is always available and resets the stamp;
///   * a refresh KEEPS the current rows on screen (`refreshing`, not `loading`);
///   * requests can never overlap (an in-flight load short-circuits);
///   * a BACKGROUND refresh failure does NOT wipe usable rows — it is surfaced
///     beside them; only a failed FIRST load shows the full error state.
/// Nothing is ever described as "live" or "real-time" — the UI shows an honest
/// "last updated" stamp.
///
/// PAGING: the server applies the QUEUE and the SORT and caps the page, so pages
/// are ACCUMULATED here (never re-sorted). Changing queue / sort / branch /
/// filter / search rebuilds the controller, which resets pagination — a cursor
/// from the old state can never be replayed (the server rejects it anyway).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/active_orders_models.dart';
import '../data/active_orders_repository.dart';
import '../data/order_history_models.dart';
import '../data/real_active_orders_repository.dart';
import 'dashboard_providers.dart';
import 'order_history_providers.dart' show demoOrderStoreProvider;

/// The single auto-refresh cadence. Coarse on purpose: an ops board is a human
/// glance surface, not a kitchen display, and Supabase must not be hammered.
const Duration kActiveOrdersRefreshInterval = Duration(seconds: 30);

/// The active-orders data seam. Demo mode (the DEFAULT) uses the computed
/// [DemoActiveOrdersRepository]; real mode returns [RealActiveOrdersRepository]
/// reading `owner_active_orders` over the authenticated transport, scoped to the
/// active membership (fails closed with no transport/scope).
final activeOrdersRepositoryProvider = Provider<ActiveOrdersRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    // The SHARED demo store, so a demo completion really drops the order off
    // this board (ORDER-COMPLETION-001).
    return DemoActiveOrdersRepository(
      store: ref.watch(demoOrderStoreProvider),
      clock: ref.watch(activeOrdersClockProvider),
    );
  }
  return RealActiveOrdersRepository(
    config.supabase,
    scope: ref.watch(dashboardMembershipProvider),
    transport: ref.watch(dashboardAuthTransportProvider),
  );
}, dependencies: [dashboardMembershipProvider, dashboardAuthTransportProvider]);

/// The clock the board reads elapsed age against. Overridable so tests use a
/// FIXED instant instead of real time (ages must never be wall-clock dependent).
final activeOrdersClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The active board's controls (queue + sort + branch + stage + type + payment +
/// search). Defaults to the IN-PROGRESS queue, NEWEST first.
final activeOrdersQueryProvider = StateProvider<ActiveOrdersQuery>(
  (ref) => const ActiveOrdersQuery(),
);

/// The auto-refresh cadence, INJECTED so scheduling is testable.
///
/// Null disables polling entirely. Widget tests default it to null (no stray
/// timer can outlive a test), and the polling tests inject an interval and
/// advance FAKE time with `tester.pump(duration)` — no test ever waits on a real
/// 30-second delay.
final activeOrdersPollIntervalProvider = Provider<Duration?>(
  (ref) => kActiveOrdersRefreshInterval,
);

/// The active board state.
class ActiveOrdersState {
  const ActiveOrdersState({
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.refreshError = false,
    this.snapshot,
    this.lastUpdated,
  });

  /// The FIRST load is in flight (nothing to show yet).
  final bool loading;

  /// A refresh is in flight while the previous rows STAY on screen.
  final bool refreshing;

  /// A "load more" page is in flight (rows already shown).
  final bool loadingMore;

  /// The FIRST-load failure. Only this replaces the board with an error state.
  final Object? error;

  /// A BACKGROUND/manual refresh failed while usable rows are on screen. The rows
  /// are KEPT and this is surfaced beside them — a transient blip must never wipe
  /// the operator's board.
  final bool refreshError;

  /// The last successful read (rows ACCUMULATED across pages).
  final ActiveOrdersSnapshot? snapshot;

  /// When [snapshot] was last successfully read (drives the honest stamp).
  final DateTime? lastUpdated;

  bool get isEmpty =>
      !loading && error == null && (snapshot?.rows.isEmpty ?? true);

  ActiveOrdersSnapshot get data => snapshot ?? const ActiveOrdersSnapshot();
}

/// Drives the active board for a fixed [ActiveOrdersQuery]. Recreated whenever
/// the query changes — which is exactly what RESETS pagination on a queue / sort /
/// filter change.
class ActiveOrdersController extends StateNotifier<ActiveOrdersState> {
  ActiveOrdersController(this._repo, this._query, this._clock, this._interval)
    : super(const ActiveOrdersState(loading: true)) {
    _load(initial: true);
  }

  final ActiveOrdersRepository _repo;
  final ActiveOrdersQuery _query;
  final DateTime Function() _clock;

  /// The injected poll cadence. Null = no polling at all.
  final Duration? _interval;

  Timer? _timer;
  bool _inFlight = false;

  /// Starts/stops the automatic refresh. Driven by the view's VISIBILITY, not by
  /// a user switch: the board polls while it is on screen and stops the moment it
  /// is not. Idempotent.
  void setPolling(bool enabled) {
    _timer?.cancel();
    _timer = null;
    final interval = _interval;
    if (!enabled || interval == null || !mounted) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  /// Re-reads the FIRST page, KEEPING the current rows on screen while it does.
  /// Resets the accumulated pages (the board is showing the freshest window).
  Future<void> refresh() => _load(initial: false);

  /// Appends the next page. A failure here just stops paging — it never wipes the
  /// rows already on screen.
  Future<void> loadMore() async {
    final snapshot = state.snapshot;
    final cursor = snapshot?.nextCursor;
    if (_inFlight ||
        state.loading ||
        state.loadingMore ||
        snapshot == null ||
        !snapshot.hasMore ||
        cursor == null) {
      return;
    }
    _inFlight = true;
    state = ActiveOrdersState(
      loading: false,
      loadingMore: true,
      snapshot: snapshot,
      lastUpdated: state.lastUpdated,
    );
    try {
      final next = await _repo.loadActive(_query, cursor: cursor);
      if (!mounted) return;
      state = ActiveOrdersState(
        loading: false,
        snapshot: ActiveOrdersSnapshot(
          // Pages are APPENDED in the order the SERVER returned them — never
          // re-sorted here (the un-fetched rows are not in the payload).
          rows: <OrderHistoryRow>[...snapshot.rows, ...next.rows],
          summary: next.summary,
          currencyCode: next.currencyCode,
          matching: next.matching,
          limit: next.limit,
          truncated: next.hasMore,
          hasMore: next.hasMore,
          nextCursor: next.nextCursor,
        ),
        lastUpdated: state.lastUpdated,
      );
    } catch (_) {
      if (!mounted) return;
      // Keep the rows; just stop paging.
      state = ActiveOrdersState(
        loading: false,
        snapshot: snapshot,
        lastUpdated: state.lastUpdated,
        refreshError: true,
      );
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _load({required bool initial}) async {
    // An in-flight load short-circuits: a slow response can never be overtaken by
    // a poll tick, and requests can never pile up.
    if (_inFlight) return;
    _inFlight = true;
    if (initial) {
      state = const ActiveOrdersState(loading: true);
    } else {
      state = ActiveOrdersState(
        loading: false,
        refreshing: true,
        snapshot: state.snapshot,
        lastUpdated: state.lastUpdated,
      );
    }
    try {
      final snapshot = await _repo.loadActive(_query);
      if (!mounted) return;
      state = ActiveOrdersState(
        loading: false,
        snapshot: snapshot,
        lastUpdated: _clock(),
      );
    } catch (e) {
      if (!mounted) return;
      final existing = state.snapshot;
      if (!initial && existing != null && existing.rows.isNotEmpty) {
        // A background/manual refresh failed but the operator still has usable
        // rows: KEEP them and flag the failure beside them. Never blank the board
        // on a transient blip.
        state = ActiveOrdersState(
          loading: false,
          snapshot: existing,
          lastUpdated: state.lastUpdated,
          refreshError: true,
        );
      } else {
        state = ActiveOrdersState(loading: false, error: e);
      }
    } finally {
      _inFlight = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// The active board controller for the current query.
///
/// AUTO-DISPOSED, and that is what implements the freshness rule: the board polls
/// from the moment it is watched (i.e. the Active-orders view is on screen) and
/// Riverpod tears the controller — and its timer — down the moment nothing
/// watches it any more (switching to History unmounts the view; so does leaving
/// the Orders area). No visibility bookkeeping, no timer can outlive the surface,
/// and the Dashboard never refreshes something nobody is looking at.
final activeOrdersControllerProvider =
    StateNotifierProvider.autoDispose<
      ActiveOrdersController,
      ActiveOrdersState
    >(
      (ref) {
        final controller = ActiveOrdersController(
          ref.watch(activeOrdersRepositoryProvider),
          ref.watch(activeOrdersQueryProvider),
          ref.watch(activeOrdersClockProvider),
          ref.watch(activeOrdersPollIntervalProvider),
        );
        controller.setPolling(true);
        return controller;
      },
      dependencies: [
        activeOrdersRepositoryProvider,
        activeOrdersQueryProvider,
        activeOrdersClockProvider,
        activeOrdersPollIntervalProvider,
      ],
    );
