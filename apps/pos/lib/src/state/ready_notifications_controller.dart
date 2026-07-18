import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ready_feed_repository.dart';
import '../data/ready_notifications_store.dart';
import '../data/sync_cursor_store.dart';
import 'order_sync_controller.dart' show posSyncClockProvider;
import 'pos_session.dart' show posSyncSessionProvider;
import 'pos_sync_scope_provider.dart';

/// PSC-001A — THE single owner of ready-feed polling and local notification
/// state. One timer, one in-flight discovery cycle, ONE SERIALIZED
/// mutation/persistence pipeline, one persisted envelope per scope.
///
/// Deliberately a SECOND coordinator beside [PosOrderSyncController], not a
/// bolt-on: the cadence differs (~7s vs ~30s), the gating differs (screen-wide
/// foreground vs orders-sheet visibility), and the cursor domain differs (the
/// ready keyset vs the order-sync keyset). Within ITS domain the same
/// discipline applies — no timers sprinkled through widgets, single-flight,
/// scope-generation fencing after every await, injected clock and interval.
///
/// HONESTY RULES:
///  * EVERY persisted-envelope mutation goes through the ONE serialized
///    pipeline ([_commit]): it REBASES on the latest envelope at commit time
///    (never a snapshot captured before an await), verifies the page's
///    request cursor against the current durable cursor, persists, and only
///    then swaps memory/state — a stale poll result can never overwrite a
///    newer read/alerted/status, and the cursor structurally cannot advance
///    past unstored rows;
///  * BOOTSTRAP IS RESUMABLE: `initialized` stays false across cycles while
///    the historical window drains (five pages per cycle, the envelope cursor
///    doubling as the durable bootstrap-progress cursor and the ORIGINAL
///    `bootstrapServerTs` frozen from the first response); it flips true only
///    on the server's `has_more == false`, and only then may the
///    genuinely-new (post-baseline) rows alert — a >500-row history can never
///    leak into discovery as a notification storm;
///  * a banner is exposed ONLY AFTER its records' `alerted=true` persisted
///    durably (a crash cannot re-present; a failed persist keeps it pending
///    and quietly retries);
///  * a terminal security refusal LATCHES the exact polling identity
///    (pinSessionId|deviceId|scopeKey): no timer, no resume, no manual
///    refresh may issue an RPC for that identity again — only a genuinely
///    NEW valid identity (the existing PIN/session flow) clears it; transport
///    failures never latch;
///  * background failures are QUIET (degraded flag, no banners); the ~7s poll
///    is the reconnect probe.
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
    this.securityBlocked = false,
    this.lastUpdatedAt,
    this.records = const [],
    this.activeAlert,
  });

  /// Bootstrap completed for the CURRENT scope (persisted marker). False
  /// also covers a PARTIALLY drained bootstrap still resuming across cycles.
  final bool initialized;

  /// The first load/bootstrap for this scope is in flight.
  final bool loading;

  /// Quietly degraded: the last poll/persist failed; records are the last
  /// good state; the poll keeps probing and recovers silently.
  final bool degraded;

  /// The TERMINAL typed session state: the server refused this exact polling
  /// identity (invalid session/device/permission). Polling is fenced until
  /// the existing PIN/session flow produces a new valid identity.
  final bool securityBlocked;
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
    bool? securityBlocked,
    DateTime? lastUpdatedAt,
    List<PosReadyNotificationRecord>? records,
    PosReadyAlert? activeAlert,
    bool clearActiveAlert = false,
  }) => PosReadyNotificationsState(
    initialized: initialized ?? this.initialized,
    loading: loading ?? this.loading,
    degraded: degraded ?? this.degraded,
    securityBlocked: securityBlocked ?? this.securityBlocked,
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

  /// FIX 2 — the ONE serialized mutation/persistence tail. Every envelope
  /// mutation chains onto it; network I/O stays OUTSIDE the queue and its
  /// result rebases on the latest envelope inside it.
  Future<void> _mutationTail = Future<void>.value();
  bool _promoting = false;
  bool _disposed = false;
  bool _foreground = true;

  /// Scope-generation fencing — plain fields advanced EAGERLY by the scope
  /// listener, re-checked after every await; a stale continuation drops
  /// itself silently.
  String? _scopeKey;
  int _generation = 0;

  /// The in-memory envelope — swapped ONLY inside [_commit] after a
  /// successful persist, so memory can never outrun durable state.
  PosReadyNotificationsEnvelope? _envelope;

  /// Queued alert ENTRIES (each = one cycle's new arrivals). Capped at
  /// [maxQueuedAlertEntries]; overflow collapses everything into one group.
  final List<List<PosReadyNotificationRecord>> _pendingEntries = [];
  int _alertSeq = 0;

  int _consecutiveFailures = 0;
  DateTime? _lastAttemptAt;
  DateTime? _lastUpdatedAt;

  /// FIX 5 — the exact identity a terminal security refusal belongs to.
  String? _securityLatchIdentity;

  /// The production tick (main.dart overrides the interval provider).
  static const Duration defaultPollInterval = Duration(seconds: 7);

  /// After [backoffAfterFailures] consecutive failures, attempts slow to one
  /// per [backoffInterval]; the first success restores the normal cadence.
  static const int backoffAfterFailures = 3;
  static const Duration backoffInterval = Duration(seconds: 30);

  /// One cycle drains at most this many pages; backlog (bootstrap included)
  /// continues on the next tick — never an unbounded drain loop.
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
    // FIX 5: a SESSION change (same scope, new PIN) must rebuild so the latch
    // re-evaluates against the new identity and polling resumes.
    ref.watch(posSyncSessionProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      _autoDismiss?.cancel();
      _autoDismiss = null;
    });
    _clearLatchIfIdentityChanged();
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
    // A SAME-SCOPE rebuild (e.g. a session change) keeps the loaded records —
    // blanking the bell/history because a provider rebuilt would be a lie.
    final env = _envelope;
    return env == null
        ? const PosReadyNotificationsState()
        : PosReadyNotificationsState(
            initialized: env.initialized,
            records: env.records,
            lastUpdatedAt: _lastUpdatedAt,
            securityBlocked: _latched,
          );
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
    _lastUpdatedAt = null;
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
  // FIX 5 — the terminal security latch
  // ---------------------------------------------------------------------------

  /// The immutable polling identity every RPC belongs to.
  String? _pollingIdentity() {
    final session = ref.read(posSyncSessionProvider);
    final key = _scopeKey;
    if (session == null || key == null) return null;
    return '${session.pinSessionId}|${session.deviceId}|$key';
  }

  /// Latched = the CURRENT identity is the exact one the server terminally
  /// refused. Resume, timer ticks, and manual refresh all fence on this; a
  /// transport failure never sets it.
  bool get _latched =>
      _securityLatchIdentity != null &&
      _securityLatchIdentity == _pollingIdentity();

  /// Whether polling is terminally fenced for the current identity
  /// (test seam).
  @visibleForTesting
  bool get isSecurityLatched => _latched;

  void _clearLatchIfIdentityChanged() {
    final latch = _securityLatchIdentity;
    if (latch == null) return;
    final id = _pollingIdentity();
    // Only a DIFFERENT valid identity clears the latch — never a resume, a
    // tick, a manual refresh, or a transport error.
    if (id != null && id != latch) {
      _securityLatchIdentity = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle (driven by PosSyncLifecycle — this controller owns no observer)
  // ---------------------------------------------------------------------------

  /// The app/page came to the foreground (also the startup signal).
  void onResume() {
    _foreground = true;
    _clearLatchIfIdentityChanged();
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
    if (_timer != null ||
        !_foreground ||
        _scopeKey == null ||
        _isDemo ||
        _latched) {
      return;
    }
    final interval = ref.read(posReadyFeedPollIntervalProvider);
    if (interval == null) return;
    _timer = Timer.periodic(interval, (_) {
      if (_inFlight != null) return; // no overlapping cycles
      if (_latched) return; // terminally fenced identity
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
  // FIX 2 — the serialized mutation/persistence pipeline
  // ---------------------------------------------------------------------------

  Future<T> _mutate<T>(Future<T> Function() action) {
    final run = _mutationTail.then((_) => action());
    _mutationTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  bool _sameCursor(PosReadyCursor? a, PosReadyCursor? b) =>
      a?.readyAt == b?.readyAt &&
      a?.workUnitType == b?.workUnitType &&
      a?.id == b?.id;

  /// THE one envelope commit. Inside the serialized mutation it REBASES on
  /// the latest envelope (never a pre-await snapshot), optionally verifies a
  /// page's request cursor against the current durable cursor (a stale page
  /// result gets ZERO side effects), persists, and only then swaps
  /// memory/state. Returns the committed envelope; null = skipped
  /// (stale/precondition/no scope). A persistence failure marks the quiet
  /// degraded state and RETHROWS [PosPersistenceException] so the calling
  /// cycle can account for it exactly once.
  Future<PosReadyNotificationsEnvelope?> _commit(
    int gen,
    String? scopeKey, {
    PosReadyCursor? expectedCursor,
    bool enforceCursorPrecondition = false,
    bool requireUninitialized = false,
    required PosReadyNotificationsEnvelope Function(
      PosReadyNotificationsEnvelope current,
    )
    build,
  }) => _mutate(() async {
    if (_isStale(gen, scopeKey)) return null;
    final scope = _scope();
    if (scope == null) return null;
    final current = _envelope ?? PosReadyNotificationsEnvelope.empty;
    if (enforceCursorPrecondition) {
      if (!_sameCursor(current.cursor, expectedCursor)) return null;
      if (requireUninitialized && current.initialized) return null;
    }
    final next = build(current);
    try {
      await ref.read(readyNotificationsStoreProvider).persist(scope, next);
    } on PosPersistenceException {
      if (!_isStale(gen, scopeKey)) {
        state = state.copyWith(loading: false, degraded: true);
      }
      rethrow;
    }
    if (_isStale(gen, scopeKey)) return null;
    _envelope = next;
    _publish(next);
    return next;
  });

  // ---------------------------------------------------------------------------
  // The refresh cycle
  // ---------------------------------------------------------------------------

  /// One discovery/bootstrap cycle now. Manual callers (refresh button,
  /// resume, scope restoration) bypass the backoff gate — but NEVER the
  /// terminal security latch; concurrent callers join the in-flight cycle.
  Future<void> refreshNow() {
    final existing = _inFlight;
    if (existing != null) return existing;
    if (_latched) return Future.value();
    final run = _run();
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  Future<void> _run() async {
    final scope = _scope();
    if (scope == null || _isDemo || _latched) return;
    final gen = _generation;
    final scopeKey = _scopeKey;
    _lastAttemptAt = _now();

    if (_envelope == null) {
      state = state.copyWith(loading: state.records.isEmpty);
      // The initial load joins the SAME serialized pipeline — a commit can
      // never interleave with it.
      final ok = await _mutate(() async {
        if (_isStale(gen, scopeKey) || _envelope != null) {
          return !_isStale(gen, scopeKey);
        }
        final PosReadyNotificationsEnvelope? loaded;
        try {
          loaded = await ref.read(readyNotificationsStoreProvider).load(scope);
        } catch (_) {
          return false;
        }
        if (_isStale(gen, scopeKey)) return false;
        _envelope = loaded ?? PosReadyNotificationsEnvelope.empty;
        _publish(_envelope!, loading: !_envelope!.initialized);
        return true;
      });
      if (!ok || _isStale(gen, scopeKey)) {
        if (!_isStale(gen, scopeKey)) _failCycle();
        return;
      }
    }

    try {
      if (!_envelope!.initialized) {
        await _bootstrap(gen, scopeKey);
      } else {
        await _poll(gen, scopeKey);
      }
    } on PosReadyFeedException catch (e) {
      if (_isStale(gen, scopeKey)) return;
      if (e.failure == PosReadyFeedFailure.session) {
        // FIX 5: latch the EXACT refused identity and stop. Recovery belongs
        // to the existing PIN/session flow — a new valid identity clears the
        // latch; resume/tick/manual refresh never do.
        _securityLatchIdentity = _pollingIdentity();
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(
          loading: false,
          degraded: true,
          securityBlocked: true,
        );
        _consecutiveFailures++;
        return;
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
    _lastUpdatedAt = _now();
    _publish(_envelope!, degraded: false, lastUpdatedAt: _lastUpdatedAt);
    await _promoteNextAlert();
  }

  void _failCycle() {
    _consecutiveFailures++;
    state = state.copyWith(loading: false, degraded: true);
  }

  /// FIX 1 — RESUMABLE bootstrap. The FIRST response of a FRESH bootstrap
  /// freezes `bootstrapServerTs`; every page (this cycle and every later
  /// resume cycle) classifies against that ORIGINAL baseline and commits
  /// through the pipeline with `initialized = !page.hasMore` — so a >500-row
  /// history stays `initialized=false` across cycles, resumes from the
  /// persisted progress cursor (never a null refetch), and can never leak
  /// into normal discovery as an alert storm. Alerts (only the genuinely-new
  /// post-baseline rows, still unalerted) queue ONLY after completion.
  Future<void> _bootstrap(int gen, String? scopeKey) async {
    final repo = ref.read(readyFeedRepositoryProvider);
    var current = _envelope!;
    var baselineTs = current.bootstrapServerTs;
    var pages = 0;
    var hasMore = true;
    while (hasMore && pages < maxPagesPerCycle) {
      final requestCursor = current.cursor;
      final page = await repo.fetch(cursor: requestCursor, limit: pageLimit);
      if (_isStale(gen, scopeKey)) return;
      baselineTs ??= page.serverTs;
      final ts = baselineTs;
      final committed = await _commit(
        gen,
        scopeKey,
        expectedCursor: requestCursor,
        enforceCursorPrecondition: true,
        requireUninitialized: true,
        build: (cur) {
          final baseline = DateTime.parse(ts);
          final byIdentity = <String, PosReadyNotificationRecord>{
            for (final r in cur.records) r.identityKey: r,
          };
          for (final row in page.rows) {
            final existing = byIdentity[row.identityKey];
            if (existing != null) {
              byIdentity[row.identityKey] = _refresh(existing, row);
            } else {
              final historical = !row.readyAtTime.isAfter(baseline);
              byIdentity[row.identityKey] = _recordFrom(
                row,
                read: historical,
                alerted: historical,
              );
            }
          }
          return PosReadyNotificationsEnvelope(
            initialized: !page.hasMore,
            bootstrapServerTs: ts,
            cursor: page.nextCursor ?? cur.cursor,
            records: _prune(byIdentity.values),
          );
        },
      );
      if (committed == null) return; // stale/precondition — resume next cycle
      current = committed;
      hasMore = page.hasMore;
      pages++;
    }
    if (current.initialized) _queueUnalerted(current);
    // else: the partial progress (initialized=false, ORIGINAL baseline, the
    // advanced cursor, accumulated records) is durable; the next cycle
    // resumes from exactly here. No alerts until completion.
  }

  /// NORMAL polling: tuple-cursor pages, each committed through the pipeline
  /// (rebased, cursor-preconditioned, persisted BEFORE the cursor advances);
  /// a new identity is unread and queues an alert only after its envelope
  /// persisted; a re-seen identity only refreshes statuses/context and keeps
  /// read/alerted sticky.
  Future<void> _poll(int gen, String? scopeKey) async {
    final repo = ref.read(readyFeedRepositoryProvider);
    var current = _envelope!;
    var pages = 0;
    var hasMore = true;
    while (hasMore && pages < maxPagesPerCycle) {
      final requestCursor = current.cursor;
      final page = await repo.fetch(cursor: requestCursor, limit: pageLimit);
      if (_isStale(gen, scopeKey)) return;
      final committed = await _commit(
        gen,
        scopeKey,
        expectedCursor: requestCursor,
        enforceCursorPrecondition: true,
        build: (cur) {
          final byIdentity = <String, PosReadyNotificationRecord>{
            for (final r in cur.records) r.identityKey: r,
          };
          for (final row in page.rows) {
            final existing = byIdentity[row.identityKey];
            byIdentity[row.identityKey] = existing == null
                ? _recordFrom(row, read: false, alerted: false)
                : _refresh(existing, row);
          }
          return PosReadyNotificationsEnvelope(
            initialized: true,
            bootstrapServerTs: cur.bootstrapServerTs,
            cursor: page.nextCursor ?? cur.cursor,
            records: _prune(byIdentity.values),
          );
        },
      );
      if (committed == null) return;
      current = committed;
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
  // Alert queue (FIX 3: alerted persists BEFORE the banner shows)
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

  /// Shows the next queued entry ONLY after its records' `alerted=true`
  /// persisted durably (grouped entries persist every identity in the same
  /// envelope write, then show ONE banner). A failed persist keeps the entry
  /// pending — quietly degraded, retried on the next successful cycle —
  /// and shows NOTHING.
  Future<void> _promoteNextAlert() async {
    if (_promoting || state.activeAlert != null || _pendingEntries.isEmpty) {
      return;
    }
    _promoting = true;
    try {
      final gen = _generation;
      final scopeKey = _scopeKey;
      final items = List.of(_pendingEntries.first);
      final ids = {for (final r in items) r.identityKey};
      final PosReadyNotificationsEnvelope? committed;
      try {
        committed = await _commit(
          gen,
          scopeKey,
          build: (cur) => PosReadyNotificationsEnvelope(
            initialized: cur.initialized,
            bootstrapServerTs: cur.bootstrapServerTs,
            cursor: cur.cursor,
            records: [
              for (final r in cur.records)
                ids.contains(r.identityKey) ? r.copyWith(alerted: true) : r,
            ],
          ),
        );
      } on PosPersistenceException {
        return; // still pending; degraded already surfaced; retried later
      }
      if (committed == null || _isStale(gen, scopeKey)) return;
      // The queue may have been cleared (markAllRead) while persisting.
      if (_pendingEntries.isEmpty ||
          !identical(_pendingEntries.first.first, items.first)) {
        return;
      }
      _pendingEntries.removeAt(0);
      final alert = PosReadyAlert(id: ++_alertSeq, items: items);
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
    } finally {
      _promoting = false;
    }
  }

  /// DISMISSAL IS NOT READ — the banner goes away; the unread badge stays.
  void dismissAlert() {
    if (state.activeAlert == null) return;
    _autoDismiss?.cancel();
    _autoDismiss = null;
    state = state.copyWith(clearActiveAlert: true);
    unawaited(_promoteNextAlert());
  }

  // ---------------------------------------------------------------------------
  // Read state (all through the serialized pipeline)
  // ---------------------------------------------------------------------------

  /// Marks ONE notification read (an intentional open).
  void markRead(String identityKey) {
    final gen = _generation;
    final scopeKey = _scopeKey;
    unawaited(
      _commit(
        gen,
        scopeKey,
        build: (cur) => PosReadyNotificationsEnvelope(
          initialized: cur.initialized,
          bootstrapServerTs: cur.bootstrapServerTs,
          cursor: cur.cursor,
          records: [
            for (final r in cur.records)
              r.identityKey == identityKey
                  ? r.copyWith(read: true, alerted: true)
                  : r,
          ],
        ),
      ).catchError((Object _) => null),
    );
  }

  /// Marks every retained record read; the explicit "I know" also clears the
  /// visible alert and the pending queue.
  void markAllRead() {
    _pendingEntries.clear();
    _autoDismiss?.cancel();
    _autoDismiss = null;
    state = state.copyWith(clearActiveAlert: true);
    final gen = _generation;
    final scopeKey = _scopeKey;
    unawaited(
      _commit(
        gen,
        scopeKey,
        build: (cur) => PosReadyNotificationsEnvelope(
          initialized: cur.initialized,
          bootstrapServerTs: cur.bootstrapServerTs,
          cursor: cur.cursor,
          records: [
            for (final r in cur.records) r.copyWith(read: true, alerted: true),
          ],
        ),
      ).catchError((Object _) => null),
    );
  }

  // ---------------------------------------------------------------------------
  // Status reconciliation (the sheet-open sweep)
  // ---------------------------------------------------------------------------

  /// One CURSORLESS feed read over the server's 24h window that refreshes the
  /// current statuses of ALREADY-KNOWN identities. It never adds records,
  /// never alerts, never touches read/alerted, and never moves the durable
  /// discovery cursor. Failures are quiet; local retention is also 24h, so
  /// every retained record stays eligible.
  Future<void> reconcileStatuses() {
    final existing = _reconcileInFlight;
    if (existing != null) return existing;
    if (_latched) return Future.value();
    final run = _reconcile();
    _reconcileInFlight = run;
    return run.whenComplete(() {
      if (identical(_reconcileInFlight, run)) _reconcileInFlight = null;
    });
  }

  Future<void> _reconcile() async {
    final scope = _scope();
    if (scope == null || _isDemo || _latched) return;
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
    try {
      await _commit(
        gen,
        scopeKey,
        build: (cur) {
          final records = <PosReadyNotificationRecord>[];
          for (final r in cur.records) {
            final row = byIdentity[r.identityKey];
            records.add(row == null ? r : _refresh(r, row));
          }
          return PosReadyNotificationsEnvelope(
            initialized: cur.initialized,
            bootstrapServerTs: cur.bootstrapServerTs,
            // The discovery cursor is NOT this sweep's to move.
            cursor: cur.cursor,
            records: records,
          );
        },
      );
    } on PosPersistenceException {
      // degraded already surfaced by _commit
    }
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
