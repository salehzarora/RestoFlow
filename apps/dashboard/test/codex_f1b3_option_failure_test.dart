import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX F-1B-3 FOLLOW-UP — a FAILED branch enumeration is not a removal.
///
/// F-1B-3 made a successful branch-option list authoritative: a selection it
/// omits stops applying, and the reports fall back to the authorized parent
/// scope. That is right, and it is only right if "successful" really means
/// successful.
///
/// `RealAuditFilterOptionsRepository.loadBranches` was written for the Activity
/// filter, where an unavailable list just means a dropdown with fewer entries,
/// so it fails SOFT: no transport, a thrown transport error, `ok:false`, or a
/// malformed envelope all returned `const []`. Once the analytics scope started
/// reading that list, those four became indistinguishable from "the
/// organization genuinely has no selectable branches" — so a network blip or a
/// denied `list_org_structure` would silently widen an owner's financial scope
/// from one branch to the whole organization, and every figure on the page
/// would change meaning without a word on screen.
///
/// The distinction now lives where the fact is known: the repository reports
/// failure as failure, and only a real answer comes back as a list. Both older
/// surfaces already fail soft AT THE POINT OF USE (`asData ?? []`), so they are
/// unchanged.
///
/// These tests drive the REAL repository through the REAL provider chain over a
/// fake transport. Modelling failure by overriding the provider with an
/// AsyncError would assume the very thing that was wrong.

// ===========================================================================
// Harness
// ===========================================================================

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.orgStructure);

  /// What `list_org_structure` does: return a payload, or throw.
  final Object? Function() orgStructure;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  int countOf(String fn) => functions.where((f) => f == fn).length;

  Map<String, dynamic>? lastTo(String fn) {
    for (var i = functions.length - 1; i >= 0; i--) {
      if (functions[i] == fn) return params[i];
    }
    return null;
  }

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    functions.add(function);
    params.add(args);
    return switch (function) {
      'list_org_structure' => orgStructure(),
      'list_staff' => <String, dynamic>{'ok': true, 'staff': <dynamic>[]},
      'owner_sales_series' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'range': 'last7',
        'buckets': <dynamic>[],
      },
      'owner_order_history' => <String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'orders': <dynamic>[],
        'has_more': false,
        'next_cursor': null,
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
}) => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
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

/// A well-formed `list_org_structure` payload containing [_harbor].
Map<String, dynamic> _structureWithHarbor() => <String, dynamic>{
  'ok': true,
  'entity': 'org_structure',
  'restaurants': <Map<String, dynamic>>[
    {
      'id': 'rest-1',
      'name': 'Rest One',
      'branches': [
        {'id': 'branch-1', 'name': 'Main'},
      ],
    },
    {
      'id': 'rest-2',
      'name': 'Rest Two',
      'branches': [
        {'id': 'branch-2', 'name': 'Harbor'},
      ],
    },
  ],
};

/// The same payload with branch-2 genuinely gone — an authoritative removal.
Map<String, dynamic> _structureWithoutHarbor() => <String, dynamic>{
  'ok': true,
  'entity': 'org_structure',
  'restaurants': <Map<String, dynamic>>[
    {
      'id': 'rest-1',
      'name': 'Rest One',
      'branches': [
        {'id': 'branch-1', 'name': 'Main'},
      ],
    },
  ],
};

ProviderContainer _container({
  required _FakeTransport? transport,
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

/// Settles the branch-option load WITHOUT letting its failure escape, so the
/// assertions below are about the resulting scope rather than about the throw.
Future<AsyncValue<List<AuditBranchOption>>> _settleOptions(
  ProviderContainer c,
) async {
  try {
    await c.read(auditBranchOptionsProvider.future);
  } catch (_) {
    // Expected for the failure outcomes; the provider holds the error.
  }
  return c.read(auditBranchOptionsProvider);
}

void main() {
  // =======================================================================
  // 1. What the REAL repository actually emits, per outcome
  // =======================================================================
  group('real branch-option failure semantics', () {
    test('A. a successful response with branches -> data', () async {
      final c = _container(transport: _FakeTransport(_structureWithHarbor));
      final state = await _settleOptions(c);
      expect(state.hasValue, isTrue);
      expect(state.requireValue.map((b) => b.branchId), [
        'branch-1',
        'branch-2',
      ]);
    });

    test('B. a successful response with NO branches -> data, empty', () async {
      final c = _container(
        transport: _FakeTransport(
          () => <String, dynamic>{'ok': true, 'restaurants': <dynamic>[]},
        ),
      );
      final state = await _settleOptions(c);
      expect(state.hasValue, isTrue);
      expect(state.requireValue, isEmpty);
      expect(state.hasError, isFalse);
    });

    test('C. a transport failure -> error, NOT an empty answer', () async {
      final c = _container(
        transport: _FakeTransport(() => throw StateError('socket closed')),
      );
      final state = await _settleOptions(c);
      expect(state.hasError, isTrue);
      expect(state.hasValue, isFalse);
    });

    test(
      'D. a REJECTED rpc -> error, never softened into "no branches"',
      () async {
        final c = _container(
          transport: _FakeTransport(
            () => <String, dynamic>{'ok': false, 'error': 'permission_denied'},
          ),
        );
        final state = await _settleOptions(c);
        expect(state.hasError, isTrue);
        expect(state.hasValue, isFalse);
      },
    );

    test('E. a malformed ENVELOPE -> error', () async {
      for (final payload in <Object?>[
        'not a map',
        null,
        <String, dynamic>{'ok': true, 'restaurants': 'not a list'},
      ]) {
        final c = _container(transport: _FakeTransport(() => payload));
        final state = await _settleOptions(c);
        expect(state.hasError, isTrue, reason: 'payload: $payload');
      }
    });

    test(
      'E2. a malformed ROW among valid ones is skipped, not fatal',
      () async {
        final c = _container(
          transport: _FakeTransport(
            () => <String, dynamic>{
              'ok': true,
              'restaurants': <dynamic>[
                'garbage',
                {
                  'id': 'rest-2',
                  'name': 'Rest Two',
                  'branches': [
                    {'name': 'no id at all'},
                    {'id': 'branch-2', 'name': 'Harbor'},
                  ],
                },
              ],
            },
          ),
        );
        final state = await _settleOptions(c);
        expect(state.hasValue, isTrue);
        expect(state.requireValue.map((b) => b.branchId), ['branch-2']);
      },
    );

    test('F. NOT WIRED (no transport) -> error, not an empty answer', () async {
      final c = _container(transport: null);
      final state = await _settleOptions(c);
      expect(state.hasError, isTrue);
      expect(state.hasValue, isFalse);
    });

    test('G. demo mode -> the demo list, unchanged', () async {
      final c = ProviderContainer(
        overrides: [
          dashboardMembershipProvider.overrideWithValue(_membership()),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
      );
      addTearDown(c.dispose);
      final state = await _settleOptions(c);
      expect(state.hasValue, isTrue);
      expect(state.requireValue, isNotEmpty);
    });
  });

  // =======================================================================
  // 2. The consequence that matters: a failure must not move the money
  // =======================================================================
  group('a failed enumeration never widens the financial scope', () {
    /// Selects branch-2, settles the option load, and reports where the
    /// analytics scope, both family keys and the history request ended up.
    Future<
      ({
        String? restaurantId,
        String? branchId,
        String? keyRestaurant,
        String? keyBranch,
        String? seriesRestaurant,
        String? seriesBranch,
        Map<String, dynamic>? history,
      })
    >
    run(_FakeTransport? transport, {MembershipContext? membership}) async {
      final c = _container(transport: transport, membership: membership);
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harbor;
      c.read(reportRangeProvider.notifier).state = ReportRange.last7;
      await _settleOptions(c);

      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      final key = c.read(currentOwnerReportKeyProvider);
      final series = c.read(currentOwnerSalesSeriesKeyProvider)!;
      Map<String, dynamic>? history;
      if (transport != null) {
        await c
            .read(orderHistoryRepositoryProvider)
            .loadHistory(const OrderHistoryQuery());
        history = transport.lastTo('owner_order_history');
      }
      return (
        restaurantId: scope.restaurantId,
        branchId: scope.branchId,
        keyRestaurant: key.restaurantId,
        keyBranch: key.branchId,
        seriesRestaurant: series.restaurantId,
        seriesBranch: series.branchId,
        history: history,
      );
    }

    void expectBranchB(dynamic r, {required String because}) {
      expect(r.restaurantId, 'rest-2', reason: because);
      expect(r.branchId, 'branch-2', reason: because);
      expect(r.keyRestaurant, 'rest-2', reason: because);
      expect(r.keyBranch, 'branch-2', reason: because);
      expect(r.seriesRestaurant, 'rest-2', reason: because);
      expect(r.seriesBranch, 'branch-2', reason: because);
      if (r.history != null) {
        expect(r.history!['p_restaurant_id'], 'rest-2', reason: because);
        expect(r.history!['p_branch_id'], 'branch-2', reason: because);
      }
    }

    test('A. a TRANSPORT failure keeps branch B everywhere', () async {
      final r = await run(
        _FakeTransport(() => throw StateError('socket closed')),
      );
      expectBranchB(r, because: 'a dropped connection is not a deleted branch');
    });

    test('B. a REJECTED enumeration keeps branch B everywhere', () async {
      final r = await run(
        _FakeTransport(
          () => <String, dynamic>{'ok': false, 'error': 'permission_denied'},
        ),
      );
      expectBranchB(
        r,
        because: 'a denied list_org_structure must not re-scope the money',
      );
    });

    test('C. a MALFORMED payload keeps branch B everywhere', () async {
      final r = await run(_FakeTransport(() => 'not a map'));
      expectBranchB(
        r,
        because: 'a decode failure is not an authoritative empty',
      );
    });

    test('D. NOT WIRED keeps branch B', () async {
      final r = await run(null);
      expectBranchB(r, because: 'an unwired transport knows nothing');
    });

    test(
      'E. a SUCCESSFUL empty list DOES move to the authorized parent',
      () async {
        final r = await run(
          _FakeTransport(
            () => <String, dynamic>{'ok': true, 'restaurants': <dynamic>[]},
          ),
        );
        expect(r.restaurantId, isNull);
        expect(r.branchId, isNull);
        expect(r.keyBranch, isNull);
        expect(r.seriesBranch, isNull);
        expect(r.history!['p_branch_id'], isNull);
        // ...and not to the pinned first branch either.
        expect(r.history!['p_branch_id'], isNot('branch-1'));
      },
    );

    test(
      'F. a SUCCESSFUL list omitting B moves to the authorized parent',
      () async {
        final r = await run(_FakeTransport(_structureWithoutHarbor));
        expect(r.restaurantId, isNull);
        expect(r.branchId, isNull);
        expect(r.keyBranch, isNull);
      },
    );

    test('G. a SUCCESSFUL list containing B keeps B', () async {
      final r = await run(_FakeTransport(_structureWithHarbor));
      expectBranchB(r, because: 'the branch is really there');
    });

    test('a RESTAURANT-wide owner keeps its restaurant on failure, and falls '
        'back only to that restaurant on a real removal', () async {
      final membership = _membership(
        role: MembershipRole.restaurantOwner,
        restaurantId: 'rest-2',
      );
      final failed = await run(
        _FakeTransport(() => throw StateError('down')),
        membership: membership,
      );
      expectBranchB(failed, because: 'a failure changes nothing');

      final removed = await run(
        _FakeTransport(
          () => <String, dynamic>{'ok': true, 'restaurants': <dynamic>[]},
        ),
        membership: membership,
      );
      expect(removed.restaurantId, 'rest-2');
      expect(removed.branchId, isNull);
    });

    test('a BRANCH-FIXED membership is untouched by either', () async {
      for (final structure in <Object? Function()>[
        () => throw StateError('down'),
        () => <String, dynamic>{'ok': true, 'restaurants': <dynamic>[]},
      ]) {
        final c = _container(
          transport: _FakeTransport(structure),
          membership: _membership(role: MembershipRole.manager),
        );
        await _settleOptions(c);
        final scope = c.read(dashboardAnalyticsScopeProvider)!;
        expect(scope.kind, DashboardAnalyticsScopeKind.singleBranch);
        expect(scope.restaurantId, 'rest-1');
        expect(scope.branchId, 'branch-1');
      }
    });
  });

  // =======================================================================
  // 3. The control stays safe and honest while the list is unavailable
  // =======================================================================
  group('selector safety on a failed enumeration', () {
    testWidgets('the branch being queried is shown, with an item, and no '
        'exception', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = _FakeTransport(() => throw StateError('down'));
      late ProviderContainer c;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(_membership()),
            dashboardAuthTransportProvider.overrideWithValue(transport),
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: restoflowLocalizationsDelegates,
                supportedLocales: kSupportedLocales,
                theme: restoflowBaseTheme(),
                home: const DashboardHomeScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harbor;
      await tester.pumpAndSettle();

      final value = tester
          .widget<DropdownButtonFormField<String?>>(
            find.byKey(const Key('overview-scope-selector')),
          )
          .initialValue;
      expect(value, 'branch-2');
      expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-2');
      expect(tester.takeException(), isNull);

      // The value really does have an item behind it.
      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();
      final values = tester
          .widgetList<DropdownMenuItem<String?>>(
            find.byType(DropdownMenuItem<String?>),
          )
          .map((i) => i.value)
          .toSet();
      expect(values, {null, 'branch-2'});
      expect(tester.takeException(), isNull);
    });
  });

  // =======================================================================
  // 4. A failure must not become a request storm
  // =======================================================================
  group('no refetch storm on failure', () {
    testWidgets('one failed enumeration stays one request across rebuilds', (
      tester,
    ) async {
      final transport = _FakeTransport(() => throw StateError('down'));
      late ProviderContainer c;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(_membership()),
            dashboardAuthTransportProvider.overrideWithValue(transport),
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: restoflowLocalizationsDelegates,
                supportedLocales: kSupportedLocales,
                theme: restoflowBaseTheme(),
                home: const DashboardHomeScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harbor;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        transport.countOf('list_org_structure'),
        1,
        reason: 'an errored FutureProvider holds its error; it does not retry',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // =======================================================================
  // 5. The two older surfaces still fail soft AT THE POINT OF USE
  // =======================================================================
  group('Activity / Active Orders are unchanged', () {
    test(
      'a failed enumeration reads as an empty option list for them',
      () async {
        final c = _container(
          transport: _FakeTransport(() => throw StateError('down')),
        );
        await _settleOptions(c);
        final async = c.read(auditBranchOptionsProvider);
        // Exactly the two expressions those screens use.
        expect(async.asData?.value ?? const <AuditBranchOption>[], isEmpty);
        expect(
          async.maybeWhen(
            data: (b) => b,
            orElse: () => const <AuditBranchOption>[],
          ),
          isEmpty,
        );
      },
    );
  });
}
