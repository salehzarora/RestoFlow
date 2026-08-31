/// RF-134 + ADMIN-125C.2 — the console must be honest about its data source,
/// and DEMO and REAL must never bleed into each other.
///
/// In REAL mode the console shows a live pill (not the demo one) and renders
/// categorized safe states for each failure. In DEMO mode it shows the demo
/// pill. The load-bearing property is the one at the bottom: a real-mode
/// FAILURE must never fall back to demo data — a fabricated tenant list on a
/// live-labelled screen is worse than an error.
///
/// No SupabaseClient and no network: the mode is forced via
/// [runtimeConfigProvider] and the data via an injected repository.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';

import 'console_test_harness.dart';

/// A repository that always throws the given error.
class _ThrowingRepo implements PlatformAdminRepository {
  const _ThrowingRepo(this._error);

  final Object _error;

  @override
  Future<ConsoleOverview> loadConsoleOverview() async => throw _error;

  @override
  Future<SubscriberPage> loadSubscribers(SubscriberQuery query) async =>
      throw _error;

  @override
  Future<SubscriberDetail> loadSubscriberDetail(String organizationId) async =>
      throw _error;

  @override
  Future<RestaurantPage> loadRestaurants(RestaurantQuery query) async =>
      throw _error;

  @override
  Future<AuditPage> loadAuditPage(AuditQuery query) async => throw _error;

  @override
  Future<RestaurantOperationsPage> loadRestaurantOperations(
    RestaurantOperationsQuery query,
  ) async => throw _error;
}

void main() {
  group('data-source provenance', () {
    testWidgets('demo mode shows the demo pill, never the live one', (
      tester,
    ) async {
      useSize(tester, kDesktop);
      await tester.pumpWidget(consoleApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-demo-banner')), findsOneWidget);
      expect(find.byKey(const Key('platform-realmode-banner')), findsNothing);
      expect(find.text('Demo data'), findsOneWidget);
    });

    testWidgets('real mode shows the live pill, never the demo one', (
      tester,
    ) async {
      useSize(tester, kDesktop);
      await tester.pumpWidget(
        consoleApp(isDemoMode: false, repo: RecordingConsoleRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-realmode-banner')), findsOneWidget);
      expect(find.byKey(const Key('platform-demo-banner')), findsNothing);
      expect(find.text('Demo data'), findsNothing);
    });

    testWidgets('an empty REAL platform stays labelled live', (tester) async {
      useSize(tester, kDesktop);
      await tester.pumpWidget(
        consoleApp(
          isDemoMode: false,
          repo: DemoPlatformAdminRepository(dataset: emptyPlatformDataset()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-empty')), findsOneWidget);
      expect(find.byKey(const Key('platform-realmode-banner')), findsOneWidget);
      expect(find.byKey(const Key('platform-demo-banner')), findsNothing);
    });
  });

  group('categorized failure safe states', () {
    testWidgets('notConfigured -> a "not configured" state with no retry', (
      tester,
    ) async {
      useSize(tester, kDesktop);
      await tester.pumpWidget(
        consoleApp(
          isDemoMode: false,
          repo: const _ThrowingRepo(
            PlatformAdminException(
              'unconfigured',
              kind: PlatformAdminErrorKind.notConfigured,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-not-configured')), findsOneWidget);
      expect(find.text("Platform admin isn't configured"), findsOneWidget);
      // Retrying cannot fix a missing config.
      expect(find.byKey(const Key('platform-retry-button')), findsNothing);
      expect(find.byKey(const Key('platform-error')), findsNothing);
    });

    testWidgets('accessDenied -> an "access denied" state with no retry', (
      tester,
    ) async {
      useSize(tester, kDesktop);
      await tester.pumpWidget(
        consoleApp(
          isDemoMode: false,
          repo: const _ThrowingRepo(
            PlatformAdminException(
              'denied',
              kind: PlatformAdminErrorKind.accessDenied,
            ),
          ),
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
      useSize(tester, kDesktop);
      await tester.pumpWidget(
        consoleApp(
          isDemoMode: false,
          repo: const _ThrowingRepo(PlatformAdminException('boom')),
        ),
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
        useSize(tester, kDesktop);
        await tester.pumpWidget(
          consoleApp(
            isDemoMode: false,
            repo: const _ThrowingRepo(FormatException('odd')),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('platform-error')), findsOneWidget);
        expect(find.byKey(const Key('platform-retry-button')), findsOneWidget);
      },
    );

    testWidgets('every failing page fails safely, not just the first', (
      tester,
    ) async {
      useSize(tester, kDesktop);
      final l10n = await englishStrings();
      await tester.pumpWidget(
        consoleApp(
          isDemoMode: false,
          repo: const _ThrowingRepo(
            PlatformAdminException(
              'denied',
              kind: PlatformAdminErrorKind.accessDenied,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final section in [
        l10n.adminNavSubscribers,
        l10n.adminNavRestaurants,
        l10n.adminNavAuditLog,
      ]) {
        await goToSection(tester, section);
        expect(
          find.byKey(const Key('platform-access-denied')),
          findsOneWidget,
          reason: '$section must fail closed too',
        );
      }
    });
  });

  group('demo/real separation', () {
    testWidgets('a REAL-mode failure NEVER falls back to demo data', (
      tester,
    ) async {
      useSize(tester, kDesktop);
      final l10n = await englishStrings();
      await tester.pumpWidget(
        consoleApp(
          isDemoMode: false,
          repo: const _ThrowingRepo(
            PlatformAdminException(
              'denied',
              kind: PlatformAdminErrorKind.accessDenied,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Not one demo tenant name may appear on a live-labelled screen.
      for (final section in [
        l10n.adminNavOverview,
        l10n.adminNavSubscribers,
        l10n.adminNavRestaurants,
      ]) {
        await goToSection(tester, section);
        for (final demoName in const [
          'Bistro Group',
          'Cafe Noor',
          'Pizza Plaza',
          'Olive Tree',
          'Sahara Grill',
        ]) {
          expect(
            find.text(demoName),
            findsNothing,
            reason: 'demo data leaked into real mode on $section',
          );
        }
      }
    });

    testWidgets('demo mode navigates exactly like real mode', (tester) async {
      useSize(tester, kDesktop);
      final l10n = await englishStrings();
      await tester.pumpWidget(consoleApp());
      await tester.pumpAndSettle();

      // The same four destinations, the same page keys — the demo repository
      // fills the SAME models, so nothing about the shape differs.
      await goToSection(tester, l10n.adminNavSubscribers);
      expect(find.byKey(const Key('subscribers-card')), findsOneWidget);
      await goToSection(tester, l10n.adminNavRestaurants);
      expect(find.byKey(const Key('restaurants-card')), findsOneWidget);
      await goToSection(tester, l10n.adminNavAuditLog);
      expect(find.byKey(const Key('audit-card')), findsOneWidget);
    });
  });
}
