/// The console's honest loading / error / empty states (RF-134, ADMIN-125C.2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';

import 'console_test_harness.dart';

void main() {
  testWidgets('shows a loading state while the overview resolves', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(consoleApp(repo: DelayedConsoleRepository()));
    await tester.pump(); // first frame: the future is still pending

    expect(find.byKey(const Key('platform-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading platform data…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('platform-loading')), findsNothing);
    expect(find.byKey(const Key('kpi-organizations')), findsOneWidget);
  });

  testWidgets('shows an error state with a retry action', (tester) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(
      consoleApp(
        repo: const DemoPlatformAdminRepository(failureMessage: 'boom'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-error')), findsOneWidget);
    expect(find.text("Couldn't load platform data."), findsOneWidget);
    expect(find.byKey(const Key('platform-retry-button')), findsOneWidget);
    // The developer-facing message stays developer-facing.
    expect(find.text('boom'), findsNothing);
  });

  testWidgets('shows an empty state when there is no platform data', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    await tester.pumpWidget(
      consoleApp(
        repo: DemoPlatformAdminRepository(dataset: emptyPlatformDataset()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-empty')), findsOneWidget);
    expect(find.text('No platform data yet.'), findsOneWidget);
    // The provenance strip stays above the empty state.
    expect(find.byKey(const Key('platform-demo-banner')), findsOneWidget);
  });

  testWidgets('retry re-runs the read', (tester) async {
    useSize(tester, kDesktop);
    final repo = RecordingConsoleRepository();
    await tester.pumpWidget(consoleApp(repo: repo));
    await tester.pumpAndSettle();
    expect(repo.calls, ['overview', 'operations']);

    await tester.tap(find.byKey(const Key('platform-refresh-button')));
    await tester.pumpAndSettle();
    // Refresh re-reads BOTH halves of the Overview — the counts and the money
    // beside them. Refreshing only one would leave a stale figure on screen
    // under a button that appeared to work.
    expect(repo.calls, ['overview', 'operations', 'overview', 'operations']);
  });
}
