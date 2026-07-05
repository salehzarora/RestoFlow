import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/admin_platform_gate.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-LIVE-002 — the Admin "open the Dashboard" link must NOT be a hardcoded
/// localhost URL on a hosted Admin. [resolveDashboardUrl] prefers the configured
/// (hosted) Dashboard URL and falls back to the local origin only for local/dev.
Future<void> _pumpExplainer(WidgetTester tester, {String? dashboardUrl}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: AdminGateExplainer(
          signedIn: true,
          onRetry: () {},
          onSignOut: () {},
          dashboardUrl: dashboardUrl,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('resolveDashboardUrl', () {
    test('a configured (hosted) URL wins over the local fallback', () {
      expect(
        resolveDashboardUrl('https://dashboard.restoflow.app'),
        'https://dashboard.restoflow.app',
      );
    });

    test('an empty/whitespace value falls back to the local origin (never a '
        'dead blank link)', () {
      expect(resolveDashboardUrl(''), kLocalDashboardUrl);
      expect(resolveDashboardUrl('   '), kLocalDashboardUrl);
    });

    test('null (no configured value / no dart-define) falls back to the local '
        'origin', () {
      // In this test build no RESTOFLOW_DASHBOARD_URL dart-define is set, so the
      // resolver returns the stable local default.
      expect(resolveDashboardUrl(), kLocalDashboardUrl);
      expect(resolveDashboardUrl(null), kLocalDashboardUrl);
    });

    test('surrounding whitespace on a real value is trimmed', () {
      expect(resolveDashboardUrl('  https://d.example  '), 'https://d.example');
    });
  });

  group('AdminGateExplainer dashboard link', () {
    testWidgets('renders the CONFIGURED hosted Dashboard URL, not localhost', (
      tester,
    ) async {
      await _pumpExplainer(
        tester,
        dashboardUrl: 'https://dashboard.restoflow.app',
      );
      expect(find.text('https://dashboard.restoflow.app'), findsOneWidget);
      expect(find.text(kLocalDashboardUrl), findsNothing);
      // The open-dashboard action is present (it opens the same resolved URL).
      expect(
        find.byKey(const Key('admin-gate-open-dashboard')),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the local URL when none is configured', (
      tester,
    ) async {
      await _pumpExplainer(tester); // dashboardUrl: null
      expect(find.text(kLocalDashboardUrl), findsOneWidget);
    });
  });
}
