import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// RF-LIVE-002 — the production demo-mode safety guard.
///
/// `RuntimeConfig.isDemoModeMisconfigured` is true ONLY when a RELEASE build
/// selected DEMO mode while a VALID real Supabase config is ALSO present (an
/// accidental production demo). It is false for local/dev demo (no real config)
/// and for debug builds, so developer preview is unaffected. The release flag
/// and the config-presence check are injected here so the rule is unit-testable
/// without a real release build or `--dart-define`s.
void main() {
  group('RuntimeConfig.isDemoModeMisconfigured', () {
    test('release + demo + valid real config present => misconfigured', () {
      final config = RuntimeConfig.fromEnvironment(
        demoModeOverride: true,
        isReleaseBuild: true,
        realConfigPresent: () => true,
      );
      expect(config.isDemoMode, isTrue);
      expect(config.isDemoModeMisconfigured, isTrue);
    });

    test('DEBUG build + demo + real config present => NOT misconfigured '
        '(developer preview is unaffected)', () {
      final config = RuntimeConfig.fromEnvironment(
        demoModeOverride: true,
        isReleaseBuild: false,
        realConfigPresent: () => true,
      );
      expect(config.isDemoModeMisconfigured, isFalse);
    });

    test('release + demo + NO real config => NOT misconfigured '
        '(explicit local/hosted demo stays valid)', () {
      final config = RuntimeConfig.fromEnvironment(
        demoModeOverride: true,
        isReleaseBuild: true,
        realConfigPresent: () => false,
      );
      expect(config.isDemoMode, isTrue);
      expect(config.isDemoModeMisconfigured, isFalse);
    });

    test('real mode is never flagged as a demo misconfiguration', () {
      final config = RuntimeConfig.fromEnvironment(
        demoModeOverride: false,
        isReleaseBuild: true,
        realConfigPresent: () => true,
      );
      expect(config.isRealMode, isTrue);
      expect(config.isDemoModeMisconfigured, isFalse);
    });

    test('the release-build config read is SKIPPED off-release '
        '(short-circuit: realConfigPresent is never called)', () {
      var configReads = 0;
      final config = RuntimeConfig.fromEnvironment(
        demoModeOverride: true,
        isReleaseBuild: false,
        realConfigPresent: () {
          configReads++;
          return true;
        },
      );
      expect(config.isDemoModeMisconfigured, isFalse);
      expect(
        configReads,
        0,
        reason: '&& short-circuits before the config read',
      );
    });

    test('RuntimeConfig.test defaults isDemoModeMisconfigured to false', () {
      expect(
        RuntimeConfig.test(isDemoMode: true).isDemoModeMisconfigured,
        isFalse,
      );
    });
  });
}
