import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_appearance.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-001-107 — the GLOBAL two-color device theme: locked default,
/// preset/custom wires, dark-premium derivation, contrast safety,
/// device-scoped persistence, draft isolation, global application and the
/// semantic/receipt freeze.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(KioskColors.resetToDefault);

  group('A. default — the locked Navy+Ember, byte for byte', () {
    test('missing/unknown/corrupt wires resolve to the exact default', () {
      for (final wire in [null, '', 'nonsense', 'custom:', 'custom:GG:HH']) {
        final pair = KioskThemePair.fromWire(wire);
        expect(pair.wire, 'navy_ember', reason: '$wire');
      }
    });

    test('default tokens are ARGB-identical to the pre-107 constants', () {
      KioskColors.resetToDefault();
      expect(KioskColors.canvasTop.toARGB32(), 0xFF0A1526);
      expect(KioskColors.canvasBottom.toARGB32(), 0xFF070E1B);
      expect(KioskColors.canvasGlow.toARGB32(), 0xFF13233E);
      expect(KioskColors.frameRing.toARGB32(), 0xFF101B2E);
      expect(KioskColors.frameLine.toARGB32(), 0xFF223A5E);
      expect(KioskColors.frameLineHi.toARGB32(), 0xFF3B527A);
      expect(KioskColors.sheetTop.toARGB32(), 0xFF12233F);
      expect(KioskColors.sheetBottom.toARGB32(), 0xFF0A1526);
      expect(KioskColors.pinCardBottom.toARGB32(), 0xFF0B1830);
      expect(KioskColors.imageWell.toARGB32(), 0xFF0E1C31);
      expect(KioskColors.wheelActiveTop.toARGB32(), 0xFF1A2C49);
      expect(KioskColors.ring.toARGB32(), 0xFFF97316);
      expect(KioskColors.accentTop.toARGB32(), 0xFFFB923C);
      expect(KioskColors.accentBottom.toARGB32(), 0xFFEA580C);
      expect(KioskColors.barGlass.toARGB32(), 0xC7080F1C);
      expect(KioskColors.cardGlass.toARGB32(), 0xA80A1220);
      expect(KioskColors.stageBase.toARGB32(), 0xFF05080F);
      expect(KioskColors.onAction, Colors.white);
      expect(kioskAccentGradient.colors.map((c) => c.toARGB32()), [
        0xFFFB923C,
        0xFFEA580C,
      ]);
    });

    test('a 102/103 appearance JSON without theme fields upgrades to the '
        'default wire WITHOUT losing existing branding/media', () {
      final legacy = {
        'v': 1,
        'restaurant_display_name': 'Burger House',
        'brand_title_primary': 'Burger',
        'brand_title_accent': 'House',
        'featured_menu_item_ids': ['i2', 'i1'],
        'custom_image_ref': 'attract_image_1.png',
        'attract_media_mode': 'custom_image',
        'attract_interval_seconds': 4,
      };
      final restored = KioskAppearanceSettings.fromJson(
        legacy,
        KioskAppearanceSettings.defaults(fallbackName: 'x'),
      );
      expect(restored.uiThemeWire, 'navy_ember');
      expect(restored.restaurantDisplayName, 'Burger House');
      expect(restored.featuredMenuItemIds, ['i2', 'i1']);
      expect(restored.customImageRef, 'attract_image_1.png');
      expect(restored.attractMediaMode, KioskAttractMediaMode.customImage);
      expect(restored.attractIntervalSeconds, 4);
    });
  });

  group('B. presets', () {
    test('every preset wire round-trips through the appearance JSON and '
        'resolves to itself', () {
      for (final preset in KioskThemePair.presets) {
        final settings = KioskAppearanceSettings.defaults(
          fallbackName: 'x',
        ).copyWith(uiThemeWire: preset.wire);
        final restored = KioskAppearanceSettings.fromJson(
          jsonDecode(jsonEncode(settings.toJson())),
          KioskAppearanceSettings.defaults(fallbackName: 'x'),
        );
        expect(restored.uiThemeWire, preset.wire);
        expect(KioskThemePair.fromWire(restored.uiThemeWire).wire, preset.wire);
      }
    });

    test('restart persistence is device-scoped: another device never '
        'inherits the theme', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = KioskAppearanceStore(prefs);
      final defaults = KioskAppearanceSettings.defaults(fallbackName: 'a');
      await store.save('dev-a', defaults.copyWith(uiThemeWire: 'forest_ember'));
      // A NEW store over the same prefs (an app restart).
      final restarted = KioskAppearanceStore(prefs);
      expect(restarted.load('dev-a', defaults)!.uiThemeWire, 'forest_ember');
      expect(restarted.load('dev-b', defaults), isNull); // no inheritance
    });

    test('preset structural families are dark and hue-shifted, never a '
        'solid-primary wall', () {
      final forest = KioskThemePair.forestEmber;
      // Canvas keeps the locked LIGHTNESS (dark premium), not the seed's.
      expect(forest.structuralCanvasBottom.computeLuminance(), lessThan(0.02));
      expect(forest.structuralCanvasTop.computeLuminance(), lessThan(0.03));
      // ...while carrying the seed's green hue (8-bit RGB quantization at
      // very low lightness drifts a couple of degrees).
      final hue = HSLColor.fromColor(forest.structuralCanvasTop).hue;
      final seedHue = HSLColor.fromColor(forest.primary).hue;
      expect((hue - seedHue).abs(), lessThan(4.0));
      // The gold preset's CTA ink derives DARK (light action).
      expect(KioskThemePair.charcoalGold.onAction, isNot(Colors.white));
    });
  });

  group('C. custom pairs', () {
    test('custom wire codec preserves the EXACT selected hexes', () {
      final pair = KioskThemePair.custom(
        primary: const Color(0xFF5C1E2E), // burgundy
        action: const Color(0xFFD89A2B), // gold
      );
      expect(pair.wire, 'custom:5C1E2E:D89A2B');
      final decoded = KioskThemePair.fromWire(pair.wire);
      expect(decoded.primary.toARGB32(), 0xFF5C1E2E);
      expect(decoded.action.toARGB32(), 0xFFD89A2B);
      expect(decoded.isCustom, isTrue);
    });

    test('a LIGHT custom primary still yields a dark canvas family with '
        'readable dark ink on exact-primary surfaces', () {
      final cream = KioskThemePair.custom(
        primary: const Color(0xFFF4EBDD),
        action: const Color(0xFF1E4D3B),
      );
      // The seed itself is never altered...
      expect(cream.primary.toARGB32(), 0xFFF4EBDD);
      // ...its ink is measured, not assumed:
      expect(cream.onPrimary, isNot(Colors.white));
      expect(
        kioskContrastRatio(cream.onPrimary, cream.primary),
        greaterThanOrEqualTo(4.5),
      );
      // ...and the huge canvas stays dark-premium (hue-tinted, never cream).
      expect(cream.structuralCanvasBottom.computeLuminance(), lessThan(0.02));
      expect(cream.structuralPanel.computeLuminance(), lessThan(0.06));
    });

    test('onAction is measured: light gold gets dark ink, dark ember keeps '
        'white; a near-black action gains a VISIBLE ring tone', () {
      final gold = KioskThemePair.custom(
        primary: const Color(0xFF16263B),
        action: const Color(0xFFF2D06B),
      );
      expect(gold.onAction, isNot(Colors.white));
      expect(
        kioskContrastRatio(gold.onAction, gold.action),
        greaterThanOrEqualTo(2.6),
      );
      final ember = KioskThemePair.custom(
        primary: const Color(0xFF16263B),
        action: const Color(0xFFF97316),
      );
      expect(ember.onAction, Colors.white);
      // Dark action on the dark bed: the derived ring walks lighter until
      // visible; the SELECTED action itself stays exact.
      final darkAction = KioskThemePair.custom(
        primary: const Color(0xFF16263B),
        action: const Color(0xFF101820),
      );
      expect(darkAction.action.toARGB32(), 0xFF101820);
      expect(
        kioskContrastRatio(
          darkAction.actionRing,
          darkAction.structuralCanvasBottom,
        ),
        greaterThanOrEqualTo(2.2),
      );
      // actionSoft reads against the panel bed.
      expect(
        kioskContrastRatio(darkAction.actionSoft, darkAction.structuralPanel),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('D/E. draft isolation, apply, global application', () {
    Future<ProviderContainer> pumpShell(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [kioskRealModeProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return container;
    }

    testWidgets('saving a preset re-themes the WHOLE shell: canvas, CTA and '
        'action roles all follow the pair', (tester) async {
      final container = await pumpShell(tester);
      expect(KioskColors.canvasTop.toARGB32(), 0xFF0A1526); // default bound
      await container
          .read(kioskAppearanceProvider.notifier)
          .save(
            KioskAppearanceSettings.defaults(
              fallbackName: 'x',
            ).copyWith(uiThemeWire: 'forest_ember'),
          );
      await tester.pump(const Duration(milliseconds: 300));
      final forest = KioskThemePair.forestEmber;
      // The bound token layer IS the pair now — every identity role follows.
      expect(KioskColors.canvasTop, forest.structuralCanvasTop);
      expect(KioskColors.sheetTop, forest.structuralPanel);
      expect(KioskColors.ring, forest.actionRing);
      expect(KioskColors.accentTop, forest.actionHi);
      // And the rendered stage really paints the themed canvas.
      final stageBox = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.gradient is LinearGradient)
          .map((d) => (d.gradient! as LinearGradient).colors.first.toARGB32());
      expect(stageBox, contains(forest.structuralCanvasTop.toARGB32()));
    });

    testWidgets('draft isolation: choosing a preset in settings changes '
        'NOTHING until Save; Reset returns the default', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          kioskRealModeProvider.overrideWithValue(true),
          kioskAppearanceStoreProvider.overrideWithValue(
            KioskAppearanceStore(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(kioskAppearanceScopeProvider.notifier).state = (
        deviceId: 'dev-1',
        fallbackName: 'x',
      );
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      );
      container.read(kioskFlowProvider.notifier).enterSettingsAfterStaffAuth();
      await tester.pump(const Duration(milliseconds: 400));

      // Tap the Forest preset card (draft only).
      await tester.scrollUntilVisible(
        find.byKey(const Key('kiosk-uitheme-forest_ember')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('kiosk-uitheme-forest_ember')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        container.read(kioskAppearanceProvider).uiThemeWire,
        'navy_ember',
        reason: 'a preset tap must stay a DRAFT until Save',
      );
      expect(KioskColors.canvasTop.toARGB32(), 0xFF0A1526);

      // Save applies + persists.
      await tester.scrollUntilVisible(
        find.byKey(const Key('kiosk-appearance-save')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('kiosk-appearance-save')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        container.read(kioskAppearanceProvider).uiThemeWire,
        'forest_ember',
      );
      expect(
        KioskColors.canvasTop,
        KioskThemePair.forestEmber.structuralCanvasTop,
      );
      expect(
        prefs.getString(KioskAppearanceStore.keyFor('dev-1')),
        contains('forest_ember'),
      );

      // Reset pill returns the draft to default; Save applies it.
      await tester.scrollUntilVisible(
        find.byKey(const Key('kiosk-uitheme-reset')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('kiosk-uitheme-reset')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('kiosk-appearance-save')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(kioskAppearanceProvider).uiThemeWire, 'navy_ember');
      expect(KioskColors.canvasTop.toARGB32(), 0xFF0A1526);
    });
  });

  group('F. semantic + receipt freeze', () {
    test(
      'semantic and receipt tokens are UNTHEMED constants under any pair',
      () {
        KioskColors.pair = KioskThemePair.custom(
          primary: const Color(0xFF5C1E2E),
          action: const Color(0xFFD89A2B),
        );
        addTearDown(KioskColors.resetToDefault);
        expect(KioskColors.successTop.toARGB32(), 0xFF22C55E);
        expect(KioskColors.successBottom.toARGB32(), 0xFF15803D);
        expect(KioskColors.danger.toARGB32(), 0xFFDC2626);
        expect(KioskColors.tableFree.toARGB32(), 0xFF4ADE80);
        expect(KioskColors.tableOccupied.toARGB32(), 0xFFF87171);
        expect(KioskColors.tableReserved.toARGB32(), 0xFFFBBF24);
        expect(KioskColors.slipPaper, Colors.white);
        expect(KioskColors.slipInk.toARGB32(), 0xFF101828);
        // BIZBOT official identity: the slip accent is the Emerald primary.
        expect(KioskColors.slipAccent.toARGB32(), 0xFF059669);
        expect(KioskColors.scrim.toARGB32(), 0xB303060C);
        expect(kioskSuccessGradient.colors.map((c) => c.toARGB32()), [
          0xFF22C55E,
          0xFF15803D,
        ]);
      },
    );
  });
}
