import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ready_feed_repository.dart';
import '../data/ready_notifications_store.dart';
import '../data/sync_cursor_store.dart';
import 'order_sync_controller.dart' show posSyncClockProvider;
import 'pos_sync_scope_provider.dart';

/// PSC-001A — THE single owner of ready-feed polling and local notification
/// state. One timer, one in-flight request, one persisted envelope per scope.
///
/// Deliberately a SECOND coordinator beside [PosOrderSyncController], not a
/// bolt-on: the cadence differs (~7s vs ~30s), the gating differs (screen-wide
/// foreground vs orders-sheet visibility), and the cursor domain differs (the
/// ready keyset vs the order-sync keyset). Within ITS domain the same
/// discipline applies — no timers sprinkled through widgets, single-flight,
/// scope-generation fencing after every await, injected clock and interval.
///
/// HONESTY RULES:
///  * the durable cursor NEVER advances past rows that were not persisted —
///    cursor and records live in ONE envelope written atomically;
///  * `initialized` is the EXPLICIT bootstrap marker (cursor null is a
///    legitimate zero-row bootstrap, never "first run");
///  * an identity ((work_unit_type, work_unit_id)) alerts AT MOST once, ever —
///    `alerted` is sticky and persisted;
///  * background failures are QUIET (degraded flag, no banners); the ~7s poll
///    is itself the reconnect probe — first success recovers;
///  * a security refusal STOPS the poller and defers to the existing
///    reauth/scope-drop flow.
class PosReadyAlert {
  const PosReadyAlert({required this.id, required this.items});

  /// Monotonic per-controller id — the announce-once / auto-dismiss handle.
  final int id;

  /// One record = an individual alert; several = one grouped alert.
  final List<PosReadyNotificationRecord> items;

  bool get isGrouped => items.length > 1;
}

class PosReadyNotificationsState {
  const PosReadyNotificationsState({
    this.initialized = false,
    this.loading = false,
    this.degraded = false,
    this.lastUpdatedAt,
    this.records = const [],
    this.activeAlert,
  });

  /// Bootstrap completed for the CURRENT scope (persisted marker).
  final bool initialized;

  /// The first load/bootstrap for this scope is in flight.
  final bool loading;

  /// Quietly degraded: the last poll/persist failed; records are the last
  /// good state; the poll keeps probing and recovers silently.
  final bool degraded;
  final DateTime? lastUpdatedAt;

  /// Newest-first for the history sheet.
  final List<PosReadyNotificationRecord> records;

  /// The ONE visible alert (individual or grouped), if any.
  final PosReadyAlert? activeAlert;

  int get unreadCount => records.where((r) => !r.read).length;

  PosReadyNotificationsState copyWith({
    bool? initialized,
    bool? loading,
    bool? degraded,
    DateTime? lastUpdatedAt,
    List<PosReadyNotificationRecord>? records,
    PosReadyAlert? activeAlert,
    bool clearActiveAlert = false,
  }) => PosReadyNotificationsState(
    initialized: initialized ?? this.initialized,
    loading: loading ?? this.loading,
    degraded: degraded ?? this.degraded,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    records: records ?? this.records,
    activeAlert: clearActiveAlert ? null : (activeAlert ?? this.activeAlert),
  );
}

class PosReadyNotificationsController
    extends Notifier<PosReadyNotificationsState> {
  Timer? _timer;
  Timer? _autoDismiss;
  Future<void>? _inFlight;
  Future<void>? _reconcileInFlight;
  bool _disposed = false;
  bool _foreground = true;

  /// Scope-generation fencing — the exact [PosOrderSyncController] pattern:
  /// plain fields advanced EAGERLY by the scope listener, re-checked after
  /// every await; a stale continuation drops itself silently.
  String? _scopeKey;
  int _generation = 0;

  /// The in-memory envelope — assigned ONLY after a successful [persist], so
  /// memory can never outrun durable state (and the cursor cannot advance
  /// past unstored rows even within one session).
  PosReadyNotificationsEnvelope? _envelope;

  /// Queued alert ENTRIES (each = one cycle's new arrivals). Capped at
  /// [maxQueuedAlertEntries]; overflow collapses everything into one group.
  final List<List<PosReadyNotificationRecord>> _pendingEntries = [];
  int _alertSeq = 0;

  int _consecutiveFailures = 0;
  DateTime? _lastAttemptAt;

  /// The production tick (main.dart overrides the interval provider).
  static const Duration defaultPollInterval = Duration(seconds: 7);

  /// After [backoffAfterFailures] consecutive failures, attempts slow to one
  /// per [backoffInterval]; the first success restores the normal cadence.
  static const int backoffAfterFailures = 3;
  static const Duration backoffInterval = Duration(seconds: 30);

  /// One refresh cycle drains at most this many pages; backlog continues on
  /// the next tick (never an unbounded drain loop).
  static const int maxPagesPerCycle = 5;
  static const int pageLimit = 100;

  /// Local retention: newest [maxRecords] within [maxAge] by readyAt.
  /// Pruning never touches the durable cursor.
  static const int maxRecords = 100;
  static const Duration maxAge = Duration(hours: 24);

  static const int maxQueuedAlertEntries = 3;

  @override
  PosReadyNotificationsState build() {
    ref.listen<PosSyncScope?>(
      posSyncScopeProvider,
      (previous, next) => _onScopeChanged(next?.key),
    );
    _onScopeChanged(ref.watch(posSyncScopeProvider)?.key);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      _autoDismiss?.cancel();
      _autoDismiss = null;
    });
    _ensureTimer();
    // The immediate first load for the (re)built scope — scheduled from BUILD,
    // never from the scope listener: the listener fires while this provider is
    // still dirty, and running a cycle against a mid-rebuild graph is exactly
    // the stale-window Riverpod forbids. Build runs on a settled graph; the
    // microtask then fences itself like every other continuation.
    if (_scopeKey != null) {
      final gen = _generation;
      final key = _scopeKey;
      Future.microtask(() {
        if (_isStale(gen, key)) return;
        unawaited(refreshNow());
      });
    }
    return const PosReadyNotificationsState();
  }

  bool _isStale(int gen, String? scopeKey) =>
      _disposed || gen != _generation || scopeKey != _scopeKey;

  /// A different scope is a different world: the generation moves (every
  /// in-flight continuation drops itself), local caches empty, and the timer
  /// stops — it re-arms, and the fresh load fires, from the next [build] on
  /// the settled provider graph.
  void _onScopeChanged(String? key) {
    if (key == _scopeKey) return;
    _generation++;
    _scopeKey = key;
    _envelope = null;
    _pendingEntries.clear();
    _inFlight = null;
    _consecutiveFailures = 0;
    _lastAttemptAt = null;
    _autoDismiss?.cancel();
    _autoDismiss = null;
    _timer?.cancel();
    _timer = null;
  }

  DateTime _now() => ref.read(posSyncClockProvider)();
  PosSyncScope? _scope() => ref.read(posSyncScopeProvider);
  bool get _isDemo => ref.read(runtimeConfigProvider).isDemoMode;

  /// Whether the periodic tick is armed (test seam).
  bool get isPolling => _timer != null;

  // ---------------------------------------------------------------------------
  // Lifecycle (driven by PosSyncLifecycle — this controller owns no observer)
  // ---------------------------------------------------------------------------

  /// The app/page came to the foreground (also the startup signal).
  void onResume() {
    _foreground = true;
    _ensureTimer();
    unawaited(refreshNow());
  }

  /// The app/page left the foreground: stop ticking (an in-flight cycle
  /// finishes and fences itself; nothing new starts).
  void onPaused() {
    _foreground = false;
    _timer?.cancel();
    _timer = null;
  }

  void _ensureTimer() {
    if (_timer != null || !_foreground || _scopeKey == null || _isDemo) return;
    final interval = ref.read(posReadyFeedPollIntervalProvider);
    if (interval == null) return;
    _timer = Timer.periodic(interval, (_) {
      if (_inFlight != null) return; // no overlapping cycles
      if (_inBackoff()) return; // quiet slow-down after repeated failures
      unawaited(refreshNow());
    });
  }

  bool _inBackoff() {
    if (_consecutiveFailures < backoffAfterFailures) return false;
    final last = _lastAttemptAt;
    return last != null && _now().difference(last) < backoffInterval;
  }

  /// Whether the periodic tick would currently skip (test seam — the timer
  /// gate itself; manual [refreshNow] always bypasses it).
  @visibleForTesting
  bool get isInBackoff => _inBackoff();

  // ---------------------------------------------------------------------------
  // The refresh cycle
  // ---------------------------------------------------------------------------

  /// One discovery cycle now. Manual callers (refresh button, resume, scope
  /// restoration) bypass the backoff gate; concurrent callers join the one
  /// in-flight cycle.
  Future<void> refreshNow() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final run = _run();
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  Future<void> _run() async {
    final scope = _scope();
    if (scope == null || _isDemo) return;
    final gen = _generation;
    final scopeKey = _scopeKey;
    _lastAttemptAt = _now();

    var env = _envelope;
    if (env == null) {
      state = state.copyWith(loading: state.records.isEmpty);
      final PosReadyNotificationsEnvelope? loaded;
      try {
        loaded = await ref.read(readyNotificationsStoreProvider).load(scope);
      } catch (_) {
        if (_isStale(gen, scopeKey)) return;
        _failCycle();
        return;
      }
      if (_isStale(gen, scopeKey)) return;
      env = loaded ?? PosReadyNotificationsEnvelope.empty;
      _envelope = env;
      _publish(env, loading: !env.initialized);
    }

    try {
      if (!env.initialized) {
        await _bootstrap(gen, scopeKey, scope, env);
      } else {
        await _poll(gen, scopeKey, scope, env);
      }
    } on PosReadyFeedException catch (e) {
      if (_isStale(gen, scopeKey)) return;
      if (e.failure == PosReadyFeedFailure.session) {
        // Security refusal: STOP the poller; the PIN gate / scope-drop owns
        // recovery. Quietly degraded — never an error banner from a poll.
        _timer?.cancel();
        _timer = null;
      }
      _failCycle();
      return;
    } on PosPersistenceException {
      if (_isStale(gen, scopeKey)) return;
      _failCycle();
      return;
    }
    if (_isStale(gen, scopeKey)) return;
    _consecutiveFailures = 0;
    _publish(_envelope!, degraded: false, lastUpdatedAt: _now());
    _promoteAlert();
  }

  void _failCycle() {
    _consecutiveFailures++;
    state = state.copyWith(loading: false, degraded: true);
  }

  /// FIRST RUN for this scope. The explicit [initialized] flag — never cursor
  /// presence — marks completion. The first successful response's `server_ts`
  /// is the BASELINE: rows at-or-before it are historical (read+alerted, no
  /// badge, no banner — no storm); rows after it became ready DURING the
  /// bootstrap and alert normally rather than being silently absorbed.
  /// Everything persists in ONE atomic envelope; a crash before that persist
  /// simply re-bootstraps.
  Future<void> _bootstrap(
    int gen,
    String? scopeKey,
    PosSyncScope scope,
    PosReadyNotificationsEnvelope env,
  ) async {
    final repo = ref.read(readyFeedRepositoryProvider);
    final byIdentity = <String, PosReadyNotificationRecord>{
      for (final r in env.records) r.identityKey: r,
    };
    String? baselineTs;
    PosReadyCursor? cursor;
    var pages = 0;
    var hasMore = true;
    while (hasMore && pages < maxPagesPerCycle) {
      final page = await repo.fetch(cursor: cursor, limit: pageLimit);
      if (_isStale(gen, scopeKey)) return;
      baselineTs ??= page.serverTs;
      final baseline = DateTime.parse(baselineTs);
      for (final row in page.rows) {
        final historical = !row.readyAtTime.isAfter(baseline);
        byIdentity[row.identityKey] = _recordFrom(
          row,
          read: historical,
          alerted: historical,
        );
      }
      cursor = page.nextCursor ?? cursor;
      hasMore = page.hasMore;
      pages++;
    }
    final complete = PosReadyNotificationsEnvelope(
      initialized: true,
      bootstrapServerTs: baselineTs,
      cursor: cursor,
      records: _prune(byIdentity.values),
    );
    await ref.read(readyNotificationsStoreProvider).persist(scope, complete);
    if (_isStale(gen, scopeKey)) return;
    _envelope = complete;
    _queueUnalerted(complete);
  }

  /// NORMAL polling: tuple-cursor pages, each persisted BEFORE the cursor
  /// advances past it; a new identity is unread and queues an alert AFTER its
  /// envelope persisted; a re-seen identity only refreshes statuses/context
  /// and keeps read/alerted sticky.
  Future<void> _poll(
    int gen,
    String? scopeKey,
    PosSyncScope scope,
    PosReadyNotificationsEnvelope env,
  ) async {
    final repo = ref.read(readyFeedRepositoryProvider);
    final store = ref.read(readyNotificationsStoreProvider);
    var current = env;
    var pages = 0;
    var hasMore = true;
    while (hasMore && pages < maxPagesPerCycle) {
      final page = await repo.fetch(cursor: current.cursor, limit: pageLimit);
      if (_isStale(gen, scopeKey)) return;
      final byIdentity = <String, PosReadyNotificationRecord>{
        for (final r in current.records) r.identityKey: r,
      };
      for (final row in page.rows) {
        final existing = byIdentity[row.identityKey];
        byIdentity[row.identityKey] = existing == null
            ? _recordFrom(row, read: false, alerted: false)
            : _refresh(existing, row);
      }
      final next = PosReadyNotificationsEnvelope(
        initialized: true,
        bootstrapServerTs: current.bootstrapServerTs,
        cursor: page.nextCursor ?? current.cursor,
        records: _prune(byIdentity.values),
      );
      await store.persist(scope, next);
      if (_isStale(gen, scopeKey)) return;
      _envelope = next;
      current = next;
      _publish(next);
      hasMore = page.hasMore;
      pages++;
    }
    _queueUnalerted(current);
  }

  PosReadyNotificationRecord _recordFrom(
    PosReadyFeedRow row, {
    required bool read,
    required bool alerted,
  }) => PosReadyNotificationRecord(
    workUnitType: row.workUnitType,
    workUnitId: row.workUnitId,
    orderId: row.orderId,
    orderCode: row.orderCode,
    roundNumber: row.roundNumber,
    orderType: row.orderType,
    tableLabel: row.tableLabel,
    readyAt: row.readyAt,
    workUnitStatus: row.workUnitStatus,
    parentOrderStatus: row.parentOrderStatus,
    revision: row.revision,
    discoveredAt: _now().toIso8601String(),
    read: read,
    alerted: alerted,
  );

  PosReadyNotificationRecord _refresh(
    PosReadyNotificationRecord existing,
    PosReadyFeedRow row,
  ) => existing.copyWith(
    workUnitStatus: row.workUnitStatus,
    parentOrderStatus: row.parentOrderStatus,
    revision: row.revision,
    orderType: row.orderType,
    tableLabel: row.tableLabel,
  );

  /// Newest [maxRecords] within [maxAge] by readyAt. The cursor is untouched.
  List<PosReadyNotificationRecord> _prune(
    Iterable<PosReadyNotificationRecord> records,
  ) {
    final floor = _now().subtract(maxAge);
    final kept = records.where((r) => r.readyAtTime.isAfter(floor)).toList()
      ..sort(_newestFirst);
    return kept.length <= maxRecords ? kept : kept.sublist(0, maxRecords);
  }

  static int _newestFirst(
    PosReadyNotificationRecord a,
    PosReadyNotificationRecord b,
  ) {
    final byTime = b.readyAtTime.compareTo(a.readyAtTime);
    if (byTime != 0) return byTime;
    final byType = b.workUnitType.compareTo(a.workUnitType);
    if (byType != 0) return byType;
    return b.workUnitId.compareTo(a.workUnitId);
  }

  void _publish(
    PosReadyNotificationsEnvelope env, {
    bool? loading,
    bool? degraded,
    DateTime? lastUpdatedAt,
  }) {
    state = state.copyWith(
      initialized: env.initialized,
      loading: loading ?? false,
      degraded: degraded,
      lastUpdatedAt: lastUpdatedAt,
      records: env.records,
    );
  }

  // ---------------------------------------------------------------------------
  // Alert queue
  // ---------------------------------------------------------------------------

  /// Queues one entry for every persisted-but-never-alerted record set. This
  /// covers the normal case (this cycle's arrivals), a crash between persist
  /// and display, and a failed page mid-cycle — the durable `alerted` flag is
  /// the single source of "was this ever presented".
  void _queueUnalerted(PosReadyNotificationsEnvelope env) {
    final alreadyPending = <String>{
      for (final entry in _pendingEntries)
        for (final r in entry) r.identityKey,
      ...?state.activeAlert?.items.map((r) => r.identityKey),
    };
    final fresh =
        env.records
            .where((r) => !r.alerted && !alreadyPending.contains(r.identityKey))
            .toList()
          ..sort((a, b) => _newestFirst(b, a)); // oldest-first presentation
    if (fresh.isEmpty) return;
    _pendingEntries.add(fresh);
    if (_pendingEntries.length > maxQueuedAlertEntries) {
      // Overflow collapses into ONE grouped summary — never a banner storm.
      final merged = <PosReadyNotificationRecord>[
        for (final entry in _pendingEntries) ...entry,
      ];
      _pendingEntries
        ..clear()
        ..add(merged);
    }
  }

  /// Shows the next queued entry when no alert is visible. Marks its items
  /// `alerted` durably (best-effort: an in-memory mark still prevents any
  /// re-alert this session; a failed write can at worst re-present once
  /// after a restart — the record stays honestly unread either way).
  void _promoteAlert() {
    if (state.activeAlert != null || _pendingEntries.isEmpty) return;
    final items = _pendingEntries.removeAt(0);
    final alert = PosReadyAlert(id: ++_alertSeq, items: items);
    _markAlerted(items);
    state = state.copyWith(activeAlert: alert);
    final autoDismiss = ref.read(posReadyAlertAutoDismissProvider);
    if (autoDismiss != null) {
      _autoDismiss?.cancel();
      final alertId = alert.id;
      _autoDismiss = Timer(autoDismiss, () {
        if (_disposed || state.activeAlert?.id != alertId) return;
        dismissAlert();
      });
    }
  }

  void _markAlerted(List<PosReadyNotificationRecord> items) {
    final env = _envelope;
    if (env == null) return;
    final ids = {for (final r in items) r.identityKey};
    final updated = PosReadyNotificationsEnvelope(
      initialized: env.initialized,
      bootstrapServerTs: env.bootstrapServerTs,
      cursor: env.cursor,
      records: [
        for (final r in env.records)
          ids.contains(r.identityKey) ? r.copyWith(alerted: true) : r,
      ],
    );
    _envelope = updated;
    _publish(updated);
    _persistQuietly(updated);
  }

  /// DISMISSAL IS NOT READ — the banner goes away; the unread badge stays.
  void dismissAlert() {
    if (state.activeAlert == null) return;
    _autoDismiss?.cancel();
    _autoDismiss = null;
    state = state.copyWith(clearActiveAlert: true);
    _promoteAlert();
  }

  // ---------------------------------------------------------------------------
  // Read state
  // ---------------------------------------------------------------------------

  /// Marks ONE notification read (an intentional open).
  void markRead(String identityKey) {
    final env = _envelope;
    if (env == null) return;
    final updated = PosReadyNotificationsEnvelope(
      initialized: env.initialized,
      bootstrapServerTs: env.bootstrapServerTs,
      cursor: env.cursor,
      records: [
        for (final r in env.records)
          r.identityKey == identityKey
              ? r.copyWith(read: true, alerted: true)
              : r,
      ],
    );
    _envelope = updated;
    _publish(updated);
    _persistQuietly(updated);
  }

  /// Marks every retained record read; the explicit "I know" also clears the
  /// visible alert and the pending queue.
  void markAllRead() {
    final env = _envelope;
    if (env == null) return;
    final updated = PosReadyNotificationsEnvelope(
      initialized: env.initialized,
      bootstrapServerTs: env.bootstrapServerTs,
      cursor: env.cursor,
      records: [
        for (final r in env.records) r.copyWith(read: true, alerted: true),
      ],
    );
    _envelope = updated;
    _pendingEntries.clear();
    _autoDismiss?.cancel();
    _autoDismiss = null;
    _publish(updated);
    state = state.copyWith(clearActiveAlert: true);
    _persistQuietly(updated);
  }

  void _persistQuietly(PosReadyNotificationsEnvelope env) {
    final scope = _scope();
    if (scope == null) return;
    final gen = _generation;
    final scopeKey = _scopeKey;
    unawaited(
      ref.read(readyNotificationsStoreProvider).persist(scope, env).catchError((
        Object _,
      ) {
        if (_isStale(gen, scopeKey)) return;
        state = state.copyWith(degraded: true);
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Status reconciliation (the sheet-open sweep)
  // ---------------------------------------------------------------------------

  /// One CURSORLESS feed read over the server's 24h window that refreshes the
  /// current statuses of ALREADY-KNOWN identities. It never adds records,
  /// never alerts, never touches read/alerted, and never moves the durable
  /// discovery cursor. Failures are quiet (the sheet shows the degraded
  /// subtitle); local retention is also 24h, so every retained record stays
  /// eligible.
  Future<void> reconcileStatuses() {
    final existing = _reconcileInFlight;
    if (existing != null) return existing;
    final run = _reconcile();
    _reconcileInFlight = run;
    return run.whenComplete(() {
      if (identical(_reconcileInFlight, run)) _reconcileInFlight = null;
    });
  }

  Future<void> _reconcile() async {
    final scope = _scope();
    if (scope == null || _isDemo) return;
    final env = _envelope;
    if (env == null || !env.initialized || env.records.isEmpty) return;
    final gen = _generation;
    final scopeKey = _scopeKey;
    final repo = ref.read(readyFeedRepositoryProvider);
    final byIdentity = <String, PosReadyFeedRow>{};
    PosReadyCursor? cursor;
    var pages = 0;
    var hasMore = true;
    try {
      while (hasMore && pages < maxPagesPerCycle) {
        final page = await repo.fetch(cursor: cursor, limit: pageLimit);
        if (_isStale(gen, scopeKey)) return;
        for (final row in page.rows) {
          byIdentity[row.identityKey] = row;
        }
        cursor = page.nextCursor ?? cursor;
        hasMore = page.hasMore;
        pages++;
      }
    } on PosReadyFeedException {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(degraded: true);
      return;
    }
    final current = _envelope;
    if (current == null) return;
    var changed = false;
    final records = <PosReadyNotificationRecord>[];
    for (final r in current.records) {
      final row = byIdentity[r.identityKey];
      if (row == null ||
          (row.workUnitStatus == r.workUnitStatus &&
              row.parentOrderStatus == r.parentOrderStatus &&
              row.revision == r.revision)) {
        records.add(r);
      } else {
        changed = true;
        records.add(_refresh(r, row));
      }
    }
    if (!changed) return;
    final updated = PosReadyNotificationsEnvelope(
      initialized: current.initialized,
      bootstrapServerTs: current.bootstrapServerTs,
      cursor:
          current.cursor, // the discovery cursor is NOT this sweep's to move
      records: records,
    );
    try {
      await ref.read(readyNotificationsStoreProvider).persist(scope, updated);
    } on PosPersistenceException {
      if (_isStale(gen, scopeKey)) return;
      state = state.copyWith(degraded: true);
      return;
    }
    if (_isStale(gen, scopeKey)) return;
    _envelope = updated;
    _publish(updated);
  }
}

/// The ~7s foreground tick. NULL by default so a live repeating timer never
/// hangs `pumpAndSettle` in widget tests; `main.dart` overrides it.
final posReadyFeedPollIntervalProvider = Provider<Duration?>((ref) => null);

/// The banner auto-dismiss delay. NULL by default (tests dismiss explicitly);
/// `main.dart` overrides to ~8s.
final posReadyAlertAutoDismissProvider = Provider<Duration?>((ref) => null);

final posReadyNotificationsControllerProvider =
    NotifierProvider<
      PosReadyNotificationsController,
      PosReadyNotificationsState
    >(PosReadyNotificationsController.new);
