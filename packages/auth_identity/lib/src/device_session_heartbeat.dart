import 'dart:async';

import 'device_context.dart';

/// BIZBOT device activity never establishes or extends a human PIN session.
enum DeviceHeartbeatResult {
  active,
  unsupported,
  offline,
  unavailable,
  invalidSession,
  superseded,
}

/// A pairing transition, without the bearer token. Invalidations are explicit
/// server verdicts; a local unpair/re-pair only cancels the previous schedule.
class DeviceSessionChange {
  const DeviceSessionChange(
    this.context, {
    this.invalidSession = false,
    this.unavailable = false,
    this.expectedDeviceType,
  });
  final DeviceContext? context;
  final bool invalidSession;
  final bool unavailable;
  final String? expectedDeviceType;
}

abstract interface class DeviceSessionHeartbeatManager {
  DeviceContext? get activeDevice;
  Stream<DeviceSessionChange> get sessionChanges;
  Future<DeviceHeartbeatResult> heartbeat();
}

/// One foreground schedule per app, above its PIN and device gates. HTTP work
/// already in flight cannot be unsent, but a superseded result cannot affect a
/// new pairing. At most one follow-up is queued across resume/re-pair events.
class DeviceSessionHeartbeatScheduler {
  DeviceSessionHeartbeatScheduler({
    required Future<DeviceHeartbeatResult> Function() heartbeat,
    required void Function(DeviceHeartbeatResult) onResult,
    Duration interval = const Duration(minutes: 15),
    Timer Function(Duration, void Function())? periodicTimer,
    Duration Function()? elapsed,
  }) : _heartbeat = heartbeat,
       _onResult = onResult,
       _interval = interval,
       _elapsed = elapsed ?? _monotonicClock(),
       _periodicTimer =
           periodicTimer ??
           ((delay, tick) => Timer.periodic(delay, (_) => tick()));

  final Future<DeviceHeartbeatResult> Function() _heartbeat;
  final void Function(DeviceHeartbeatResult) _onResult;
  final Duration _interval;
  final Duration Function() _elapsed;
  Duration? _lastSuccess;
  static Duration Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  final Timer Function(Duration, void Function()) _periodicTimer;
  Timer? _timer;
  bool _active = false;
  bool _foreground = false;
  bool _disposed = false;
  bool _inFlight = false;
  bool _pending = false;
  int _generation = 0;

  void replaceSession({required bool active}) {
    _lastSuccess = null;
    _generation++;
    _active = active;
    _restart();
  }

  void setForeground(bool foreground, {bool resume = false}) {
    if (_disposed) return;
    if (_foreground == foreground) {
      if (foreground && resume) _requestOnResume();
      return;
    }
    _generation++;
    _foreground = foreground;
    _restart(resume: foreground);
  }

  bool get _mayRun => !_disposed && _active && _foreground;

  void _restart({bool resume = false}) {
    _timer?.cancel();
    _timer = null;
    _pending = false;
    if (!_mayRun) return;
    _timer = _periodicTimer(_interval, request);
    if (resume) {
      _requestOnResume();
    } else {
      request();
    }
  }

  void _requestOnResume() {
    final last = _lastSuccess;
    if (last == null || _elapsed() - last >= const Duration(seconds: 60))
      request();
  }

  void request() {
    if (!_mayRun) return;
    if (_inFlight) {
      _pending = true;
      return;
    }
    _inFlight = true;
    final generation = _generation;
    unawaited(_run(generation));
  }

  Future<void> _run(int generation) async {
    DeviceHeartbeatResult result;
    try {
      result = await _heartbeat();
    } catch (_) {
      result = DeviceHeartbeatResult.offline;
    }
    _inFlight = false;
    if (_mayRun && generation == _generation) {
      if (result == DeviceHeartbeatResult.active) _lastSuccess = _elapsed();
      _onResult(result);
    }
    if (_pending && _mayRun) {
      _pending = false;
      request();
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _pending = false;
    _timer?.cancel();
    _timer = null;
  }
}
