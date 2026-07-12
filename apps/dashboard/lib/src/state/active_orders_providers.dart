/// Active-orders state seam (ACTIVE-ORDERS-001).
///
/// Picks the demo vs real repository from [runtimeConfigProvider] (the one
/// audited mode switch) exactly like the order-history seam, scoped to the
/// active membership + authenticated transport.
///
/// FRESHNESS — deliberately restrained (the Dashboard has no background timer
/// anywhere today, and the repo's only Realtime source is a KDS/paired-device
/// branch-topic construct that a JWT dashboard principal is not authorized for):
///   * a MANUAL refresh is always available;
///   * an OPT-IN, user-visible auto-refresh polls on ONE coarse interval
///     ([kActiveOrdersRefreshInterval]) and is OFF by default;
///   * a refresh KEEPS the current rows on screen (`refreshing`, not `loading`);
///   * overlapping requests are impossible (an in-flight load short-circuits);
///   * the timer is cancelled on dispose.
/// Nothing is ever presented as "live" that is not actually being refreshed.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/active_orders_models.dart';
import '../data/active_orders_repository.dart';
import '../data/real_active_orders_repository.dart';
import 'dashboard_providers.dart';

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
    return DemoActiveOrdersRepository(
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

/// The active board's controls (branch + stage + type + payment + search).
final activeOrdersQueryProvider = StateProvider<ActiveOrdersQuery>(
  (ref) => const ActiveOrdersQuery(),
);

/// Whether the opt-in auto-refresh is running. OFF by default — the board never
/// silently claims to be live.
final activeOrdersAutoRefreshProvider = StateProvider<bool>((ref) => false);

/// The active board state: the initial load status, the current snapshot, and
/// when it was last successfully refreshed.
class ActiveOrdersState {
  const ActiveOrdersState({
    this.loading = true,
    this.refreshing = false,
    this.error,
    this.snapshot,
    this.lastUpdated,
  });

  /// The FIRST load is in flight (nothing to show yet).
  final bool loading;

  /// A refresh is in flight while the previous rows STAY on screen.
  final bool refreshing;

  /// The load failure, if any.
  final Object? error;

  /// The last successful read. Null until the first load lands.
  final ActiveOrdersSnapshot? snapshot;

  /// When [snapshot] was read (used for the honest "updated HH:MM" stamp).
  final DateTime? lastUpdated;

  bool get isEmpty =>
      !loading && error == null && (snapshot?.rows.isEmpty ?? true);

  ActiveOrdersSnapshot get data => snapshot ?? const ActiveOrdersSnapshot();
}

/// Drives the active board for a fixed [ActiveOrdersQuery]. Recreated whenever
/// the query changes (so a filter change reloads the board).
class ActiveOrdersController extends StateNotifier<ActiveOrdersState> {
  ActiveOrdersController(this._repo, this._query, this._clock)
    : super(const ActiveOrdersState(loading: true)) {
    _load(initial: true);
  }

  final ActiveOrdersRepository _repo;
  final ActiveOrdersQuery _query;
  final DateTime Function() _clock;

  Timer? _timer;
  bool _inFlight = false;

  /// Starts/stops the opt-in polling. Idempotent.
  void setAutoRefresh(bool enabled) {
    _timer?.cancel();
    _timer = null;
    if (!enabled || !mounted) return;
    _timer = Timer.periodic(
      kActiveOrdersRefreshInterval,
      (_) => unawaited(refresh()),
    );
  }

  /// Re-reads the board, KEEPING the current rows on screen while it does.
  Future<void> refresh() => _load(initial: false);

  Future<void> _load({required bool initial}) async {
    // An in-flight load short-circuits: a slow response can never be overtaken
    // by a tick, and requests can never pile up.
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
      // A failed refresh does NOT keep showing stale rows as if they were fresh:
      // the board surfaces the error and offers a retry.
      state = ActiveOrdersState(loading: false, error: e);
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
final activeOrdersControllerProvider =
    StateNotifierProvider<ActiveOrdersController, ActiveOrdersState>(
      (ref) {
        final controller = ActiveOrdersController(
          ref.watch(activeOrdersRepositoryProvider),
          ref.watch(activeOrdersQueryProvider),
          ref.watch(activeOrdersClockProvider),
        );
        ref.listen<bool>(
          activeOrdersAutoRefreshProvider,
          (_, enabled) => controller.setAutoRefresh(enabled),
          fireImmediately: true,
        );
        return controller;
      },
      dependencies: [
        activeOrdersRepositoryProvider,
        activeOrdersQueryProvider,
        activeOrdersClockProvider,
        activeOrdersAutoRefreshProvider,
      ],
    );
