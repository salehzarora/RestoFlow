import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';
import 'package:restoflow_admin/src/data/platform_overview.dart';
import 'package:restoflow_admin/src/data/platform_overview_calculator.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A repository whose [loadOverview] resolves after a delay (to observe loading).
class _DelayedRepo implements PlatformAdminRepository {
  @override
  Future<PlatformOverview> loadOverview() => Future.delayed(
    const Duration(milliseconds: 50),
    () => computePlatformOverview(demoPlatformDataset()),
  );
}

Widget _wrap(PlatformAdminRepository repo) => ProviderScope(
  overrides: [platformAdminRepositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: PlatformAdminScreen(),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shows a loading state while the overview resolves', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(_DelayedRepo()));
    await tester.pump(); // first frame: future still pending

    expect(find.byKey(const Key('platform-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading platform data…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80)); // resolve the future
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('platform-loading')), findsNothing);
    expect(find.byKey(const Key('platform-overview-title')), findsOneWidget);
  });

  testWidgets('shows an error state with a retry action', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(const DemoPlatformAdminRepository(failureMessage: 'boom')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-error')), findsOneWidget);
    expect(find.text("Couldn't load platform data."), findsOneWidget);
    expect(find.byKey(const Key('platform-retry-button')), findsOneWidget);
  });

  testWidgets('shows an empty state when there is no platform data', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(DemoPlatformAdminRepository(dataset: emptyPlatformDataset())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-empty')), findsOneWidget);
    expect(find.text('No platform data yet.'), findsOneWidget);
    // The honest demo banner is still shown above the empty state.
    expect(find.byKey(const Key('platform-demo-banner')), findsOneWidget);
  });
}
