import 'dart:math' as math;

/// STOREFRONT-PUBLISH-001 — a Dart port, in BEHAVIOUR, of the storefront's
/// primary-colour rule: `inspectPrimary` of `storefront/src/theme/sanitize.ts`
/// over `storefront/src/theme/contrast.ts`, with `AA` from `buildTheme.ts`.
///
/// It exists ONLY to show a truthful warning in the editor: the public
/// storefront REPLACES a primary colour with the neutral one when white text
/// would not reach AA contrast on the flat hero or on the hero glass (the
/// primary at 74% over white — the worst case). It never changes what is
/// saved; the storefront applies the rule itself.

/// `NEUTRAL_PRIMARY` of sanitize.ts — what an unsupported primary becomes.
const String kStorefrontNeutralPrimary = '#13322a';

/// `AA` of buildTheme.ts.
const double kStorefrontContrastAa = 4.5;

/// `GLASS_ALPHA` of sanitize.ts: `--glass` composites the primary at 74%.
const double kStorefrontGlassAlpha = 0.74;

final RegExp _hex6 = RegExp(r'^#[0-9a-fA-F]{6}$');
final RegExp _hex3 = RegExp(r'^#[0-9a-fA-F]{3}$');

/// `isHex`: true for `#rgb` or `#rrggbb`, nothing else.
bool isStorefrontHex(String value) =>
    _hex6.hasMatch(value) || _hex3.hasMatch(value);

/// `hexToRgb` (expands `#rgb`).
List<int> storefrontHexToRgb(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  final n = int.parse(h, radix: 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/// `rgbToHex`: clamps to 0..255 and rounds half up, lower-case.
String storefrontRgbToHex(List<num> rgb) =>
    '#${rgb.map((v) => math.max(0, math.min(255, v)).round().toRadixString(16).padLeft(2, '0')).join()}';

/// `luminance`: WCAG 2.x relative luminance.
double storefrontLuminance(String hex) {
  final c = storefrontHexToRgb(hex).map((v) {
    final s = v / 255;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }).toList();
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

/// `contrast`: the WCAG ratio, always >= 1; argument order does not matter.
double storefrontContrast(String a, String b) {
  final la = storefrontLuminance(a);
  final lb = storefrontLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// `glassOverWhite`: the primary at 74% over WHITE (the lightest photo).
String storefrontGlassOverWhite(String primary) {
  final rgb = storefrontHexToRgb(primary);
  return storefrontRgbToHex([
    for (final v in rgb)
      v * kStorefrontGlassAlpha + 255 * (1 - kStorefrontGlassAlpha),
  ]);
}

/// Why a primary is not supported (the three `reason`s of `inspectPrimary`).
enum StorefrontPrimaryIssue {
  /// Not `#rgb` / `#rrggbb`.
  notHex,

  /// White ink is below AA on the flat hero.
  heroBelowAa,

  /// White ink is below AA on the hero glass (primary at 74% over white).
  glassBelowAa,
}

/// `PrimaryVerdict`.
class StorefrontPrimaryVerdict {
  const StorefrontPrimaryVerdict({
    required this.supported,
    required this.heroRatio,
    required this.glassRatio,
    this.issue,
  });

  /// True when the storefront renders this primary as-is; false when it
  /// replaces it with [kStorefrontNeutralPrimary].
  final bool supported;

  /// White on the flat primary (0 when not a hex colour).
  final double heroRatio;

  /// White on the worst-case glass composite (0 when not a hex colour).
  final double glassRatio;
  final StorefrontPrimaryIssue? issue;
}

/// `inspectPrimary`: a primary is supported only when WHITE reaches AA on BOTH
/// the flat hero and the worst-case glass composite.
StorefrontPrimaryVerdict inspectStorefrontPrimary(String primary) {
  if (!isStorefrontHex(primary)) {
    return const StorefrontPrimaryVerdict(
      supported: false,
      heroRatio: 0,
      glassRatio: 0,
      issue: StorefrontPrimaryIssue.notHex,
    );
  }
  final heroRatio = storefrontContrast('#FFFFFF', primary);
  final glassRatio = storefrontContrast(
    '#FFFFFF',
    storefrontGlassOverWhite(primary),
  );
  if (heroRatio < kStorefrontContrastAa) {
    return StorefrontPrimaryVerdict(
      supported: false,
      heroRatio: heroRatio,
      glassRatio: glassRatio,
      issue: StorefrontPrimaryIssue.heroBelowAa,
    );
  }
  if (glassRatio < kStorefrontContrastAa) {
    return StorefrontPrimaryVerdict(
      supported: false,
      heroRatio: heroRatio,
      glassRatio: glassRatio,
      issue: StorefrontPrimaryIssue.glassBelowAa,
    );
  }
  return StorefrontPrimaryVerdict(
    supported: true,
    heroRatio: heroRatio,
    glassRatio: glassRatio,
  );
}

/// `sanitizePrimary`: the colour the storefront will actually render.
String storefrontEffectivePrimary(String? primary) {
  if (primary == null) return kStorefrontNeutralPrimary;
  if (!inspectStorefrontPrimary(primary).supported) {
    return kStorefrontNeutralPrimary;
  }
  // normaliseHex: expand #rgb and lower-case.
  return storefrontRgbToHex(storefrontHexToRgb(primary)).toLowerCase();
}
