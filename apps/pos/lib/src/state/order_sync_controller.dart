/// POS-OPERATIONS-SYNC-001 — the ONE synchronization coordinator.
///
/// Every authoritative refresh in the POS goes through here. Deliberately ONE
/// object rather than timers sprinkled through widgets: overlapping pulls, a timer
/// that outlives its screen, and a resume that fires three refreshes are all bugs
/// that only exist when the timing lives in the UI.
///
/// It owns WHEN we sync. `order_reconciler.dart` owns WHAT a snapshot means. The
/// two are kept apart so the merge rules stay pure and testable.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/demo_order_snapshots.dart';
import '../data/order_snapshot_repository.dart';
import '../data/sync_cursor_store.dart';
import 'outbox_controller.dart';
import 'pos_device_context.dart';
import 'pos_session.dart';
import 'recent_orders_controller.dart';

/// Why the last sync attempt failed, in terms the UI can speak honestly about.
enum PosSyncError {
  /// Network/transport. RETRYABLE — and the rows already on screen stay put.
  offline,

  /// The session/device was refused, or the request was malformed. NOT fixed by
  /// blindly retrying the same call.
  refused,

  /// The server sent something we could not trust. The cursor did NOT advance.
  malformed,
}

/// The coordinator's observable state. Presentation-free: Commit 3 renders it.
class PosSyncStatus {
  const PosSyncStatus({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.error,
    this.hasEverSynced = false,
  });

  /// A pull is in flight. Exactly one can be.
  final bool isSyncing;

  /// When the last SUCCESSFUL sync completed. Drives "Last updated …".
  final DateTime? lastSyncedAt;

  /// The last failure, or null. A failure NEVER clears the rows: stale-but-labelled
  /// data beats an empty screen, and the cashier is told which it is.
  final PosSyncError? error;

  final bool hasEverSynced;

  /// True when we are showing data we know may be behind.
  bool get isStale => error != null && hasEverSynced;

  PosSyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    PosSyncError? error,
    bool? hasEverSynced,
    bool clearError = false,
  }) => PosSyncStatus(
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: clearError ? null : (error ?? this.error),
    hasEverSynced: hasEverSynced ?? this.hasEverSynced,
  );
}

/// Drives every authoritative refresh.
class PosOrderSyncController extends Notifier<PosSyncStatus> {
  Timer? _periodic;
  Future<void>? _inFlight;
  int _visibleConsumers = 0;
  bool _disposed = false;

  /// The production tick. Not "real-time" — we do not pretend to be, and we never
  /// say so in the UI.
  static const Duration defaultPeriodicInterval = Duration(seconds: 30);

  @override
  PosSyncStatus build() {
    ref.onDispose(() {
      _disposed = true;
      _periodic?.cancel();
      _periodic = null;
    });
    return const PosSyncStatus();
  }

  DateTime _now() => ref.read(posSyncClockProvider)();

  PosSyncScope? _scope() {
    final session = ref.read(posSyncSessionProvider);
    final ctx = ref.read(posDeviceContextProvider);
    if (session == null || ctx == null) return null;
    return PosSyncScope(
      organizationId: ctx.organizationId,
      // DeviceContext.restaurantId is optional. It is not load-bearing for SCOPE
      // (the server derives org+branch from the PIN session itself and ignores
      // anything the client claims) — it only widens the local cache key, so an
      // empty value is safe and simply groups by org+branch+device.
      restaurantId: ctx.restaurantId ?? '',
      branchId: ctx.branchId,
      deviceId: session.deviceId,
    );
  }

  // ---------------------------------------------------------------------------
  // Triggers
  // ---------------------------------------------------------------------------

  /// The full reconnect / startup sequence.
  ///
  ///   1. push whatever is queued
  ///   2. let its acknowledgements/rejections land
  ///   3. pull changes since the cursor
  ///   4. reconcile + persist
  ///   5. advance the cursor — ONLY now
  ///
  /// PUSH BEFORE PULL. Pulling first would observe a server that has not yet seen
  /// this device's queued payment, and we would "reconcile" the till back to a
  /// state we are in the middle of changing.
  Future<void> syncNow({bool pushFirst = true}) {
    final existing = _inFlight;
    // NO OVERLAPPING PULLS. A second caller joins the one already running rather
    // than starting a race whose loser silently overwrites the winner.
    if (existing != null) return existing;
    final run = _run(pushFirst: pushFirst);
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  /// TARGETED refresh — the authoritative truth about specific orders, right now.
  /// Used after every successful write and after every typed refusal, because none
  /// of the write envelopes carries a full money snapshot.
  Future<void> refreshOrders(List<String> orderIds) async {
    final ids = orderIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) return;
    final repo = ref.read(orderSnapshotRepositoryProvider);
    try {
      final page = await repo.fetchOrders(ids);
      if (_disposed) return;
      await ref
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots(page.orders);
      if (_disposed) return;
      // A targeted fetch does NOT move the incremental cursor: it is not a page of
      // the change feed and says nothing about what else may have changed.
      state = state.copyWith(lastSyncedAt: _now(), clearError: true);
    } on PosSnapshotException catch (e) {
      if (_disposed) return;
      state = state.copyWith(error: _mapError(e));
    }
  }

  /// A surface that wants live-ish data appeared. Refreshes once immediately and —
  /// when an interval is configured — starts the periodic tick while at least one
  /// consumer is visible.
  ///
  /// The interval is NULL by default and is set only in `main.dart` (the same seam
  /// `outboxAutoSweepIntervalProvider` uses). That keeps a real repeating Timer out
  /// of the widget tests, where a live periodic timer makes `pumpAndSettle` hang
  /// forever waiting for a tick that never stops coming.
  void addVisibleConsumer() {
    _visibleConsumers++;
    final interval = ref.read(posSyncPollIntervalProvider);
    if (_visibleConsumers == 1 && interval != null) {
      _periodic?.cancel();
      _periodic = Timer.periodic(interval, (_) {
        // Never stack a tick on top of a running pull.
        if (_inFlight == null) unawaited(syncNow(pushFirst: false));
      });
    }
    unawaited(syncNow());
  }

  /// The surface went away. When the last one does, polling STOPS — a POS in a
  /// drawer must not sit there hitting the server all night.
  void removeVisibleConsumer() {
    if (_visibleConsumers > 0) _visibleConsumers--;
    if (_visibleConsumers == 0) {
      _periodic?.cancel();
      _periodic = null;
    }
  }

  /// True while the periodic tick is armed. Test seam.
  bool get isPolling => _periodic != null;

  /// App resume. Debounced to ONE refresh: a resume can fire more than once, and
  /// three simultaneous pulls would be three chances to race.
  Future<void> onResume() => syncNow();

  // ---------------------------------------------------------------------------

  Future<void> _run({required bool pushFirst}) async {
    if (_disposed) return;
    final scope = _scope();
    final repo = ref.read(orderSnapshotRepositoryProvider);
    if (scope == null) {
      // No device/PIN context yet. Not an error — there is simply nothing to sync
      // against, and pretending otherwise would show a scary banner at startup.
      return;
    }

    state = state.copyWith(isSyncing: true);
    try {
      if (pushFirst) {
        // Step 1+2. A push failure is NOT fatal to the pull: the queue stays
        // durable and the next sweep retries it. We still want the freshest read.
        try {
          await ref.read(outboxControllerProvider.notifier).pushQueued();
        } catch (_) {
          // swallowed by design — the queue is durable and retries itself.
        }
        if (_disposed) return;
      }

      final cursorStore = ref.read(posSyncCursorStoreProvider);
      var cursor = await cursorStore.load(scope);
      if (_disposed) return;

      // Drain the feed, page by page. Bounded so a very busy branch cannot spin
      // here forever; the next tick simply carries on from the cursor.
      const maxPages = 10;
      for (var page = 0; page < maxPages; page++) {
        final result = await repo.fetchChanges(cursor: cursor);
        if (_disposed) return;

        final ok = await ref
            .read(posRecentOrdersControllerProvider.notifier)
            .applySnapshots(result.orders);
        if (_disposed) return;

        // THE CURSOR MOVES LAST, AND ONLY ON SUCCESS. If persistence failed we must
        // NOT advance: the cursor only goes forward, so skipping past data we did
        // not store loses it permanently — the server will never offer it again.
        if (!ok) {
          state = state.copyWith(
            isSyncing: false,
            error: PosSyncError.malformed,
          );
          return;
        }
        final next = result.nextCursor;
        if (next != null) {
          await cursorStore.save(scope, next);
          if (_disposed) return;
          cursor = next;
        }
        if (!result.hasMore) break;
      }

      state = state.copyWith(
        isSyncing: false,
        lastSyncedAt: _now(),
        hasEverSynced: true,
        clearError: true,
      );
    } on PosSnapshotException catch (e) {
      if (_disposed) return;
      // FAILURE PRESERVES THE ROWS. We change the status, never the data: a cashier
      // mid-service would rather see yesterday's total labelled stale than a blank
      // screen that looks like the orders were lost.
      state = state.copyWith(isSyncing: false, error: _mapError(e));
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(isSyncing: false, error: PosSyncError.malformed);
    }
  }

  PosSyncError _mapError(PosSnapshotException e) => switch (e.failure) {
    PosSnapshotFailure.transport => PosSyncError.offline,
    PosSnapshotFailure.session => PosSyncError.refused,
    PosSnapshotFailure.malformed => PosSyncError.malformed,
  };
}

/// Injected clock — tests read a fixed time instead of waiting for one.
final posSyncClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// How often to re-pull while an orders surface is visible.
///
/// NULL = no periodic tick. That is the DEFAULT, and it is deliberate: a live
/// repeating Timer makes `pumpAndSettle` wait forever for a stream of ticks that
/// never ends, so every widget test in the app would hang. `main.dart` sets the
/// real interval; tests opt in explicitly. Same seam as
/// `outboxAutoSweepIntervalProvider`.
final posSyncPollIntervalProvider = Provider<Duration?>((ref) => null);

/// The snapshot seam: DEMO in demo mode, the real RPC otherwise — the same
/// `isDemoMode` switch every other POS repository uses.
final orderSnapshotRepositoryProvider = Provider<OrderSnapshotRepository>((
  ref,
) {
  final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
  if (isDemo) return DemoOrderSnapshotRepository();
  return RealOrderSnapshotRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
  );
});

/// The cursor store. Overridden with the shared-preferences store in `main.dart`.
final posSyncCursorStoreProvider = Provider<PosSyncCursorStore>(
  (ref) => InMemorySyncCursorStore(),
);

final posOrderSyncControllerProvider =
    NotifierProvider<PosOrderSyncController, PosSyncStatus>(
      PosOrderSyncController.new,
    );
