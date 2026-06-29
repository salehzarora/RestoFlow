import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';
import 'package:restoflow_admin/src/data/platform_overview.dart';
import 'package:restoflow_admin/src/data/platform_overview_calculator.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-134: the platform-admin overview must be honest about its data source.
/// In REAL mode it shows a "live but limited" notice (not the demo banner),
/// hides the KPIs the RF-091/RF-125 read panel does not provide, hides the
/// per-branch health section, and renders categorized safe states for the
/// real-mode failures. Demo mode keeps the full demo overview.
///
/// No SupabaseClient and no network: the mode is forced via
/// [runtimeConfigProvider] and the data via an injected repository.

/// A repository that returns a fixed overview (or throws) so the screen can be
/// driven in real mode without a transport.
class _FixedRepo implements PlatformAdminRepository {
  const _FixedRepo(this._overview);

  final PlatformOverview _overview;

  @override
  Future<PlatformOverview> loadOverview() async => _overview;
}

/// A repository that always throws the given [PlatformAdminException].
class _ThrowingRepo implements PlatformAdminRepository {
  const _ThrowingRepo(this._error);

  final Object _error;

  @override
  Future<PlatformOverview> loadOverview() async => throw _error;
}

/// A real-shaped overview, mirroring [RealPlatformAdminRepository]'s mapping:
/// org/restaurant/branch counts + the active-org count + organizations +
/// activity are real; the panel does NOT provide active branches, devices,
/// today's orders, or per-branch health, so those stay 0 / empty.
PlatformOverview _realShapedOverview() => PlatformOverview(
  generatedDateLabel: '2026-06-28',
  organizationCount: 2,
  activeOrganizationCount: 1,
  restaurantCount: 3,
  branchCount: 4,
  activeBranchCount: 0,
  deviceCount: 0,
  warningCount: 1,
  todayOrderCount: 0,
  organizations: const [
    OrgSummary(
      organizationName: 'Aleph Foods',
      restaurantCount: 1,
      branchCount: 1,
      status: 'suspended',
      plan: '—',
      createdAtLabel: '—',
    ),
    OrgSummary(
      organizationName: 'Bistro Co',
      restaurantCount: 2,
      branchCount: 3,
      status: 'active',
      plan: '—',
      createdAtLabel: '—',
    ),
  ],
  branchHealth: const <BranchHealth>[],
  activity: const [
    ActivityEvent(
      timestampLabel: '2026-06-28 10:15',
      action: 'platform.organizations.overview',
      summary: 'platform overview (read-only)',
    ),
  ],
);

Widget _wrap(PlatformAdminRepository repo, {required bool demo}) =>
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: demo),
        ),
        platformAdminRepositoryProvider.overrideWithValue(repo),
      ],
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
  group('real mode chrome + KPI honesty', () {
    testWidgets('shows the real-mode notice (not the demo banner) and the '
        '"Live · limited" pill', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(_FixedRepo(_realShapedOverview()), demo: false),
      );
      await tester.pumpAndSettle();

      // Real-mode notice replaces the demo banner.
      expect(find.byKey(const Key('platform-realmode-banner')), findsOneWidget);
      expect(find.byKey(const Key('platform-demo-banner')), findsNothing);

      // The header pill is honest: "Live · limited", never "Demo data".
      expect(find.text('Live · limited'), findsOneWidget);
      expect(find.text('Demo data'), findsNothing);
    });

    testWidgets('hides the KPIs the read panel does not provide; keeps the '
        'org/restaurant/branch KPIs', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(_FixedRepo(_realShapedOverview()), demo: false),
      );
      await tester.pumpAndSettle();

      // Provided by the RF-091 panel -> shown.
      expect(find.byKey(const Key('kpi-organizations')), findsOneWidget);
      expect(find.byKey(const Key('kpi-restaurants')), findsOneWidget);
      expect(find.byKey(const Key('kpi-branches')), findsOneWidget);

      // NOT provided by the panel -> hidden (never a fabricated 0).
      expect(find.byKey(const Key('kpi-active-branches')), findsNothing);
      expect(find.byKey(const Key('kpi-devices')), findsNothing);
      expect(find.byKey(const Key('kpi-alerts')), findsNothing);
      expect(find.byKey(const Key('kpi-orders-today')), findsNothing);
    });

    testWidgets('hides the per-branch health section; keeps organizations + '
        'activity', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(_FixedRepo(_realShapedOverview()), demo: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('branch-health-card')), findsNothing);
      expect(find.byKey(const Key('organizations-card')), findsOneWidget);
      expect(find.byKey(const Key('recent-activity-card')), findsOneWidget);
    });
  });

  group('real mode empty overview stays honest', () {
    testWidgets('an empty real overview shows the empty state under the '
        'real-mode banner (never the demo banner)', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(
          _FixedRepo(computePlatformOverview(emptyPlatformDataset())),
          demo: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-empty')), findsOneWidget);
      expect(find.byKey(const Key('platform-realmode-banner')), findsOneWidget);
      expect(find.byKey(const Key('platform-demo-banner')), findsNothing);
      expect(find.text('Demo data'), findsNothing);
    });
  });

  group('demo mode keeps the full overview (regression both ways)', () {
    testWidgets('shows the demo banner + all KPIs; no real-mode notice', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(
          _FixedRepo(computePlatformOverview(demoPlatformDataset())),
          demo: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-demo-banner')), findsOneWidget);
      expect(find.byKey(const Key('platform-realmode-banner')), findsNothing);
      expect(find.text('Demo data'), findsOneWidget);

      // All four otherwise-hidden KPIs are present in demo mode.
      expect(find.byKey(const Key('kpi-active-branches')), findsOneWidget);
      expect(find.byKey(const Key('kpi-devices')), findsOneWidget);
      expect(find.byKey(const Key('kpi-alerts')), findsOneWidget);
      expect(find.byKey(const Key('kpi-orders-today')), findsOneWidget);
      expect(find.byKey(const Key('branch-health-card')), findsOneWidget);
    });
  });

  group('categorized failure safe states', () {
    testWidgets('notConfigured -> a "not configured" state with no retry', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(
          const _ThrowingRepo(
            PlatformAdminException(
              'unconfigured',
              kind: PlatformAdminErrorKind.notConfigured,
            ),
          ),
          demo: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-not-configured')), findsOneWidget);
      expect(find.text("Platform admin isn't configured"), findsOneWidget);
      // Retrying cannot fix a missing config -> no retry action, no generic
      // error state.
      expect(find.byKey(const Key('platform-retry-button')), findsNothing);
      expect(find.byKey(const Key('platform-error')), findsNothing);
    });

    testWidgets('accessDenied -> an "access denied" state with no retry', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(
          const _ThrowingRepo(
            PlatformAdminException(
              'denied',
              kind: PlatformAdminErrorKind.accessDenied,
            ),
          ),
          demo: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-access-denied')), findsOneWidget);
      expect(find.text('Platform admin access denied'), findsOneWidget);
      expect(find.byKey(const Key('platform-retry-button')), findsNothing);
      expect(find.byKey(const Key('platform-error')), findsNothing);
    });

    testWidgets('unexpected -> the generic, retryable error state', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _wrap(const _ThrowingRepo(PlatformAdminException('boom')), demo: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-error')), findsOneWidget);
      expect(find.text("Couldn't load platform data."), findsOneWidget);
      expect(find.byKey(const Key('platform-retry-button')), findsOneWidget);
      expect(find.byKey(const Key('platform-not-configured')), findsNothing);
      expect(find.byKey(const Key('platform-access-denied')), findsNothing);
    });

    testWidgets(
      'a non-PlatformAdminException falls back to the generic error',
      (tester) async {
        _wide(tester);
        await tester.pumpWidget(
          _wrap(const _ThrowingRepo(FormatException('odd')), demo: false),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('platform-error')), findsOneWidget);
        expect(find.byKey(const Key('platform-retry-button')), findsOneWidget);
      },
    );
  });
}
