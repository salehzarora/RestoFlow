import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/activity/activity_log_screen.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/order_completion_repository.dart';
import 'package:restoflow_dashboard/src/orders/active_orders_screen.dart';
import 'package:restoflow_dashboard/src/state/active_orders_providers.dart';
import 'package:restoflow_dashboard/src/state/analytics_branch_providers.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_completion_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX FINAL STATIC RE-REVIEW — the last six findings.
///
/// 1 & 2 — both operational surfaces built their dropdown items from the RAW
/// async option list. A technical enumeration failure emptied it while the
/// effective query, and the wire, still carried branch B. Activity therefore
/// held a value with no item and ASSERTED; the active board silently displayed
/// "All" while every request was filtered to B — the original UI/transport
/// contradiction, back through a different door.
///
/// 3 — demo mode has no membership and therefore no coverage, and the
/// reconciliation read that as "not covered". Every demo branch selection
/// projected to All, disabling demo branch filtering entirely.
///
/// 4 — `orderCompletionRepositoryProvider` watched the membership IDENTITY but
/// still declared the labelled provider in its `dependencies`. Riverpod
/// validates scoped reads against that list, so constructing the real
/// completion repository inside the Dashboard's scoped container asserted.
///
/// 5 — the refresh controller survives a widget remount, which was the point.
/// It did not survive the CONTAINER: sign-out disposes the shell while the
/// enumeration is parked, and the continuation then read a disposed `Ref`.
///
/// 6 — Activity's branch was reconciled but its ACTOR was not. A stale
/// employee-profile id from the previous organization stayed on the wire while
/// the control showed "All staff".

// ===========================================================================
// Harness
// ===========================================================================

class _FakeTransport implements SyncRpcTransport {
  /// Overrides `list_org_structure`; returning a Future parks the call.
  Object? Function()? orgStructure;

  /// Overrides `list_staff`.
  Object? Function()? staff;

  List<(String, String, String)> branches = const [
    ('rest-1', 'branch-1', 'Main'),
    ('rest-2', 'branch-2', 'Harbor'),
  ];

  List<(String, String)> actors = const [('ep-1', 'Amira'), ('ep-2', 'Sami')];

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
      'list_staff' =>
        (staff ??
            () => <String, dynamic>{
              'ok': true,
              'staff': [
                for (final (id, name) in actors)
                  {
                    'employee_profile_id': id,
                    'display_name': name,
                    'role': 'cashier',
                    'employment_status': 'active',
                  },
              ],
            })(),
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
}) => MembershipContext(
  id: id,
  organizationId: organizationId,
  organizationName: 'Org',
  restaurantId: restaurantId,
  restaurantName: 'Rest One',
  branchId: branchId,
  branchName: 'Main',
  role: role,
  status: 'active',
);

const _harbor = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-2',
  label: 'Rest Two · Harbor',
);
const _amira = AuditActorOption(employeeProfileId: 'ep-1', label: 'Amira');

final _realMode = RuntimeConfig.test(isDemoMode: false);
final _demoMode = RuntimeConfig.test(isDemoMode: true);

List<Override> _real(_FakeTransport t, MembershipContext m) => [
  dashboardMembershipProvider.overrideWithValue(m),
  dashboardAuthTransportProvider.overrideWithValue(t),
  runtimeConfigProvider.overrideWithValue(_realMode),
  activeOrdersPollIntervalProvider.overrideWithValue(null),
];

Future<void> _settle(ProviderContainer c) async {
  for (final f in [
    () => c.read(auditBranchOptionsProvider.future),
    () => c.read(analyticsBranchAnswerProvider.future),
    () => c.read(auditActorOptionsProvider.future),
    () => c.read(auditActorAnswerProvider.future),
  ]) {
    try {
      await f();
    } catch (_) {}
  }
}

Future<void> _pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Widget _app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: Scaffold(body: home),
  ),
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String? _dropdownValue(WidgetTester tester, String key) => tester
    .widget<DropdownButtonFormField<String?>>(find.byKey(Key(key)))
    .initialValue;

void main() {
  // =======================================================================
  // 1 — Activity: a failed enumeration must not assert
  // =======================================================================
  group(
    'FINDING 1: Activity survives an option failure with branch B live',
    () {
      testWidgets('retained B: no assertion, visible B, and an item for it', (
        tester,
      ) async {
        _size(tester);
        final t = _FakeTransport();
        late ProviderContainer c;
        await tester.pumpWidget(
          _app(
            _real(t, _membership()),
            Consumer(
              builder: (context, ref, _) {
                c = ProviderScope.containerOf(context);
                return const ActivityLogScreen();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
          branch: _harbor,
        );
        await tester.pumpAndSettle();
        expect(_dropdownValue(tester, 'activity-branch-filter'), 'branch-2');

        // The enumeration now fails. The last answer still has B, so the query
        // stays on B — and the control must still be able to render it.
        t.orgStructure = () => throw StateError('down');
        c.invalidate(auditBranchOptionsProvider);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'no dropdown assertion');
        expect(_dropdownValue(tester, 'activity-branch-filter'), 'branch-2');
        expect(c.read(effectiveAuditQueryProvider).branch, _harbor);
        expect(
          c
              .read(activityBranchItemsProvider)
              .where((o) => o.branchId == 'branch-2')
              .length,
          1,
          reason: 'exactly one item carries the value',
        );
      });

      testWidgets('after an omission, a later failure keeps BOTH at All', (
        tester,
      ) async {
        _size(tester);
        final t = _FakeTransport();
        late ProviderContainer c;
        await tester.pumpWidget(
          _app(
            _real(t, _membership()),
            Consumer(
              builder: (context, ref, _) {
                c = ProviderScope.containerOf(context);
                return const ActivityLogScreen();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
          branch: _harbor,
        );
        await tester.pumpAndSettle();

        t.branches = const [('rest-1', 'branch-1', 'Main')];
        c.invalidate(auditBranchOptionsProvider);
        await tester.pumpAndSettle();
        t.orgStructure = () => throw StateError('down');
        c.invalidate(auditBranchOptionsProvider);
        await tester.pumpAndSettle();

        expect(_dropdownValue(tester, 'activity-branch-filter'), isNull);
        expect(c.read(effectiveAuditQueryProvider).branch, isNull);
        expect(tester.takeException(), isNull);
      });
    },
  );

  // =======================================================================
  // 2 — Active Orders: the board shows what it queries
  // =======================================================================
  group('FINDING 2: Active Orders shows the branch it is querying', () {
    testWidgets('retained B through an option failure', (tester) async {
      _size(tester);
      final t = _FakeTransport();
      late ProviderContainer c;
      await tester.pumpWidget(
        _app(
          _real(t, _membership()),
          Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return const ActiveOrdersView();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.read(activeOrdersQueryProvider.notifier).state =
          const ActiveOrdersQuery(branch: _harbor);
      await tester.pumpAndSettle();
      expect(_dropdownValue(tester, 'active-orders-branch-filter'), 'branch-2');

      t.orgStructure = () => throw StateError('down');
      c.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();

      expect(
        _dropdownValue(tester, 'active-orders-branch-filter'),
        'branch-2',
        reason: 'the board must not claim All while filtering to B',
      );
      expect(c.read(effectiveActiveOrdersQueryProvider).branch, _harbor);
      expect(t.lastTo('owner_active_orders')!['p_branch_id'], 'branch-2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('after an omission, both go to All', (tester) async {
      _size(tester);
      final t = _FakeTransport();
      late ProviderContainer c;
      await tester.pumpWidget(
        _app(
          _real(t, _membership()),
          Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return const ActiveOrdersView();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.read(activeOrdersQueryProvider.notifier).state =
          const ActiveOrdersQuery(branch: _harbor);
      await tester.pumpAndSettle();

      t.branches = const [('rest-1', 'branch-1', 'Main')];
      c.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();

      expect(_dropdownValue(tester, 'active-orders-branch-filter'), isNull);
      expect(t.lastTo('owner_active_orders')!['p_branch_id'], isNull);
      expect(tester.takeException(), isNull);
    });
  });

  // =======================================================================
  // 3 — demo branch filtering
  // =======================================================================
  group('FINDING 3: demo mode filters by branch', () {
    ProviderContainer demo() {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(_demoMode),
          activeOrdersPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'a demo branch selection survives reconciliation on both surfaces',
      () async {
        final c = demo();
        await _settle(c);
        final options = c.read(analyticsBranchOptionsProvider);
        expect(options, isNotNull, reason: 'the demo list is a real answer');
        expect(options, isNotEmpty);
        final demoBranch = options!.first;

        c.read(auditLogQueryProvider.notifier).state = AuditQuery(
          branch: demoBranch,
        );
        c.read(activeOrdersQueryProvider.notifier).state = ActiveOrdersQuery(
          branch: demoBranch,
        );
        expect(c.read(effectiveAuditQueryProvider).branch, demoBranch);
        expect(c.read(effectiveActiveOrdersQueryProvider).branch, demoBranch);
      },
    );

    test('REAL mode with no coverage still fails closed', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(
        overrides: [
          // Real mode, NO membership: nothing is authorized.
          dashboardAuthTransportProvider.overrideWithValue(t),
          runtimeConfigProvider.overrideWithValue(_realMode),
          activeOrdersPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        branch: _harbor,
      );
      await _settle(c);
      expect(c.read(effectiveAuditQueryProvider).branch, isNull);
    });

    test('a demo branch cannot leak into a real membership', () async {
      // The override SET has to match across `updateOverrides`, so the demo
      // container starts with the same four and a null membership.
      final t0 = _FakeTransport();
      final c = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(null),
          dashboardAuthTransportProvider.overrideWithValue(t0),
          runtimeConfigProvider.overrideWithValue(_demoMode),
          activeOrdersPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);
      await _settle(c);
      final demoBranch = c.read(analyticsBranchOptionsProvider)!.first;
      c.read(auditLogQueryProvider.notifier).state = AuditQuery(
        branch: demoBranch,
      );
      expect(c.read(effectiveAuditQueryProvider).branch, demoBranch);

      final t = _FakeTransport();
      c.updateOverrides([
        dashboardMembershipProvider.overrideWithValue(_membership()),
        dashboardAuthTransportProvider.overrideWithValue(t),
        runtimeConfigProvider.overrideWithValue(_realMode),
        activeOrdersPollIntervalProvider.overrideWithValue(null),
      ]);
      expect(
        c.read(effectiveAuditQueryProvider).branch,
        isNull,
        reason: 'demo-org-1 is not this organization',
      );
    });
  });

  // =======================================================================
  // 4 — the completion provider constructs inside the scoped container
  // =======================================================================
  group('FINDING 4: order completion declares what it watches', () {
    testWidgets('the REAL repository constructs under the scoped Dashboard '
        'ProviderScope with no dependency assertion', (tester) async {
      final t = _FakeTransport();
      late OrderCompletionRepository repo;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [runtimeConfigProvider.overrideWithValue(_realMode)],
          // The shell's own shape: the scoped overrides live in a NESTED scope,
          // which is exactly where a mismatched `dependencies` list asserts.
          child: ProviderScope(
            overrides: [
              dashboardMembershipProvider.overrideWithValue(_membership()),
              dashboardAuthTransportProvider.overrideWithValue(t),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                repo = ref.watch(orderCompletionRepositoryProvider);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo, isA<RealOrderCompletionRepository>());
    });
  });

  // =======================================================================
  // 5 — a parked refresh must not outlive its container
  // =======================================================================
  group('FINDING 5: refresh abandons itself when the container goes', () {
    test('sign-out during a parked enumeration: no uncaught error, and no '
        'financial call afterwards', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _real(t, _membership()));
      await _settle(c);

      final gate = Completer<void>();
      t.orgStructure = () => gate.future.then(
        (_) => <String, dynamic>{
          'ok': true,
          'entity': 'org_structure',
          'restaurants': <dynamic>[],
        },
      );

      final refresh = c
          .read(dashboardRefreshControllerProvider.notifier)
          .refresh();
      await _pump();
      final from = t.params.length;

      // Sign-out: the whole shell container goes.
      c.dispose();
      gate.complete();
      await refresh; // must NOT throw
      await _pump();

      for (final call in t.params.skip(from)) {
        expect(call.keys, isNot(contains('p_range')));
      }
      expect(
        t.params.skip(from).length,
        lessThanOrEqualTo(1),
        reason: 'at most the parked enumeration itself completes',
      );
    });

    test('a fresh container refreshes normally afterwards', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _real(t, _membership()));
      addTearDown(c.dispose);
      await _settle(c);
      final before = t.countOf('owner_report_range');
      await c.read(dashboardRefreshControllerProvider.notifier).refresh();
      expect(t.countOf('owner_report_range'), greaterThan(before));
    });

    test('single-flight still holds', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _real(t, _membership()));
      addTearDown(c.dispose);
      await _settle(c);
      final gate = Completer<void>();
      t.orgStructure = () => gate.future.then(
        (_) => <String, dynamic>{
          'ok': true,
          'entity': 'org_structure',
          'restaurants': <dynamic>[],
        },
      );
      final before = t.countOf('list_org_structure');
      final notifier = c.read(dashboardRefreshControllerProvider.notifier);
      final a = notifier.refresh();
      final b = notifier.refresh();
      expect(t.countOf('list_org_structure'), before + 1);
      gate.complete();
      await Future.wait([a, b]);
      expect(c.read(dashboardRefreshControllerProvider), isFalse);
    });
  });

  // =======================================================================
  // 6 — the Activity actor
  // =======================================================================
  group('FINDING 6: a stale actor never reaches the wire', () {
    test('a membership change makes the actor inert, in UI and transport '
        'alike', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _real(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        actor: _amira,
      );
      await _settle(c);
      expect(c.read(effectiveAuditQueryProvider).actor, _amira);
      await c
          .read(auditLogRepositoryProvider)
          .loadEvents(c.read(effectiveAuditQueryProvider));
      expect(
        t.lastTo('owner_audit_events')!['p_actor_employee_profile_id'],
        'ep-1',
      );

      // A different organization, whose own staff list has not arrived yet.
      t.actors = const [('ep-9', 'Noor')];
      c.updateOverrides(
        _real(t, _membership(id: 'm-2', organizationId: 'org-2')),
      );
      expect(
        c.read(effectiveAuditQueryProvider).actor,
        isNull,
        reason:
            'an actor id carries no organization; without a list for THIS '
            'membership there is nothing to justify sending it',
      );

      final from = t.params.length;
      await c
          .read(auditLogRepositoryProvider)
          .loadEvents(c.read(effectiveAuditQueryProvider));
      for (final call in t.params.skip(from)) {
        expect(call.values, isNot(contains('ep-1')));
      }
      // The raw intent is untouched, and inert.
      expect(c.read(auditLogQueryProvider).actor, _amira);
    });

    test('a valid actor in the SAME context is stable, including across a '
        'transient reload', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _real(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        actor: _amira,
      );
      await _settle(c);
      expect(c.read(effectiveAuditQueryProvider).actor, _amira);

      c.invalidate(auditActorOptionsProvider);
      await _settle(c);
      expect(c.read(effectiveAuditQueryProvider).actor, _amira);
    });

    test('renaming the staff member does not change the query', () async {
      final t = _FakeTransport();
      final c = ProviderContainer(overrides: _real(t, _membership()));
      addTearDown(c.dispose);
      c.read(auditLogQueryProvider.notifier).state = const AuditQuery(
        actor: _amira,
      );
      await _settle(c);
      final before = c.read(effectiveAuditQueryProvider);

      t.actors = const [('ep-1', 'Amira Q.'), ('ep-2', 'Sami')];
      c.invalidate(auditActorOptionsProvider);
      await _settle(c);

      expect(
        c.read(effectiveAuditQueryProvider),
        before,
        reason: 'the id did not move, so the query did not either',
      );
    });
  });
}
