import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/state/analytics_branch_providers.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX FINAL F-1B RE-REVIEW — the four remaining findings.
///
/// F-1B-1-R1 — a branch RENAME rebuilt Orders History. `DashboardAnalyticsScope`
/// includes `branchLabel` in its equality, and `orderHistoryRepositoryProvider`
/// watched the whole scope, so editing a branch's NAME produced an unequal
/// value, rebuilt the repository, rebuilt the controller, and threw away the
/// owner's loaded page to re-issue `owner_order_history` from a null cursor.
/// Display metadata was acting as query identity.
///
/// F-1B-2-R1 — the conflict check was documented as whole-response and was not.
/// The real repository role-filtered rows AS IT DECODED them, so for a
/// restaurant owner of rest-2 a conflicting `rest-CONFLICT/branch-2` row was
/// dropped before anything compared it to `rest-2/branch-2`. The sanitiser saw
/// one clean tuple and offered branch-2 as if the payload had never
/// contradicted itself.
///
/// F-1B-3-R1 — an omission could be undone by ignorance. After a successful
/// list retired branch B, any later non-`AsyncData` state fell back to the
/// still-stored raw selection, so a failed refresh RESURRECTED B and moved the
/// money back to a branch nothing had reintroduced.
///
/// F-1B-3-R2 — Orders and Activity each rebuilt a `ProviderScope` overriding
/// membership and transport with values identical to the shell's own hoisted
/// scope. An override decides where a provider LIVES, so each surface got its
/// own branch-options chain: its own request, and its own memory of what the
/// last answer said. Overview could learn that B was gone while Orders, mounting
/// fresh, had never been told and asked for B's history anyway.

// ===========================================================================
// Harness
// ===========================================================================

class _RecordingTransport implements SyncRpcTransport {
  /// Overrides what `list_org_structure` does; null uses [branches].
  /// Returning a Future parks the call — `invoke` is async, so it awaits.
  Object? Function()? orgStructure;

  /// The branches the payload should contain, as (restaurantId, branchId, name).
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
        'orders': <dynamic>[],
        'has_more': true,
        'next_cursor': 'cursor-1',
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
  String organizationId = 'org-1',
  MembershipRole role = MembershipRole.orgOwner,
  String? restaurantId = 'rest-1',
  String? branchId = 'branch-1',
}) => MembershipContext(
  id: 'm-1',
  organizationId: organizationId,
  organizationName: 'Org',
  restaurantId: restaurantId,
  restaurantName: 'Rest One',
  branchId: branchId,
  branchName: 'Main',
  role: role,
  status: 'active',
);

const _harborOld = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-2',
  label: 'Rest Two · Harbor',
);

ProviderContainer _container({
  required _RecordingTransport transport,
  MembershipContext? membership,
}) {
  final c = ProviderContainer(
    overrides: [
      dashboardMembershipProvider.overrideWithValue(
        membership ?? _membership(),
      ),
      dashboardAuthTransportProvider.overrideWithValue(transport),
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Settles the whole branch-option chain, failures included.
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

/// Reads the history controller — whose constructor loads the first page — and
/// lets that load complete. There is no `loadFirstPage`; the load IS the
/// controller's construction, which is exactly why a needless rebuild costs a
/// request.
Future<void> _settleHistory(ProviderContainer c) async {
  c.read(orderHistoryControllerProvider);
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // =======================================================================
  // F-1B-1-R1 — a rename is display metadata, not a new query
  // =======================================================================
  group('F-1B-1-R1: a rename does not re-query Orders History', () {
    test('transportIdentity drops the label and nothing else', () {
      const scope = DashboardAnalyticsScope(
        organizationId: 'org-1',
        restaurantId: 'rest-2',
        branchId: 'branch-2',
        kind: DashboardAnalyticsScopeKind.singleBranch,
        branchLabel: 'Old',
      );
      final renamed = DashboardAnalyticsScope(
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        branchId: scope.branchId,
        kind: scope.kind,
        branchLabel: 'New',
      );
      // The defect in one line: the display value differs...
      expect(scope == renamed, isFalse);
      // ...but the request identity does not.
      expect(scope.transportIdentity, renamed.transportIdentity);
      expect(scope.transportIdentity.branchLabel, isNull);
      expect(scope.transportIdentity.restaurantId, 'rest-2');
      expect(scope.transportIdentity.branchId, 'branch-2');
      expect(scope.transportIdentity.kind, scope.kind);
      // Two genuinely different scopes stay different.
      expect(
        scope.transportIdentity,
        isNot(
          const DashboardAnalyticsScope(
            organizationId: 'org-1',
            restaurantId: 'rest-2',
            branchId: 'branch-9',
            kind: DashboardAnalyticsScopeKind.singleBranch,
          ).transportIdentity,
        ),
      );
    });

    test('a rename keeps the repository, the controller, the cursor and the '
        'rows — and issues no request', () async {
      final t = _RecordingTransport();
      final c = _container(transport: t);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await _settle(c);

      // Load a first page and take note of everything that must survive.
      final repoBefore = c.read(orderHistoryRepositoryProvider);
      final controllerBefore = c.read(orderHistoryControllerProvider.notifier);
      await _settleHistory(c);
      final stateBefore = c.read(orderHistoryControllerProvider);
      final reportKeyBefore = c.read(currentOwnerReportKeyProvider);
      final seriesKeyBefore = c.read(currentOwnerSalesSeriesKeyProvider)!;
      final historyCallsBefore = t.countOf('owner_order_history');
      expect(historyCallsBefore, greaterThan(0));
      expect(stateBefore.cursor, 'cursor-1');
      expect(
        c.read(dashboardAnalyticsScopeProvider)!.branchLabel,
        contains('Harbor'),
      );

      // The branch is RENAMED server-side and the list is refetched.
      t.branches = const [
        ('rest-1', 'branch-1', 'Main'),
        ('rest-2', 'branch-2', 'Harbour Point'),
      ];
      await _reload(c);

      // The display really did change...
      expect(
        c.read(dashboardAnalyticsScopeProvider)!.branchLabel,
        'Rest Two · Harbour Point',
      );
      // ...and the request identity really did not.
      expect(
        c.read(analyticsTransportScopeProvider),
        DashboardAnalyticsScope.ofIds(
          organizationId: 'org-1',
          restaurantId: 'rest-2',
          branchId: 'branch-2',
        ),
      );
      expect(c.read(currentOwnerReportKeyProvider), reportKeyBefore);
      expect(c.read(currentOwnerSalesSeriesKeyProvider), seriesKeyBefore);

      // Nothing downstream was rebuilt, so nothing was refetched or reset.
      expect(
        identical(c.read(orderHistoryRepositoryProvider), repoBefore),
        isTrue,
        reason: 'a rename must not rebuild the history repository',
      );
      expect(
        identical(
          c.read(orderHistoryControllerProvider.notifier),
          controllerBefore,
        ),
        isTrue,
        reason: 'a rename must not rebuild the history controller',
      );
      expect(t.countOf('owner_order_history'), historyCallsBefore);
      final stateAfter = c.read(orderHistoryControllerProvider);
      expect(stateAfter.cursor, 'cursor-1', reason: 'the page is retained');
      expect(stateAfter.loading, isFalse);
    });

    test('a REAL scope change still rebuilds and resets, as it must', () async {
      final t = _RecordingTransport();
      final c = _container(transport: t);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await _settle(c);
      final repoBefore = c.read(orderHistoryRepositoryProvider);
      await _settleHistory(c);
      final callsBefore = t.countOf('owner_order_history');

      // Branch B is genuinely removed: this IS a new query.
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await _reload(c);

      expect(
        identical(c.read(orderHistoryRepositoryProvider), repoBefore),
        isFalse,
      );
      await _settleHistory(c);
      expect(t.countOf('owner_order_history'), greaterThan(callsBefore));
      expect(t.lastTo('owner_order_history')!['p_branch_id'], isNull);
      expect(t.lastTo('owner_order_history')!['p_cursor'], isNull);
    });
  });

  // =======================================================================
  // F-1B-2-R1 — conflicts decided over the WHOLE response, before role filtering
  // =======================================================================
  group(
    'F-1B-2-R1: the real repository detects conflicts before it filters',
    () {
      Future<List<String>> branchIdsFor(
        List<(String, String, String)> rows, {
        MembershipRole role = MembershipRole.restaurantOwner,
        String restaurantId = 'rest-2',
      }) async {
        final t = _RecordingTransport()..branches = rows;
        final repo = RealAuditFilterOptionsRepository(
          scope: _membership(role: role, restaurantId: restaurantId),
          transport: t,
        );
        final out = await repo.loadBranches();
        return out.map((b) => b.branchId).toList();
      }

      test(
        'A. the conflicting tuple FIRST — branch-2 is dropped even though the '
        'conflicting row is outside this owner\'s coverage',
        () async {
          expect(
            await branchIdsFor(const [
              ('rest-CONFLICT', 'branch-2', 'Harbor'),
              ('rest-2', 'branch-2', 'Harbor'),
              ('rest-2', 'branch-9', 'Airport'),
            ]),
            ['branch-9'],
          );
        },
      );

      test('B. the valid tuple FIRST — same answer, so order is not '
          'load-bearing', () async {
        expect(
          await branchIdsFor(const [
            ('rest-2', 'branch-2', 'Harbor'),
            ('rest-CONFLICT', 'branch-2', 'Harbor'),
            ('rest-2', 'branch-9', 'Airport'),
          ]),
          ['branch-9'],
        );
      });

      test(
        'C. an exact duplicate composite is one branch, not a conflict',
        () async {
          expect(
            await branchIdsFor(const [
              ('rest-2', 'branch-2', 'Harbor'),
              ('rest-2', 'branch-2', 'Harbor'),
            ]),
            ['branch-2'],
          );
        },
      );

      test(
        'D. the same composite under a different label is one identity',
        () async {
          expect(
            await branchIdsFor(const [
              ('rest-2', 'branch-2', 'Harbor'),
              ('rest-2', 'branch-2', 'Harbour Point'),
            ]),
            ['branch-2'],
          );
        },
      );

      test(
        'E. the same label on different branch ids is not a conflict',
        () async {
          expect(
            await branchIdsFor(const [
              ('rest-2', 'branch-2', 'Harbor'),
              ('rest-2', 'branch-9', 'Harbor'),
            ]),
            ['branch-2', 'branch-9'],
          );
        },
      );

      test('F. an ORG owner sees the same conflict exclusion', () async {
        expect(
          await branchIdsFor(
            const [
              ('rest-CONFLICT', 'branch-2', 'Harbor'),
              ('rest-2', 'branch-2', 'Harbor'),
              ('rest-1', 'branch-1', 'Main'),
            ],
            role: MembershipRole.orgOwner,
            restaurantId: 'rest-1',
          ),
          ['branch-1'],
        );
      });

      test(
        'G. a BRANCH-FIXED membership whose own branch id is conflicted gets '
        'no option for it',
        () async {
          expect(
            await branchIdsFor(
              const [
                ('rest-CONFLICT', 'branch-1', 'Main'),
                ('rest-1', 'branch-1', 'Main'),
              ],
              role: MembershipRole.manager,
              restaurantId: 'rest-1',
            ),
            isEmpty,
          );
        },
      );

      test('the conflicting rows never leave the repository', () async {
        final t = _RecordingTransport()
          ..branches = const [
            ('rest-CONFLICT', 'branch-2', 'Harbor'),
            ('rest-2', 'branch-2', 'Harbor'),
            ('rest-2', 'branch-9', 'Airport'),
          ];
        final repo = RealAuditFilterOptionsRepository(
          scope: _membership(
            role: MembershipRole.restaurantOwner,
            restaurantId: 'rest-2',
          ),
          transport: t,
        );
        final out = await repo.loadBranches();
        expect(out.any((b) => b.restaurantId == 'rest-CONFLICT'), isFalse);
      });
    },
  );

  // =======================================================================
  // F-1B-3-R1 — an omission is not undone by later ignorance
  // =======================================================================
  group('F-1B-3-R1: the last real ANSWER decides, not the last known state', () {
    String? branchScope(ProviderContainer c) =>
        c.read(dashboardAnalyticsScopeProvider)!.branchId;

    test('INITIAL failure, with no prior answer, keeps branch B', () async {
      final t = _RecordingTransport()
        ..orgStructure = () => throw StateError('down');
      final c = _container(transport: t);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await _settle(c);

      expect(
        c.read(analyticsBranchOptionsProvider),
        isNull,
        reason: 'never answered',
      );
      expect(branchScope(c), 'branch-2');
    });

    test('INITIAL loading, with no prior answer, keeps branch B', () async {
      final gate = Completer<void>();
      final t = _RecordingTransport()
        // `invoke` is async, so returning a Future parks the call.
        ..orgStructure = () => gate.future;
      final c = _container(transport: t);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      c.read(analyticsBranchAnswerProvider);
      expect(branchScope(c), 'branch-2');
      gate.complete();
    });

    test('answer CONTAINS B, then a refresh fails -> B stays', () async {
      final t = _RecordingTransport();
      final c = _container(transport: t);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await _settle(c);
      expect(branchScope(c), 'branch-2');

      t.orgStructure = () => throw StateError('down');
      await _reload(c);
      expect(branchScope(c), 'branch-2', reason: 'the last answer still has B');
    });

    test('answer OMITS B, then a refresh fails -> the parent stays. B is NOT '
        'resurrected', () async {
      final t = _RecordingTransport();
      final c = _container(transport: t);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await _settle(c);
      expect(branchScope(c), 'branch-2');

      // Authoritative removal.
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await _reload(c);
      expect(branchScope(c), isNull);

      // ...and now the enumeration starts failing.
      t.orgStructure = () => throw StateError('down');
      await _reload(c);

      expect(
        branchScope(c),
        isNull,
        reason: 'not knowing is not the same as being told B is back',
      );
      expect(c.read(currentOwnerReportKeyProvider).branchId, isNull);
      expect(c.read(currentOwnerSalesSeriesKeyProvider)!.branchId, isNull);
      // The raw selection is still stored, and still inert.
      expect(c.read(selectedAnalyticsBranchProvider), _harborOld);

      final from = t.params.length;
      await c
          .read(orderHistoryRepositoryProvider)
          .loadHistory(const OrderHistoryQuery());
      for (final call in t.params.skip(from)) {
        expect(call.values, isNot(contains('branch-2')));
      }
    });

    test(
      'answer OMITS B, then a refresh is in flight -> the parent stays',
      () async {
        final t = _RecordingTransport();
        final c = _container(transport: t);
        c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
        await _settle(c);
        t.branches = const [('rest-1', 'branch-1', 'Main')];
        await _reload(c);
        expect(branchScope(c), isNull);

        final gate = Completer<void>();
        t.orgStructure = () => gate.future;
        c.invalidate(auditBranchOptionsProvider);
        c.read(analyticsBranchAnswerProvider);
        expect(branchScope(c), isNull);
        gate.complete();
      },
    );

    test('a later answer that REINTRODUCES B resumes it; one that still omits '
        'it does not', () async {
      final t = _RecordingTransport();
      final c = _container(transport: t);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await _settle(c);
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      await _reload(c);
      expect(branchScope(c), isNull);

      // Still omitted: still the parent.
      await _reload(c);
      expect(branchScope(c), isNull);

      // Really back, and still authorized: it may resume.
      t.branches = const [
        ('rest-1', 'branch-1', 'Main'),
        ('rest-2', 'branch-2', 'Harbor'),
      ];
      await _reload(c);
      expect(branchScope(c), 'branch-2');
    });

    test('org A\'s answer is never applied to org B — including when org B\'s '
        'own load FAILS', () async {
      final t = _RecordingTransport();
      final c = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(
            _membership(organizationId: 'org-1'),
          ),
          dashboardAuthTransportProvider.overrideWithValue(t),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );
      addTearDown(c.dispose);
      await _settle(c);
      expect(c.read(analyticsBranchOptionsProvider), isNotNull);

      // A DIFFERENT organization, whose enumeration then fails. Riverpod keeps
      // org-1's value on the provider across both the dependency change and the
      // failure, so only the stamp can tell them apart.
      t.orgStructure = () => throw StateError('down');
      c.updateOverrides([
        dashboardMembershipProvider.overrideWithValue(
          _membership(organizationId: 'org-2', restaurantId: 'rest-X'),
        ),
        dashboardAuthTransportProvider.overrideWithValue(t),
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ]);
      await _settle(c);

      expect(
        c.read(analyticsBranchOptionsProvider),
        isNull,
        reason: 'org-1 answered a question org-2 is not asking',
      );
      expect(c.read(dashboardAnalyticsScopeProvider)!.organizationId, 'org-2');
    });
  });

  // =======================================================================
  // F-1B-3-R2 — ONE shared branch-options state across the whole shell
  // =======================================================================
  group('F-1B-3-R2: the real shell shares one branch-options state', () {
    Future<_RecordingTransport> pumpShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = _RecordingTransport();
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

    NavigationBar nav(WidgetTester tester) => tester.widget<NavigationBar>(
      find.byKey(const Key('dashboard-bottom-nav')),
    );

    /// The container the analytics chain actually lives in.
    ///
    /// NOT the one behind the NavigationBar: the nav is a sibling of the shell's
    /// hoisted content scope, so reading from it yields the ROOT container and
    /// an invalidate there would refresh a different instance entirely. Reading
    /// from inside the Overview subtree gets the shared one — which is the same
    /// instance Orders resolves to, and that is the property under test.
    ProviderContainer _sharedContainer(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byKey(const Key('overview-scope-selector'))),
          listen: false,
        );

    Future<void> goTo(WidgetTester tester, DashboardDestination d) async {
      nav(tester).onDestinationSelected!(d.visibleIndex!);
      await tester.pumpAndSettle();
    }

    Future<void> selectBranchB(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest Two · Harbor').last);
      await tester.pumpAndSettle();
    }

    testWidgets('navigating between tabs does NOT re-enumerate branches', (
      tester,
    ) async {
      final t = await pumpShell(tester);
      final afterOverview = t.countOf('list_org_structure');
      expect(afterOverview, 1, reason: 'one shared enumeration');

      await goTo(tester, DashboardDestination.orders);
      expect(t.countOf('list_org_structure'), afterOverview);

      await tester.tap(find.byKey(const Key('orders-tab-history')));
      await tester.pumpAndSettle();
      expect(t.countOf('list_org_structure'), afterOverview);

      await goTo(tester, DashboardDestination.overview);
      await goTo(tester, DashboardDestination.orders);
      expect(
        t.countOf('list_org_structure'),
        afterOverview,
        reason: 'a recreated tab subtree must not mint a second state',
      );
    });

    testWidgets('an authoritative omission on Overview is already true in '
        'Orders — no stale Branch B history request', (tester) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);

      // Confirm the selection really took effect first.
      await goTo(tester, DashboardDestination.orders);
      await tester.tap(find.byKey(const Key('orders-tab-history')));
      await tester.pumpAndSettle();
      expect(t.lastTo('owner_order_history')!['p_branch_id'], 'branch-2');

      // Back to Overview; branch B is removed and the list refreshes.
      await goTo(tester, DashboardDestination.overview);
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      final container = _sharedContainer(tester);
      container.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();

      final fromOmission = t.params.length;

      // Now open Orders history again.
      await goTo(tester, DashboardDestination.orders);
      await tester.tap(find.byKey(const Key('orders-tab-history')));
      await tester.pumpAndSettle();

      final history = t.lastTo('owner_order_history')!;
      expect(history['p_restaurant_id'], isNull);
      expect(history['p_branch_id'], isNull);
      for (final call in t.params.skip(fromOmission)) {
        expect(
          call.values,
          isNot(contains('branch-2')),
          reason: 'no surface may still be asking for a removed branch',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('omission, then a FAILING refresh, then Orders — still the '
        'parent scope', (tester) async {
      final t = await pumpShell(tester);
      await selectBranchB(tester);
      await tester.pumpAndSettle();

      final container = _sharedContainer(tester);
      t.branches = const [('rest-1', 'branch-1', 'Main')];
      container.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();

      t.orgStructure = () => throw StateError('down');
      container.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();

      final fromFailure = t.params.length;
      await goTo(tester, DashboardDestination.orders);
      await tester.tap(find.byKey(const Key('orders-tab-history')));
      await tester.pumpAndSettle();

      final history = t.lastTo('owner_order_history')!;
      expect(history['p_branch_id'], isNull);
      for (final call in t.params.skip(fromFailure)) {
        expect(call.values, isNot(contains('branch-2')));
      }

      // And returning to Overview agrees.
      await goTo(tester, DashboardDestination.overview);
      expect(
        tester
            .widget<DropdownButtonFormField<String?>>(
              find.byKey(const Key('overview-scope-selector')),
            )
            .initialValue,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
