import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_color_picker.dart';
import 'storefront_contrast.dart';
import 'storefront_copy.dart';

/// Render-only colors for the explicit site modes. Stored custom colors remain
/// unchanged; a custom ink has priority only when it remains readable.
class StorefrontSiteThemePalette {
  StorefrontSiteThemePalette({
    required String siteTheme,
    String? scenePreset,
    required StorefrontColorSample sample,
  }) : background = siteTheme == 'light'
           ? Colors.white
           : scenePreset == 'reference_dark'
           ? const Color(0xff151515)
           : _darkBackground(sample.background),
       accent = _colour(sample.accent) ?? const Color(0xffe4ad83) {
    final light = siteTheme == 'light';
    final surfaces = light
        ? [background, Colors.white, const Color(0xfff5f6f7)]
        : [
            background,
            _darkSurface(background, .03),
            _darkSurface(background, .07),
          ];
    final fallback = light ? const Color(0xff202124) : Colors.white;
    final candidate = _mix(accent, surfaces[1], .91);
    selection =
        storefrontContrast(
              storefrontFormatColor(fallback),
              storefrontFormatColor(candidate),
            ) >=
            kStorefrontContrastAa
        ? candidate
        : surfaces[1];
    surfaces.add(selection);
    text = _customInk(sample.text, surfaces) ?? fallback;
    buttonText =
        _customInk(sample.buttonText, [accent]) ?? _readableInk(accent);
    usesTextFallback =
        sample.text != null && _customInk(sample.text, surfaces) == null;
    usesButtonTextFallback =
        sample.buttonText != null &&
        _customInk(sample.buttonText, [accent]) == null;
  }
  final Color background, accent;
  late final Color text, buttonText, selection;
  late final bool usesTextFallback, usesButtonTextFallback;
  bool get hasContrastFallback => usesTextFallback || usesButtonTextFallback;

  static Color _darkBackground(String primary) {
    final parsed = _colour(primary);
    return parsed != null &&
            storefrontContrast('#ffffff', primary) >= kStorefrontContrastAa
        ? parsed
        : const Color(0xff151513);
  }

  static Color _mix(Color a, Color b, double amount) {
    final first = storefrontHexToRgb(storefrontFormatColor(a));
    final second = storefrontHexToRgb(storefrontFormatColor(b));
    return storefrontParseColor(
      storefrontRgbToHex([
        for (var i = 0; i < 3; i++) first[i] + (second[i] - first[i]) * amount,
      ]),
    )!;
  }

  static Color _darkSurface(Color background, double amount) {
    final candidate = _mix(background, Colors.white, amount);
    return storefrontContrast('#ffffff', storefrontFormatColor(candidate)) >=
            kStorefrontContrastAa
        ? candidate
        : _mix(background, Colors.black, amount);
  }

  static Color _readableInk(Color background) {
    final hex = storefrontFormatColor(background);
    final whiteRatio = storefrontContrast('#ffffff', hex);
    final legacy = whiteRatio >= kStorefrontContrastAa
        ? Colors.white
        : const Color(0xff0b1512);
    if (storefrontContrast(storefrontFormatColor(legacy), hex) >=
        kStorefrontContrastAa) {
      return legacy;
    }
    // Explicit-mode preview only: retain a passing legacy ink, otherwise
    // choose the black/white fallback with the higher actual button contrast.
    return storefrontContrast('#000000', hex) >= whiteRatio
        ? Colors.black
        : Colors.white;
  }

  static Color? _colour(String? value) =>
      value != null && isStorefrontHex(value)
      ? storefrontParseColor(storefrontRgbToHex(storefrontHexToRgb(value)))
      : null;

  static Color? _customInk(String? value, List<Color> surfaces) {
    final color = _colour(value);
    if (color == null ||
        surfaces.any(
          (background) =>
              storefrontContrast(value!, storefrontFormatColor(background)) <
              kStorefrontContrastAa,
        )) {
      return null;
    }
    return color;
  }
}

/// A small draft-only sample. It neither modifies the palette nor publishes an
/// image, and it is not a substitute for previewing the whole customer journey.
class StorefrontSiteThemePreview extends StatelessWidget {
  const StorefrontSiteThemePreview({
    super.key,
    required this.siteTheme,
    required this.scenePreset,
    required this.sample,
    required this.backgroundUrl,
    required this.dim,
  });
  final String siteTheme;
  final String? scenePreset;
  final StorefrontColorSample sample;
  final Uri? backgroundUrl;
  final int dim;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String c(String key) => storefrontContentCopy(l10n, key);
    final palette = StorefrontSiteThemePalette(
      siteTheme: siteTheme,
      scenePreset: scenePreset,
      sample: sample,
    );
    final showPhotograph =
        siteTheme == 'dark' &&
        backgroundUrl != null &&
        TickerMode.valuesOf(context).enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c('siteThemePreview')),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            key: const Key('content-site-theme-preview'),
            color: palette.background,
            child: Column(
              children: [
                SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (showPhotograph) ...[
                        Image.network(
                          backgroundUrl.toString(),
                          key: const Key('content-site-theme-photo'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        ColoredBox(
                          key: const Key('content-site-theme-dim'),
                          color: Colors.black.withValues(alpha: dim / 100),
                        ),
                      ],
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          color: palette.background,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            c('sceneMenu'),
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: palette.text.withValues(alpha: .4),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          c('siteThemeSampleField'),
                          key: const Key('content-site-theme-sample-text'),
                          style: TextStyle(color: palette.text),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          c('colorPreviewButton'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.buttonText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (palette.hasContrastFallback)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              c('siteThemeContrastNotice'),
              key: const Key('content-site-theme-contrast-notice'),
            ),
          ),
      ],
    );
  }
}
