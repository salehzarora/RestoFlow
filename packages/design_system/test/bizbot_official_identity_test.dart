import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// BIZBOT OFFICIAL IDENTITY — pins the official palette, the theme roles built
/// on it, the relationship between the brand and semantic accents, and the
/// repository-level brand surfaces (web shells, manifests, Android labels and
/// icons, the asset generator manifest) so the identity cannot drift back to
/// the navy/orange era or the temporary monogram.
void main() {
  group('official palette', () {
    test('the four official colours are exact', () {
      expect(kBizbotFoundation, const Color(0xFF1F2937));
      expect(kBizbotPrimary, const Color(0xFF059669));
      expect(kBizbotHighlight, const Color(0xFFA7F3D0));
      expect(kBizbotSurface, const Color(0xFFF4F6F5));
      expect(BizbotBrand.foundation, kBizbotFoundation);
      expect(BizbotBrand.primary, kBizbotPrimary);
      expect(BizbotBrand.highlight, kBizbotHighlight);
      expect(BizbotBrand.surface, kBizbotSurface);
      expect(BizbotBrand.lightNeutral, kBizbotSurface);
    });

    test('the legacy tokens are re-valued onto the official palette', () {
      expect(kRestoflowSeedColor, kBizbotPrimary);
      expect(kRestoflowCanvas, kBizbotSurface);
      expect(kRestoflowInk, kBizbotFoundation);
      expect(kRestoflowShadowInk, kBizbotFoundationDeep);
      // Not a single navy/orange value survives in the brand roles.
      const retired = {
        0xFF16335E,
        0xFF0F2547,
        0xFFE9EEF6,
        0xFFC2410C,
        0xFFFB923C,
        0xFFFFEDD5,
        0xFF0F2038,
        0xFF223A5E,
        0xFF0B1526,
        0xFF7FA3DA,
      };
      for (final palette in [
        RestoflowBrandPalette.light,
        RestoflowBrandPalette.dark,
      ]) {
        for (final color in [
          palette.primaryNavy,
          palette.primaryNavyHover,
          palette.primaryNavyContainer,
          palette.accentOrange,
          palette.accentOrangeContainer,
          palette.surfaceDark,
          palette.borderDark,
          palette.textPrimaryDark,
          palette.textSecondaryDark,
          palette.chartGridDark,
        ]) {
          expect(retired, isNot(contains(color.toARGB32())));
        }
      }
      for (final semantic in [
        RestoflowSemanticColors.light,
        RestoflowSemanticColors.dark,
      ]) {
        for (final color in [
          semantic.accent,
          semantic.accentContainer,
          semantic.sidebarSurface,
          semantic.sidebarActiveBackground,
        ]) {
          expect(retired, isNot(contains(color.toARGB32())));
        }
      }
      expect(kRestoflowBrandGradient.colors, [
        kBizbotFoundationDeep,
        kBizbotFoundation,
        kBizbotPrimary,
        kBizbotHighlight,
      ]);
    });

    test('brand roles map onto the official colours (light and dark)', () {
      const light = RestoflowBrandPalette.light;
      expect(light.primaryNavy, kBizbotPrimary);
      expect(light.primaryNavyContainer, kBizbotHighlight);
      expect(light.accentOrange, kBizbotFoundation);
      expect(light.accentOrangeContainer, kBizbotHighlight);
      expect(light.canvasLight, kBizbotSurface);
      expect(light.surfaceDark, kBizbotFoundation);
      const dark = RestoflowBrandPalette.dark;
      expect(dark.primaryNavy, kBizbotHighlight);
      expect(dark.accentOrange, kBizbotSurface);
      expect(dark.textPrimaryDark, kBizbotSurface);
      // Identity and attention agree, on both grounds.
      expect(RestoflowSemanticColors.light.accent, light.accentOrange);
      expect(RestoflowSemanticColors.dark.accent, dark.accentOrange);
      // The semantic statuses stay their own colours — a brand revaluation
      // never repaints an operational state.
      for (final semantic in [
        RestoflowSemanticColors.light,
        RestoflowSemanticColors.dark,
      ]) {
        for (final state in [
          semantic.success,
          semantic.warning,
          semantic.danger,
          semantic.info,
        ]) {
          expect(state, isNot(kBizbotPrimary));
          expect(state, isNot(kBizbotHighlight));
          expect(state, isNot(kBizbotFoundation));
          expect(state, isNot(semantic.accent));
        }
      }
    });

    test('the theme pins the official primary roles', () {
      final light = restoflowLightBrandTheme();
      expect(light.colorScheme.primary, kBizbotPrimary);
      expect(light.colorScheme.onPrimary, Colors.white);
      expect(light.colorScheme.primaryContainer, kBizbotHighlight);
      expect(light.colorScheme.onPrimaryContainer, kBizbotFoundation);
      expect(light.scaffoldBackgroundColor, kBizbotSurface);
      final dark = restoflowKdsDarkBrandTheme();
      expect(dark.colorScheme.primary, kBizbotHighlight);
      expect(dark.colorScheme.onPrimary, kBizbotFoundation);
      expect(dark.colorScheme.primaryContainer, kBizbotPrimaryDeep);
      expect(dark.colorScheme.onPrimaryContainer, kBizbotSurface);
      expect(dark.brightness, Brightness.dark);
    });

    test('contrast: the documented pairs clear their targets', () {
      double lum(Color c) {
        double f(double v) => v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
      }

      double ratio(Color a, Color b) {
        final la = lum(a), lb = lum(b);
        final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      // Body text on the canvas and on white.
      expect(ratio(kBizbotFoundation, kBizbotSurface), greaterThan(13.0));
      expect(ratio(kRestoflowInk2, kBizbotSurface), greaterThan(4.5));
      expect(ratio(kRestoflowInk3, kBizbotSurface), greaterThan(4.5));
      expect(ratio(kRestoflowInk3, Colors.white), greaterThan(4.5));
      // White on Emerald: AA for large text / UI components (>= 3:1).
      expect(ratio(Colors.white, kBizbotPrimary), greaterThan(3.0));
      // Deep emerald carries body-size brand text on light grounds.
      expect(ratio(kBizbotPrimaryDeep, Colors.white), greaterThan(4.5));
      expect(ratio(kBizbotPrimaryDeep, kBizbotSurface), greaterThan(4.5));
      // Charcoal on Mint (selection beds, accent containers) and the dark
      // board's Mint primary / Light Neutral text on Charcoal.
      expect(ratio(kBizbotFoundation, kBizbotHighlight), greaterThan(7.0));
      expect(ratio(kBizbotHighlight, kBizbotFoundation), greaterThan(7.0));
      expect(ratio(kBizbotSurface, kBizbotFoundation), greaterThan(7.0));
      // The high-emphasis accent button on both grounds.
      expect(ratio(Colors.white, kBizbotFoundation), greaterThan(7.0));
      expect(ratio(kBizbotFoundation, kBizbotSurface), greaterThan(7.0));
    });
  });

  group('repository brand surfaces', () {
    final root = _repoRoot();

    test('no temporary-monogram or VEYRO asset reference remains active', () {
      expect(
        File(
          '${root.path}/tools/brand/generate_bizbot_temp_icons.py',
        ).existsSync(),
        isFalse,
        reason: 'the temporary icon generator is retired',
      );
      final brandMark = File(
        '${root.path}/packages/design_system/lib/src/components/brand_mark.dart',
      ).readAsStringSync();
      expect(brandMark, isNot(contains('monogram')));
      expect(brandMark, isNot(contains("'B'")));
      expect(brandMark, isNot(contains('veyro')));
      final pubspec = File(
        '${root.path}/packages/design_system/pubspec.yaml',
      ).readAsStringSync();
      expect(pubspec, contains('assets/brand/bizbot/bizbot_symbol.png'));
      expect(pubspec, contains('assets/brand/bizbot/bizbot_wordmark_en.png'));
      expect(pubspec, contains('assets/brand/bizbot/bizbot_wordmark_ar.png'));
      expect(pubspec, isNot(contains('- assets/brand/archive')));
      expect(pubspec, isNot(contains('veyro_mark')));
      for (final asset in [
        RestoflowBrandMark.symbolAsset,
        RestoflowBrandMark.wordmarkLatinAsset,
        RestoflowBrandMark.wordmarkArabicAsset,
      ]) {
        expect(
          File('${root.path}/packages/design_system/$asset').existsSync(),
          isTrue,
          reason: '$asset must be committed',
        );
      }
    });

    test('every web shell and manifest still says BIZBOT, with the '
        'official theme colour', () {
      for (final app in ['pos', 'kds', 'kiosk', 'dashboard', 'admin']) {
        final index = File(
          '${root.path}/apps/$app/web/index.html',
        ).readAsStringSync();
        expect(index, contains('<title>BIZBOT '), reason: app);
        expect(index, isNot(contains('VEYRO')), reason: app);
        final manifest =
            jsonDecode(
                  File(
                    '${root.path}/apps/$app/web/manifest.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(manifest['name'], startsWith('BIZBOT '), reason: app);
        expect(manifest['short_name'], startsWith('BIZBOT '), reason: app);
        expect(
          (manifest['theme_color'] as String).toUpperCase(),
          '#059669',
          reason: '$app manifest theme_color is the Emerald primary',
        );
        expect(
          (manifest['background_color'] as String).toUpperCase(),
          '#F4F6F5',
          reason: '$app manifest background_color is the Light Neutral',
        );
        for (final icon in [
          'favicon.png',
          'icons/Icon-192.png',
          'icons/Icon-512.png',
          'icons/Icon-maskable-192.png',
          'icons/Icon-maskable-512.png',
        ]) {
          expect(
            File('${root.path}/apps/$app/web/$icon').existsSync(),
            isTrue,
            reason: '$app/$icon',
          );
        }
      }
    });

    test('Android labels stay BIZBOT while application IDs stay '
        'com.restoflow.*, with the official adaptive icon', () {
      for (final app in ['pos', 'kds', 'kiosk', 'dashboard']) {
        final android = '${root.path}/apps/$app/android/app';
        final manifest = File(
          '$android/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        expect(
          RegExp(r'android:label="BIZBOT [A-Za-z]+"').hasMatch(manifest),
          isTrue,
          reason: app,
        );
        expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
        expect(manifest, isNot(contains('VEYRO')));
        final gradle = [
          File('$android/build.gradle.kts'),
          File('$android/build.gradle'),
        ].firstWhere((f) => f.existsSync()).readAsStringSync();
        expect(
          RegExp(
            r'applicationId\s*=?\s*"com\.restoflow\.[a-z_.]+"',
          ).hasMatch(gradle),
          isTrue,
          reason: '$app applicationId must remain com.restoflow.*',
        );
        expect(gradle, isNot(contains('com.bizbot')));
        expect(gradle, isNot(contains('com.veyro')));
        expect(
          File(
            '$android/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
          ).readAsStringSync(),
          contains('@mipmap/ic_launcher_foreground'),
          reason: app,
        );
        expect(
          File(
            '$android/src/main/res/values/ic_launcher_background.xml',
          ).readAsStringSync(),
          contains('#F4F6F5'),
          reason: app,
        );
        for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
          expect(
            File(
              '$android/src/main/res/mipmap-$density/ic_launcher.png',
            ).existsSync(),
            isTrue,
          );
          expect(
            File(
              '$android/src/main/res/mipmap-$density/ic_launcher_foreground.png',
            ).existsSync(),
            isTrue,
          );
        }
      }
    });

    test('icons and brand assets are the generator outputs derived from the '
        'pinned official masters', () {
      final manifest = File(
        '${root.path}/tools/brand/BIZBOT_BRAND_ASSETS.md',
      ).readAsStringSync();
      // The masters are pinned by hash in the manifest: the FINAL approved
      // symbol (App-logo/c2355a92-43d1-42a2-8dbf-aa13e0121514.png, installed
      // 2026-09-06) and the unchanged wordmarks...
      const finalSymbolMaster =
          'b09550aa9b283b43c7f3791e2b6b46cbf06584838a875a3d673832a9add651ef';
      const retiredSymbolMaster =
          'd3cafcf6e3bdfbdbd22948d39b6cb6da035af39302348a8ffa7581600813b339';
      const retiredSymbolAsset =
          'a74ffc9b55075377c066942ea85d6c5ab8a598b582c5eeba7f0ea158b257a557';
      expect(
        manifest,
        contains(finalSymbolMaster),
        reason: 'symbol master hash',
      );
      expect(
        manifest,
        contains(
          '486f3aaaff6fc1e8a3b9fad2c62164e5944939d974818f8b8d13713974795c2b',
        ),
        reason: 'EN wordmark master unchanged',
      );
      expect(
        manifest,
        contains(
          '7d68c76cceeeb397f172019ad32140ab1c6c2cb8dc8d0bb3c92a742eae7b12c8',
        ),
        reason: 'AR wordmark master unchanged',
      );
      expect(
        manifest,
        contains(
          '9b817af0d163535bab9db7369a19007098147288fda374329ae0b5702a7c576c',
        ),
        reason: 'EN wordmark asset unchanged by the symbol swap',
      );
      expect(
        manifest,
        contains(
          'b92c4417df36878da9e917943eea331c42182b8da692e3e91f5d756b3e3aaf2a',
        ),
        reason: 'AR wordmark asset unchanged by the symbol swap',
      );
      // ...the retired first symbol is gone from the manifest, the generator
      // and the canonical asset (BIZBOT-SYMBOL-SWAP, 2026-09-06)...
      expect(manifest, isNot(contains(retiredSymbolMaster)));
      expect(manifest, isNot(contains(retiredSymbolAsset)));
      final generator = File(
        '${root.path}/tools/brand/generate_bizbot_official_icons.py',
      ).readAsStringSync();
      expect(generator, contains(finalSymbolMaster));
      expect(generator, contains('"bizbot_symbol_master.png"'));
      expect(generator, isNot(contains(retiredSymbolMaster)));
      final canonicalSymbol = crypto.sha256
          .convert(
            File(
              '${root.path}/packages/design_system/assets/brand/bizbot/'
              'bizbot_symbol.png',
            ).readAsBytesSync(),
          )
          .toString();
      expect(canonicalSymbol, isNot(retiredSymbolAsset));
      // ...and every committed derivative matches the hash the generator
      // recorded for it (so nothing was hand-edited or left over from the
      // temporary generator).
      // `\r?` — the checkout may be CRLF on Windows.
      final rows =
          RegExp(r'^\| `([^`]+)` \| `([0-9a-f]{64})` \|\r?$', multiLine: true)
              .allMatches(manifest)
              .where((m) => !m.group(1)!.startsWith('tools/brand/masters/'))
              .toList();
      expect(rows.length, greaterThanOrEqualTo(60));
      for (final row in rows) {
        final file = File('${root.path}/${row.group(1)}');
        expect(file.existsSync(), isTrue, reason: row.group(1));
        final digest = crypto.sha256.convert(file.readAsBytesSync()).toString();
        expect(digest, row.group(2), reason: '${row.group(1)} was modified');
      }
      final masters = Directory('${root.path}/tools/brand/masters/bizbot');
      expect(masters.existsSync(), isTrue);
      final symbolMaster = File('${masters.path}/bizbot_symbol_master.png');
      expect(symbolMaster.existsSync(), isTrue);
      expect(
        crypto.sha256.convert(symbolMaster.readAsBytesSync()).toString(),
        finalSymbolMaster,
        reason: 'the pinned master is the byte-identical owner original',
      );
      expect(
        File('${masters.path}/bizbot_symbol_master.jpg').existsSync(),
        isFalse,
        reason: 'the retired symbol master must not stay in the tree',
      );
    });
  });
}

/// The workspace root is the directory holding `vercel.json` next to the
/// workspace `pubspec.yaml` — found by walking up from wherever the test runs
/// (the package directory under `flutter test`, the root under melos).
Directory _repoRoot() {
  var dir = Directory.current;
  while (!(File('${dir.path}/vercel.json').existsSync() &&
      File('${dir.path}/pubspec.yaml').existsSync())) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found from ${Directory.current}');
    }
    dir = parent;
  }
  return dir;
}
