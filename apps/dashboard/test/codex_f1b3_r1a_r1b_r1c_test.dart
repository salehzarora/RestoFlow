import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/state/analytics_branch_providers.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX FINAL STATIC RE-REVIEW — the last three F-1B-3 findings.
///
/// R1A — the authoritative-answer stamp still carried `branchLabel`.
/// `DashboardAnalyticsScope.coveredBy` copies `membership.branchName` into the
/// coverage for a branch-fixed membership, and scope equality includes it, so
/// RENAMING that branch changed the stamp. The remembered answer was discarded,
/// the context read as "never answered", and resolution fell back to the raw
/// selection — the resurrection F-1B-3-R1 exists to prevent, reached through a
/// rename instead of a failure.
///
/// R1B — the shared ProviderScope sat INSIDE the responsive LayoutBuilder. The
/// wide and narrow trees are structurally different (`Row > Expanded > Column`
/// versus `Column`), so crossing ~560px gave it a different ancestor chain, its
/// element could not be reused, and the container was disposed — taking the
/// loaded report and the remembered branch answer with it. Resizing a window
/// undid an authoritative omission.
///
/// R1C — nothing in production ever re-ran `list_org_structure`. The whole
/// authoritative-omission machinery was reachable only from tests: a branch
/// deleted mid-session stayed selectable, and stayed the financial scope, for
/// the life of the session.

// ===========================================================================
// Harness
// ===========================================================================

class _FakeTransport implements SyncRpcTransport {
  /// Overrides `list_org_structure`; null uses [branches].
  Object? Function()? orgStructure;

  List<(String, String, String)> branches = const [
    ('rest-1', 'branch-1', 'Main'),
    ('rest-2', 'branch-2', 'Harbor'),
  ];

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  int countOf(String fn) => functions.where((f) => f == fn).length;

  Map<String, dynamic>? lastTo(String fn) {
    for (var i = functions.length - 1; i >= 0; i--) {
      if (functions[i] == fn) return params[i];
    }
    return null;
  }

  Map<String, dynamic> _structure() {
    final byRestaurant = <String, List<Map<String, dynamic>>>{};
    for (final (restaurantId, branchId, name) in branches) {
      byRestaurant
          .putIfAbsent(restaurantId, () => <Map<String, dynamic>>[])
          .add({'id': branchId, 'name': name});
    }
    return <String, dynamic>{
      'ok': true,
      'entity': 'org_structure',
      'restaurants': [
        for (final e in byRestaurant.entries)
          {
            'id': e.key,
            'name': e.key == 'rest-1' ? 'Rest One' : 'Rest Two',
            'branches': e.value,
          },
      ],
    };
  }

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    functions.add(function);
    params.add(args);
    return switch (function) {
      'list_org_structure' => (orgStructure ?? _structure)(),
      'list_staff' => <String, dynamic>{'ok': true, 'staff': <dynamic>[]},
      'owner_order_history' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'orders': <dynamic>[],
        'has_more': false,
        'next_cursor': null,
      },
      'owner_sales_series' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'range': 'last7',
        'buckets': <dynamic>[],
      },
      'owner_active_orders' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'orders': <dynamic>[],
      },
      _ => <String, dynamic>{
        'ok': true,
        'entity': 'owner_report_range',
        'currency_code': 'ILS',
        'range': 'today',
        'current': <String, dynamic>{'order_count': 1, 'net_minor': 1000},
        'comparison': <String, dynamic>{'order_count': 1, 'net_minor': 900},
        'hourly': <dynamic>[],
      },
    };
  }
}

MembershipContext _membership({
  MembershipRole role = MembershipRole.orgOwner,
  String? restaurantId = 'rest-1',
  String? branchId = 'branch-1',
  String branchName = 'Main',
}) => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: restaurantId,
  restaurantName: 'Rest One',
  branchId: branchId,
  branchName: branchName,
  role: role,
  status: 'active',
);

const _main = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  label: 'Rest One · Main',
);

List<Override> _overrides(_FakeTransport t, MembershipContext m) => [
  dashboardMembershipProvider.overrideWithValue(m),
  dashboardAuthTransportProvider.overrideWithValue(t),
  runtimeConfigProvider.overrideWithValue(
    RuntimeConfig.test(isDemoMode: false),
  ),
];

Future<void> _settle(ProviderContainer c) async {
  try {
    await c.read(auditBranchOptionsProvider.future);
  } catch (_) {}
  try {
    await c.read(analyticsBranchAnswerProvider.future);
  } catch (_) {}
}

Future<void> _reload(ProviderContainer c) async {
  c.invalidate(auditBranchOptionsProvider);
  await _settle(c);
}

void main() {
  // =======================================================================
  // R1A — the stamp is ids, never a name
  // =======================================================================
  group('R1A: the authoritative stamp is label-free', () {
    test('a coverage that differs ONLY by branch name is the same context', () {
      final before = DashboardAnalyticsScope.coveredBy(
        _membership(role: MembershipRole.manager, branchName: 'Main'),
      );
      final after = DashboardAnalyticsScope.coveredBy(
        _membership(role: MembershipRole.manager, branchName: 'Main Street'),
      );
      // The defect in one line: the coverage values differ...
      expect(before == after, isFalse);
      // ...but the context they describe does not.
      expect(before.transportIdentity, after.transportIdentity);
    });

    test('a branch-fixed membership keeps its remembered answer across a '
        'label-only rename, then through loading and error', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(
        overrides: _overrides(
          t,
          _membership(role: MembershipRole.manager, branchName: 'Main'),
        ),
      );
      addTearDown(c.dispose);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _main;
      await _settle(c);
      expect(c.read(analyticsBranchOptionsProvider), isNotNull);
      expect(c.read(analyticsBranchOptionsProvider), [_main]);

      // The branch is renamed: the membership's branchName changes, the ids do
      // not. Under the labelled stamp this alone discarded the answer.
      c.updateOverrides(
        _overrides(
          t,
          _membership(role: MembershipRole.manager, branchName: 'Main Street'),
        ),
      );
      expect(
        c.read(analyticsBranchOptionsProvider),
        isNotNull,
        reason: 'a rename is not a new authorization context',
      );

      // ...and it survives a subsequent failure, which is the state the stamp
      // exists to protect.
      t.orgStructure = () => throw StateError('down');
      await _reload(c);
      expect(c.read(analyticsBranchOptionsProvider), isNotNull);
      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.restaurantId, 'rest-1');
      expect(scope.branchId, 'branch-1');
    });

    test('a genuinely different context is still rejected', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      await _settle(c);
      expect(c.read(analyticsBranchOptionsProvider), isNotNull);

      t.orgStructure = () => throw StateError('down');
      c.updateOverrides(
        _overrides(
          t,
          _membership(
            role: MembershipRole.restaurantOwner,
            restaurantId: 'rest-2',
          ),
        ),
      );
      await _settle(c);
      expect(
        c.read(analyticsBranchOptionsProvider),
        isNull,
        reason: 'different coverage IDS really is a different question',
      );
    });
  });

  // =======================================================================
  // Real-shell harness, shared by R1B and R1C
  // =======================================================================
  group('R1B / R1C: the real shell', () {
    Future<_FakeTransport> pumpShell(
      WidgetTester tester, {
      Size size = const Size(1100, 2000),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = _FakeTransport();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: DashboardShell(
              membership: _membership(role: MembershipRole.orgOwner),
              reportsTransport: transport,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return transport;
    }

    Future<void> resize(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
    }

    ProviderContainer shared(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byKey(const Key('overview-scope-selector'))),
      listen: false,
    );

    Future<void> selectBranchB(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest Two · Harbor').last);
      await tester.pumpAndSettle();
    }

    /// Presses the owner's OWN refresh control.
    Future<void> tapRefresh(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('reports-refresh-button')));
      await tester.pumpAndSettle();
    }

    /// Navigates through the shell's OWN bottom nav, which is the phone-width
    /// control — so callers resize to a phone width first. The side rail has no
    /// per-destination key to drive, and reaching into its internals would test
    /// the rail rather than the scope.
    Future<void> openOrdersHistory(WidgetTester tester) async {
      tester
          .widget<NavigationBar>(find.byKey(const Key('dashboard-bottom-nav')))
          .onDestinationSelected!(DashboardDestination.orders.visibleIndex!);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('orders-tab-history')));
      await tester.pumpAndSettle();
    }

    String? selectorValue(WidgetTester tester) => tester
        .widget<DropdownButtonFormField<String?>>(
          find.byKey(const Key('overview-scope-selector')),
        )
        .initialValue;

    // ---------------------------------------------------------------- R1C
    testWidgets('R1C: the owner\'s refresh re-reads the branch list, exactly '
        'once, and settles the scope BEFORE the financial reads', (
      tester,
    ) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);
      expect(t.lastTo('owner_report_range')!['p_branch_id'], 'branch-2');

      final optionsBefore = t.countOf('list_org_structure');
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      final from = t.params.length;

      await tapRefresh(tester);

      expect(
        t.countOf('list_org_structure'),
        optionsBefore + 1,
        reason: 'exactly one intended enumeration',
      );
      // The scope moved, and the UI says so.
      expect(selectorValue(tester), isNull);
      expect(
        shared(tester).read(dashboardAnalyticsScopeProvider)!.branchId,
        isNull,
      );
      // The financial read went out ONCE, for the parent — never for B first.
      final reports = [
        for (var i = from; i < t.functions.length; i++)
          if (t.functions[i] == 'owner_report_range') t.params[i],
      ];
      expect(reports, hasLength(1));
      expect(reports.single['p_branch_id'], isNull);
      for (var i = from; i < t.params.length; i++) {
        expect(t.params[i].values, isNot(contains('branch-2')));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('R1C: a refresh whose enumeration FAILS keeps the scope and '
        'still refreshes the figures', (tester) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);
      final reportsBefore = t.countOf('owner_report_range');

      t.orgStructure = () => throw StateError('down');
      await tapRefresh(tester);

      expect(selectorValue(tester), 'branch-2');
      expect(
        shared(tester).read(dashboardAnalyticsScopeProvider)!.branchId,
        'branch-2',
        reason: 'a failed enumeration must never widen the figures',
      );
      expect(
        t.countOf('owner_report_range'),
        greaterThan(reportsBefore),
        reason: 'the financial refresh still runs on the retained scope',
      );
      expect(t.lastTo('owner_report_range')!['p_branch_id'], 'branch-2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('R1C: a later refresh that brings B back resumes it', (
      tester,
    ) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);

      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await tapRefresh(tester);
      expect(selectorValue(tester), isNull);

      t.branches = const [
        ('rest-1', 'branch-1', 'Main'),
        ('rest-2', 'branch-2', 'Harbor'),
      ];
      await tapRefresh(tester);
      expect(selectorValue(tester), 'branch-2');
      expect(
        shared(tester).read(dashboardAnalyticsScopeProvider)!.branchId,
        'branch-2',
      );
    });

    testWidgets('R1C: nothing else re-enumerates — not tabs, not a resize', (
      tester,
    ) async {
      // Phone width so the bottom nav is the navigation control.
      final t = await pumpShell(tester, size: const Size(430, 2000));
      final baseline = t.countOf('list_org_structure');
      expect(baseline, 1, reason: 'one enumeration for the whole shell');

      await openOrdersHistory(tester);
      expect(
        t.countOf('list_org_structure'),
        baseline,
        reason: 'navigating is not new information about branches',
      );

      await resize(tester, const Size(1100, 2000));
      expect(t.countOf('list_org_structure'), baseline);
      await resize(tester, const Size(430, 2000));
      expect(
        t.countOf('list_org_structure'),
        baseline,
        reason: 'resizing is not new information either',
      );
    });

    // ---------------------------------------------------------------- R1B
    testWidgets('R1B: crossing the breakpoint does not undo an authoritative '
        'omission', (tester) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);

      // A real refresh removes B.
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await tapRefresh(tester);
      expect(selectorValue(tester), isNull);

      // Every later enumeration now fails, so a container that was thrown away
      // could only fall back to the raw selection — which is the bug.
      t.orgStructure = () => throw StateError('down');
      final optionsBefore = t.countOf('list_org_structure');
      final from = t.params.length;

      // Wide -> narrow -> wide.
      await resize(tester, const Size(430, 2000));
      expect(
        shared(tester).read(dashboardAnalyticsScopeProvider)!.branchId,
        isNull,
        reason: 'a resize is not new information about branches',
      );
      await resize(tester, const Size(1100, 2000));
      expect(
        shared(tester).read(dashboardAnalyticsScopeProvider)!.branchId,
        isNull,
      );
      expect(selectorValue(tester), isNull);
      expect(
        t.countOf('list_org_structure'),
        optionsBefore,
        reason: 'layout must not cost a request',
      );

      // ...and Orders agrees, with no stale B call anywhere after the omission.
      await resize(tester, const Size(430, 2000));
      await openOrdersHistory(tester);
      final history = t.lastTo('owner_order_history')!;
      expect(history['p_restaurant_id'], isNull);
      expect(history['p_branch_id'], isNull);
      for (var i = from; i < t.params.length; i++) {
        expect(t.params[i].values, isNot(contains('branch-2')));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('R1B: a resize does not throw away the loaded report either', (
      tester,
    ) async {
      final t = await pumpShell(tester);
      final reportsBefore = t.countOf('owner_report_range');
      expect(reportsBefore, greaterThan(0));

      await resize(tester, const Size(430, 2000));
      await resize(tester, const Size(1100, 2000));

      expect(
        t.countOf('owner_report_range'),
        reportsBefore,
        reason: 'the report container survives the breakpoint',
      );
    });
  });
}
