import 'dart:async';

import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'backoff.dart';
import 'kds_sync_state.dart';
import 'sync_cursor_store.dart';

/// The non-financial kitchen entity set RF-063 ever requests (approved decision
/// A5 — a financial entity is never requested, so the kitchen money-redaction
/// posture holds even before the server role check).
const List<String> kKdsPullEntities = [
  'orders',
  'order_items',
  'order_item_modifiers',
];

/// A pull-only KDS sync coordinator (RF-063).
///
/// Pulls `app.sync_pull` on start, on a poll timer, and on manual refresh;
/// drains `has_more` pages; advances per-entity `(updated_at, id)` cursors; and
/// emits a [KdsSyncState] stream. It implements NO push/outbox. Realtime is not
/// used (DECISION D-010). The poll tick source and the backoff delay are
/// injectable so tests are fully deterministic with no real clock.
class KdsSyncCoordinator implements KdsSyncSource {
  KdsSyncCoordinator({
    required SyncPullApi api,
    required SyncSession session,
    SyncCursorStore? cursorStore,
    List<String> entities = kKdsPullEntities,
    Duration pollInterval = const Duration(seconds: 5),
    int limit = 500,
    BackoffConfig backoff = const BackoffConfig(),
    Stream<void>? ticks,
    Future<void> Function(Duration)? delay,
    double Function()? random,
  }) : _api = api,
       _session = session,
       _cursors = cursorStore ?? InMemorySyncCursorStore(),
       _entities = List.unmodifiable(entities),
       _pollInterval = pollInterval,
       _limit = limit,
       _backoff = backoff,
       _ticks = ticks,
       _delay = delay ?? Future<void>.delayed,
       _random = random;

  final SyncPullApi _api;
  final SyncSession _session;
  final SyncCursorStore _cursors;
  final List<String> _entities;
  final Duration _pollInterval;
  final int _limit;
  final BackoffConfig _backoff;
  final Stream<void>? _ticks;
  final Future<void> Function(Duration) _delay;
  final double Function()? _random;

  final StreamController<KdsSyncState> _controller =
      StreamController<KdsSyncState>.broadcast();

  /// Accumulated rows: entity -> id -> raw row (tombstones removed).
  final Map<String, Map<String, Map<String, dynamic>>> _rows = {};

  KdsSyncState _state = KdsSyncState.initial;
  StreamSubscription<void>? _tickSub;
  bool _started = false;
  bool _stopped = false;
  bool _disposed = false;
  bool _cycleInFlight = false;
  bool _retryPending = false;
  int _transientAttempts = 0;

  /// Safety cap on pages drained in one cycle (prevents a runaway loop).
  static const int _maxDrainPages = 1000;

  @override
  KdsSyncState get state => _state;

  @override
  Stream<KdsSyncState> get states => _controller.stream;

  void _emit(KdsSyncState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await _pullCycle();
    if (_stopped || _disposed) return;
    final tickStream = _ticks ?? Stream<void>.periodic(_pollInterval);
    _tickSub = tickStream.listen((_) => _onTick());
  }

  void _onTick() {
    if (_stopped || _disposed || _cycleInFlight || _retryPending) return;
    unawaited(_pullCycle());
  }

  @override
  Future<void> refresh() async {
    // A manual refresh deliberately bypasses any pending backoff (the user wants
    // fresh data now), so — unlike _onTick — it does NOT gate on _retryPending.
    // _pullCycle's own _cycleInFlight guard still prevents overlapping pulls.
    if (_stopped || _disposed || _cycleInFlight) return;
    await _pullCycle();
  }

  Future<void> _pullCycle() async {
    if (_cycleInFlight || _stopped || _disposed) return;
    _cycleInFlight = true;
    try {
      if (!_state.hasData) {
        _emit(
          _state.copyWith(status: KdsSyncStatus.loading, clearFailure: true),
        );
      }
      var pages = 0;
      while (pages < _maxDrainPages) {
        pages++;
        final request = SyncPullRequest(
          entities: List.of(_entities),
          cursors: _cursors.snapshot(),
          limit: _limit,
        );
        final result = await _api.pull(_session, request);
        if (_disposed) return;
        switch (result) {
          case Success(:final value):
            final advanced = _applyPages(value);
            _transientAttempts = 0;
            _emit(
              KdsSyncState(
                status: KdsSyncStatus.data,
                entities: _flatten(),
                serverTs: value.serverTs,
              ),
            );
            // Only keep draining while a cursor actually advanced. has_more with
            // no cursor progress (a misbehaving server) would otherwise re-pull
            // the identical request; stop instead of hammering it (A5).
            if (_anyHasMore(value) && advanced) continue;
            return;
          case Failure(:final failure):
            _onFailure(failure);
            return;
        }
      }
    } finally {
      _cycleInFlight = false;
    }
  }

  void _onFailure(SyncFailure failure) {
    switch (failure) {
      case ReauthRequiredFailure():
        _emit(
          _state.copyWith(
            status: KdsSyncStatus.reauthRequired,
            failureMessage: failure.message,
          ),
        );
        _stopPolling();
      case TransientFailure():
        // Keep the last successful data; mark stale; back off and retry.
        _emit(
          _state.copyWith(
            status: KdsSyncStatus.offlineStale,
            failureMessage: failure.message,
          ),
        );
        _scheduleRetry();
      case ServerFailure() || InvalidResponseFailure():
        // Non-transient, non-auth: keep prior data, no auto-retry (next tick/
        // refresh will try again).
        _emit(
          _state.copyWith(
            status: KdsSyncStatus.error,
            failureMessage: failure.message,
          ),
        );
    }
  }

  void _scheduleRetry() {
    if (_stopped || _disposed || _retryPending) return;
    _retryPending = true;
    final attempt = _transientAttempts;
    _transientAttempts++;
    final wait = _backoff.delayFor(attempt, random: _random);
    _delay(wait).then((_) {
      _retryPending = false;
      if (_stopped || _disposed) return;
      unawaited(_pullCycle());
    });
  }

  /// Applies each page's rows + cursor. Returns whether ANY entity's cursor
  /// advanced to a new value (used to decide whether draining should continue).
  bool _applyPages(SyncPullResponse resp) {
    var advanced = false;
    resp.changes.entities.forEach((entity, page) {
      final byId = _rows.putIfAbsent(entity, () => {});
      for (final row in page.rows) {
        final id = row['id'];
        if (id is! String) {
          continue; // defensive: every operational row has a uuid id
        }
        if (row['deleted_at'] != null) {
          byId.remove(id); // tombstone (D-020): drop locally
        } else {
          byId[id] = row;
        }
      }
      final cursor = page.nextCursor;
      if (cursor != null && cursor != _cursors.cursorFor(entity)) {
        _cursors.setCursor(entity, cursor);
        advanced = true;
      }
    });
    return advanced;
  }

  bool _anyHasMore(SyncPullResponse resp) =>
      resp.changes.entities.values.any((p) => p.hasMore);

  Map<String, List<Map<String, dynamic>>> _flatten() => {
    for (final entry in _rows.entries) entry.key: entry.value.values.toList(),
  };

  void _stopPolling() {
    _stopped = true;
    _tickSub?.cancel();
    _tickSub = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stopped = true;
    await _tickSub?.cancel();
    _tickSub = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
