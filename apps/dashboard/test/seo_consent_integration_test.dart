import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/support/support_mode_scope.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_repository.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_operations.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

late SeoConsentOperations _operations;

class _Journal implements SeoConsentJournal {
  final values = <String, Map<String, String>>{};
  @override
  Future<Map<String, String>> read(String scope) async =>
      Map.of(values[scope] ?? {});
  @override
  Future<void> write(String scope, String requestId, String value) async {
    values.putIfAbsent(scope, () => {})[requestId] = value;
  }

  @override
  Future<void> remove(String scope, String requestId) async {
    values[scope]?.remove(requestId);
  }
}

class _Repo implements SeoConsentRepository {
  int reads = 0;
  @override
  Future<SeoConsentResult> read() async {
    reads++;
    return const SeoConsentResult(
      SeoConsentOutcome.ok,
      state: SeoConsentState(
        revision: '12',
        consentEnabled: false,
        canManage: true,
      ),
    );
  }

  @override
  Future<SeoConsentResult> save(SeoConsentMutation intent) =>
      throw StateError('no writes in integration render');
  @override
  Future<SeoConsentReconciliation> reconcile(SeoConsentMutation intent) =>
      throw StateError('no receipt query in integration render');
}

class _Transport implements SyncRpcTransport {
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    if (function != 'get_storefront_seo_consent_v1')
      throw StateError('offline unrelated read');
    return {
      'ok': true,
      'entity': 'storefront_seo_consent',
      'organization_id': params['p_organization_id'],
      'restaurant_id': params['p_restaurant_id'],
      'provisioned': false,
      'consent_enabled': false,
      'revision': '0',
      'can_manage': true,
      'indexing_active': false,
      'effective_indexing_eligible': false,
    };
  }
}

class _PendingTransport extends _Transport {
  Map<String, dynamic>? intent;
  bool committed = false;
  bool denied = false;
  final mutations = <Map<String, dynamic>>[];
  final checks = <Map<String, dynamic>>[];

  Map<String, dynamic> get state => {
    'ok': true,
    'entity': 'storefront_seo_consent',
    'organization_id': 'synthetic-org',
    'restaurant_id': 'synthetic-restaurant',
    'provisioned': committed,
    'consent_enabled': committed,
    'revision': committed ? '1' : '0',
    'can_manage': !denied,
    'indexing_active': false,
    'effective_indexing_eligible': false,
  };

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'get_storefront_seo_consent_v1') return state;
    if (function == 'set_storefront_seo_consent_v1') {
      intent = Map.of(params);
      mutations.add(Map.of(params));
      throw StateError('Reply lost; original request may arrive late');
    }
    if (function == 'reconcile_storefront_seo_consent_v1') {
      checks.add(Map.of(params));
      if (denied) return {'ok': false, 'error': 'permission_denied'};
      return {
        ...state,
        'mutation_state': committed ? 'committed' : 'not_recorded',
        'result': committed
            ? {...state, 'client_request_id': params['p_client_request_id']}
            : null,
        'current': state,
      };
    }
    return super.invoke(function, params);
  }
}

Future<void> _pumpShell(
  WidgetTester tester,
  _Transport transport, {
  bool enabled = true,
  bool support = false,
  String status = 'active',
  String? restaurant = 'synthetic-restaurant',
  MembershipRole role = MembershipRole.orgOwner,
}) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final member = MembershipContext(
    id: 'synthetic-membership',
    organizationId: 'synthetic-org',
    organizationName: 'Synthetic org',
    restaurantId: restaurant,
    restaurantName: 'Synthetic restaurant',
    branchId: null,
    branchName: null,
    role: role,
    status: status,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        seoConsentOperationsProvider.overrideWithValue(_operations),
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ],
      child: SupportModeScope(
        active: support,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: restoflowLocalizationsDelegates,
          home: DashboardShell(
            key: ValueKey(dashboardShellIdentity(member, currencyCode: 'ILS')),
            membership: member,
            currencyCode: 'ILS',
            reportsTransport: transport,
            storefrontEditorEnabled: enabled,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('dashboard-side-rail')),
      matching: find.text(l10n.dashboardNavSettings),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  SeoConsentRepository? repository,
  MembershipRole role = MembershipRole.manager,
  String? branch,
  String status = 'active',
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [seoConsentOperationsProvider.overrideWithValue(_operations)],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: restoflowLocalizationsDelegates,
        home: Scaffold(
          body: RealSettingsView(
            membership: MembershipContext(
              id: 'synthetic-membership',
              organizationId: 'synthetic-org',
              organizationName: 'Synthetic org',
              restaurantId: 'synthetic-restaurant',
              restaurantName: 'Synthetic restaurant',
              branchId: branch,
              branchName: 'Selected QA branch',
              role: role,
              status: status,
            ),
            currencyCode: 'ILS',
            seoConsentRepository: repository,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _operations = SeoConsentOperations(_Journal()));
  for (final role in [
    MembershipRole.orgOwner,
    MembershipRole.restaurantOwner,
  ]) {
    testWidgets('${role.name} gets restaurant consent card without a branch', (
      tester,
    ) async {
      final repo = _Repo();
      await _pump(tester, repository: repo, role: role);
      expect(repo.reads, 1);
      expect(
        find.byKey(const Key('seo-consent-settings-section')),
        findsOneWidget,
      );
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('seo-consent-toggle')),
      );
      expect(toggle.onChanged, isNotNull);
      expect(find.text('Synthetic restaurant'), findsWidgets);
    });
  }
  for (final role in [
    MembershipRole.manager,
    MembershipRole.cashier,
    MembershipRole.kitchenStaff,
    MembershipRole.accountant,
  ]) {
    testWidgets(
      '${role.name} cannot edit even if injected repository returns state',
      (tester) async {
        await _pump(tester, repository: _Repo(), role: role);
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('seo-consent-toggle')),
              )
              .onChanged,
          isNull,
        );
      },
    );
  }
  testWidgets('no versioned seam means no fake controls', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('seo-consent-settings-section')), findsNothing);
  });
  testWidgets('inactive membership cannot edit even if role is owner', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _Repo(),
      role: MembershipRole.orgOwner,
      status: 'revoked',
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('seo-consent-toggle')))
          .onChanged,
      isNull,
    );
  });

  testWidgets('real shell pins restaurant RPC scope without a branch', (
    tester,
  ) async {
    final transport = _Transport();
    await _pumpShell(tester, transport);
    expect(
      tester
          .widget<RealSettingsView>(find.byType(RealSettingsView))
          .seoConsentRepository,
      isNotNull,
    );
    expect(
      transport.calls
          .where((call) => call.$1 == 'get_storefront_seo_consent_v1')
          .single
          .$2,
      {
        'p_organization_id': 'synthetic-org',
        'p_restaurant_id': 'synthetic-restaurant',
      },
    );
    expect(
      find.byKey(const Key('seo-consent-settings-section')),
      findsOneWidget,
    );
  });

  testWidgets(
    'membership status transitions invalidate the restaurant seam without a shell remount',
    (tester) async {
      final transport = _Transport();
      await _pumpShell(tester, transport, status: 'revoked');
      expect(
        tester
            .widget<RealSettingsView>(find.byType(RealSettingsView))
            .seoConsentRepository,
        isNull,
      );
      await _pumpShell(tester, transport);
      expect(
        tester
            .widget<RealSettingsView>(find.byType(RealSettingsView))
            .seoConsentRepository,
        isNotNull,
      );
      await _pumpShell(tester, transport, status: 'revoked');
      expect(
        tester
            .widget<RealSettingsView>(find.byType(RealSettingsView))
            .seoConsentRepository,
        isNull,
      );
      expect(
        transport.calls.where(
          (call) => call.$1 == 'get_storefront_seo_consent_v1',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'actual Dashboard tab remount retains not-recorded intent until late original commit',
    (tester) async {
      final transport = _PendingTransport();
      await _pumpShell(tester, transport);
      await tester.tap(find.byKey(const Key('seo-consent-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('seo-consent-save')));
      await tester.pumpAndSettle();
      final original = transport.intent!;
      await tester.tap(find.byKey(const Key('seo-consent-check-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('seo-consent-resend')), findsOneWidget);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('dashboard-side-rail')),
          matching: find.text(l10n.dashboardNavOverview),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('seo-consent-toggle')), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('dashboard-side-rail')),
          matching: find.text(l10n.dashboardNavSettings),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('seo-consent-toggle')),
      );
      expect(toggle.onChanged, isNull);
      expect(find.byKey(const Key('seo-consent-save')), findsNothing);
      expect(find.byKey(const Key('seo-consent-reload')), findsNothing);
      // The stale GET still says OFF/revision 0; it cannot release the journal.
      expect(transport.committed, false);
      transport.committed = true;
      await tester.tap(find.byKey(const Key('seo-consent-check-save')));
      await tester.pumpAndSettle();
      expect(transport.mutations, hasLength(1));
      expect(
        transport.checks.every(
          (check) =>
              check['p_client_request_id'] == original['p_client_request_id'] &&
              check['p_expected_revision'] == '0' &&
              check['p_consent_enabled'] == true,
        ),
        true,
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('seo-consent-toggle')))
            .value,
        true,
      );
      expect(find.byKey(const Key('seo-consent-check-save')), findsNothing);
    },
  );

  testWidgets(
    'role and transport refresh retain unknown operation under its actor-owned identity',
    (tester) async {
      final first = _PendingTransport();
      await _pumpShell(tester, first);
      await tester.tap(find.byKey(const Key('seo-consent-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('seo-consent-save')));
      await tester.pumpAndSettle();
      final refreshed = _PendingTransport()..denied = true;
      await _pumpShell(tester, refreshed, role: MembershipRole.manager);
      expect(find.byKey(const Key('seo-consent-save')), findsNothing);
      await tester.tap(find.byKey(const Key('seo-consent-check-save')));
      await tester.pumpAndSettle();
      expect(
        refreshed.checks.single['p_client_request_id'],
        first.intent!['p_client_request_id'],
      );
      expect(find.byKey(const Key('seo-consent-reload')), findsNothing);
      refreshed.denied = false;
      refreshed.committed = true;
      await _pumpShell(tester, refreshed);
      expect(find.byKey(const Key('seo-consent-save')), findsNothing);
      await tester.tap(find.byKey(const Key('seo-consent-check-save')));
      await tester.pumpAndSettle();
      expect(first.mutations, hasLength(1));
      expect(refreshed.mutations, isEmpty);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('seo-consent-toggle')))
            .value,
        true,
      );
    },
  );

  for (final condition in ['support', 'dark', 'inactive', 'no-restaurant']) {
    testWidgets('real shell with $condition builds no consent seam or RPC', (
      tester,
    ) async {
      final transport = _Transport();
      await _pumpShell(
        tester,
        transport,
        support: condition == 'support',
        enabled: condition != 'dark',
        status: condition == 'inactive' ? 'revoked' : 'active',
        restaurant: condition == 'no-restaurant'
            ? null
            : 'synthetic-restaurant',
      );
      expect(
        tester
            .widget<RealSettingsView>(find.byType(RealSettingsView))
            .seoConsentRepository,
        isNull,
      );
      expect(
        transport.calls.where((call) => call.$1.contains('seo_consent')),
        isEmpty,
      );
      expect(
        find.byKey(const Key('seo-consent-settings-section')),
        findsNothing,
      );
    });
  }
}
