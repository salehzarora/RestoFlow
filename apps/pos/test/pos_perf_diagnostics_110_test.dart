import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — the TEST-BUILD-ONLY perf diagnostics
/// section in the POS staff Device Settings sheet: absent by default (the
/// compile-time flag is false), present with the POS layout rows when the
/// build enables it.
void main() {
  Future<void> pumpSheet(WidgetTester tester, {bool? enabled}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (enabled != null)
            perfDiagnosticsEnabledProvider.overrideWithValue(enabled),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: PosDeviceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ABSENT in a stock build (flag defaults to false)', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(find.byKey(const Key('perf-diagnostics-section')), findsNothing);
    expect(find.byKey(const Key('perf-diagnostics-panel')), findsNothing);
  });

  testWidgets('PRESENT when enabled: POS layout rows + frame stats + reset', (
    tester,
  ) async {
    await pumpSheet(tester, enabled: true);
    final section = find.byKey(const Key('perf-diagnostics-section'));
    await tester.scrollUntilVisible(
      section,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(section, findsOneWidget);
    expect(find.byKey(const Key('perf-diagnostics-panel')), findsOneWidget);
    expect(find.text('POS'), findsOneWidget);
    // 1280x800 → tablet / twoPane / 4 columns
    expect(find.text('tablet'), findsOneWidget);
    expect(find.text('twoPane'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    // logical AND physical (dpr 1.0 in the test view)
    expect(find.text('1280 × 800'), findsNWidgets(2));
    expect(find.byKey(const Key('perf-diagnostics-reset')), findsOneWidget);
    await tester.tap(find.byKey(const Key('perf-diagnostics-reset')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
