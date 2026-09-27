import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_contrast.dart';

/// STOREFRONT-PUBLISH-001 — the Dart port of the storefront's primary-colour
/// rule (`inspectPrimary` in storefront/src/theme/sanitize.ts over
/// contrast.ts, AA = 4.5, glass = primary at 74% over white). The expected
/// values were computed by running a verbatim JS copy of that TS logic
/// (Node 22) — they are the storefront's own numbers, not re-derived here.
const _eps = 1e-9;

void main() {
  group('inspectStorefrontPrimary matches the TS verdicts', () {
    // (primary, supported, heroRatio, glassRatio, glass hex, issue)
    final cases =
        <(String, bool, double, double, String?, StorefrontPrimaryIssue?)>[
          (
            '#13322a',
            true,
            13.839793066118926,
            6.080246549552479,
            '#506761',
            null,
          ),
          ('#000000', true, 21, 10.049743700462349, '#424242', null),
          (
            '#7a1f1f',
            true,
            10.277515334347315,
            5.241057624121327,
            '#9d5959',
            null,
          ),
          (
            '#ffffff',
            false,
            1,
            1,
            '#ffffff',
            StorefrontPrimaryIssue.heroBelowAa,
          ),
          (
            '#e07b2c',
            false,
            2.9833732045669583,
            2.2259628163934204,
            '#e89d63',
            StorefrontPrimaryIssue.heroBelowAa,
          ),
          (
            '#1D4ED8',
            false,
            6.701618401398807,
            3.891627846061611,
            '#587ce2',
            StorefrontPrimaryIssue.glassBelowAa,
          ),
          (
            '#b8460f',
            false,
            5.35573438220564,
            3.381724711360369,
            '#ca764d',
            StorefrontPrimaryIssue.glassBelowAa,
          ),
          (
            '#2f6f5e',
            false,
            5.905057256985911,
            3.4175143940462918,
            '#659488',
            StorefrontPrimaryIssue.glassBelowAa,
          ),
          (
            '#595959',
            false,
            7.004729208035935,
            3.7401147628174307,
            '#848484',
            StorefrontPrimaryIssue.glassBelowAa,
          ),
          (
            '#0055aa',
            false,
            7.292031899110611,
            4.091248767199351,
            '#4281c0',
            StorefrontPrimaryIssue.glassBelowAa,
          ),
          (
            '#abc',
            false,
            1.9645876970822407,
            1.6184006939772664,
            '#c0cdd9',
            StorefrontPrimaryIssue.heroBelowAa,
          ),
        ];

    for (final (hex, supported, hero, glass, glassHex, issue) in cases) {
      test(hex, () {
        final v = inspectStorefrontPrimary(hex);
        expect(v.supported, supported);
        expect(v.heroRatio, closeTo(hero, _eps));
        expect(v.glassRatio, closeTo(glass, _eps));
        expect(v.issue, issue);
        expect(storefrontGlassOverWhite(hex), glassHex);
      });
    }

    test('non-hex input is unsupported with zero ratios', () {
      for (final bad in [
        'red',
        '#12345',
        '#GGGGGG',
        '',
        '13322a',
        '#13322a ',
      ]) {
        final v = inspectStorefrontPrimary(bad);
        expect(v.supported, isFalse, reason: bad);
        expect(v.issue, StorefrontPrimaryIssue.notHex);
        expect(v.heroRatio, 0);
        expect(v.glassRatio, 0);
      }
    });
  });

  group('helpers', () {
    test('the default primary is supported; the default accent is not', () {
      // The writer's defaults: primary '#13322a', accent '#e07b2c'.
      expect(
        inspectStorefrontPrimary(kStorefrontNeutralPrimary).supported,
        isTrue,
      );
      expect(inspectStorefrontPrimary('#e07b2c').supported, isFalse);
    });

    test('storefrontEffectivePrimary = sanitizePrimary', () {
      expect(storefrontEffectivePrimary('#1D4ED8'), kStorefrontNeutralPrimary);
      expect(storefrontEffectivePrimary('#ffffff'), kStorefrontNeutralPrimary);
      expect(storefrontEffectivePrimary(null), kStorefrontNeutralPrimary);
      expect(storefrontEffectivePrimary('#7A1F1F'), '#7a1f1f');
      expect(storefrontEffectivePrimary('#000'), '#000000');
    });

    test('contrast is symmetric and >= 1; luminance of the extremes', () {
      expect(storefrontContrast('#000000', '#ffffff'), closeTo(21, _eps));
      expect(
        storefrontContrast('#13322a', '#FFFFFF'),
        storefrontContrast('#FFFFFF', '#13322a'),
      );
      expect(storefrontContrast('#13322a', '#13322a'), 1);
      expect(storefrontLuminance('#ffffff'), closeTo(1, _eps));
      expect(storefrontLuminance('#000000'), 0);
    });

    test('hex round-trip, #rgb expansion, clamping', () {
      expect(storefrontHexToRgb('#13322a'), [0x13, 0x32, 0x2a]);
      expect(storefrontHexToRgb('#abc'), [0xaa, 0xbb, 0xcc]);
      expect(storefrontRgbToHex([19, 50, 42]), '#13322a');
      expect(storefrontRgbToHex([-4, 300, 127.5]), '#00ff80');
      expect(isStorefrontHex('#AbC'), isTrue);
      expect(isStorefrontHex('#abcd'), isFalse);
    });
  });
}
