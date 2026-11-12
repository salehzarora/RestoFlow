// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: a Zone that captures the timers a call
// creates, so a test reads the exact deadline a transport armed and fires it on
// demand - no real waiting and no fake-clock package.
import 'dart:async';

/// A captured one-shot [Timer]; it runs only when a test calls [fire].
final class CapturedTimer implements Timer {
  CapturedTimer._(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  /// Runs the callback as if the deadline had passed.
  void fire() {
    if (!_active) throw StateError('the captured timer is no longer active');
    _active = false;
    _tick++;
    _callback();
  }
}

/// Runs [body] in a Zone that captures every non-zero one-shot timer into
/// [timers] and every periodic timer into [periodic] (neither ever runs by
/// itself). Zero-duration timers - plain event-loop hops - stay real.
R runCapturingTimers<R>(
  List<CapturedTimer> timers,
  R Function() body, {
  List<Duration>? periodic,
}) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration <= Duration.zero) {
        return parent.createTimer(zone, duration, callback);
      }
      final timer = CapturedTimer._(duration, callback);
      timers.add(timer);
      return timer;
    },
    createPeriodicTimer: (self, parent, zone, period, callback) {
      periodic?.add(period);
      final timer = CapturedTimer._(period, () {});
      timer.cancel();
      return timer;
    },
  ),
);
