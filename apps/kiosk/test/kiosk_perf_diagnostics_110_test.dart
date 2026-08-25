import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_appearance.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/screens/perf_diagnostics_section.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — the TEST-BUILD-ONLY perf diagnostics
/// card in the kiosk's REAL-mode staff settings: absent by default, present
/// (with the stage scale row) when the build enables it.
void main() {
  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    bool? enabled,
    Size physical = const Size(1080, 1920),
    double dpr = 1,
  }) async {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        kioskRealModeProvider.overrideWithValue(true),
        if (enabled != null)
          kioskPerfDiagnosticsEnabledProvider.overrideWithValue(enabled),
      ],
    );
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
    container.read(kioskFlowProvider.notifier).enterSettingsAfterStaffAuth();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(kioskFlowProvider).screen, KioskScreen.settings);
    return container;
  }

  testWidgets('ABSENT in a stock build (flag defaults to false)', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(
      find.byKey(const Key('kiosk-settings-perf-diagnostics')),
      findsNothing,
    );
  });

  testWidgets('PRESENT when enabled: stage scale + device rows + reset', (
    tester,
  ) async {
    await pumpSettings(tester, enabled: true);
    final card = find.byKey(const Key('kiosk-settings-perf-diagnostics'));
    await tester.scrollUntilVisible(
      card,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('perf-row-app'))).data,
      'Kiosk',
    );
    expect(find.text('1.0000'), findsOneWidget); // stage scale at native size
    expect(find.text('1080 × 1920'), findsWidgets); // design + logical
    expect(find.text('portrait'), findsOneWidget);
    expect(find.byKey(const Key('perf-diagnostics-reset')), findsOneWidget);
  });

  testWidgets('the stage scale row reports the real letterbox factor', (
    tester,
  ) async {
    // 540×960 logical (1080×1920 physical at dpr 2) → stage scale 0.5.
    await pumpSettings(
      tester,
      enabled: true,
      physical: const Size(1080, 1920),
      dpr: 2,
    );
    final card = find.byKey(const Key('kiosk-settings-perf-diagnostics'));
    await tester.scrollUntilVisible(
      card,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('0.5000'), findsOneWidget);
    expect(find.text('540 × 960'), findsOneWidget); // logical
    expect(find.text('2.000'), findsOneWidget); // dpr
  });
}
