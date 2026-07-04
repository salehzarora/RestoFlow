import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/real_platform_admin_repository.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-119-b Codex fix — the platform OVERVIEW reads must ride the SAME
/// session-carrying transport the Admin app uses for `get_my_context`, so the
/// operator's signed-in aal2 session reaches `app.platform_admin_guard`. The fix
/// makes [platformAdminRepositoryProvider] read its transport from the injectable
/// [platformAdminTransportProvider] (default NULL, fail-closed); `main.dart`
/// overrides it with `SupabaseSyncRpcTransport(Supabase.instance.client)` — the
/// one client that also feeds `AuthContextRepository`.
///
/// These tests prove, WITHOUT a SupabaseClient or network, that:
///   * the real repo reads through the INJECTED transport (never a fresh
///     sessionless anon-key client);
///   * ONE transport serves BOTH get_my_context and the overview (main.dart's
///     single-instance wiring);
///   * with no injected transport the overview fails CLOSED (honest, no read);
///   * the screen loads real data through the injected transport, and a denied
///     (42501) transport surfaces the honest access-denied state — never fake
///     data. The server guard stays the authorization boundary (D-026 read-only).

/// A [SyncRpcTransport] that records every call and answers via [_handler], so a
/// test can prove which RPCs the overview/get_my_context reads went through.
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

/// Answers the two RF-125 wrappers with a real-shaped payload (2 orgs / 3
/// restaurants / 4 branches / 1 active) plus a minimal get_my_context echo.
Object? _overviewHandler(String function, Map<String, dynamic> params) {
  switch (function) {
    case 'platform_admin_organization_overview':
      return <String, dynamic>{
        'server_ts': '2026-07-01T09:30:00Z',
        'organizations': <Map<String, dynamic>>[
          {
            'name': 'Bistro Co',
            'status': 'active',
            'restaurants_count': 2,
            'branches_count': 3,
          },
          {
            'name': 'Aleph Foods',
            'status': 'suspended',
            'restaurants_count': 1,
            'branches_count': 1,
          },
        ],
      };
    case 'platform_admin_recent_audit':
      return <String, dynamic>{
        'events': <Map<String, dynamic>>[
          {
            'occurred_at': '2026-07-01T09:15:00Z',
            'action': 'platform.organizations.overview',
            'reason': 'platform overview (read-only)',
          },
        ],
      };
    case 'get_my_context':
      // Shape is irrelevant to the wiring assertion (the fetcher maps it and
      // never throws); we only need to record that this transport was used.
      return <String, dynamic>{};
    default:
      fail('unexpected RPC: $function');
  }
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

Widget _screenInRealMode(SyncRpcTransport transport) => ProviderScope(
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

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('real overview reads go through the INJECTED authenticated transport '
      '(both RF-125 wrappers, with the read-only reason)', () async {
    final transport = _RecordingTransport(_overviewHandler);
    final container = _realContainer(transport);

    final repo = container.read(platformAdminRepositoryProvider);
    expect(repo, isA<RealPlatformAdminRepository>());

    final overview = await repo.loadOverview();

    // The reads went through the injected transport — never a fresh, sessionless
    // anon-key client (which app.platform_admin_guard would reject).
    expect(
      transport.calls,
      containsAllInOrder(<String>[
        'platform_admin_organization_overview',
        'platform_admin_recent_audit',
      ]),
    );
    // Every wrapper call carries the non-empty read-only reason (D-026 reason-tag).
    expect(
      transport.params.every(
        (p) => (p['p_reason'] as String? ?? '').isNotEmpty,
      ),
      isTrue,
    );
    // Real data mapped from the transport response (not fabricated / demo).
    expect(overview.organizationCount, 2);
    expect(overview.restaurantCount, 3);
    expect(overview.branchCount, 4);
    expect(overview.activeOrganizationCount, 1);
  });

  test('ONE authenticated transport serves BOTH get_my_context AND the platform '
      'overview (mirrors main.dart single-instance wiring)', () async {
    final transport = _RecordingTransport(_overviewHandler);
    final container = _realContainer(transport);

    // main.dart builds the get_my_context fetcher from the SAME transport it
    // injects into platformAdminTransportProvider — model that with one instance.
    await AuthContextRepository(transport).fetchMyContext();
    await container.read(platformAdminRepositoryProvider).loadOverview();

    // Both the identity read and the overview reads used the one session client.
    expect(transport.calls, contains('get_my_context'));
    expect(transport.calls, contains('platform_admin_organization_overview'));
    expect(transport.calls, contains('platform_admin_recent_audit'));
  });

  test('real mode WITHOUT an injected transport fails CLOSED (notConfigured); '
      'never a sessionless read', () async {
    final container = _realContainer(null); // no override -> null default

    // Fail-closed default: real platform reads require the app to inject the
    // authenticated transport; absent it there is NO transport at all.
    expect(container.read(platformAdminTransportProvider), isNull);

    final repo = container.read(platformAdminRepositoryProvider);
    expect(repo, isA<RealPlatformAdminRepository>());
    await expectLater(
      repo.loadOverview(),
      throwsA(
        isA<PlatformAdminException>().having(
          (e) => e.kind,
          'kind',
          PlatformAdminErrorKind.notConfigured,
        ),
      ),
    );
  });

  testWidgets('PlatformAdminScreen loads the overview through the injected '
      'authenticated transport (real-mode chrome, real KPIs)', (tester) async {
    _wide(tester);
    final transport = _RecordingTransport(_overviewHandler);

    await tester.pumpWidget(_screenInRealMode(transport));
    await tester.pumpAndSettle();

    // The screen's overview read went through the injected (session) transport.
    expect(transport.calls, contains('platform_admin_organization_overview'));
    // Real overview rendered from that data, under the honest real-mode banner.
    expect(find.byKey(const Key('platform-realmode-banner')), findsOneWidget);
    expect(find.byKey(const Key('kpi-organizations')), findsOneWidget);
    expect(find.byKey(const Key('organizations-card')), findsOneWidget);
    expect(find.byKey(const Key('platform-error')), findsNothing);
  });

  testWidgets('an injected transport that is DENIED (42501) -> the honest '
      'access-denied state, never fabricated data', (tester) async {
    _wide(tester);
    final transport = _RecordingTransport(
      (function, params) => throw const SyncTransportException(
        SyncTransportErrorKind.auth,
        code: '42501',
        message: 'denied',
      ),
    );

    await tester.pumpWidget(_screenInRealMode(transport));
    await tester.pumpAndSettle();

    // A denied/sessionless read surfaces the categorized safe state...
    expect(find.byKey(const Key('platform-access-denied')), findsOneWidget);
    // ...and NO fabricated KPIs / organizations are shown.
    expect(find.byKey(const Key('kpi-organizations')), findsNothing);
    expect(find.byKey(const Key('organizations-card')), findsNothing);
    expect(find.byKey(const Key('platform-realmode-banner')), findsNothing);
  });
}
