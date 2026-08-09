import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_drilldown.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-E2) — Orders scope synchronization.
///
/// CLIENT-E1 fixed the Overview. Orders HISTORY had the same defect and was left
/// behind: it read `p_restaurant_id` / `p_branch_id` straight off the resolved
/// membership, which `resolveTenantContext` has already pinned to the first
/// restaurant and first branch. So an org owner's "order history" was one
/// branch's orders, and after E1 the Overview and the list disagreed outright.
///
/// The active board and the audit log already resolved coverage correctly, so
/// they are deliberately untouched — see the "left independent" group.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport([this._handler]);

  final Object? Function(String function, Map<String, dynamic> params)?
  _handler;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  Map<String, dynamic>? get lastParams => params.isEmpty ? null : params.last;
  int get callCount => functions.length;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    functions.add(function);
    params.add(args);
    if (_handler != null) return _handler(function, args);
    return <String, dynamic>{
      'ok': true,
      'currency_code': 'ILS',
      'orders': <dynamic>[],
      'has_more': false,
      'next_cursor': null,
    };
  }
}

MembershipContext _membership(
  MembershipRole role, {
  String organizationId = 'org-1',
}) => MembershipContext(
  id: 'm-1',
  organizationId: organizationId,
  organizationName: 'Org',
  // Exactly what resolveTenantContext produces: the FIRST restaurant and the
  // FIRST branch, pinned onto a membership that may cover far more.
  restaurantId: 'rest-1',
  restaurantName: 'Rest One',
  branchId: 'branch-1',
  branchName: 'Main',
  role: role,
  status: 'active',
);

const _branchInRest1 = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  label: 'Rest One · Main',
);
const _otherBranchInRest1 = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-1',
  label: 'Rest One · Harbor',
);
const _branchInRest2 = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-9',
  restaurantId: 'rest-2',
  label: 'Rest Two · Airport',
);

/// CODEX F-1B-3 — the branches that actually EXIST in these fixtures.
///
/// A successful option list is now authoritative about existence: a selection
/// it omits stops applying, so the reports fall back to the authorized parent
/// scope instead of querying a branch that is no longer there. A test asserting
/// that a selection reaches the wire must therefore say the branch exists —
/// otherwise it is asserting the very defect F-1B-3 fixes.
const _liveOptions = <AuditBranchOption>[
  _branchInRest1,
  _otherBranchInRest1,
  _branchInRest2,
];

/// Invokes the history RPC through the repository and returns the params sent.
Future<Map<String, dynamic>> _historyParams({
  required MembershipRole role,
  AuditBranchOption? selected,
  OrderHistoryQuery query = const OrderHistoryQuery(),
}) async {
  final transport = _FakeTransport();
  final container = ProviderContainer(
    overrides: [
      dashboardMembershipProvider.overrideWithValue(_membership(role)),
      dashboardAuthTransportProvider.overrideWithValue(transport),
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      auditBranchOptionsProvider.overrideWith((ref) async => _liveOptions),
    ],
  );
  addTearDown(container.dispose);
  container.read(selectedAnalyticsBranchProvider.notifier).state = selected;
  await container.read(orderHistoryRepositoryProvider).loadHistory(query);
  return transport.lastParams!;
}

void main() {
  group('Orders history follows the selected scope', () {
    test('A. an ORG-wide scope queries the organization — no restaurant, no '
        'branch, and above all not the pinned first branch', () async {
      final params = await _historyParams(role: MembershipRole.orgOwner);

      expect(params['p_organization_id'], 'org-1');
      expect(params['p_restaurant_id'], isNull);
      expect(params['p_branch_id'], isNull);
      expect(
        params['p_branch_id'],
        isNot('branch-1'),
        reason: 'the resolver pinned branch-1; it is not the owner\'s scope',
      );
    });

    test(
      'B. a RESTAURANT-wide scope queries that restaurant, all branches',
      () async {
        final params = await _historyParams(
          role: MembershipRole.restaurantOwner,
        );

        expect(params['p_organization_id'], 'org-1');
        expect(params['p_restaurant_id'], 'rest-1');
        expect(params['p_branch_id'], isNull);
      },
    );

    test(
      'C. a SINGLE-BRANCH selection carries both ids, from the option',
      () async {
        final params = await _historyParams(
          role: MembershipRole.orgOwner,
          selected: _branchInRest2,
        );

        expect(params['p_organization_id'], 'org-1');
        // From the OPTION: an org owner picking a branch of their second
        // restaurant must send THAT restaurant, not the pinned first one.
        expect(params['p_restaurant_id'], 'rest-2');
        expect(params['p_branch_id'], 'branch-9');
      },
    );

    test('a branch-FIXED membership queries its own branch and cannot escape '
        'it, even with a foreign selection set', () async {
      final params = await _historyParams(
        role: MembershipRole.manager,
        selected: _branchInRest2,
      );

      expect(params['p_restaurant_id'], 'rest-1');
      expect(params['p_branch_id'], 'branch-1');
    });

    test(
      'a restaurant owner cannot be pushed into a sibling restaurant',
      () async {
        final params = await _historyParams(
          role: MembershipRole.restaurantOwner,
          selected: _branchInRest2,
        );

        expect(params['p_restaurant_id'], 'rest-1');
        expect(params['p_branch_id'], isNull);
      },
    );

    test('D. business filters still thread through untouched alongside the '
        'scope', () async {
      final params = await _historyParams(
        role: MembershipRole.orgOwner,
        selected: _otherBranchInRest1,
        query: const OrderHistoryQuery(
          range: OrderHistoryRange.last7,
          search: 'Layla',
          status: OrderStatusFilter.completed,
          orderType: OrderTypeFilter.dineIn,
          payment: PaymentFilter.card,
        ),
      );

      expect(params['p_branch_id'], 'branch-2');
      expect(params['p_restaurant_id'], 'rest-1');
      expect(params['p_range'], 'last7');
      expect(params['p_search'], 'Layla');
      expect(params['p_status'], 'completed');
      expect(params['p_order_type'], 'dine_in');
      expect(params['p_payment'], 'card');
      expect(params['p_limit'], 25);
      expect(params['p_cursor'], isNull);
    });

    test('the DETAIL lookup is scoped exactly like the list that produced the '
        'row', () async {
      final transport = _FakeTransport(
        (_, _) => <String, dynamic>{
          'ok': true,
          'currency_code': 'ILS',
          'order': <String, dynamic>{
            'order_id': 'o1',
            'status': 'completed',
            'order_type': 'dine_in',
          },
        },
      );
      final repo = RealOrderHistoryRepository(
        null,
        scope: _membership(MembershipRole.orgOwner),
        transport: transport,
        analyticsScope: DashboardAnalyticsScope.branch(
          organizationId: 'org-1',
          option: _branchInRest2,
        ),
      );

      try {
        await repo.loadDetail('o1');
      } catch (_) {
        // The mapped payload is deliberately minimal; only the params matter.
      }

      expect(transport.lastParams!['p_restaurant_id'], 'rest-2');
      expect(transport.lastParams!['p_branch_id'], 'branch-9');
    });

    test('an UNWIRED analytics scope still uses COVERAGE, never the pinned '
        'ids — no first-branch narrowing can come back', () async {
      final transport = _FakeTransport();
      final repo = RealOrderHistoryRepository(
        null,
        scope: _membership(MembershipRole.orgOwner),
        transport: transport,
        // analyticsScope deliberately omitted.
      );
      await repo.loadHistory(const OrderHistoryQuery());

      expect(transport.lastParams!['p_restaurant_id'], isNull);
      expect(transport.lastParams!['p_branch_id'], isNull);
    });
  });

  group('drill-down keeps its business filters and the scope', () {
    /// Runs a drill-down against a live container and returns the resulting
    /// history request params.
    Future<Map<String, dynamic>> run(
      DashboardDrillDown drillDown, {
      AuditBranchOption? selected = _otherBranchInRest1,
    }) async {
      final transport = _FakeTransport();
      late WidgetRef captured;
      final tester = _binding;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(
              _membership(MembershipRole.orgOwner),
            ),
            dashboardAuthTransportProvider.overrideWithValue(transport),
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            auditBranchOptionsProvider.overrideWith(
              (ref) async => _liveOptions,
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );
      container.read(selectedAnalyticsBranchProvider.notifier).state = selected;
      // A stale, conflicting filter set the drill-down must clear.
      container
          .read(orderHistoryQueryProvider.notifier)
          .state = const OrderHistoryQuery(
        status: OrderStatusFilter.voided,
        search: 'leftover',
        payment: PaymentFilter.paid,
        orderType: OrderTypeFilter.takeaway,
      );

      runDashboardDrillDown(
        ref: captured,
        drillDown: drillDown,
        navigate: (_) {},
      );
      await tester.pump();

      await container
          .read(orderHistoryRepositoryProvider)
          .loadHistory(container.read(orderHistoryQueryProvider));
      return transport.lastParams!;
    }

    testWidgets('unpaid keeps branch B', (tester) async {
      _binding = tester;
      final p = await run(const OrdersHistoryDrillDown.unpaid());
      expect(p['p_payment'], 'unpaid');
      expect(p['p_branch_id'], 'branch-2');
      // ...and the stale filters are gone, exactly as F0 requires.
      expect(p['p_status'], isNull);
      expect(p['p_order_type'], isNull);
      expect(p['p_search'], isNull);
    });

    testWidgets('cash keeps branch B', (tester) async {
      _binding = tester;
      final p = await run(const OrdersHistoryDrillDown.cash());
      expect(p['p_payment'], 'cash');
      expect(p['p_branch_id'], 'branch-2');
    });

    testWidgets('card / bit / external keep branch B', (tester) async {
      _binding = tester;
      for (final (drill, wire) in const [
        (OrdersHistoryDrillDown.card(), 'card'),
        (OrdersHistoryDrillDown.bit(), 'bit'),
        (OrdersHistoryDrillDown.external(), 'external'),
      ]) {
        final p = await run(drill);
        expect(p['p_payment'], wire);
        expect(p['p_branch_id'], 'branch-2');
      }
    });

    testWidgets('dine_in and takeaway keep branch B', (tester) async {
      _binding = tester;
      for (final (drill, wire) in const [
        (OrdersHistoryDrillDown.dineIn(), 'dine_in'),
        (OrdersHistoryDrillDown.takeaway(), 'takeaway'),
      ]) {
        final p = await run(drill);
        expect(p['p_order_type'], wire);
        expect(p['p_branch_id'], 'branch-2');
        expect(p['p_payment'], isNull);
      }
    });

    testWidgets('voided keeps branch B', (tester) async {
      _binding = tester;
      final p = await run(const OrdersHistoryDrillDown.voided());
      expect(p['p_status'], 'voided');
      expect(p['p_branch_id'], 'branch-2');
    });

    testWidgets('resetting the business filters does NOT reset the scope', (
      tester,
    ) async {
      _binding = tester;
      final p = await run(const OrdersHistoryDrillDown.unpaid());
      expect(
        p['p_branch_id'],
        'branch-2',
        reason: 'the fresh OrderHistoryQuery carries no scope to erase',
      );
    });

    testWidgets('the drill-down model still carries NO scope fields', (
      tester,
    ) async {
      // Structural: the payload has no field capable of expressing tenancy, so
      // a drill-down cannot widen what its originator could see.
      const drill = OrdersHistoryDrillDown.cash();
      expect(drill.payment, PaymentFilter.cash);
      expect(drill.status, OrderStatusFilter.all);
      expect(drill.orderType, OrderTypeFilter.all);
      expect(drill.destination, DashboardDestination.orders);
    });
  });

  group('request identity and pagination', () {
    test('a scope change rebuilds the repository, so a cursor from one scope '
        'can never be replayed under another', () async {
      final transport = _FakeTransport();
      final container = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(
            _membership(MembershipRole.orgOwner),
          ),
          dashboardAuthTransportProvider.overrideWithValue(transport),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          auditBranchOptionsProvider.overrideWith((ref) async => _liveOptions),
        ],
      );
      addTearDown(container.dispose);

      final broad = container.read(orderHistoryRepositoryProvider);
      container.read(selectedAnalyticsBranchProvider.notifier).state =
          _branchInRest1;
      final branchA = container.read(orderHistoryRepositoryProvider);
      container.read(selectedAnalyticsBranchProvider.notifier).state =
          _otherBranchInRest1;
      final branchB = container.read(orderHistoryRepositoryProvider);

      expect(identical(broad, branchA), isFalse);
      expect(identical(branchA, branchB), isFalse);
    });

    test('an UNCHANGED scope does not rebuild the repository — no duplicate '
        'fetch from a rebuild', () async {
      final transport = _FakeTransport();
      final container = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(
            _membership(MembershipRole.orgOwner),
          ),
          dashboardAuthTransportProvider.overrideWithValue(transport),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          auditBranchOptionsProvider.overrideWith((ref) async => _liveOptions),
        ],
      );
      addTearDown(container.dispose);

      final first = container.read(orderHistoryRepositoryProvider);
      // Setting the SAME value (null -> null) must not churn the graph.
      container.read(selectedAnalyticsBranchProvider.notifier).state = null;
      expect(
        identical(first, container.read(orderHistoryRepositoryProvider)),
        isTrue,
      );
    });

    test(
      'each scope issues exactly one request for its own first page',
      () async {
        final transport = _FakeTransport();
        final container = ProviderContainer(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(
              _membership(MembershipRole.orgOwner),
            ),
            dashboardAuthTransportProvider.overrideWithValue(transport),
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            auditBranchOptionsProvider.overrideWith(
              (ref) async => _liveOptions,
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(orderHistoryRepositoryProvider)
            .loadHistory(const OrderHistoryQuery());
        expect(transport.callCount, 1);
        expect(transport.lastParams!['p_branch_id'], isNull);

        container.read(selectedAnalyticsBranchProvider.notifier).state =
            _branchInRest1;
        await container
            .read(orderHistoryRepositoryProvider)
            .loadHistory(const OrderHistoryQuery());
        expect(transport.callCount, 2);
        expect(transport.lastParams!['p_branch_id'], 'branch-1');

        container.read(selectedAnalyticsBranchProvider.notifier).state =
            _otherBranchInRest1;
        await container
            .read(orderHistoryRepositoryProvider)
            .loadHistory(const OrderHistoryQuery());
        expect(transport.callCount, 3);
        expect(transport.lastParams!['p_branch_id'], 'branch-2');
      },
    );

    test('visiting Orders issues NO owner_report_range or owner_sales_series '
        'request', () async {
      final transport = _FakeTransport();
      final container = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(
            _membership(MembershipRole.orgOwner),
          ),
          dashboardAuthTransportProvider.overrideWithValue(transport),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          auditBranchOptionsProvider.overrideWith((ref) async => _liveOptions),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(orderHistoryRepositoryProvider)
          .loadHistory(const OrderHistoryQuery());

      expect(transport.functions, ['owner_order_history']);
      expect(transport.functions, isNot(contains('owner_report_range')));
      expect(transport.functions, isNot(contains('owner_sales_series')));
    });
  });

  group('membership change fails closed before any request', () {
    test('a selection the NEW membership cannot read is dropped from the '
        'request, not merely from the UI', () async {
      // An org owner picked a branch of their second restaurant. The same
      // selection under a branch-scoped membership must never reach the wire.
      final params = await _historyParams(
        role: MembershipRole.manager,
        selected: _branchInRest2,
      );
      expect(params['p_branch_id'], 'branch-1');
      expect(params['p_restaurant_id'], 'rest-1');
      expect(params['p_branch_id'], isNot('branch-9'));
      expect(params['p_restaurant_id'], isNot('rest-2'));
    });

    test(
      'a different organization is never queried under the old one',
      () async {
        final transport = _FakeTransport();
        final container = ProviderContainer(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(
              _membership(MembershipRole.orgOwner, organizationId: 'org-2'),
            ),
            dashboardAuthTransportProvider.overrideWithValue(transport),
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            auditBranchOptionsProvider.overrideWith(
              (ref) async => _liveOptions,
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(selectedAnalyticsBranchProvider.notifier).state =
            _branchInRest1;

        await container
            .read(orderHistoryRepositoryProvider)
            .loadHistory(const OrderHistoryQuery());

        expect(transport.lastParams!['p_organization_id'], 'org-2');
      },
    );
  });

  group('surfaces deliberately left independent', () {
    test('the active board and the audit log already resolve COVERAGE '
        'themselves, so an E1 selection does not silently widen them', () {
      // Both repositories call auditCoveredScope(membership) and apply their
      // OWN visible branch filter on top. This test pins the property that
      // matters: an analytics selection is not secretly readable as their
      // scope, because their query type is the one their own selector writes.
      const activityQuery = AuditQuery();
      expect(activityQuery.branch, isNull);

      // A restaurant-wide analytics scope has no equivalent in a filter whose
      // only states are "one branch" and "null". Mapping it onto null would
      // claim org-wide, which is strictly broader than the owner selected.
      final restaurantWide = DashboardAnalyticsScope.coveredBy(
        _membership(MembershipRole.restaurantOwner),
      );
      expect(restaurantWide.kind, DashboardAnalyticsScopeKind.restaurantWide);
      expect(restaurantWide.branchId, isNull);
      expect(
        restaurantWide.restaurantId,
        isNotNull,
        reason: 'a single nullable branchId cannot carry this scope',
      );
    });
  });
}

/// The active tester, set by each widget test before calling the shared runner.
late WidgetTester _binding;
