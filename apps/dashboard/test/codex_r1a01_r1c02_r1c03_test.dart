import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/state/active_orders_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_membership_identity.dart';
import 'package:restoflow_dashboard/src/state/analytics_branch_providers.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX FINAL STATIC RE-REVIEW — the last three P2 findings.
///
/// R1A-01 — the financial providers watched the whole `MembershipContext`,
/// which carries display text and has no `==` at all. Any new instance rebuilt
/// the report repository, the sales-series repository and the Orders History
/// repository AND its controller: fresh RPCs, the loaded page discarded,
/// pagination restarted from a null cursor — because someone had renamed a
/// branch.
///
/// R1C-02 — Activity and Active Orders read their dropdown value from the
/// current option list while their repositories transported `query.branch`. The
/// two could disagree: after an authoritative omission the control showed "All"
/// and the RPC stayed filtered to the removed branch. A root-lived query could
/// also carry a branch across a membership change.
///
/// R1C-03 — the refresh sequence ran on the Overview's `WidgetRef` and checked
/// `ref.context.mounted` after awaiting the branch enumeration. Crossing the
/// responsive breakpoint mid-flight remounts that widget, so the check failed
/// and the financial half was skipped: branch authority updated, every figure
/// stale, and nothing on screen saying so.

// ===========================================================================
// Harness
// ===========================================================================

class _FakeTransport implements SyncRpcTransport {
  /// Overrides `list_org_structure`. Returning a Future parks the call.
  Object? Function()? orgStructure;

  List<(String, String, String)> branches = const [
    ('rest-1', 'branch-1', 'Main'),
    ('rest-2', 'branch-2', 'Harbor'),
  ];

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  int countOf(String fn) => functions.where((f) => f == fn).length;

  List<Map<String, dynamic>> callsTo(String fn) => [
    for (var i = 0; i < functions.length; i++)
      if (functions[i] == fn) params[i],
  ];

  Map<String, dynamic>? lastTo(String fn) {
    final all = callsTo(fn);
    return all.isEmpty ? null : all.last;
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
        'orders': <dynamic>[
          {
            'order_id': 'o-1',
            'order_code': '#000123',
            'status': 'completed',
            'order_type': 'dine_in',
            'created_at': '2026-08-09T10:00:00Z',
            'item_count': 2,
            'grand_total_minor': 4200,
            'payment_status': 'paid',
          },
        ],
        'has_more': true,
        'next_cursor': 'cursor-1',
      },
      'owner_audit_events' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'events': <dynamic>[],
        'has_more': false,
        'next_cursor': null,
      },
      'owner_active_orders' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'orders': <dynamic>[],
      },
      'owner_sales_series' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'range': 'last7',
        'buckets': <dynamic>[],
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
  String id = 'm-1',
  String organizationId = 'org-1',
  MembershipRole role = MembershipRole.orgOwner,
  String? restaurantId = 'rest-1',
  String? branchId = 'branch-1',
  String branchName = 'Main',
  String organizationName = 'Org',
  String status = 'active',
}) => MembershipContext(
  id: id,
  organizationId: organizationId,
  organizationName: organizationName,
  restaurantId: restaurantId,
  restaurantName: 'Rest One',
  branchId: branchId,
  branchName: branchName,
  role: role,
  status: status,
);

const _harbor = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-2',
  label: 'Rest Two · Harbor',
);

/// ONE runtime config for the whole file.
///
/// `RuntimeConfig` is identity-compared, so minting a fresh one inside
/// `updateOverrides` would rebuild every repository by itself and the
/// label-only assertions below would be testing the harness rather than the
/// fix. Holding it constant means the ONLY thing that changes is what the case
/// says changes.
final _realMode = RuntimeConfig.test(isDemoMode: false);

List<Override> _overrides(_FakeTransport t, MembershipContext m) => [
  dashboardMembershipProvider.overrideWithValue(m),
  dashboardAuthTransportProvider.overrideWithValue(t),
  runtimeConfigProvider.overrideWithValue(_realMode),
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

Future<void> _pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // =======================================================================
  // R1A-01 — a display rename is not a new query
  // =======================================================================
  group('R1A-01: membership identity excludes display text', () {
    test('identity ignores names and respects every authorization field', () {
      final base = _membership();
      DashboardMembershipIdentity id(MembershipContext m) =>
          DashboardMembershipIdentity.of(m);

      // Display-only differences are the same identity.
      expect(
        id(_membership(branchName: 'Main Street', organizationName: 'Renamed')),
        id(base),
      );
      // Anything that changes what is asked, or what is allowed, is not.
      for (final other in [
        _membership(id: 'm-2'),
        _membership(organizationId: 'org-2'),
        _membership(restaurantId: 'rest-9'),
        _membership(branchId: 'branch-9'),
        _membership(role: MembershipRole.manager),
        _membership(status: 'suspended'),
      ]) {
        expect(id(other), isNot(id(base)), reason: '$other');
      }
    });

    test('a label-only rename keeps every financial provider, the loaded page '
        'and the cursor — and costs no request', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harbor;
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await _settle(c);

      final reportRepo = c.read(ownerReportsRepositoryProvider);
      final seriesRepo = c.read(ownerSalesSeriesRepositoryProvider);
      final historyRepo = c.read(orderHistoryRepositoryProvider);
      final controller = c.read(orderHistoryControllerProvider.notifier);
      await c.read(
        ownerReportForKeyProvider(c.read(currentOwnerReportKeyProvider)).future,
      );
      await _pump();
      final before = c.read(orderHistoryControllerProvider);
      expect(before.rows, isNotEmpty);
      expect(before.cursor, 'cursor-1');
      final counts = {
        for (final fn in const [
          'owner_report_range',
          'owner_sales_series',
          'owner_order_history',
          'list_org_structure',
        ])
          fn: t.countOf(fn),
      };

      // ONLY the display names change.
      c.updateOverrides(
        _overrides(
          t,
          _membership(branchName: 'Main Street', organizationName: 'Renamed'),
        ),
      );
      await _pump();

      expect(
        identical(c.read(ownerReportsRepositoryProvider), reportRepo),
        isTrue,
      );
      expect(
        identical(c.read(ownerSalesSeriesRepositoryProvider), seriesRepo),
        isTrue,
      );
      expect(
        identical(c.read(orderHistoryRepositoryProvider), historyRepo),
        isTrue,
      );
      expect(
        identical(c.read(orderHistoryControllerProvider.notifier), controller),
        isTrue,
      );
      for (final entry in counts.entries) {
        expect(
          t.countOf(entry.key),
          entry.value,
          reason: '${entry.key} must not be re-issued for a rename',
        );
      }
      final after = c.read(orderHistoryControllerProvider);
      expect(after.rows, before.rows);
      expect(after.cursor, 'cursor-1');

      // The UI still sees the LIVE name.
      expect(c.read(dashboardMembershipProvider)!.branchName, 'Main Street');
    });

    test('a REAL authorization change still rebuilds and re-scopes', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      await _settle(c);
      final historyRepo = c.read(orderHistoryRepositoryProvider);
      await c
          .read(orderHistoryRepositoryProvider)
          .loadHistory(const OrderHistoryQuery());

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
        identical(c.read(orderHistoryRepositoryProvider), historyRepo),
        isFalse,
      );
      await c
          .read(orderHistoryRepositoryProvider)
          .loadHistory(const OrderHistoryQuery());
      expect(t.lastTo('owner_order_history')!['p_restaurant_id'], 'rest-2');
    });
  });

  // =======================================================================
  // R1C-02 — the operational filters say what they send
  // =======================================================================
  group('R1C-02: Activity and Active Orders show what they transport', () {
    test('Activity: an authoritative omission clears the branch from BOTH the '
        'visible query and the wire', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        branch: _harbor,
      );
      await _settle(c);
      expect(c.read(effectiveAuditQueryProvider).branch, _harbor);
      await c
          .read(auditLogRepositoryProvider)
          .loadEvents(c.read(effectiveAuditQueryProvider));
      expect(t.lastTo('owner_audit_events')!['p_branch_id'], 'branch-2');

      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await _reload(c);

      expect(c.read(effectiveAuditQueryProvider).branch, isNull);
      final from = t.params.length;
      await c
          .read(auditLogRepositoryProvider)
          .loadEvents(c.read(effectiveAuditQueryProvider));
      expect(t.lastTo('owner_audit_events')!['p_branch_id'], isNull);
      for (final call in t.params.skip(from)) {
        expect(call.values, isNot(contains('branch-2')));
      }
      // The raw filter is untouched — nothing is written during a build.
      expect(c.read(auditLogQueryProvider).branch, _harbor);
    });

    test('Activity: a technical failure follows the LAST authority, in both '
        'directions', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        branch: _harbor,
      );
      await _settle(c);

      // Last answer HAS the branch -> a failure keeps it.
      t.orgStructure = () => throw StateError('down');
      await _reload(c);
      expect(c.read(effectiveAuditQueryProvider).branch, _harbor);

      // Last answer OMITS it -> a failure keeps it omitted.
      t.orgStructure = null;
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await _reload(c);
      expect(c.read(effectiveAuditQueryProvider).branch, isNull);
      t.orgStructure = () => throw StateError('down');
      await _reload(c);
      expect(c.read(effectiveAuditQueryProvider).branch, isNull);
    });

    test('Activity: a foreign branch is inert the instant the membership '
        'changes, before any list is consulted', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        branch: _harbor,
      );
      await _settle(c);
      expect(c.read(effectiveAuditQueryProvider).branch, _harbor);

      c.updateOverrides(
        _overrides(
          t,
          _membership(organizationId: 'org-2', restaurantId: 'r-2'),
        ),
      );
      expect(
        c.read(effectiveAuditQueryProvider).branch,
        isNull,
        reason: 'coverage answers immediately; no list is needed',
      );
      final from = t.params.length;
      await c
          .read(auditLogRepositoryProvider)
          .loadEvents(c.read(effectiveAuditQueryProvider));
      for (final call in t.params.skip(from)) {
        expect(call.values, isNot(contains('branch-2')));
      }
    });

    test(
      'Active Orders: omission, failure retention and membership change',
      () async {
        final t = _FakeTransport();
        final c = ProviderContainer(overrides: _overrides(t, _membership()));
        addTearDown(c.dispose);
        c.read(activeOrdersQueryProvider.notifier).state =
            const ActiveOrdersQuery(branch: _harbor);
        await _settle(c);
        expect(c.read(effectiveActiveOrdersQueryProvider).branch, _harbor);
        await c
            .read(activeOrdersRepositoryProvider)
            .loadActive(c.read(effectiveActiveOrdersQueryProvider));
        expect(t.lastTo('owner_active_orders')!['p_branch_id'], 'branch-2');

        t.branches = const [('rest-1', 'branch-1', 'Main')];
        await _reload(c);
        expect(c.read(effectiveActiveOrdersQueryProvider).branch, isNull);
        final from = t.params.length;
        await c
            .read(activeOrdersRepositoryProvider)
            .loadActive(c.read(effectiveActiveOrdersQueryProvider));
        expect(t.lastTo('owner_active_orders')!['p_branch_id'], isNull);
        for (final call in t.params.skip(from)) {
          expect(call.values, isNot(contains('branch-2')));
        }

        // A failure after the omission keeps it omitted.
        t.orgStructure = () => throw StateError('down');
        await _reload(c);
        expect(c.read(effectiveActiveOrdersQueryProvider).branch, isNull);

        // A membership change makes a foreign branch inert at once.
        t.orgStructure = null;
        c.read(activeOrdersQueryProvider.notifier).state =
            const ActiveOrdersQuery(branch: _harbor);
        c.updateOverrides(
          _overrides(
            t,
            _membership(organizationId: 'org-2', restaurantId: 'r-2'),
          ),
        );
        expect(c.read(effectiveActiveOrdersQueryProvider).branch, isNull);
      },
    );

    // THE WIRING, not just the value. Reading the effective query and handing
    // it to a repository by hand proves the reconciliation is right; it does
    // NOT prove the controllers use it — and the controllers are what transport
    // in production. These two drive the real controller.
    test('Activity: the CONTROLLER stops sending a retired branch', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        branch: _harbor,
      );
      await _settle(c);
      c.read(auditLogControllerProvider);
      await _pump();
      expect(t.lastTo('owner_audit_events')!['p_branch_id'], 'branch-2');

      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await _reload(c);
      final from = t.params.length;
      c.read(auditLogControllerProvider);
      await _pump();

      expect(t.lastTo('owner_audit_events')!['p_branch_id'], isNull);
      for (final call in t.params.skip(from)) {
        expect(call.values, isNot(contains('branch-2')));
      }
    });

    test(
      'Active Orders: the CONTROLLER stops sending a retired branch',
      () async {
        final t = _FakeTransport();
        final c = ProviderContainer(
          overrides: [
            ..._overrides(t, _membership()),
            // No polling: a stray timer must not outlive the test.
            activeOrdersPollIntervalProvider.overrideWithValue(null),
          ],
        );
        addTearDown(c.dispose);
        c.read(activeOrdersQueryProvider.notifier).state =
            const ActiveOrdersQuery(branch: _harbor);
        await _settle(c);
        final sub = c.listen(activeOrdersControllerProvider, (_, _) {});
        addTearDown(sub.close);
        await _pump();
        expect(t.lastTo('owner_active_orders')!['p_branch_id'], 'branch-2');

        t.branches = const [('rest-1', 'branch-1', 'Main')];
        await _reload(c);
        final from = t.params.length;
        await _pump();

        expect(t.lastTo('owner_active_orders')!['p_branch_id'], isNull);
        for (final call in t.params.skip(from)) {
          expect(call.values, isNot(contains('branch-2')));
        }
      },
    );

    test('the reconciliation is one rule, shared with the analytics scope', () {
      const covered = null;
      expect(
        analyticsBranchStillApplies(_harbor, coverage: covered, answer: null),
        isFalse,
        reason: 'no coverage, no filter',
      );
    });

    test('an unchanged branch does not churn the query value', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _overrides(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        branch: _harbor,
      );
      await _settle(c);
      final first = c.read(effectiveAuditQueryProvider);
      // A refresh that returns the SAME branches must not look like a new
      // query, or the timeline would reload on every refresh.
      await _reload(c);
      expect(c.read(effectiveAuditQueryProvider), first);
    });
  });

  // =======================================================================
  // R1C-03 — the refresh survives the widget that started it
  // =======================================================================
  group('R1C-03: refresh is owned by the shared container', () {
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
              membership: _membership(),
              reportsTransport: transport,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return transport;
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

    /// Taps the owner's refresh, crosses the breakpoint while the enumeration
    /// is parked, then releases it — the exact sequence that used to cancel the
    /// financial half.
    Future<({_FakeTransport t, int from})> refreshAcrossBreakpoint(
      WidgetTester tester, {
      required _FakeTransport t,
      required void Function() beforeRelease,
    }) async {
      final gate = Completer<void>();
      final parked = t.orgStructure;
      t.orgStructure = () => gate.future.then((_) {
        t.orgStructure = parked;
        beforeRelease();
        return t.invoke('list_org_structure', const {}).then((v) {
          // Drop the extra recorded call so counts stay about the refresh.
          t.functions.removeLast();
          t.params.removeLast();
          return v;
        });
      });

      final from = t.params.length;
      await tester.tap(find.byKey(const Key('reports-refresh-button')));
      await tester.pump();

      // The Overview widget is remounted underneath the in-flight refresh.
      tester.view.physicalSize = const Size(430, 2000);
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();
      return (t: t, from: from);
    }

    testWidgets('the financial refresh completes even though the Overview was '
        'remounted mid-flight (unchanged branches)', (tester) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);
      final r = await refreshAcrossBreakpoint(
        tester,
        t: t,
        beforeRelease: () {},
      );

      final reports = [
        for (var i = r.from; i < t.functions.length; i++)
          if (t.functions[i] == 'owner_report_range') t.params[i],
      ];
      expect(reports, hasLength(1), reason: 'skipped or duplicated otherwise');
      expect(reports.single['p_branch_id'], 'branch-2');
      expect(
        t.countOf('list_org_structure'),
        greaterThan(0),
        reason: 'the enumeration ran',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('...and for an OMISSION, exactly one report request, for the '
        'parent scope', (tester) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);
      final r = await refreshAcrossBreakpoint(
        tester,
        t: t,
        beforeRelease: () =>
            t.branches = const [('rest-1', 'branch-1', 'Main')],
      );

      final reports = [
        for (var i = r.from; i < t.functions.length; i++)
          if (t.functions[i] == 'owner_report_range') t.params[i],
      ];
      expect(reports, hasLength(1));
      expect(reports.single['p_branch_id'], isNull);
      for (var i = r.from; i < t.params.length; i++) {
        expect(t.params[i].values, isNot(contains('branch-2')));
      }
      expect(
        shared(tester).read(dashboardAnalyticsScopeProvider)!.branchId,
        isNull,
      );
    });

    testWidgets('...and for a FAILED enumeration, the retained scope still '
        'refreshes', (tester) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);
      final r = await refreshAcrossBreakpoint(
        tester,
        t: t,
        beforeRelease: () => t.orgStructure = () => throw StateError('down'),
      );

      final reports = [
        for (var i = r.from; i < t.functions.length; i++)
          if (t.functions[i] == 'owner_report_range') t.params[i],
      ];
      expect(reports, hasLength(1));
      expect(reports.single['p_branch_id'], 'branch-2');
      expect(
        shared(tester).read(dashboardAnalyticsScopeProvider)!.branchId,
        'branch-2',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid taps coalesce into ONE refresh', (tester) async {
      final t = await pumpShell(tester);
      final gate = Completer<void>();
      t.orgStructure = () => gate.future.then(
        (_) => <String, dynamic>{
          'ok': true,
          'entity': 'org_structure',
          'restaurants': <dynamic>[],
        },
      );

      final optionsBefore = t.countOf('list_org_structure');
      final from = t.params.length;
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('reports-refresh-button')));
        await tester.pump();
      }
      expect(
        t.countOf('list_org_structure'),
        optionsBefore + 1,
        reason: 'later taps join the running refresh',
      );
      expect(
        shared(tester).read(dashboardRefreshControllerProvider),
        isTrue,
        reason: 'the controller reports it is refreshing',
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(shared(tester).read(dashboardRefreshControllerProvider), isFalse);
      final reports = [
        for (var i = from; i < t.functions.length; i++)
          if (t.functions[i] == 'owner_report_range') t.params[i],
      ];
      expect(reports, hasLength(1), reason: 'one sequence, one financial read');
    });
  });
}
