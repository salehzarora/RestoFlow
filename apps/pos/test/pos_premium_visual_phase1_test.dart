import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/design/pos_motion.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart' show PosMenuScreen;
import 'package:restoflow_pos/src/pos_palette.dart';
import 'package:restoflow_pos/src/state/pos_device_accent.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_device_theme.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-PREMIUM-VISUAL-POLISH-001 Phase 1 — tokens, fonts, motion foundation,
/// and the per-device secondary accent (state + settings UI).

Widget _app(Widget child, {bool disableAnimations = false}) => ProviderScope(
  overrides: [posPrinterScopeSegmentProvider.overrideWith((ref) => 'test-dev')],
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    locale: const Locale('en'),
    theme: posPremiumTheme(),
    // Derive from the REAL test MediaQuery (a raw MediaQueryData would carry
    // Size.zero and lay the whole tree out at 0x0).
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: app!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. Visual tokens', () {
    test('A1. structural darks obey the POS cool-law (b > r, b > g)', () {
      for (final c in [kPosMidnightNavy, kPosSlateInk]) {
        expect(c.b, greaterThan(c.r), reason: '$c must be navy-family');
        expect(c.b, greaterThan(c.g), reason: '$c must be navy-family');
      }
    });

    test('A2. ivory is a canvas, not a control surface: distinct from the '
        'pinned cool surface family and from pure card', () {
      expect(kPosIvorySurface, isNot(equals(kPosPureCard)));
      // The V4-pinned cool family must NOT contain the warm canvas.
      for (final cool in [kPosInnerSurface, kPosChipBg, kPosDisabledBg]) {
        expect(cool, isNot(equals(kPosIvorySurface)));
      }
    });

    test('A3. ember is decorative and distinct from the interactive brand '
        'accent; the default secondary accent is Mint Leaf', () {
      final brandAccent = RestoflowBrandPalette.light.accentOrange;
      expect(kPosEmberOrange, isNot(equals(brandAccent)));
      expect(PosDeviceAccent.mint.color, kPosDefaultSecondaryAccent);
      expect(kPosDefaultSecondaryAccent, const Color(0xFF4E8B7A));
    });

    test('A4. every accent choice is distinct from every semantic status '
        'colour (the accent may never impersonate a state)', () {
      final semantic = RestoflowSemanticColors.light;
      final statuses = {
        semantic.success,
        semantic.warning,
        semantic.danger,
        semantic.info,
      };
      for (final accent in PosDeviceAccent.values) {
        expect(
          statuses.contains(accent.color),
          isFalse,
          reason: '${accent.wire} must not equal a semantic status colour',
        );
      }
    });

    test('A5. motion tokens: the spring curve and the 150-400ms band', () {
      expect(kPosSpring, const Cubic(0.34, 1.56, 0.64, 1));
      for (final d in [
        PosMotionDurations.tap,
        PosMotionDurations.base,
        PosMotionDurations.entrance,
        PosMotionDurations.flight,
      ]) {
        expect(d.inMilliseconds, inInclusiveRange(150, 400));
      }
      expect(
        PosMotionDurations.stagger.inMilliseconds,
        inInclusiveRange(30, 50),
      );
    });
  });

  group('B. Fonts', () {
    test('B1. display voice is Tajawal, body voice is IBM Plex Sans Arabic, '
        'both with the shared fallback chain', () {
      final t = posPremiumTheme().textTheme;
      expect(t.titleLarge!.fontFamily, kPosDisplayFontFamily);
      expect(t.headlineSmall!.fontFamily, kPosDisplayFontFamily);
      expect(t.labelLarge!.fontFamily, kPosDisplayFontFamily);
      expect(t.titleMedium!.fontFamily, kPosBodyFontFamily);
      expect(t.bodyMedium!.fontFamily, kPosBodyFontFamily);
      expect(t.bodySmall!.fontFamily, kPosBodyFontFamily);
      expect(t.bodyMedium!.fontFamilyFallback, kPosFontFallbacks);
      expect(t.titleLarge!.fontFamilyFallback, kPosFontFallbacks);
    });

    test('B2. the theme derives from the shared light brand theme; the '
        'PRIMARY role follows the device pair '
        '(POS-THEME-NAVBAR-POLISH-001)', () {
      final pos = posPremiumTheme();
      final base = restoflowLightBrandTheme();
      // Default pair: the primary role is the pair's midnight navy.
      expect(pos.colorScheme.primary, PosThemePair.navyEmber.primary);
      // A non-default pair genuinely re-leads the theme — a green preset
      // makes the primary role green, not navy-with-green-corners.
      expect(
        posPremiumTheme(pair: PosThemePair.forestCharcoal).colorScheme.primary,
        PosThemePair.forestCharcoal.primary,
      );
      // Everything else still derives from the shared brand theme.
      expect(pos.scaffoldBackgroundColor, base.scaffoldBackgroundColor);
      expect(
        pos.extension<RestoflowBrandPalette>(),
        base.extension<RestoflowBrandPalette>(),
      );
    });
  });

  group('C. Device accent state', () {
    test('C1. fromWire round-trips every value and falls back to mint', () {
      for (final a in PosDeviceAccent.values) {
        expect(PosDeviceAccent.fromWire(a.wire), a);
      }
      expect(PosDeviceAccent.fromWire(null), PosDeviceAccent.mint);
      expect(PosDeviceAccent.fromWire('teal-ish'), PosDeviceAccent.mint);
    });

    test(
      'C2. defaults to mint when nothing is stored; setAccent persists '
      'under the device namespace and a fresh container reads it back',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer(
          overrides: [
            posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-9'),
          ],
        );
        addTearDown(container.dispose);
        expect(
          await container.read(posDeviceAccentProvider.future),
          PosDeviceAccent.mint,
        );
        expect(
          container.read(posDeviceAccentColorProvider),
          kPosDefaultSecondaryAccent,
        );

        await container
            .read(posDeviceAccentProvider.notifier)
            .setAccent(PosDeviceAccent.saffron);
        expect(
          container.read(posDeviceAccentColorProvider),
          PosDeviceAccent.saffron.color,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('restoflow.pos.device_accent.dev-9'), 'saffron');

        final fresh = ProviderContainer(
          overrides: [
            posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-9'),
          ],
        );
        addTearDown(fresh.dispose);
        expect(
          await fresh.read(posDeviceAccentProvider.future),
          PosDeviceAccent.saffron,
        );
      },
    );

    test(
      'C3. a corrupt stored token reads as mint (never breaks paint)',
      () async {
        SharedPreferences.setMockInitialValues({
          'restoflow.pos.device_accent.dev-9': 'neon-zebra',
        });
        final container = ProviderContainer(
          overrides: [
            posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-9'),
          ],
        );
        addTearDown(container.dispose);
        expect(
          await container.read(posDeviceAccentProvider.future),
          PosDeviceAccent.mint,
        );
      },
    );

    test(
      'C4. the namespace is per device: another segment stays default',
      () async {
        SharedPreferences.setMockInitialValues({
          'restoflow.pos.device_accent.dev-9': 'aubergine',
        });
        final other = ProviderContainer(
          overrides: [
            posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-2'),
          ],
        );
        addTearDown(other.dispose);
        expect(
          await other.read(posDeviceAccentProvider.future),
          PosDeviceAccent.mint,
        );
      },
    );
  });

  group('C2. Device THEME state (POS-THEME-NAVBAR-POLISH-001)', () {
    test('T1. fromWire round-trips every preset and falls back to '
        'navy+ember', () {
      for (final p in PosThemePair.presets) {
        expect(PosThemePair.fromWire(p.wire).wire, p.wire);
      }
      expect(PosThemePair.fromWire(null).wire, 'navy_ember');
      expect(PosThemePair.fromWire('disco-zebra').wire, 'navy_ember');
    });

    test('T2. defaults to navy+ember; setTheme persists under the device '
        'namespace and a fresh container reads it back', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-9'),
        ],
      );
      addTearDown(container.dispose);
      expect(
        (await container.read(posDeviceThemeProvider.future)).wire,
        'navy_ember',
      );
      await container
          .read(posDeviceThemeProvider.notifier)
          .setTheme(PosThemePair.forestCharcoal);
      expect(
        container.read(posDeviceThemePairProvider).wire,
        'forest_charcoal',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.dev-9'),
        'forest_charcoal',
      );

      final fresh = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) => 'dev-9'),
        ],
      );
      addTearDown(fresh.dispose);
      expect(
        (await fresh.read(posDeviceThemeProvider.future)).wire,
        'forest_charcoal',
      );
    });

    test('T3. every preset keeps the CTA readable and never impersonates a '
        'semantic status', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      final semantic = RestoflowSemanticColors.of(Brightness.light);
      final statuses = {
        semantic.success,
        semantic.warning,
        semantic.danger,
        semantic.info,
      };
      for (final p in PosThemePair.presets) {
        // HONEST BASELINE: the owner-approved merged design ships the
        // default white-on-ember CTA at 3.62:1 — below the 4.5 nominal for
        // its 16/800 label (WCAG's large-bold discount starts at 18.66px),
        // an owner-accepted trade. The floor here is therefore pinned AT
        // the shipped worst case: no preset may ever regress BELOW what has
        // already shipped, and the gold pair proves the dark-ink escape
        // hatch works (#231A08 on #D89A2B measures ~7.0:1).
        expect(
          contrast(p.onAction, p.action),
          greaterThanOrEqualTo(3.6),
          reason: '${p.wire}: CTA ink below the shipped worst-case floor',
        );
        // White structure labels must clear 4.5:1 on the pair's primary.
        expect(
          contrast(Colors.white, p.primary),
          greaterThanOrEqualTo(4.5),
          reason: '${p.wire}: white ink unreadable on its primary',
        );
        // The identity colours never equal a semantic status colour.
        expect(statuses.contains(p.primary), isFalse, reason: p.wire);
        expect(statuses.contains(p.action), isFalse, reason: p.wire);
      }
    });

    testWidgets('T4. a non-default pair genuinely re-leads the screen: the '
        'top bar paints the pair primary', (tester) async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.test-dev': 'forest_charcoal',
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
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, PosThemePair.forestCharcoal.primary);
    });
  });

  group('D. Settings UI', () {
    testWidgets('D1. the sheet offers all four swatches; tapping one selects '
        'it and persists it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();

      // The appearance section sits LAST in the sheet and the list
      // virtualizes — scroll it into view the way a user would.
      await tester.scrollUntilVisible(
        find.byKey(const Key('device-accent-mint')),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('device-settings-sheet')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      for (final a in PosDeviceAccent.values) {
        expect(
          find.byKey(Key('device-accent-${a.wire}')),
          findsOneWidget,
          reason: '${a.wire} swatch must render',
        );
      }

      await tester.ensureVisible(
        find.byKey(const Key('device-accent-pomegranate')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-accent-pomegranate')));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_accent.test-dev'),
        'pomegranate',
      );
      final selectedNode = tester
          .getSemantics(find.byKey(const Key('device-accent-pomegranate')))
          .getSemanticsData();
      expect(selectedNode.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('D2. swatch tap targets are >= 44px tall', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(const PosDeviceSettingsSheet()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('device-accent-mint')),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('device-settings-sheet')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byKey(const Key('device-accent-mint')));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('E. Motion foundation', () {
    testWidgets(
      'E1. posMotionEnabled honors the platform reduced-motion flag',
      (tester) async {
        late bool enabledDefault;
        late bool enabledReduced;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                enabledDefault = posMotionEnabled(context);
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: Builder(
                    builder: (context) {
                      enabledReduced = posMotionEnabled(context);
                      return const SizedBox();
                    },
                  ),
                );
              },
            ),
          ),
        );
        expect(enabledDefault, isTrue);
        expect(enabledReduced, isFalse);
      },
    );

    testWidgets('E2. PosEntrance settles fully visible and, under reduced '
        'motion, renders the bare child immediately', (tester) async {
      await tester.pumpWidget(
        _app(const PosEntrance(index: 3, child: Text('X'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1.0);

      await tester.pumpWidget(
        _app(
          const PosEntrance(index: 3, child: Text('Y')),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(find.text('Y'), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });

    testWidgets('E3. PosTapBump never consumes the tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          PosTapBump(
            child: FilledButton(
              onPressed: () => taps++,
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('E4. PosAnimatedCount and PosAnimatedAmount settle on the '
        'exact final value (integer minor units only)', (tester) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              PosAnimatedCount(value: 7, builder: (context, v) => Text('c$v')),
              PosAnimatedAmount(
                minor: 12345,
                builder: (context, m) => Text('m$m'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('c7'), findsOneWidget);
      expect(find.text('m12345'), findsOneWidget);
    });

    testWidgets('E5. PosShimmerSweep is one-shot: it settles and renders the '
        'bare child under reduced motion', (tester) async {
      await tester.pumpWidget(
        _app(const PosShimmerSweep(trigger: 1, child: Text('CTA'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('CTA'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          const PosShimmerSweep(trigger: 1, child: Text('CTA')),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(find.byType(ShaderMask), findsNothing);
    });
  });
}
