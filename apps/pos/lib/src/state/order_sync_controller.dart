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
import '../data/order_snapshot.dart';
import '../data/order_snapshot_repository.dart';
import '../data/sync_cursor_store.dart';
import 'outbox_controller.dart';
import 'pos_session.dart';
import 'pos_sync_scope_provider.dart';
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

  /// THE LOCAL WRITE FAILED. We fetched fine — we could not STORE it.
  ///
  /// This is not cosmetic. `SharedPreferences.setString` returns a `Future<bool>` and
  /// can report `false` WITHOUT throwing (a full disk, a browser refusing
  /// localStorage). Treating that as success is how rows vanish on restart while the
  /// cursor sails past them and the server never offers them again. The cursor stays
  /// put, the same page is re-offered, and we do NOT claim a successful sync.
  persistence,

  /// The change feed had more pages than the runaway guard allows. What we stored is
  /// durable and the cursor is honest — but this was not a COMPLETE sync, and saying
  /// it was would be a lie the next refresh has to live with.
  incomplete,
}

/// The coordinator's observable state. Presentation-free: Commit 3 renders it.
class PosSyncStatus {
  const PosSyncStatus({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.error,
    this.hasEverSynced = false,
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
  });

  /// A pull is in flight. Exactly one can be.
  final bool isSyncing;

  /// When the last SUCCESSFUL sync completed. Drives "Last updated …".
  final DateTime? lastSyncedAt;

  /// The last failure, or null. A failure NEVER clears the rows: stale-but-labelled
  /// data beats an empty screen, and the cashier is told which it is.
  final PosSyncError? error;

  final bool hasEverSynced;

  /// More HISTORY pages remain in the operational window. Drives "Load more".
  final bool hasMoreHistory;

  /// A history page is being fetched. Distinct from [isSyncing]: loading older rows
  /// and refreshing the current ones are different promises to the cashier.
  final bool isLoadingMore;

  /// True when we are showing data we know may be behind.
  bool get isStale => error != null && hasEverSynced;

  PosSyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    PosSyncError? error,
    bool? hasEverSynced,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    bool clearError = false,
  }) => PosSyncStatus(
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: clearError ? null : (error ?? this.error),
    hasEverSynced: hasEverSynced ?? this.hasEverSynced,
    hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );
}

/// Drives every authoritative refresh.
class PosOrderSyncController extends Notifier<PosSyncStatus> {
  Timer? _periodic;
  Future<void>? _inFlight;
  Future<void>? _inFlightLoadMore;
  int _visibleConsumers = 0;
  bool _disposed = false;

  /// THE WINDOW — how far back "Load more" has reached, in days.
  ///
  /// It is deliberately SEPARATE from the persisted incremental cursor, and it is
  /// deliberately NOT persisted. They answer different questions:
  ///
  ///   incremental cursor -> "what has CHANGED since I last looked?"  (DURABLE,
  ///                           ascending, only ever moves FORWARD)
  ///   window cursor      -> "how far back am I looking right now?"   (SESSION-local,
  ///                           descending, newest-first)
  ///
  /// They are never conflated. Widening the view is not the same event as learning
  /// that something changed, and dragging the durable cursor along while paging back
  /// through history would skip changes the server never offers again.
  ///
  /// NEWEST-FIRST IS A CORRECTNESS REQUIREMENT. The previous build DRAINED the window
  /// ascending, page after page, because the server only paged from oldest to newest.
  /// On a branch with more rows than the drain cap, that meant re-fetching the same
  /// oldest prefix on every refresh and NEVER reaching the newest order — while the UI
  /// happily reported a successful sync. The server now pages the window DESCENDING,
  /// so the newest order is the first row of the first page, at any volume, and there
  /// is no drain loop left to overflow.
  PosSyncCursor? _windowCursor;

  /// The operational window: today + yesterday, matching the POS's own local prune.
  static const int defaultWindowDays = 2;

  /// One page of the window. The FIRST page already contains the newest orders, so
  /// this is a page size, not a race against the volume of the branch.
  static const int windowPageSize = 50;

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

  /// THE canonical scope — the SAME one the recent-order cache keys on. There is one
  /// definition of "where this till is", and it is not re-derived here.
  PosSyncScope? _scope() => ref.read(posSyncScopeProvider);

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

  /// Where "Load more" has paged back to. Test/UI seam.
  PosSyncCursor? get windowCursor => _windowCursor;

  /// LOAD MORE — pages BACKWARD into older orders, newest-first.
  ///
  /// It moves ONLY the session-local window cursor. The durable change-feed cursor is
  /// untouched: how far back we are looking says nothing about what has changed since
  /// we last looked, and dragging that cursor along would skip changes the server
  /// never offers again.
  ///
  /// Rows already on screen are PRESERVED — reconciliation dedupes by SERVER ORDER ID
  /// and is idempotent, so a page can add rows but never duplicate or drop one.
  Future<void> loadMore() {
    final existing = _inFlightLoadMore;
    // No overlapping load-more: two concurrent pages would start from the same cursor
    // and fetch the same rows.
    if (existing != null) return existing;
    final run = _loadMore();
    _inFlightLoadMore = run;
    return run.whenComplete(() {
      if (identical(_inFlightLoadMore, run)) _inFlightLoadMore = null;
    });
  }

  Future<void> _loadMore() async {
    if (_disposed || _scope() == null) return;
    if (!state.hasMoreHistory) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await ref
          .read(orderSnapshotRepositoryProvider)
          .fetchWindow(before: _windowCursor, limit: windowPageSize);
      if (_disposed) return;

      final ok = await ref
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots(page.orders);
      if (_disposed) return;

      if (!ok) {
        // DURABILITY FAILED. The window cursor does NOT advance, so the very same
        // page is re-offered on the next attempt. Advancing past rows we could not
        // store would lose them: nothing else would ever fetch them again.
        state = state.copyWith(
          isLoadingMore: false,
          error: PosSyncError.persistence,
        );
        return;
      }

      _windowCursor = page.nextCursor ?? _windowCursor;
      state = state.copyWith(
        isLoadingMore: false,
        hasMoreHistory: page.hasMore,
        lastSyncedAt: _now(),
        clearError: true,
      );
    } on PosSnapshotException catch (e) {
      if (_disposed) return;
      // The rows we already have stay exactly where they are.
      state = state.copyWith(isLoadingMore: false, error: _mapError(e));
    }
  }

  /// Rebuilds the window from its NEWEST page (first load / manual refresh / scope
  /// change). Reconciliation is idempotent, so re-reading rows we hold is a no-op.
  ///
  /// It also SEEDS the durable incremental cursor when there is none, to the newest
  /// row it just saw. That is what makes the incremental feed cheap forever after:
  /// it only ever asks for things newer than the newest thing we have, instead of
  /// re-walking the branch from the beginning of time.
  Future<void> refreshWindow() async {
    if (_disposed) return;
    final scope = _scope();
    if (scope == null) return;
    state = state.copyWith(isSyncing: true);
    try {
      final page = await ref
          .read(orderSnapshotRepositoryProvider)
          .fetchWindow(limit: windowPageSize);
      if (_disposed) return;

      final ok = await ref
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots(page.orders);
      if (_disposed) return;

      if (!ok) {
        // Durable write failed: report it, keep the rows on screen, and do NOT claim
        // a successful sync. `lastSyncedAt` is a promise, not a decoration.
        state = state.copyWith(
          isSyncing: false,
          error: PosSyncError.persistence,
        );
        return;
      }

      _windowCursor = page.nextCursor;

      // SEED the durable cursor to the NEWEST row (page 0, descending) when we have
      // none. Without this the first incremental pull would have a null cursor, which
      // is the WINDOW question, not the change question.
      final cursorStore = ref.read(posSyncCursorStoreProvider);
      final existing = await cursorStore.load(scope);
      if (_disposed) return;
      if (existing == null && page.orders.isNotEmpty) {
        await cursorStore.save(scope, page.orders.first.cursor);
        if (_disposed) return;
      }

      state = state.copyWith(
        isSyncing: false,
        lastSyncedAt: _now(),
        hasEverSynced: true,
        hasMoreHistory: page.hasMore,
        clearError: true,
      );
    } on PosSnapshotException catch (e) {
      if (_disposed) return;
      state = state.copyWith(isSyncing: false, error: _mapError(e));
    } on PosPersistenceException {
      if (_disposed) return;
      state = state.copyWith(isSyncing: false, error: PosSyncError.persistence);
    }
  }

  /// A scope change (branch / device / PIN). The window collapses back to the
  /// default and the session-local paging is forgotten — the DURABLE cursor and the
  /// queued operations are NOT touched here; they belong to their own scope's store.
  void resetWindow() {
    _windowCursor = null;
    state = const PosSyncStatus();
  }

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
      final cursor = await cursorStore.load(scope);
      if (_disposed) return;

      if (cursor == null) {
        // NO DURABLE CURSOR YET. A cursorless incremental call is the WINDOW question,
        // not the change question — asking it here is exactly the bug that made the
        // POS re-walk the branch from its oldest row on every start. Take the newest
        // window page instead; it seeds the cursor and we are done.
        state = state.copyWith(isSyncing: false);
        await refreshWindow();
        return;
      }

      // INCREMENTAL. Changes since the cursor are normally a handful of rows, so this
      // drains to the end rather than gambling on a cap. The cap that remains is a
      // runaway guard, and if it is ever hit we say so instead of claiming success.
      const maxPages = 20;
      var current = cursor;
      var complete = false;
      for (var page = 0; page < maxPages; page++) {
        final result = await repo.fetchChanges(cursor: current);
        if (_disposed) return;

        final ok = await ref
            .read(posRecentOrdersControllerProvider.notifier)
            .applySnapshots(result.orders);
        if (_disposed) return;

        // THE CURSOR MOVES LAST, AND ONLY ON SUCCESS. It only ever goes forward, so
        // skipping past data we did not store loses it permanently — the server will
        // never offer it again.
        if (!ok) {
          state = state.copyWith(
            isSyncing: false,
            error: PosSyncError.persistence,
          );
          return;
        }

        final next = result.nextCursor;
        if (next != null) {
          await cursorStore.save(scope, next);
          if (_disposed) return;
          current = next;
        }
        if (!result.hasMore) {
          complete = true;
          break;
        }
      }

      if (!complete) {
        // We stopped at the guard with more still pending. The data we DID store is
        // durable and the cursor is honest, but this was not a complete sync and we
        // will not pretend it was: `lastSyncedAt` is a promise, not a decoration.
        state = state.copyWith(
          isSyncing: false,
          error: PosSyncError.incomplete,
        );
        return;
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
  if (isDemo) {
    // A DETERMINISTIC demo BRANCH — including orders another till took, which is the
    // whole point of a branch view. Seeded from the injected clock, never
    // DateTime.now(): a demo that drifts with the wall clock cannot be tested.
    final now = ref.watch(posSyncClockProvider)();
    return DemoOrderSnapshotRepository(seed: demoBranchSnapshots(now))
      ..clock = now;
  }
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
