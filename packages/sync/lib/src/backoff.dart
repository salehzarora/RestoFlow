import 'dart:math';

/// Exponential-backoff configuration for transient pull failures (RF-063).
///
/// Defaults follow the proposed OFFLINE_SYNC §6 (Q-018) schedule: base 2s,
/// ×2 per attempt, capped at 5 minutes, with full jitter. The randomness source
/// is injectable so tests are deterministic.
class BackoffConfig {
  const BackoffConfig({
    this.base = const Duration(seconds: 2),
    this.multiplier = 2.0,
    this.max = const Duration(minutes: 5),
    this.jitter = true,
  });

  /// First-retry delay.
  final Duration base;

  /// Exponential factor applied per attempt.
  final double multiplier;

  /// Cap on a single inter-attempt delay.
  final Duration max;

  /// Whether to apply full jitter (random in `[0, ceiling]`).
  final bool jitter;

  /// The delay for a zero-based [attempt] (0 = first retry).
  ///
  /// `random` returns a value in `[0,1)` (defaults to [Random]); with jitter the
  /// delay is `random() * ceiling`, otherwise it is exactly `ceiling`. The
  /// uncapped ceiling is `base * multiplier^attempt`, clamped to [max].
  Duration delayFor(int attempt, {double Function()? random}) {
    final factor = pow(multiplier, attempt).toDouble();
    final rawMicros = base.inMicroseconds * factor;
    final cappedMicros = rawMicros > max.inMicroseconds
        ? max.inMicroseconds.toDouble()
        : rawMicros;
    if (!jitter) return Duration(microseconds: cappedMicros.round());
    final rng = (random ?? Random().nextDouble)();
    return Duration(microseconds: (cappedMicros * rng).round());
  }
}
