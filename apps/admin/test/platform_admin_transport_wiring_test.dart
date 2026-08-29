/// RF-119-b + ADMIN-125C.2 — the console reads must ride the SAME
/// session-carrying transport the Admin app uses for `get_my_context`, so the
/// operator's signed-in aal2 session reaches `app.platform_admin_guard`.
///
/// [platformAdminRepositoryProvider] reads its transport from the injectable
/// [platformAdminTransportProvider] (default NULL, fail-closed); `main.dart`
/// overrides it with `SupabaseSyncRpcTransport(Supabase.instance.client)` — the
/// one client that also feeds `AuthContextRepository`.
///
/// These tests prove, WITHOUT a SupabaseClient or network, that:
///   * the console reads through the INJECTED transport (never a fresh,
///     sessionless client);
///   * ONE transport serves BOTH get_my_context AND the console;
///   * with no injected transport the console fails CLOSED;
///   * the shell renders live data through that transport, and a denied (42501)
///     transport surfaces the honest access-denied state — never fake data, and
///     never a silent fall back to the demo repository.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/real_platform_admin_repository.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'console_test_harness.dart';

/// A [SyncRpcTransport] that records every call and answers via [_handler].
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    this.params.add(params);
    return _handler(function, params);
  }
}

Object? _consoleHandler(String function, Map<String, dynamic> params) {
  switch (function) {
    case 'platform_admin_console_overview':
      return <String, dynamic>{
        'ok': true,
        'organizations_total': 2,
        'organizations_active': 1,
        'organizations_suspended': 1,
        'restaurants_total': 3,
        'branches_total': 4,
        'active_memberships_total': 11,
        'subscriptions_trialing': 0,
        'subscriptions_active': 1,
        'subscriptions_past_due': 0,
        'subscriptions_canceled': 0,
        'server_ts': '2026-09-02T09:30:00+00:00',
      };
    case 'platform_admin_list_subscribers':
      return <String, dynamic>{
        'ok': true,
        'rows': <Map<String, dynamic>>[
          {
            'organization_id': 'aaaaaaaa-0000-4000-8000-000000000001',
            'organization_name': 'Bistro Co',
            'organization_status': 'active',
            'created_at': '2026-07-01T09:00:00+00:00',
            'default_currency': 'ILS',
            'restaurants_count': 2,
            'branches_count': 3,
            'active_memberships_count': 8,
            'plan_code': 'basic',
            'plan_display_name': 'Basic',
            'subscription_status': 'active',
            'current_period_start': '2026-08-01T00:00:00+00:00',
            'current_period_end': '2026-09-01T00:00:00+00:00',
          },
        ],
        'total_count': 1,
        'limit': 25,
        'offset': 0,
        'server_ts': '2026-09-02T09:30:00+00:00',
      };
    case 'get_my_context':
      return <String, dynamic>{
        'app_user_id': '92b4483f-0be3-462e-aced-e35e7493b337',
        'memberships': <Map<String, dynamic>>[],
        'is_platform_admin': true,
        'is_mfa_aal2': true,
      };
  }
  return null;
}

ProviderContainer _realContainer(SyncRpcTransport? transport) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      if (transport != null)
        platformAdminTransportProvider.overrideWithValue(transport),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _shellInRealMode(SyncRpcTransport transport) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: false),
    ),
    platformAdminTransportProvider.overrideWithValue(transport),
  ],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: PlatformAdminScreen(),
  ),
);

void main() {
  test('console reads go through the INJECTED authenticated transport, with a '
      'non-empty read-only reason', () async {
    final transport = _RecordingTransport(_consoleHandler);
    final container = _realContainer(transport);

    final repo = container.read(platformAdminRepositoryProvider);
    expect(repo, isA<RealPlatformAdminRepository>());

    final overview = await repo.loadConsoleOverview();
    await repo.loadSubscribers(const SubscriberQuery());

    expect(
      transport.calls,
      containsAllInOrder(<String>[
        'platform_admin_console_overview',
        'platform_admin_list_subscribers',
      ]),
    );
    expect(
      transport.params.every(
        (p) => (p['p_reason'] as String? ?? '').isNotEmpty,
      ),
      isTrue,
    );
    // Real data mapped from the transport response (not fabricated / demo).
    expect(overview.organizationsTotal, 2);
    expect(overview.restaurantsTotal, 3);
    expect(overview.branchesTotal, 4);
    expect(overview.organizationsSuspended, 1);
  });

  test('ONE authenticated transport serves BOTH get_my_context AND the console '
      '(mirrors main.dart single-instance wiring)', () async {
    final transport = _RecordingTransport(_consoleHandler);
    final container = _realContainer(transport);

    await AuthContextRepository(transport).fetchMyContext();
    await container.read(platformAdminRepositoryProvider).loadConsoleOverview();

    expect(transport.calls, contains('get_my_context'));
    expect(transport.calls, contains('platform_admin_console_overview'));
  });

  test('real mode WITHOUT an injected transport fails CLOSED; never a '
      'sessionless read and never demo data', () async {
    final container = _realContainer(null);

    expect(container.read(platformAdminTransportProvider), isNull);
    final repo = container.read(platformAdminRepositoryProvider);
    expect(repo, isA<RealPlatformAdminRepository>());
    expect(repo, isNot(isA<DemoPlatformAdminRepository>()));
    await expectLater(
      repo.loadConsoleOverview(),
      throwsA(
        isA<PlatformAdminException>().having(
          (e) => e.kind,
          'kind',
          PlatformAdminErrorKind.notConfigured,
        ),
      ),
    );
  });

  testWidgets('the shell loads the console through the injected transport', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final transport = _RecordingTransport(_consoleHandler);

    await tester.pumpWidget(_shellInRealMode(transport));
    await tester.pumpAndSettle();

    expect(transport.calls, contains('platform_admin_console_overview'));
    expect(find.byKey(const Key('platform-realmode-banner')), findsOneWidget);
    expect(find.byKey(const Key('kpi-organizations')), findsOneWidget);
    expect(find.byKey(const Key('platform-error')), findsNothing);

    // Navigating reads the NEXT endpoint through the same transport.
    await goToSection(tester, (await englishStrings()).adminNavSubscribers);
    expect(transport.calls, contains('platform_admin_list_subscribers'));
    expect(find.text('Bistro Co'), findsOneWidget);
  });

  testWidgets(
    'a DENIED (42501) transport shows the honest access-denied state, '
    'never fabricated data',
    (tester) async {
      useSize(tester, kDesktop);
      final transport = _RecordingTransport(
        (function, params) => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message: 'denied',
        ),
      );

      await tester.pumpWidget(_shellInRealMode(transport));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-access-denied')), findsOneWidget);
      // No fabricated metrics, and no demo fallback.
      expect(find.byKey(const Key('kpi-organizations')), findsNothing);
      expect(find.text('Bistro Group'), findsNothing); // a demo tenant name
      // The provenance strip still says LIVE — the console must not quietly
      // relabel a denied live read as demo data.
      expect(find.byKey(const Key('platform-realmode-banner')), findsOneWidget);
      expect(find.byKey(const Key('platform-demo-banner')), findsNothing);
    },
  );
}
