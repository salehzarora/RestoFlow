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

  /// THE SCOPE THIS CONTROLLER IS SYNCHRONIZING, and the generation that owns it.
  ///
  /// Scoping the STORAGE KEY was not enough. Every method here awaits the network and
  /// then writes: rows into the recent-order state, a cursor into the durable store, a
  /// `lastSyncedAt` onto the status. Between the await and the write, the till can be
  /// re-paired into another branch — and the old response then lands in the NEW branch,
  /// carrying the OLD branch's orders. Correct key, wrong branch, real leak.
  ///
  /// So a scope change bumps [_generation], and EVERY await boundary re-checks it
  /// before touching anything. A result from a scope we have left is dropped. It is not
  /// an error and it is not shown as one: nothing failed, the question simply stopped
  /// being ours.
  String? _scopeKey;
  int _generation = 0;

  /// True when work begun at [gen] may no longer mutate state, storage or cursors.
  ///
  /// A PLAIN FIELD COMPARISON, deliberately. It cannot consult `ref`: Riverpod forbids
  /// any ref access between a dependency changing and the provider rebuilding — which is
  /// precisely the window a stale response lands in. The generation is instead advanced
  /// EAGERLY, by the scope listener in [build], so it is already correct by the time any
  /// awaited continuation resumes.
  bool _isStale(int gen, String? scopeKey) =>
      _disposed || gen != _generation || scopeKey != _scopeKey;

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

  /// THE SCOPE THE WINDOW CURSOR BELONGS TO. A position in branch A's history is
  /// meaningless in branch B, so the cursor is not merely cleared on a scope change —
  /// it is STRUCTURALLY unusable outside the scope it was earned in, whether or not the
  /// controller has been rebuilt yet.
  String? _windowScopeKey;

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
    // WATCHED, not read. The controller used to `ref.read` the scope, so it never
    // rebuilt when the till was re-paired: the window cursor, `hasMoreHistory` and
    // `lastSyncedAt` all survived the move, and branch B began paging from branch A's
    // position — skipping B's own history and reporting a sync that never happened.
    // LISTENED, not merely watched. `watch` alone rebuilds this controller only when
    // something next reads it — and a stale network response can land before that. The
    // listener fires as soon as the scope changes, so the generation has ALREADY moved
    // by the time any awaited continuation resumes, without this controller having to
    // touch `ref` in the window where Riverpod forbids it.
    ref.listen<PosSyncScope?>(
      posSyncScopeProvider,
      (previous, next) => _onScopeChanged(next?.key),
    );
    _onScopeChanged(ref.watch(posSyncScopeProvider)?.key);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _periodic?.cancel();
      _periodic = null;
    });
    // A fresh scope starts from a FRESH status: an empty branch has not "last synced"
    // at the moment the previous branch did, and inheriting that timestamp would be a
    // promise about data this branch has never fetched.
    return const PosSyncStatus();
  }

  /// A DIFFERENT SCOPE IS A DIFFERENT WORLD. Everything begun for the previous one is
  /// obsolete: the generation moves (so every in-flight operation discards itself when
  /// it resumes), and the session-local window position is dropped — a place in branch
  /// A's history means nothing in branch B.
  ///
  /// The DURABLE cursor and the queued operations are NOT touched: they belong to their
  /// own scope's store and are still exactly right for it.
  void _onScopeChanged(String? key) {
    if (key == _scopeKey) return;
    _generation++;
    _scopeKey = key;
    _windowCursor = null;
    _windowScopeKey = null;
    _inFlight = null;
    _inFlightLoadMore = null;
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
    final gen = _generation;
    final scopeKey = _scope()?.key;
    final repo = ref.read(orderSnapshotRepositoryProvider);
    try {
      final page = await repo.fetchOrders(ids);
      // The till may have moved branch while this was in flight. These rows belong to
      // the branch we asked FROM, not the one we are in now.
      if (_isStale(gen, scopeKey)) return;

      final ok = await ref
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots(page.orders);
      if (_isStale(gen, scopeKey)) return;

      if (!ok) {
        // DURABILITY FAILED — and this path used to ignore that entirely, stamping a
        // fresh `lastSyncedAt` over rows it had not managed to store. It reported a
        // successful synchronization that had not happened, which is worse than the
        // failure: the cashier is told the day is safe when it is not, and the three
        // refresh paths disagreed about what "synced" even meant. All three now answer
        // the same way.
        state = state.copyWith(error: PosSyncError.persistence);
        return;
      }

      // A targeted fetch does NOT move the incremental cursor: it is not a page of
      // the change feed and says nothing about what else may have changed.
      state = state.copyWith(lastSyncedAt: _now(), clearError: true);
    } on PosSnapshotException catch (e) {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(error: _mapError(e));
    } on PosPersistenceException {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(error: PosSyncError.persistence);
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

  /// Where "Load more" has paged back to IN THE CURRENT SCOPE — null in any other.
  /// [_onScopeChanged] clears it the moment the till moves, so it can never be sent to
  /// a branch it was not earned in.
  PosSyncCursor? get windowCursor =>
      _windowScopeKey == _scopeKey ? _windowCursor : null;

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
    final scope = _scope();
    if (_disposed || scope == null) return;
    if (!state.hasMoreHistory) return;
    final gen = _generation;
    final scopeKey = scope.key;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await ref
          .read(orderSnapshotRepositoryProvider)
          // The SCOPE-OWNED cursor: in a branch this cursor does not belong to, it
          // reads null and we start from that branch's newest order.
          .fetchWindow(before: windowCursor, limit: windowPageSize);
      // A page of branch A's history, arriving in branch B. Dropped: it is not B's
      // history, and appending it would put another branch's orders on this till.
      if (_isStale(gen, scopeKey)) return;

      final ok = await ref
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots(page.orders);
      if (_isStale(gen, scopeKey)) return;

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
      _windowScopeKey = scopeKey;
      state = state.copyWith(
        isLoadingMore: false,
        hasMoreHistory: page.hasMore,
        lastSyncedAt: _now(),
        clearError: true,
      );
    } on PosSnapshotException catch (e) {
      if (_isStale(gen, scopeKey)) return;
      // The rows we already have stay exactly where they are.
      state = state.copyWith(isLoadingMore: false, error: _mapError(e));
    } on PosPersistenceException {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: PosSyncError.persistence,
      );
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
    // CAPTURED. Every write below is made against THIS scope and this generation —
    // never against `_scope()` re-read after an await, which is how branch A's newest
    // page ended up as branch B's opening screen.
    final gen = _generation;
    final scope = _scope();
    if (scope == null) return;
    final scopeKey = scope.key;
    state = state.copyWith(isSyncing: true);
    try {
      final page = await ref
          .read(orderSnapshotRepositoryProvider)
          .fetchWindow(limit: windowPageSize);
      if (_isStale(gen, scopeKey)) return;

      final ok = await ref
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots(page.orders);
      if (_isStale(gen, scopeKey)) return;

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
      _windowScopeKey = scopeKey;

      // SEED the durable cursor to the NEWEST row (page 0, descending) when we have
      // none. Without this the first incremental pull would have a null cursor, which
      // is the WINDOW question, not the change question.
      //
      // Saved against the CAPTURED scope, so even a write that slips past the guard
      // lands in the store of the branch it was read from — never in another's.
      final cursorStore = ref.read(posSyncCursorStoreProvider);
      final existing = await cursorStore.load(scope);
      if (_isStale(gen, scopeKey)) return;
      if (existing == null && page.orders.isNotEmpty) {
        await cursorStore.save(scope, page.orders.first.cursor);
        if (_isStale(gen, scopeKey)) return;
      }

      state = state.copyWith(
        isSyncing: false,
        lastSyncedAt: _now(),
        hasEverSynced: true,
        hasMoreHistory: page.hasMore,
        clearError: true,
      );
    } on PosSnapshotException catch (e) {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(isSyncing: false, error: _mapError(e));
    } on PosPersistenceException {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(isSyncing: false, error: PosSyncError.persistence);
    }
  }

  /// App resume. Debounced to ONE refresh: a resume can fire more than once, and
  /// three simultaneous pulls would be three chances to race.
  Future<void> onResume() => syncNow();

  // ---------------------------------------------------------------------------

  Future<void> _run({required bool pushFirst}) async {
    if (_disposed) return;
    final gen = _generation;
    final scope = _scope();
    final scopeKey = scope?.key;
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
        if (_isStale(gen, scopeKey)) return;
      }

      final cursorStore = ref.read(posSyncCursorStoreProvider);
      final cursor = await cursorStore.load(scope);
      if (_isStale(gen, scopeKey)) return;

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
        // Changes from the branch we have LEFT. They are not this branch's changes, and
        // applying them would import another branch's orders into this till.
        if (_isStale(gen, scopeKey)) return;

        final ok = await ref
            .read(posRecentOrdersControllerProvider.notifier)
            .applySnapshots(result.orders);
        if (_isStale(gen, scopeKey)) return;

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
          if (_isStale(gen, scopeKey)) return;
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
      if (_isStale(gen, scopeKey)) return;
      // FAILURE PRESERVES THE ROWS. We change the status, never the data: a cashier
      // mid-service would rather see yesterday's total labelled stale than a blank
      // screen that looks like the orders were lost.
      state = state.copyWith(isSyncing: false, error: _mapError(e));
    } on PosPersistenceException {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(isSyncing: false, error: PosSyncError.persistence);
    } catch (_) {
      if (_isStale(gen, scopeKey)) return;
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
