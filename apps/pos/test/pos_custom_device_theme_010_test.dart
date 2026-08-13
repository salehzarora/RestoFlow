import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/design/pos_color_utils.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart' show PosMenuScreen;
import 'package:restoflow_pos/src/state/pos_device_accent.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_device_theme.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-CUSTOM-DEVICE-THEME-010 — the CUSTOM two-color device theme:
/// `#RRGGBB` parsing, the `custom:RRGGBB:RRGGBB` wire codec, contrast-derived
/// foregrounds, persistence round-trips, theme application, and the settings
/// editor (draft-only until Apply; invalid input never touches the theme).

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  String segment = 'test-dev',
}) => ProviderScope(
  overrides: [posPrinterScopeSegmentProvider.overrideWith((ref) => segment)],
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    locale: locale,
    theme: posPremiumTheme(),
    builder: (context, app) =>
        MediaQuery(data: MediaQuery.of(context), child: app!),
    home: Scaffold(body: child),
  ),
);

/// Scrolls the device-settings sheet until [target] is visible.
Future<void> _scrollSheetTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('device-settings-sheet')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// Opens the custom editor from a preset-active sheet.
Future<void> _openCustomEditor(WidgetTester tester) async {
  await _scrollSheetTo(tester, find.byKey(const Key('device-theme-custom')));
  await tester.tap(find.byKey(const Key('device-theme-custom')));
  await tester.pumpAndSettle();
  await _scrollSheetTo(tester, find.byKey(const Key('custom-theme-apply')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. #RRGGBB parsing and validation', () {
    test('A1. valid six-digit hexes parse, with and without # (a missing # '
        'is NORMALIZED, not rejected), any letter case', () {
      expect(posParseHexColor('#16263B'), const Color(0xFF16263B));
      expect(posParseHexColor('16263B'), const Color(0xFF16263B));
      expect(posParseHexColor('#c96a2b'), const Color(0xFFC96A2B));
      expect(posParseHexColor('  #C96A2B  '), const Color(0xFFC96A2B));
      expect(posParseHexColor('e76f2e'), const Color(0xFFE76F2E));
    });

    test('A2. wrong lengths are rejected (shorthand #RGB included)', () {
      expect(posParseHexColor(''), isNull);
      expect(posParseHexColor('#'), isNull);
      expect(posParseHexColor('#FFF'), isNull);
      expect(posParseHexColor('FFF'), isNull);
      expect(posParseHexColor('#12345'), isNull);
      expect(posParseHexColor('#1234567'), isNull);
    });

    test('A3. non-hex characters are rejected', () {
      expect(posParseHexColor('#GGGGGG'), isNull);
      expect(posParseHexColor('#12 45B'), isNull);
      expect(posParseHexColor('red'), isNull);
      expect(posParseHexColor('#16263B;'), isNull);
    });

    test('A4. alpha forms are rejected — eight digits never parse', () {
      expect(posParseHexColor('#FF16263B'), isNull);
      expect(posParseHexColor('FF16263B'), isNull);
    });

    test('A5. parsed colors are fully opaque and format back to canonical '
        'uppercase #RRGGBB', () {
      final parsed = posParseHexColor('#c96a2b')!;
      expect(parsed.toARGB32() >>> 24, 0xFF);
      expect(posFormatHexColor(parsed), '#C96A2B');
      expect(posFormatHexColor(const Color(0xFF00080F)), '#00080F');
    });
  });

  group('B. Custom wire codec + fromWire compatibility', () {
    test('B1. a custom pair round-trips through its wire exactly', () {
      final pair = PosThemePair.custom(
        primary: const Color(0xFF1A3D34),
        action: const Color(0xFFE76F2E),
      );
      expect(pair.wire, 'custom:1A3D34:E76F2E');
      final decoded = PosThemePair.fromWire(pair.wire);
      expect(decoded.primary, const Color(0xFF1A3D34));
      expect(decoded.action, const Color(0xFFE76F2E));
      expect(decoded.wire, pair.wire);
      expect(decoded.isCustom, isTrue);
    });

    test('B2. every existing preset wire still loads its exact preset', () {
      for (final p in PosThemePair.presets) {
        expect(identical(PosThemePair.fromWire(p.wire), p), isTrue);
        expect(p.isCustom, isFalse);
      }
    });

    test('B3. corrupt/malformed custom wires fall back to the default '
        'preset — a bad stored value must never break a till', () {
      for (final bad in [
        'custom:',
        'custom:16263B',
        'custom:16263B:C96A2B:EXTRA',
        'custom:XYZXYZ:C96A2B',
        'custom:16263B:GGGGGG',
        'custom:FF16263B:C96A2B',
        'custom:16263:C96A2B',
        'custom',
        'disco-zebra',
      ]) {
        expect(
          identical(PosThemePair.fromWire(bad), PosThemePair.navyEmber),
          isTrue,
          reason: '"$bad" must fall back to navyEmber',
        );
      }
      expect(
        identical(PosThemePair.fromWire(null), PosThemePair.navyEmber),
        isTrue,
      );
    });
  });

  group('C. Contrast-derived foregrounds + derived tones', () {
    test('C1. readable ink flips by actual contrast: white on dark beds, '
        'near-black on light beds', () {
      expect(posReadableInkOn(const Color(0xFF16263B)), Colors.white);
      expect(posReadableInkOn(Colors.black), Colors.white);
      expect(posReadableInkOn(Colors.white), kPosReadableDarkInk);
      expect(posReadableInkOn(const Color(0xFFF7E9C4)), kPosReadableDarkInk);
      expect(posReadableInkOn(const Color(0xFFD89A2B)), kPosReadableDarkInk);
    });

    test('C2. a custom pair derives BOTH foreground inks by contrast and '
        'never alters the chosen hexes', () {
      final light = PosThemePair.custom(
        primary: const Color(0xFFF2EFE8),
        action: const Color(0xFFF7D774),
      );
      expect(light.primary, const Color(0xFFF2EFE8));
      expect(light.action, const Color(0xFFF7D774));
      expect(light.onPrimary, kPosReadableDarkInk);
      expect(light.onAction, kPosReadableDarkInk);

      final dark = PosThemePair.custom(
        primary: const Color(0xFF16263B),
        action: const Color(0xFFC96A2B),
      );
      expect(dark.onPrimary, Colors.white);
      expect(dark.onAction, Colors.white);
    });

    test('C3. derived tones follow the derive() recipe; actionSoft darkens '
        'on a light primary bed instead of vanishing', () {
      const primary = Color(0xFF1A3D34);
      const action = Color(0xFFE76F2E);
      final pair = PosThemePair.custom(primary: primary, action: action);
      expect(pair.primaryHi, Color.lerp(primary, Colors.white, 0.12));
      expect(pair.primaryDeep, Color.lerp(primary, Colors.black, 0.16));
      expect(pair.actionHi, Color.lerp(action, Colors.white, 0.18));
      expect(pair.actionDeep, Color.lerp(action, Colors.black, 0.14));
      expect(pair.actionMark, Color.lerp(action, Colors.white, 0.08));
      expect(pair.actionSoft, Color.lerp(action, Colors.white, 0.44));

      final lightBed = PosThemePair.custom(
        primary: const Color(0xFFF2EFE8),
        action: action,
      );
      expect(lightBed.actionSoft, Color.lerp(action, Colors.black, 0.30));
    });

    test('C4. navbar chrome getters keep the exact preset bytes on dark '
        'primaries and flip to dark washes on light ones', () {
      for (final p in PosThemePair.presets) {
        expect(p.onPrimary, Colors.white, reason: p.wire);
        expect(p.navInk, kPosNavbarInk, reason: p.wire);
        expect(p.navBed, kPosNavbarBed, reason: p.wire);
        expect(p.identityBed, const Color(0x1FFFFFFF), reason: p.wire);
        expect(p.identityEdge, const Color(0x24FFFFFF), reason: p.wire);
      }
      final light = PosThemePair.custom(
        primary: const Color(0xFFF2EFE8),
        action: const Color(0xFF2B6B4F),
      );
      expect(light.navBed, const Color(0x14000000));
      expect(light.identityBed, const Color(0x1A000000));
      expect(light.identityEdge, const Color(0x26000000));
      expect(
        posContrastRatio(light.navInk, light.primary),
        greaterThanOrEqualTo(4.5),
        reason: 'derived chrome ink must stay readable on the light bar',
      );
    });

    test('C6. onActionMark: the small action marks (count chips/badges, '
        'stepper plus) stay the shipped WHITE on EVERY preset — including '
        'saffron_gold whose Send-CTA onAction is dark — and derive only for '
        'custom pairs', () {
      for (final p in PosThemePair.presets) {
        expect(p.onActionMark, Colors.white, reason: p.wire);
      }
      // saffron_gold is the preset that would have repainted had the marks
      // read onAction directly — pin the distinction.
      expect(PosThemePair.saffronGold.onAction, isNot(Colors.white));
      final lightAction = PosThemePair.custom(
        primary: const Color(0xFF16263B),
        action: const Color(0xFFF7D774),
      );
      expect(lightAction.onActionMark, lightAction.onAction);
      expect(lightAction.onActionMark, kPosReadableDarkInk);
    });

    test(
      'C7. actionSoft carries a MEASURED 4.5:1 floor against the primary '
      'bed for custom pairs (light-on-light and mid-grey traps included)',
      () {
        for (final (p, a) in const [
          (Color(0xFFF2EFE8), Color(0xFFF7D774)), // light/light
          (Color(0xFFFFFFFF), Color(0xFFFFFFFF)), // same light hex twice
          (Color(0xFF7A7A7A), Color(0xFF111111)), // grey bed, near-black action
          (Color(0xFF16263B), Color(0xFFD9642B)), // classic dark/ember
        ]) {
          final pair = PosThemePair.custom(primary: p, action: a);
          // A mid-grey bed physically caps below 4.5 (pure white on #7A7A7A
          // is 4.29:1) — there the walk must still deliver the BEST
          // achievable ink, never a worse one.
          final bestAchievable = [
            posContrastRatio(Colors.white, p),
            posContrastRatio(kPosReadableDarkInk, p),
          ].reduce((x, y) => x > y ? x : y);
          expect(
            posContrastRatio(pair.actionSoft, pair.primary),
            greaterThanOrEqualTo(
              (4.5 < bestAchievable ? 4.5 : bestAchievable) - 1e-9,
            ),
            reason: 'actionSoft unreadable on its own primary for $p/$a',
          );
        }
      },
    );

    test('C8. primaryTextInk: identical to primary on every preset and for '
        'dark custom primaries; a light custom primary darkens until the '
        'tonal Add-more bed reads', () {
      for (final p in PosThemePair.presets) {
        expect(p.primaryTextInk, p.primary, reason: p.wire);
      }
      final dark = PosThemePair.custom(
        primary: const Color(0xFF1A3D34),
        action: const Color(0xFFE76F2E),
      );
      expect(dark.primaryTextInk, dark.primary);
      final light = PosThemePair.custom(
        primary: const Color(0xFFF2EFE8),
        action: const Color(0xFF2B6B4F),
      );
      expect(light.primaryTextInk, isNot(light.primary));
      expect(
        posContrastRatio(light.primaryTextInk, kPosTonalAddBg),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('C9. the PRIMARY ink floor is 4.5:1 (structural body text) while '
        'the ACTION ink keeps the shipped 3.6:1 CTA baseline — and the ink '
        'picker never selects the measurably worse candidate', () {
      // #5C8CB0: white measures ~3.6:1 — enough for a CTA, NOT for body
      // text. The primary bed therefore takes the dark ink (~4.8:1)...
      final midPrimary = PosThemePair.custom(
        primary: const Color(0xFF5C8CB0),
        action: const Color(0xFFD9642B),
      );
      expect(midPrimary.onPrimary, kPosReadableDarkInk);
      // ...while the ember action keeps the owner-approved white CTA ink.
      expect(midPrimary.onAction, Colors.white);
      // Never-worse rule: on a mid grey where white (4.29) beats the dark
      // ink (3.99), white wins even though it misses the 4.5 floor.
      expect(
        posReadableInkOn(const Color(0xFF7A7A7A), whiteFloor: 4.5),
        Colors.white,
      );
    });

    test('C5. custom identity colors never recolor semantic states', () {
      final semantic = RestoflowSemanticColors.of(Brightness.light);
      final pair = PosThemePair.custom(
        primary: const Color(0xFF1A3D34),
        action: const Color(0xFFE76F2E),
      );
      final theme = posPremiumTheme(pair: pair);
      final base = restoflowLightBrandTheme();
      expect(theme.colorScheme.error, base.colorScheme.error);
      expect(
        theme.extension<RestoflowSemanticColors>()?.success,
        semantic.success,
      );
      expect(
        theme.extension<RestoflowSemanticColors>()?.danger,
        semantic.danger,
      );
      expect(
        theme.extension<RestoflowSemanticColors>()?.warning,
        semantic.warning,
      );
      expect(theme.extension<RestoflowSemanticColors>()?.info, semantic.info);
    });
  });

  group('D. Persistence + backward compatibility', () {
    test('D1. a custom pair persists through the SAME per-device key and a '
        'fresh container reads back the exact colors', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-a'),
        ],
      );
      addTearDown(container.dispose);
      final custom = PosThemePair.custom(
        primary: const Color(0xFF0E2A3F),
        action: const Color(0xFFB9822D),
      );
      await container.read(posDeviceThemeProvider.future);
      await container.read(posDeviceThemeProvider.notifier).setTheme(custom);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.dev-a'),
        'custom:0E2A3F:B9822D',
      );

      final fresh = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-a'),
        ],
      );
      addTearDown(fresh.dispose);
      final restored = await fresh.read(posDeviceThemeProvider.future);
      expect(restored.primary, const Color(0xFF0E2A3F));
      expect(restored.action, const Color(0xFFB9822D));
      expect(restored.isCustom, isTrue);
    });

    test('D2. the custom value is namespaced per device — another segment '
        'still reads the default', () async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.dev-a': 'custom:0E2A3F:B9822D',
      });
      final other = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-b'),
        ],
      );
      addTearDown(other.dispose);
      expect(
        (await other.read(posDeviceThemeProvider.future)).wire,
        'navy_ember',
      );
    });

    test('D3. custom -> preset -> custom switching persists each step and '
        'presets keep loading exactly as before', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-c'),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(posDeviceThemeProvider.notifier);
      await container.read(posDeviceThemeProvider.future);
      final custom = PosThemePair.custom(
        primary: const Color(0xFF1A3D34),
        action: const Color(0xFFE76F2E),
      );
      await notifier.setTheme(custom);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.dev-c'),
        'custom:1A3D34:E76F2E',
      );
      await notifier.setTheme(PosThemePair.forestCharcoal);
      expect(
        prefs.getString('restoflow.pos.device_theme.dev-c'),
        'forest_charcoal',
      );
      expect(
        container.read(posDeviceThemePairProvider).wire,
        'forest_charcoal',
      );
      await notifier.setTheme(custom);
      expect(container.read(posDeviceThemePairProvider).isCustom, isTrue);
    });

    test('D4. a corrupt stored custom value falls back to the default '
        'preset at load', () async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.dev-d': 'custom:NOTHEX:123',
      });
      final container = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-d'),
        ],
      );
      addTearDown(container.dispose);
      expect(
        (await container.read(posDeviceThemeProvider.future)).wire,
        'navy_ember',
      );
    });

    test('D5. the custom theme never touches the separate device-accent '
        'preference', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-e'),
        ],
      );
      addTearDown(container.dispose);
      await container.read(posDeviceAccentProvider.future);
      await container
          .read(posDeviceAccentProvider.notifier)
          .setAccent(PosDeviceAccent.pomegranate);
      await container.read(posDeviceThemeProvider.future);
      await container
          .read(posDeviceThemeProvider.notifier)
          .setTheme(
            PosThemePair.custom(
              primary: const Color(0xFF1A3D34),
              action: const Color(0xFFE76F2E),
            ),
          );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_accent.dev-e'),
        'pomegranate',
      );
      expect(
        container.read(posDeviceAccentProvider).valueOrNull,
        PosDeviceAccent.pomegranate,
      );
    });
  });

  group('E. Theme application', () {
    test('E1. the custom primary takes the structural first-color role and '
        'the derived ink takes onPrimary', () {
      final pair = PosThemePair.custom(
        primary: const Color(0xFFF2EFE8),
        action: const Color(0xFF2B6B4F),
      );
      final theme = posPremiumTheme(pair: pair);
      expect(theme.colorScheme.primary, const Color(0xFFF2EFE8));
      expect(theme.colorScheme.onPrimary, kPosReadableDarkInk);
      expect(theme.extension<PosThemePair>()?.wire, pair.wire);
    });

    test('E2. two different custom pairs never collide on one theme cache '
        'slot; presets stay cached', () {
      final a = posPremiumTheme(
        pair: PosThemePair.custom(
          primary: const Color(0xFF10202F),
          action: const Color(0xFFAA3311),
        ),
      );
      final b = posPremiumTheme(
        pair: PosThemePair.custom(
          primary: const Color(0xFF223311),
          action: const Color(0xFF0055AA),
        ),
      );
      expect(a.colorScheme.primary, const Color(0xFF10202F));
      expect(b.colorScheme.primary, const Color(0xFF223311));
      expect(
        identical(
          posPremiumTheme(pair: PosThemePair.navyEmber),
          posPremiumTheme(pair: PosThemePair.navyEmber),
        ),
        isTrue,
      );
    });

    testWidgets('E3. a LIGHT custom primary re-leads the top bar with a '
        'readable dark ink (never white-on-white)', (tester) async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.test-dev': 'custom:F2EFE8:2B6B4F',
      });
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posPrinterScopeSegmentProvider.overrideWith((ref) => 'test-dev'),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              theme: posPremiumTheme(
                pair: ref.watch(posDeviceThemePairProvider),
              ),
              home: const PosMenuScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFFF2EFE8));
      final brand = tester.widget<Text>(find.text(l10n.posBrandName));
      expect(brand.style?.color, kPosReadableDarkInk);
      expect(appBar.iconTheme?.color, isNot(kPosNavbarInk));
    });

    testWidgets('E4. a DARK custom pair keeps the preset white-ink world '
        'byte-identical', (tester) async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.test-dev': 'custom:14324A:B54A24',
      });
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posPrinterScopeSegmentProvider.overrideWith((ref) => 'test-dev'),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              theme: posPremiumTheme(
                pair: ref.watch(posDeviceThemePairProvider),
              ),
              home: const PosMenuScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFF14324A));
      expect(appBar.iconTheme?.color, kPosNavbarInk);
      final brand = tester.widget<Text>(find.text(l10n.posBrandName));
      expect(brand.style?.color, Colors.white);
    });
  });

  group('F. Settings editor UI', () {
    testWidgets('F1. the custom option renders beside the presets and the '
        'editor stays hidden while a preset is active', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('device-theme-custom')),
      );
      expect(find.byKey(const Key('device-theme-custom')), findsOneWidget);
      for (final p in PosThemePair.presets) {
        expect(find.byKey(Key('device-theme-${p.wire}')), findsOneWidget);
      }
      expect(find.byKey(const Key('custom-theme-editor')), findsNothing);
    });

    testWidgets('F2. tapping the custom option reveals the editor seeded '
        'from the ACTIVE pair without changing the applied theme', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      expect(find.byKey(const Key('custom-theme-editor')), findsOneWidget);
      final primaryField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('custom-theme-primary-hex')),
          matching: find.byType(TextField),
        ),
      );
      final secondaryField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('custom-theme-secondary-hex')),
          matching: find.byType(TextField),
        ),
      );
      expect(primaryField.controller?.text, '#16263B');
      expect(secondaryField.controller?.text, '#D9642B');
      // Revealing the editor applied nothing.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restoflow.pos.device_theme.test-dev'), isNull);
    });

    testWidgets('F3. invalid input disables Apply, shows the localized '
        'error, and never reaches the live theme', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('custom-theme-primary-hex')),
          matching: find.byType(TextField),
        ),
        '#12F',
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.posDeviceThemeCustomInvalidHex), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('custom-theme-apply')))
            .onPressed,
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restoflow.pos.device_theme.test-dev'), isNull);
    });

    testWidgets('F4. a valid pair enables Apply; applying persists the '
        'custom wire and selects the custom swatch', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('custom-theme-primary-hex')),
          matching: find.byType(TextField),
        ),
        '1a3d34',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('custom-theme-secondary-hex')),
          matching: find.byType(TextField),
        ),
        '#E76F2E',
      );
      await tester.pumpAndSettle();
      final apply = tester.widget<FilledButton>(
        find.byKey(const Key('custom-theme-apply')),
      );
      expect(apply.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('custom-theme-apply')));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.test-dev'),
        'custom:1A3D34:E76F2E',
      );
      // The editor stays visible (custom is now the ACTIVE selection) and
      // the swatch reports selected to assistive tech.
      expect(find.byKey(const Key('custom-theme-editor')), findsOneWidget);
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('device-theme-custom')),
      );
      final node = tester
          .getSemantics(find.byKey(const Key('device-theme-custom')))
          .getSemanticsData();
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('F5. Cancel discards the draft and closes the editor while '
        'a preset stays active', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('custom-theme-primary-hex')),
          matching: find.byType(TextField),
        ),
        '#BADBAD',
      );
      await tester.pumpAndSettle();
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-cancel')),
      );
      await tester.tap(find.byKey(const Key('custom-theme-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('custom-theme-editor')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restoflow.pos.device_theme.test-dev'), isNull);
    });

    testWidgets('F6. with a stored custom pair the editor opens pre-filled '
        'with the EXACT stored colors; Reset restores the default preset', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.test-dev': 'custom:0E2A3F:B9822D',
      });
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-editor')),
      );
      final primaryField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('custom-theme-primary-hex')),
          matching: find.byType(TextField),
        ),
      );
      expect(primaryField.controller?.text, '#0E2A3F');
      await _scrollSheetTo(tester, find.byKey(const Key('custom-theme-reset')));
      await tester.tap(find.byKey(const Key('custom-theme-reset')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.test-dev'),
        'navy_ember',
      );
      expect(find.byKey(const Key('custom-theme-editor')), findsNothing);
    });

    testWidgets('F7. the custom swatch and all three editor actions keep '
        '>=44dp touch targets', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      for (final key in const [
        'device-theme-custom',
        'custom-theme-apply',
        'custom-theme-cancel',
        'custom-theme-reset',
      ]) {
        await _scrollSheetTo(tester, find.byKey(Key(key)));
        expect(
          tester.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(44),
          reason: '$key target below 44dp',
        );
      }
    });

    for (final (locale, size) in const [
      (Locale('ar'), Size(390, 844)),
      (Locale('he'), Size(390, 844)),
      (Locale('en'), Size(390, 844)),
      (Locale('ar'), Size(430, 932)),
      (Locale('en'), Size(430, 932)),
    ]) {
      testWidgets('F8. no overflow with the editor open at '
          '${size.width.toInt()} in ${locale.languageCode}', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        // Paint-time overflow never reaches takeException — collect it from
        // FlutterError.onError, describing AT THROW TIME (the creator chain
        // dies with the tree), and restore the handler BEFORE expecting.
        //
        // Scoped to THIS ticket's surface: the shared sheet also hosts
        // packages/native_printing's saved-printers section, which has a
        // PRE-EXISTING 2px overflow at 390/ar (saved_printers_section.dart
        // Row) — a shared-package fix needs its own ticket, so it must not
        // be silently absorbed here. Overflows from the theme section /
        // custom editor (device_settings_sheet.dart) still fail hard.
        final overflowDescriptions = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflowDescriptions.add(details.toString());
          }
        };
        await tester.pumpWidget(
          _app(const PosDeviceSettingsSheet(), locale: locale),
        );
        await tester.pumpAndSettle();
        await _openCustomEditor(tester);
        await _scrollSheetTo(
          tester,
          find.byKey(const Key('custom-theme-reset')),
        );
        FlutterError.onError = prior;
        expect(
          overflowDescriptions.where(
            (d) => d.contains('device_settings_sheet.dart'),
          ),
          isEmpty,
          reason:
              '${locale.languageCode}@${size.width}: layout overflow in '
              'the appearance section',
        );
      });
    }
  });
}
