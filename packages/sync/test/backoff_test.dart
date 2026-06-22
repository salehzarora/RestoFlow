import 'package:restoflow_sync/restoflow_sync.dart';
import 'package:test/test.dart';

/// RF-063: exponential backoff schedule (OFFLINE_SYNC §6 / Q-018 defaults).
void main() {
  group('BackoffConfig.delayFor', () {
    test('no-jitter schedule is base * multiplier^attempt, capped at max', () {
      const cfg = BackoffConfig(jitter: false);
      expect(cfg.delayFor(0), const Duration(seconds: 2));
      expect(cfg.delayFor(1), const Duration(seconds: 4));
      expect(cfg.delayFor(2), const Duration(seconds: 8));
      expect(cfg.delayFor(3), const Duration(seconds: 16));
      // Far-out attempts clamp to the 5-minute ceiling.
      expect(cfg.delayFor(20), const Duration(minutes: 5));
    });

    test('full jitter scales the ceiling by the injected random in [0,1)', () {
      const cfg = BackoffConfig();
      expect(cfg.delayFor(1, random: () => 1.0), const Duration(seconds: 4));
      expect(cfg.delayFor(1, random: () => 0.0), Duration.zero);
      expect(cfg.delayFor(1, random: () => 0.5), const Duration(seconds: 2));
    });
  });
}
