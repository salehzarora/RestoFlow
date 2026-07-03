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
      home: const DeviceSignInUnavailableView(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('states the exact cause and the local fix', (tester) async {
    await _pump(tester);
    expect(find.text('Device sign-in unavailable'), findsOneWidget);
    // The prescribed, actionable reason — never a generic account denial.
    expect(
      find.text(
        'Anonymous device sign-in is disabled or Supabase auth is not '
        'configured.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('enable_anonymous_sign_ins = true'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No personal account is needed'),
      findsOneWidget,
    );
  });

  testWidgets('never shows a secret value — config names only', (tester) async {
    await _pump(tester);
    expect(find.textContaining('eyJ'), findsNothing);
    expect(find.textContaining('sb_secret'), findsNothing);
  });

  testWidgets('renders under RTL (Hebrew) without overflow', (tester) async {
    await _pump(tester, locale: const Locale('he'));
    expect(find.byType(DeviceSignInUnavailableView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
