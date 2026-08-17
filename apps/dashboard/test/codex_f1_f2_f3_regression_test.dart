import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/active_orders_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart' show ReportRange;
import 'package:restoflow_dashboard/src/data/real_active_orders_repository.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX ADVERSARIAL REVIEW — regressions for findings F-1, F-2 and F-3.
///
/// F-1 (P1): a branch selected in one organization could survive a sign-out and
/// still be applied under the NEXT organization's membership, because the
/// selection lives in the root provider container (never rebuilt on sign-out)
/// and `covers()`'s org-wide arm returned true for any branch id. The previous
/// "does not leak into org B" test used TWO ProviderContainers — two roots — so
/// it could not observe this at all. These tests use ONE container and replace
/// the membership through `updateOverrides`, which is what the real app does
/// when a session changes beneath a live root scope.
///
/// F-2 (P2): the shared `PaymentFilter` gained card/bit/external for the order
/// history RPC, but `owner_active_orders` enum-validates to paid/unpaid/cash
/// and raises 22023.
///
/// F-3 (P2): CLIENT-E2's cross-surface scope sync was only ever tested through
/// flat containers, never through the real shell's hoisted + nested scopes.

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

class _RecordingTransport implements SyncRpcTransport {
  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  /// Every call made to [function], in order.
  List<Map<String, dynamic>> callsTo(String function) => [
    for (var i = 0; i < functions.length; i++)
      if (functions[i] == function) params[i],
  ];

  Map<String, dynamic>? lastTo(String function) {
    final all = callsTo(function);
    return all.isEmpty ? null : all.last;
  }

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    functions.add(function);
    params.add(args);
    return switch (function) {
      'owner_order_history' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'orders': <dynamic>[],
        'has_more': false,
        'next_cursor': null,
      },
      'owner_report_range' => <String, dynamic>{
        'ok': true,
        'entity': 'owner_report_range',
        'currency_code': 'ILS',
        'range': 'today',
        'current': <String, dynamic>{
          'order_count': 3,
          'completed_count': 2,
          'open_count': 1,
          'unpaid_count': 1,
          'gross_minor': 9000,
          'discount_minor': 0,
          'net_minor': 9000,
          'collected_minor': 9000,
          'cash_minor': 9000,
          'tenders': <Map<String, dynamic>>[
            {'method': 'cash', 'count': 2, 'total_minor': 9000},
          ],
        },
        'comparison': <String, dynamic>{
          'order_count': 2,
          'gross_minor': 6000,
          'net_minor': 6000,
          'cash_minor': 6000,
          'collected_minor': 6000,
        },
        'hourly': <dynamic>[],
        'shift_cash': null,
      },
      _ => <String, dynamic>{'ok': true},
    };
  }
}

class _FixedOptions implements AuditFilterOptionsRepository {
  const _FixedOptions(this.branches);

  final List<AuditBranchOption> branches;

  @override
  Future<List<AuditBranchOption>> loadBranches() async => branches;

  @override
  Future<List<AuditActorOption>> loadActors() async => const [];
}

MembershipContext _membership({
  required String organizationId,
  required MembershipRole role,
  String restaurantId = 'rest-1',
  String branchId = 'branch-1',
  String branchName = 'Main',
}) => MembershipContext(
  id: 'm-$organizationId',
  organizationId: organizationId,
  organizationName: 'Org',
  // The shape resolveTenantContext produces: a concrete FIRST restaurant and
  // FIRST branch pinned onto a membership that may cover much more.
  restaurantId: restaurantId,
  restaurantName: 'Rest One',
  branchId: branchId,
  branchName: branchName,
  role: role,
  status: 'active',
);

const _orgABranch = AuditBranchOption(
  organizationId: 'org-A',
  branchId: 'branch-A1',
  restaurantId: 'rest-A',
  label: 'Org A · Harbor',
);
const _orgBBranch = AuditBranchOption(
  organizationId: 'org-B',
  branchId: 'branch-B1',
  restaurantId: 'rest-B',
  label: 'Org B · Airport',
);

void main() {
  // =========================================================================
  // F-1 — one container, membership replaced underneath it
  // =========================================================================
  group('F-1: a selection cannot survive into another organization', () {
    /// One container whose membership can be REPLACED in place, exactly as the
    /// live app does: `main.dart` creates the root ProviderScope once in
    /// `runApp`, and DashboardAuthFlow swaps the membership through widget
    /// state without rebuilding it.
    ProviderContainer container(MembershipContext membership) {
      final c = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(membership),
          dashboardAuthTransportProvider.overrideWithValue(
            _RecordingTransport(),
          ),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('org A selection is dropped when an org B membership replaces it, '
        'and no org A id reaches ANY request', () async {
      final transport = _RecordingTransport();
      final c = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(
            _membership(organizationId: 'org-A', role: MembershipRole.orgOwner),
          ),
          dashboardAuthTransportProvider.overrideWithValue(transport),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );
      addTearDown(c.dispose);

      // 1-4: pick org A's branch and confirm it takes effect.
      c.read(selectedAnalyticsBranchProvider.notifier).state = _orgABranch;
      final beforeScope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(beforeScope.organizationId, 'org-A');
      expect(beforeScope.restaurantId, 'rest-A');
      expect(beforeScope.branchId, 'branch-A1');
      expect(c.read(effectiveAnalyticsBranchProvider), _orgABranch);

      // CODEX F-1B-3 — reading the scope now also enumerates the live branch
      // options, because a selection has to be checked against what still
      // exists. That enumeration ran under the org A membership and asked for
      // org A, which is correct. What must never happen is an org A id
      // reaching a request AFTER the membership changes, so the decisive scan
      // below starts here rather than at the beginning of the session.
      final callsUnderOrgA = transport.params.length;

      // 5: the membership is REPLACED on the same container. No new root.
      c.updateOverrides([
        dashboardMembershipProvider.overrideWithValue(
          _membership(
            organizationId: 'org-B',
            role: MembershipRole.orgOwner,
            restaurantId: 'rest-B',
            branchId: 'branch-B1',
          ),
        ),
        dashboardAuthTransportProvider.overrideWithValue(transport),
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ]);

      // 7: the stale selection is sanitised away and the scope is org B broad.
      expect(
        c.read(effectiveAnalyticsBranchProvider),
        isNull,
        reason: 'the org A option is no longer covered',
      );
      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.organizationId, 'org-B');
      expect(scope.restaurantId, isNull);
      expect(scope.branchId, isNull);
      expect(scope.kind, DashboardAnalyticsScopeKind.orgWide);

      // The cache keys carry no org A identifier.
      final reportKey = c.read(currentOwnerReportKeyProvider);
      expect(reportKey.organizationId, 'org-B');
      expect(reportKey.restaurantId, isNull);
      expect(reportKey.branchId, isNull);

      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      final seriesKey = c.read(currentOwnerSalesSeriesKeyProvider)!;
      expect(seriesKey.organizationId, 'org-B');
      expect(seriesKey.restaurantId, isNull);
      expect(seriesKey.branchId, isNull);

      // ...and neither does the actual Orders history request.
      await c
          .read(orderHistoryRepositoryProvider)
          .loadHistory(const OrderHistoryQuery());
      final history = transport.lastTo('owner_order_history')!;
      expect(history['p_organization_id'], 'org-B');
      expect(history['p_restaurant_id'], isNull);
      expect(history['p_branch_id'], isNull);

      // The decisive assertion: no org A identifier on the wire once org B is
      // the membership.
      for (final call in transport.params.skip(callsUnderOrgA)) {
        expect(call.values, isNot(contains('rest-A')));
        expect(call.values, isNot(contains('branch-A1')));
        expect(call.values, isNot(contains('org-A')));
      }
      // And the only thing that DID go out under org A was the branch
      // enumeration, which carries the organization and nothing else — so org
      // A's restaurant and branch reached no request at any point in the
      // session.
      expect(
        transport.functions.take(callsUnderOrgA),
        everyElement('list_org_structure'),
      );
      for (final call in transport.params) {
        expect(call.values, isNot(contains('rest-A')));
        expect(call.values, isNot(contains('branch-A1')));
      }
    });

    test('org A selection is dropped for an org B BRANCH-FIXED membership, '
        'which keeps its own branch', () {
      final transport = _RecordingTransport();
      final c = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(
            _membership(organizationId: 'org-A', role: MembershipRole.orgOwner),
          ),
          dashboardAuthTransportProvider.overrideWithValue(transport),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _orgABranch;

      c.updateOverrides([
        dashboardMembershipProvider.overrideWithValue(
          _membership(
            organizationId: 'org-B',
            role: MembershipRole.manager,
            restaurantId: 'rest-B',
            branchId: 'branch-B1',
          ),
        ),
        dashboardAuthTransportProvider.overrideWithValue(transport),
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ]);

      expect(c.read(effectiveAnalyticsBranchProvider), isNull);
      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.organizationId, 'org-B');
      expect(scope.restaurantId, 'rest-B');
      expect(scope.branchId, 'branch-B1');
    });

    test('a RESTAURANT coverage shrink inside one org drops a now-uncovered '
        'sibling branch', () {
      const sibling = AuditBranchOption(
        organizationId: 'org-A',
        branchId: 'branch-A2',
        restaurantId: 'rest-A2',
        label: 'Org A · Second restaurant',
      );
      final c = container(
        _membership(organizationId: 'org-A', role: MembershipRole.orgOwner),
      );
      c.read(selectedAnalyticsBranchProvider.notifier).state = sibling;
      expect(c.read(effectiveAnalyticsBranchProvider), sibling);

      // Demoted to restaurant owner of a DIFFERENT restaurant.
      c.updateOverrides([
        dashboardMembershipProvider.overrideWithValue(
          _membership(
            organizationId: 'org-A',
            role: MembershipRole.restaurantOwner,
            restaurantId: 'rest-A',
          ),
        ),
        dashboardAuthTransportProvider.overrideWithValue(_RecordingTransport()),
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ]);

      expect(c.read(effectiveAnalyticsBranchProvider), isNull);
      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.kind, DashboardAnalyticsScopeKind.restaurantWide);
      expect(scope.restaurantId, 'rest-A');
    });

    test('a STILL-VALID selection is not cleared unnecessarily', () {
      final c = container(
        _membership(organizationId: 'org-A', role: MembershipRole.orgOwner),
      );
      c.read(selectedAnalyticsBranchProvider.notifier).state = _orgABranch;

      // Same org, same coverage — a rebuild must not drop the choice.
      c.updateOverrides([
        dashboardMembershipProvider.overrideWithValue(
          _membership(organizationId: 'org-A', role: MembershipRole.orgOwner),
        ),
        dashboardAuthTransportProvider.overrideWithValue(_RecordingTransport()),
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ]);

      expect(c.read(effectiveAnalyticsBranchProvider), _orgABranch);
      expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-A1');
    });

    test('covers() requires organization equality on EVERY kind', () {
      for (final role in const [
        MembershipRole.orgOwner,
        MembershipRole.restaurantOwner,
        MembershipRole.manager,
      ]) {
        final scope = DashboardAnalyticsScope.coveredBy(
          _membership(organizationId: 'org-B', role: role),
        );
        expect(
          scope.covers(_orgABranch),
          isFalse,
          reason: 'another organization, role $role',
        );
      }
      // ...and the org-wide arm still accepts its OWN organization.
      final orgB = DashboardAnalyticsScope.coveredBy(
        _membership(organizationId: 'org-B', role: MembershipRole.orgOwner),
      );
      expect(orgB.covers(_orgBBranch), isTrue);
    });
  });

  // =========================================================================
  // F-1 — the selector's value/item invariant, in the widget
  // =========================================================================
  testWidgets('F-1: the scope selector never holds a value outside its item '
      'set after an organization change', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = _RecordingTransport();
    late ProviderContainer container;

    Widget app(MembershipContext membership, List<AuditBranchOption> options) =>
        ProviderScope(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(membership),
            dashboardAuthTransportProvider.overrideWithValue(transport),
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            auditFilterOptionsRepositoryProvider.overrideWithValue(
              _FixedOptions(options),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: restoflowLocalizationsDelegates,
                supportedLocales: kSupportedLocales,
                theme: restoflowBaseTheme(),
                home: DashboardShell(
                  membership: membership,
                  reportsTransport: transport,
                ),
              );
            },
          ),
        );

    await tester.pumpWidget(
      app(
        _membership(organizationId: 'org-A', role: MembershipRole.orgOwner),
        const [_orgABranch],
      ),
    );
    await tester.pumpAndSettle();

    container.read(selectedAnalyticsBranchProvider.notifier).state =
        _orgABranch;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String?>>(
            find.byKey(const Key('overview-scope-selector')),
          )
          .initialValue,
      'branch-A1',
    );

    // A whole new session as org B. The raw selection is still in memory; the
    // item list is org B's. Before the fix this asserted.
    await tester.pumpWidget(
      app(
        _membership(
          organizationId: 'org-B',
          role: MembershipRole.orgOwner,
          restaurantId: 'rest-B',
          branchId: 'branch-B1',
        ),
        const [_orgBBranch],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final field = tester.widget<DropdownButtonFormField<String?>>(
      find.byKey(const Key('overview-scope-selector')),
    );
    expect(field.initialValue, isNull, reason: 'broad, not a stale org A id');
  });

  // =========================================================================
  // F-2 — owner_active_orders payment domain
  // =========================================================================
  group('F-2: unsupported tender filters never reach owner_active_orders', () {
    RealActiveOrdersRepository repo(_RecordingTransport t) =>
        RealActiveOrdersRepository(
          null,
          scope: _membership(
            organizationId: 'org-1',
            role: MembershipRole.orgOwner,
          ),
          transport: t,
        );

    for (final filter in const [
      PaymentFilter.all,
      PaymentFilter.paid,
      PaymentFilter.unpaid,
      PaymentFilter.cash,
    ]) {
      test('${filter.name} is forwarded unchanged', () async {
        final t = _RecordingTransport();
        await repo(t).loadActive(ActiveOrdersQuery(payment: filter));
        expect(t.lastTo('owner_active_orders')!['p_payment'], filter.wire);
      });
    }

    for (final filter in const [
      PaymentFilter.card,
      PaymentFilter.bit,
      PaymentFilter.external,
    ]) {
      test('${filter.name} fails closed with ZERO transport calls', () async {
        final t = _RecordingTransport();
        await expectLater(
          repo(t).loadActive(ActiveOrdersQuery(payment: filter)),
          throwsA(isA<ActiveOrdersException>()),
        );
        expect(
          t.functions,
          isEmpty,
          reason: 'the guard runs BEFORE the RPC, so nothing is sent',
        );
      });
    }

    test('no unsupported token can be found in any recorded call', () async {
      final t = _RecordingTransport();
      for (final filter in PaymentFilter.values) {
        try {
          await repo(t).loadActive(ActiveOrdersQuery(payment: filter));
        } on ActiveOrdersException {
          // expected for the unsupported three
        }
      }
      for (final call in t.callsTo('owner_active_orders')) {
        expect(const [
          'card',
          'bit',
          'external',
        ], isNot(contains(call['p_payment'])));
      }
    });

    test('the ORDER HISTORY path still supports all three — the guard is '
        'local to the active board', () {
      expect(PaymentFilter.card.wire, 'card');
      expect(PaymentFilter.bit.wire, 'bit');
      expect(PaymentFilter.external.wire, 'external');
      expect(PaymentFilter.card.isMethod, isTrue);
      expect(PaymentFilter.paid.isMethod, isFalse);
    });
  });

  // =========================================================================
  // F-3 — the REAL shell: hoisted scope + KeyedSubtree + nested Orders scope
  // =========================================================================
  group('F-3: scope synchronisation through the real DashboardShell', () {
    Future<(_RecordingTransport, WidgetTester)> pumpShell(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = _RecordingTransport();
      const branchB = AuditBranchOption(
        organizationId: 'org-1',
        branchId: 'branch-2',
        restaurantId: 'rest-2',
        label: 'Rest Two · Harbor',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            auditFilterOptionsRepositoryProvider.overrideWithValue(
              const _FixedOptions([branchB]),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: DashboardShell(
              membership: _membership(
                organizationId: 'org-1',
                role: MembershipRole.orgOwner,
              ),
              reportsTransport: transport,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (transport, tester);
    }

    /// Picks Branch B through the ACTUAL selector UI.
    Future<void> selectBranchB(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest Two · Harbor').last);
      await tester.pumpAndSettle();
    }

    NavigationBar nav(WidgetTester tester) => tester.widget<NavigationBar>(
      find.byKey(const Key('dashboard-bottom-nav')),
    );

    testWidgets('selecting Branch B on Overview, then navigating to Orders '
        'through the real tab bar, scopes the history request', (tester) async {
      final (transport, _) = await pumpShell(tester);

      await selectBranchB(tester);

      // Navigate with the SHELL's own control — no provider is written here.
      nav(tester).onDestinationSelected!(
        DashboardDestination.orders.visibleIndex!,
      );
      await tester.pumpAndSettle();

      // Reach History through its own segmented control.
      await tester.tap(find.byKey(const Key('orders-tab-history')));
      await tester.pumpAndSettle();

      final history = transport.lastTo('owner_order_history');
      expect(history, isNotNull, reason: 'Orders history really loaded');
      expect(history!['p_organization_id'], 'org-1');
      expect(
        history['p_restaurant_id'],
        'rest-2',
        reason: 'the SELECTED branch restaurant, crossing the nested scope',
      );
      expect(history['p_branch_id'], 'branch-2');

      // ...and returning to Overview still shows the choice.
      nav(tester).onDestinationSelected!(
        DashboardDestination.overview.visibleIndex!,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String?>>(
              find.byKey(const Key('overview-scope-selector')),
            )
            .initialValue,
        'branch-2',
      );
    });

    testWidgets('one representative drill-down: the Cash payment row lands on '
        'Orders history with payment=cash AND Branch B', (tester) async {
      final (transport, _) = await pumpShell(tester);
      await selectBranchB(tester);

      // Scroll the payment card into view and tap its cash row.
      final cashRow = find.byKey(const Key('payment-mix-row-cash'));
      await tester.scrollUntilVisible(
        cashRow,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(cashRow);
      await tester.pumpAndSettle();

      final history = transport.lastTo('owner_order_history');
      expect(history, isNotNull);
      expect(history!['p_payment'], 'cash');
      expect(history['p_branch_id'], 'branch-2');
      expect(history['p_restaurant_id'], 'rest-2');
      // The F0 fresh-query contract still holds alongside the scope.
      expect(history['p_status'], isNull);
      expect(history['p_order_type'], isNull);
      expect(history['p_search'], isNull);
    });
  });
}
