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

/// Optional observable state for recoverable online-call verification blocks.
abstract interface class DeviceSessionRecoveryManager {
  bool get protectedCallsBlocked;
  Stream<bool> get protectedCallBlockChanges;
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
    DateTime Function()? wallClock,
    bool Function()? recoveryRequired,
  }) : _heartbeat = heartbeat,
       _onResult = onResult,
       _interval = interval,
       _elapsed = elapsed ?? _monotonicClock(),
       _wallClock = wallClock ?? DateTime.now,
       _recoveryRequired = recoveryRequired ?? (() => false),
       _periodicTimer =
           periodicTimer ??
           ((delay, tick) => Timer.periodic(delay, (_) => tick()));

  final Future<DeviceHeartbeatResult> Function() _heartbeat;
  final void Function(DeviceHeartbeatResult) _onResult;
  final Duration _interval;
  final Duration Function() _elapsed;
  final DateTime Function() _wallClock;
  final bool Function() _recoveryRequired;
  Duration? _lastSuccess;
  DateTime? _lastSuccessWall;
  bool _recovering = false;
  int _recoverySeconds = 60;
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
    _lastSuccessWall = null;
    _recovering = _recoveryRequired();
    _recoverySeconds = 60;
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

  /// Re-arm after an external restore changes the guard, without an extra RPC.
  void refreshRecoveryState() {
    if (_disposed) return;
    final blocked = _recoveryRequired();
    if (_recovering == blocked) return;
    _recovering = blocked;
    _recoverySeconds = 60;
    _armTimer();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_mayRun) return;
    final delay = _recovering ? Duration(seconds: _recoverySeconds) : _interval;
    _timer = _periodicTimer(delay, () {
      _timer?.cancel();
      _timer = null;
      if (_recovering) {
        _recoverySeconds = (_recoverySeconds * 2).clamp(60, 300);
      }
      request();
    });
  }

  void _restart({bool resume = false}) {
    _timer?.cancel();
    _timer = null;
    _pending = false;
    if (!_mayRun) return;
    _armTimer();
    if (resume) {
      _requestOnResume();
    } else {
      request();
    }
  }

  void _requestOnResume() {
    final last = _lastSuccess;
    final wall = _lastSuccessWall;
    final monotonicDelta = last == null ? null : _elapsed() - last;
    final wallDelta = wall == null ? null : _wallClock().difference(wall);
    const fresh = Duration(seconds: 60);
    final recentlyVerified =
        monotonicDelta != null &&
        wallDelta != null &&
        monotonicDelta >= Duration.zero &&
        monotonicDelta < fresh &&
        wallDelta >= Duration.zero &&
        wallDelta < fresh;
    if (_recoveryRequired() || !recentlyVerified) request();
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
      if (result == DeviceHeartbeatResult.active) {
        _lastSuccess = _elapsed();
        _lastSuccessWall = _wallClock();
      }
      refreshRecoveryState();
      _onResult(result);
      _armTimer();
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
