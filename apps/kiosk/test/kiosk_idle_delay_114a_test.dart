import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_appearance.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-UX-114A — configurable inactivity delay BEFORE the idle warning.
///
/// Contract (owner-approved, verbatim):
/// * `idleDelaySeconds` on [KioskAppearanceSettings]; wire key
///   `idle_delay_seconds`; allowed values EXACTLY {10, 15, 20, 25, 30, 60};
/// * the value is the PRE-WARNING delay — the existing 10-second warning
///   window then runs unchanged, so total = delay + 10;
/// * missing / null / malformed → the LEGACY behavior byte-for-byte: warning
///   after 50 quiet seconds, reset at 60 (the fixture
///   `state.settings.idleSeconds` path — never a silently invented default);
/// * touch, "I'm still here", attract/settings/submit exemptions, and the
///   24-second confirmation auto-return are all untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const allowed = [10, 15, 20, 25, 30, 60];

  group('A. model contract', () {
    test('the choice list is exactly {10,15,20,25,30,60}', () {
      expect(KioskAppearanceLimits.idleDelayChoices, allowed);
    });

    test('both defaults ship UNSET (null) — nobody invents a hidden value', () {
      expect(KioskAppearanceSettings.demoDefaults().idleDelaySeconds, isNull);
      expect(
        KioskAppearanceSettings.defaults(
          fallbackName: 'first',
        ).idleDelaySeconds,
        isNull,
      );
    });

    test('copyWith sets, keeps-when-omitted, and clears back to null', () {
      final base = KioskAppearanceSettings.demoDefaults();
      final set = base.copyWith(idleDelaySeconds: 20);
      expect(set.idleDelaySeconds, 20);
      expect(set.copyWith().idleDelaySeconds, 20);
      expect(set.copyWith(brandTitlePrimary: 'X').idleDelaySeconds, 20);
      expect(set.copyWith(idleDelaySeconds: null).idleDelaySeconds, isNull);
    });

    test('toJson: unset writes NO key; set writes idle_delay_seconds', () {
      final base = KioskAppearanceSettings.demoDefaults();
      expect(base.toJson().containsKey('idle_delay_seconds'), isFalse);
      expect(
        base.copyWith(idleDelaySeconds: 25).toJson()['idle_delay_seconds'],
        25,
      );
    });

    test('fromJson round-trips every allowed choice AND the unset state', () {
      final fallback = KioskAppearanceSettings.defaults(fallbackName: 'x');
      for (final seconds in allowed) {
        final wire = jsonDecode(
          jsonEncode(fallback.copyWith(idleDelaySeconds: seconds).toJson()),
        );
        expect(
          KioskAppearanceSettings.fromJson(wire, fallback).idleDelaySeconds,
          seconds,
        );
      }
      final unsetWire = jsonDecode(jsonEncode(fallback.toJson()));
      expect(
        KioskAppearanceSettings.fromJson(unsetWire, fallback).idleDelaySeconds,
        isNull,
      );
    });

    test(
      'malformed stored values degrade to legacy (null) without crashing',
      () {
        final fallback = KioskAppearanceSettings.defaults(fallbackName: 'x');
        for (final bad in const <Object?>['20', 45, -5, 0, true, 3.5, null]) {
          final decoded = KioskAppearanceSettings.fromJson({
            ...fallback.toJson(),
            'idle_delay_seconds': bad,
          }, fallback);
          expect(
            decoded.idleDelaySeconds,
            isNull,
            reason: 'stored $bad must fall back to legacy, not crash or stick',
          );
        }
      },
    );
  });

  group('B. tick engine', () {
    late ProviderContainer container;
    late KioskFlowController controller;

    KioskState state() => container.read(kioskFlowProvider);

    setUp(() {
      container = ProviderContainer();
      controller = container.read(kioskFlowProvider.notifier);
      addTearDown(container.dispose);
    });

    Future<void> configureDelay(int? seconds) => container
        .read(kioskAppearanceProvider.notifier)
        .save(
          KioskAppearanceSettings.demoDefaults().copyWith(
            idleDelaySeconds: seconds,
          ),
        );

    void enterMenu() {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
    }

    void tickTimes(int n) {
      for (var i = 0; i < n; i++) {
        controller.tick();
      }
    }

    for (final delay in allowed) {
      test(
        '$delay s: warning at exactly $delay ticks, reset at ${delay + 10}',
        () async {
          await configureDelay(delay);
          enterMenu();
          tickTimes(delay - 1);
          expect(state().idleSecondsLeft, isNull);
          expect(state().screen, KioskScreen.menu);
          controller.tick(); // second `delay` → the 10s warning window opens
          expect(state().idleSecondsLeft, 10);
          tickTimes(9);
          expect(state().idleSecondsLeft, 1);
          expect(state().screen, KioskScreen.menu);
          controller.tick(); // second delay+10 → full reset
          expect(state().screen, KioskScreen.attract);
          expect(state().idleSecondsLeft, isNull);
        },
      );
    }

    test('UNSET preserves the legacy timeline byte-for-byte: warning at 50, '
        'reset at 60', () {
      enterMenu();
      tickTimes(49);
      expect(state().idleSecondsLeft, isNull);
      controller.tick();
      expect(state().idleSecondsLeft, 10);
      tickTimes(9);
      expect(state().idleSecondsLeft, 1);
      controller.tick();
      expect(state().screen, KioskScreen.attract);
    });

    test(
      'an out-of-range stored value resolves as LEGACY, never as itself',
      () async {
        await configureDelay(45); // not an allowed choice
        enterMenu();
        tickTimes(49);
        expect(state().idleSecondsLeft, isNull);
        controller.tick(); // legacy second 50, NOT 45
        expect(state().idleSecondsLeft, 10);
      },
    );

    test('touch resets the configured countdown', () async {
      await configureDelay(10);
      enterMenu();
      tickTimes(12); // warning showing (12 ≥ 10)
      expect(state().idleSecondsLeft, isNotNull);
      controller.touch();
      expect(state().idleSecondsLeft, isNull);
      tickTimes(9);
      expect(state().idleSecondsLeft, isNull);
      controller.tick();
      expect(state().idleSecondsLeft, 10);
    });

    test('"I\'m still here" restarts the configured delay', () async {
      await configureDelay(15);
      enterMenu();
      tickTimes(15);
      expect(state().idleSecondsLeft, 10);
      controller.dismissIdleWarning();
      expect(state().idleSecondsLeft, isNull);
      tickTimes(14);
      expect(state().idleSecondsLeft, isNull);
      controller.tick();
      expect(state().idleSecondsLeft, 10);
    });

    test('attract stays exempt under the shortest configured delay', () async {
      await configureDelay(10);
      tickTimes(200);
      expect(state().screen, KioskScreen.attract);
      expect(state().idleSecondsLeft, isNull);
    });

    test('settings stays exempt under the shortest configured delay', () async {
      await configureDelay(10);
      controller.enterSettingsAfterStaffAuth();
      tickTimes(200);
      expect(state().screen, KioskScreen.settings);
    });

    test(
      'the 24 s confirmation auto-return is UNTOUCHED by a 10 s delay',
      () async {
        await configureDelay(10);
        controller.startFromAttract();
        controller.pickService(KioskServiceType.takeaway);
        controller.openItem('d1');
        controller.submitDraft();
        controller.placeOrder();
        expect(state().screen, KioskScreen.confirm);
        tickTimes(23);
        expect(state().screen, KioskScreen.confirm);
        controller.tick();
        expect(state().screen, KioskScreen.attract);
      },
    );
  });

  group('C. persistence', () {
    test('store round-trip: set survives, unset survives, malformed JSON '
        'degrades to defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = KioskAppearanceStore(prefs);
      final defaults = KioskAppearanceSettings.defaults(fallbackName: 'first');

      await store.save('dev-1', defaults.copyWith(idleDelaySeconds: 25));
      expect(store.load('dev-1', defaults)!.idleDelaySeconds, 25);

      await store.save('dev-1', defaults);
      expect(store.load('dev-1', defaults)!.idleDelaySeconds, isNull);

      await prefs.setString(
        KioskAppearanceStore.keyFor('dev-1'),
        '{"idle_delay_seconds":"soon"',
      );
      expect(store.load('dev-1', defaults), isNull); // fails safely
    });
  });

  group('D. settings UI', () {
    late ProviderContainer container;
    late SharedPreferences prefs;

    Future<void> pumpSettings(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      container = ProviderContainer(
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
        fallbackName: 'first',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('en'),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: KioskShell(),
          ),
        ),
      );
      container.read(kioskFlowProvider.notifier).enterSettingsAfterStaffAuth();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> showChip(WidgetTester tester, int seconds) =>
        tester.scrollUntilVisible(
          find.byKey(Key('kiosk-idle-delay-$seconds')),
          600,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('all six chips render; unset shows the legacy note', (
      tester,
    ) async {
      await pumpSettings(tester);
      await showChip(tester, 10);
      for (final seconds in allowed) {
        expect(
          find.byKey(Key('kiosk-idle-delay-$seconds')),
          findsOneWidget,
          reason: 'chip $seconds s must exist',
        );
      }
      expect(
        find.byKey(const Key('kiosk-idle-delay-legacy-note')),
        findsOneWidget,
        reason: 'unset must SAY it is on the legacy timing, not fake a chip',
      );
    });

    testWidgets('a chip tap is a DRAFT until Save; Save applies + persists', (
      tester,
    ) async {
      await pumpSettings(tester);
      await showChip(tester, 20);
      await tester.tap(find.byKey(const Key('kiosk-idle-delay-20')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        container.read(kioskAppearanceProvider).idleDelaySeconds,
        isNull,
        reason: 'the tap must stay a draft until Save',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('kiosk-appearance-save')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('kiosk-appearance-save')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(kioskAppearanceProvider).idleDelaySeconds, 20);
      expect(
        prefs.getString(KioskAppearanceStore.keyFor('dev-1')),
        contains('"idle_delay_seconds":20'),
      );
      // The chosen value replaces the legacy note.
      await showChip(tester, 20);
      expect(
        find.byKey(const Key('kiosk-idle-delay-legacy-note')),
        findsNothing,
      );
    });

    testWidgets('saving OTHER fields never invents an idle delay', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('kiosk-appearance-save')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('kiosk-appearance-save')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(kioskAppearanceProvider).idleDelaySeconds, isNull);
      expect(
        prefs.getString(KioskAppearanceStore.keyFor('dev-1')) ?? '',
        isNot(contains('idle_delay_seconds')),
      );
    });
  });
}
