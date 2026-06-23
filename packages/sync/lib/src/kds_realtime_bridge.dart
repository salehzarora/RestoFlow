import 'dart:async';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'kds_sync_state.dart';

/// Bridges a realtime [InvalidationSource] to the polling [KdsSyncSource]
/// (RF-058): on each hint it triggers a (debounced) `refresh()` → `sync_pull`.
///
/// It is a thin nudge layer — it applies NO data and parses NO business rows;
/// `sync_pull` remains the source of truth. Polling is untouched, so if realtime
/// is absent/errors/drops the KDS keeps updating on its poll cadence. When the
/// coordinator reaches `reauthRequired` (a revoked/expired session), the bridge
/// stops listening and disposes the source so no further refreshes are issued.
class KdsRealtimeBridge {
  KdsRealtimeBridge({
    required InvalidationSource source,
    required KdsSyncSource coordinator,
    Duration debounce = const Duration(milliseconds: 250),
    Future<void> Function(Duration)? delay,
  }) : _source = source,
       _coordinator = coordinator,
       _debounce = debounce,
       _delay = delay ?? Future<void>.delayed;

  final InvalidationSource _source;
  final KdsSyncSource _coordinator;
  final Duration _debounce;
  final Future<void> Function(Duration) _delay;

  StreamSubscription<InvalidationHint>? _hintSub;
  StreamSubscription<KdsSyncState>? _stateSub;
  bool _started = false;
  bool _stopped = false;
  bool _disposed = false;
  bool _refreshScheduled = false;

  /// The number of refreshes the bridge has issued (test-observable).
  int refreshCount = 0;

  /// Whether the bridge has stopped (after reauth or dispose).
  bool get isStopped => _stopped;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    // If the session is already revoked/expired, do not start listening.
    if (_coordinator.state.status == KdsSyncStatus.reauthRequired) {
      await stop();
      return;
    }
    await _source.start();
    _hintSub = _source.hints.listen(
      _onHint,
      onError: (_) {
        /* realtime error -> polling continues; ignore */
      },
    );
    _stateSub = _coordinator.states.listen((s) {
      if (s.status == KdsSyncStatus.reauthRequired) {
        unawaited(stop());
      }
    });
  }

  void _onHint(InvalidationHint hint) {
    // Coalesce a storm: while a refresh is already scheduled, drop extra hints.
    if (_stopped || _disposed || _refreshScheduled) return;
    _refreshScheduled = true;
    _delay(_debounce).then((_) {
      _refreshScheduled = false;
      if (_stopped || _disposed) return;
      refreshCount++;
      unawaited(_coordinator.refresh());
    });
  }

  /// Stop listening + dispose the source (no further refreshes). Idempotent.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _hintSub?.cancel();
    _hintSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _source.dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
  }
}
