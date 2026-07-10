import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PILOT-OFFLINE-BOOT-001: the retryable boot gate used by BOTH POS and KDS.
/// Testing it once covers both apps' launch-resilience behaviour (the gate is
/// generic; each app only supplies the bootstrap + builder).

/// The "real app" the gate builds for a NON-offline result.
Widget _appMarker() => MaterialApp(
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: const Scaffold(body: Text('app-ready')),
);

DeviceBootGate<bool> _gate({
  required Future<bool> Function() bootstrap,
  Locale locale = const Locale('en'),
  Duration? autoRetryInterval,
}) => DeviceBootGate<bool>(
  locale: locale,
  autoRetryInterval: autoRetryInterval,
  bootstrap: bootstrap,
  isOffline: (offline) => offline,
  builder: (_) => _appMarker(),
);

void main() {
  testWidgets('an offline result shows the retryable offline screen', (
    tester,
  ) async {
    await tester.pumpWidget(_gate(bootstrap: () async => true));
    await tester.pumpAndSettle();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.byKey(const Key('offline-boot-retry')), findsOneWidget);
    expect(find.text('app-ready'), findsNothing);
  });

  testWidgets('Retry re-runs bootstrap and reaches the app when the network '
      'returns — no restart', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _gate(
        bootstrap: () async {
          calls++;
          return calls == 1; // offline first, online after
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No connection'), findsOneWidget);

    await tester.tap(find.byKey(const Key('offline-boot-retry')));
    await tester.pumpAndSettle();

    expect(find.text('app-ready'), findsOneWidget);
    expect(find.text('No connection'), findsNothing);
    expect(calls, 2);
  });

  testWidgets('a NON-offline result goes straight to the app (config/auth '
      'errors are not shown as offline)', (tester) async {
    // isOffline=false -> the gate hands the result to builder, which for the
    // real apps renders the config/sign-in help page (not the offline screen).
    await tester.pumpWidget(_gate(bootstrap: () async => false));
    await tester.pumpAndSettle();

    expect(find.text('app-ready'), findsOneWidget);
    expect(find.text('No connection'), findsNothing);
  });

  testWidgets('shows a loading indicator while bootstrap is pending', (
    tester,
  ) async {
    final completer = Completer<bool>();
    await tester.pumpWidget(_gate(bootstrap: () => completer.future));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('app-ready'), findsOneWidget);
  });

  testWidgets('Arabic offline labels render in RTL', (tester) async {
    await tester.pumpWidget(
      _gate(bootstrap: () async => true, locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا يوجد اتصال'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('لا يوجد اتصال'))),
      TextDirection.rtl,
    );
  });

  testWidgets('auto-retry re-runs bootstrap after the interval without a tap', (
    tester,
  ) async {
    var calls = 0;
    // Explicit pumps (not pumpAndSettle) so the fake clock is advanced
    // deterministically past the pending auto-retry timer.
    await tester.pumpWidget(
      _gate(
        autoRetryInterval: const Duration(milliseconds: 50),
        bootstrap: () async {
          calls++;
          return calls == 1; // offline first, online after
        },
      ),
    );
    await tester.pump(); // bootstrap completes -> offline screen + timer armed
    expect(find.text('No connection'), findsOneWidget);
    expect(calls, 1);

    await tester.pump(const Duration(milliseconds: 60)); // fire the auto-retry
    await tester.pump(); // 2nd bootstrap completes -> app
    expect(find.text('app-ready'), findsOneWidget);
    expect(calls, 2);
  });
}
