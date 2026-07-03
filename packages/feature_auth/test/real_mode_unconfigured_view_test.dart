import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<void> _pump(WidgetTester tester, {Locale? locale}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: const RealModeUnconfiguredView(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the config help: title, required defines, demo hint', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Real mode is not configured'), findsOneWidget);
    // The exact --dart-define lines a developer must supply.
    expect(find.textContaining('RESTOFLOW_DEMO_MODE=false'), findsOneWidget);
    expect(find.textContaining('RESTOFLOW_SUPABASE_URL'), findsOneWidget);
    expect(find.textContaining('RESTOFLOW_SUPABASE_ANON_KEY'), findsOneWidget);
    expect(find.textContaining('demo mode is the default'), findsOneWidget);
  });

  testWidgets('never shows a secret value — env NAMES only', (tester) async {
    await _pump(tester);
    // The page teaches the env names; it must not echo any configured value.
    expect(find.textContaining('eyJ'), findsNothing);
    expect(find.textContaining('sb_secret'), findsNothing);
  });

  testWidgets('renders under RTL (Arabic) without overflow', (tester) async {
    await _pump(tester, locale: const Locale('ar'));
    expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
