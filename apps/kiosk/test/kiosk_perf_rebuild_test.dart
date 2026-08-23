import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/screens/menu_screen.dart';
import 'package:restoflow_kiosk/src/screens/service_screen.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/widgets/category_wheel.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — the invisible 1-second clock
/// (`secondsSinceActivity`) must NOT rebuild the root shell or the active
/// screen subtree; only the legitimately visible countdowns (idle warning,
/// confirmation auto-return) may update once per second.
///
/// Instrumentation: `debugOnRebuildDirtyWidget` counts every widget rebuilt
/// per frame, so the assertions are about REAL element rebuilds, not about
/// provider emissions alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  final rebuilt = <Type, int>{};

  void startCounting() {
    rebuilt.clear();
    debugOnRebuildDirtyWidget = (element, _) {
      final w = element.widget;
      // Riverpod's scope element marks ITSELF dirty to flush the provider
      // graph after any state change (an InheritedWidget with
      // updateShouldNotify=false, so nothing below it rebuilds). That one
      // framework-internal element is inherent to the clock advancing at
      // all and is not app churn — ignore it.
      if (w is UncontrolledProviderScope || w is ProviderScope) return;
      final t = w.runtimeType;
      rebuilt[t] = (rebuilt[t] ?? 0) + 1;
    };
  }

  void stopCounting() {
    debugOnRebuildDirtyWidget = null;
  }

  int count(Type t) => rebuilt[t] ?? 0;

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(stopCounting);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: Locale(ref.watch(kioskFlowProvider.select((s) => s.lang))),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  KioskFlowController controller() =>
      container.read(kioskFlowProvider.notifier);
  KioskState state() => container.read(kioskFlowProvider);

  Future<void> toMenu(WidgetTester tester) async {
    controller().startFromAttract();
    controller().pickService(KioskServiceType.takeaway);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Settles any in-flight screen fade so later frames are quiet.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('A. invisible clock churn', () {
    testWidgets(
      'a tick that only advances secondsSinceActivity rebuilds NOTHING on the '
      'menu (shell, menu screen, wheel, bottom bar, product cards all quiet)',
      (tester) async {
        await pumpShell(tester);
        await toMenu(tester);
        await settle(tester);
        expect(state().screen, KioskScreen.menu);
        expect(state().secondsSinceActivity, 0);

        startCounting();
        controller().tick(); // 0 -> 1 second idle, far from the warning
        await tester.pump();
        await tester.pump();
        stopCounting();

        expect(state().secondsSinceActivity, 1);
        expect(state().idleSecondsLeft, isNull);
        expect(count(KioskShell), 0, reason: 'root shell rebuilt on clock');
        expect(count(KioskMenuScreen), 0, reason: 'menu screen rebuilt');
        expect(count(KioskCategoryWheel), 0, reason: 'wheel rebuilt');
        expect(count(KioskBottomBar), 0, reason: 'bottom bar rebuilt');
        expect(rebuilt, isEmpty, reason: 'some widget rebuilt: $rebuilt');
      },
    );

    testWidgets('the same holds on the service screen', (tester) async {
      await pumpShell(tester);
      controller().startFromAttract();
      await settle(tester);
      expect(state().screen, KioskScreen.service);

      startCounting();
      controller().tick();
      await tester.pump();
      await tester.pump();
      stopCounting();

      expect(state().secondsSinceActivity, 1);
      expect(count(KioskShell), 0);
      expect(count(KioskServiceScreen), 0);
      expect(rebuilt, isEmpty, reason: 'some widget rebuilt: $rebuilt');
    });

    testWidgets(
      'touch() when already at zero/null is a TRUE no-op (no new state)',
      (tester) async {
        await pumpShell(tester);
        await toMenu(tester);
        await settle(tester);
        var emissions = 0;
        container.listen(kioskFlowProvider, (_, _) => emissions++);
        final before = state();
        controller().touch();
        expect(emissions, 0, reason: 'touch emitted a redundant state');
        expect(identical(state(), before), isTrue);

        // ...but still clears a real idle count.
        controller().tick();
        expect(state().secondsSinceActivity, 1);
        emissions = 0;
        controller().touch();
        expect(emissions, 1);
        expect(state().secondsSinceActivity, 0);
        expect(state().idleSecondsLeft, isNull);
      },
    );

    testWidgets(
      'ordinary idle counting 60→11 never rebuilds the menu; the warning '
      'overlay appears at the same 10-second point and counts down visibly',
      (tester) async {
        await pumpShell(tester);
        await toMenu(tester);
        await settle(tester);
        final idle = state().settings.idleSeconds; // 60
        startCounting();
        for (var i = 0; i < idle - 11; i++) {
          controller().tick();
        }
        await tester.pump();
        await tester.pump();
        stopCounting();
        expect(state().secondsSinceActivity, idle - 11);
        expect(state().idleSecondsLeft, isNull);
        expect(find.byKey(const Key('kiosk-idle-count')), findsNothing);
        expect(rebuilt, isEmpty, reason: 'idle counting rebuilt: $rebuilt');

        // Next tick reaches the warning window: left == 10.
        controller().tick();
        await tester.pump();
        expect(state().idleSecondsLeft, 10);
        expect(find.byKey(const Key('kiosk-idle-count')), findsOneWidget);
        expect(find.text('10'), findsOneWidget);

        // Visible countdown updates once per second; the MENU stays quiet.
        startCounting();
        controller().tick();
        await tester.pump();
        await tester.pump();
        stopCounting();
        expect(find.text('9'), findsOneWidget);
        expect(count(KioskMenuScreen), 0, reason: 'menu rebuilt under warning');
        expect(count(KioskCategoryWheel), 0);
        expect(count(KioskBottomBar), 0);

        // Exact timeout preserved: 9 more ticks -> reset to attract.
        for (var i = 0; i < 9; i++) {
          controller().tick();
        }
        expect(state().screen, KioskScreen.attract);
      },
    );
  });
}
