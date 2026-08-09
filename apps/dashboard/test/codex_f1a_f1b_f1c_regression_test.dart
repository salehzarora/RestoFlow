import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/owner_report_query_key.dart';
import 'package:restoflow_dashboard/src/analytics/owner_sales_series_query_key.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX RE-REVIEW — regressions for F-1A, F-1B and F-1C.
///
/// F-1A (P1): the sanitised scope reached the family KEYS but not the RPC. Both
/// family loaders passed only the range, and both real repositories read
/// restaurant/branch off the resolved membership — which resolveTenantContext
/// has already pinned to the FIRST of each. So a broad owner's analytics stayed
/// silently narrowed no matter what the selector said, and branch A's data could
/// be cached under a branch B key. The E1 tests asserted only the keys, which is
/// exactly how this survived.
///
/// F-1B (P2): the selector's value was resolved against COVERAGE, not against
/// the current item set. Returning to an organization makes its branch
/// coverage-valid immediately while the option list is still loading, so the
/// field could hold a value with no matching item.
///
/// F-1C (P2): single-branch coverage compared the branch id but not the
/// restaurant id.

class _RecordingTransport implements SyncRpcTransport {
  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

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

class _FixedOptions implements AuditFilterOptionsRepository {
  const _FixedOptions(this.branches, {this.delay, this.fail = false});

  final List<AuditBranchOption> branches;
  final Duration? delay;
  final bool fail;

  @override
  Future<List<AuditBranchOption>> loadBranches() async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (fail) throw StateError('branch options unavailable');
    return branches;
  }

  @override
  Future<List<AuditActorOption>> loadActors() async => const [];
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
  // Exactly the pin resolveTenantContext applies.
  restaurantId: restaurantId,
  restaurantName: 'Rest One',
  branchId: branchId,
  branchName: 'Main',
  role: role,
  status: 'active',
);

const _branchB = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-2',
  label: 'Rest Two · Harbor',
);
const _orgAOption = AuditBranchOption(
  organizationId: 'org-A',
  branchId: 'branch-A1',
  restaurantId: 'rest-A',
  label: 'Org A · Harbor',
);

ProviderContainer _container({
  MembershipContext? membership,
  required _RecordingTransport transport,
  AuditFilterOptionsRepository? options,
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
      // CODEX F-1B-3 — a successful option list is now authoritative about
      // which branches EXIST, and one that omits the selection retires it. The
      // default therefore says branch B is real, so these F-1A transport cases
      // exercise the scope path they are about rather than the omission path.
      auditFilterOptionsRepositoryProvider.overrideWithValue(
        options ?? const _FixedOptions([_branchB]),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Loads the report + series THROUGH THE REAL PROVIDERS and returns the params.
Future<({Map<String, dynamic> report, Map<String, dynamic> series})> _loadBoth(
  ProviderContainer c,
  _RecordingTransport t,
) async {
  await c.read(
    ownerReportForKeyProvider(c.read(currentOwnerReportKeyProvider)).future,
  );
  c.read(reportRangeProvider.notifier).state = ReportRange.last7;
  await c.read(
    ownerSalesSeriesForKeyProvider(
      c.read(currentOwnerSalesSeriesKeyProvider)!,
    ).future,
  );
  return (
    report: t.lastTo('owner_report_range')!,
    series: t.lastTo('owner_sales_series')!,
  );
}

void main() {
  // =========================================================================
  // F-1A — the key's scope IS the request's scope
  // =========================================================================
  group('F-1A: family key scope reaches the transport', () {
    test('A. ORG-WIDE — neither the pinned restaurant nor the pinned branch is '
        'sent', () async {
      final t = _RecordingTransport();
      final c = _container(transport: t);
      final p = await _loadBoth(c, t);

      for (final call in [p.report, p.series]) {
        expect(call['p_organization_id'], 'org-1');
        expect(call['p_restaurant_id'], isNull);
        expect(call['p_branch_id'], isNull);
      }
      // E. no pinned-fallback leakage.
      for (final call in t.params) {
        expect(call.values, isNot(contains('rest-1')));
        expect(call.values, isNot(contains('branch-1')));
      }
    });

    test('B. RESTAURANT-WIDE — that restaurant, all branches', () async {
      final t = _RecordingTransport();
      final c = _container(
        membership: _membership(
          role: MembershipRole.restaurantOwner,
          restaurantId: 'rest-2',
        ),
        transport: t,
      );
      final p = await _loadBoth(c, t);

      for (final call in [p.report, p.series]) {
        expect(call['p_restaurant_id'], 'rest-2');
        expect(call['p_branch_id'], isNull);
      }
    });

    test(
      'C. SINGLE BRANCH B — both ids come from the selection, not the pin',
      () async {
        final t = _RecordingTransport();
        final c = _container(transport: t);
        c.read(selectedAnalyticsBranchProvider.notifier).state = _branchB;
        final p = await _loadBoth(c, t);

        for (final call in [p.report, p.series]) {
          expect(call['p_restaurant_id'], 'rest-2');
          expect(call['p_branch_id'], 'branch-2');
        }
        for (final call in t.params) {
          expect(call.values, isNot(contains('rest-1')));
          expect(call.values, isNot(contains('branch-1')));
        }
      },
    );

    test('D. KEY/TRANSPORT IDENTITY holds for every request', () async {
      for (final selected in const [null, _branchB]) {
        final t = _RecordingTransport();
        final c = _container(transport: t);
        c.read(selectedAnalyticsBranchProvider.notifier).state = selected;

        final reportKey = c.read(currentOwnerReportKeyProvider);
        await c.read(ownerReportForKeyProvider(reportKey).future);
        final report = t.lastTo('owner_report_range')!;
        expect(report['p_organization_id'], reportKey.organizationId);
        expect(report['p_restaurant_id'], reportKey.restaurantId);
        expect(report['p_branch_id'], reportKey.branchId);

        c.read(reportRangeProvider.notifier).state = ReportRange.last7;
        final seriesKey = c.read(currentOwnerSalesSeriesKeyProvider)!;
        await c.read(ownerSalesSeriesForKeyProvider(seriesKey).future);
        final series = t.lastTo('owner_sales_series')!;
        expect(series['p_organization_id'], seriesKey.organizationId);
        expect(series['p_restaurant_id'], seriesKey.restaurantId);
        expect(series['p_branch_id'], seriesKey.branchId);
      }
    });

    test(
      'a RETAINED entry keeps its own scope when the selection moves on',
      () async {
        // The scenario the instance-level fix could not have handled: the family
        // entry for the broad key is re-read AFTER the selection changed. Its
        // request must still be the broad one.
        final t = _RecordingTransport();
        final c = _container(transport: t);

        final broadKey = c.read(currentOwnerReportKeyProvider);
        await c.read(ownerReportForKeyProvider(broadKey).future);

        c.read(selectedAnalyticsBranchProvider.notifier).state = _branchB;
        await c.read(
          ownerReportForKeyProvider(
            c.read(currentOwnerReportKeyProvider),
          ).future,
        );
        expect(t.lastTo('owner_report_range')!['p_branch_id'], 'branch-2');

        // Force the retained broad entry to re-run; it must ask broadly.
        c.invalidate(ownerReportForKeyProvider(broadKey));
        await c.read(ownerReportForKeyProvider(broadKey).future);
        expect(t.lastTo('owner_report_range')!['p_branch_id'], isNull);
        expect(t.lastTo('owner_report_range')!['p_restaurant_id'], isNull);
      },
    );

    test('F. CROSS-ORG scope fails closed BEFORE transport', () async {
      final t = _RecordingTransport();
      final m = _membership();
      final foreign = DashboardAnalyticsScope.ofIds(
        organizationId: 'org-OTHER',
        restaurantId: 'rest-X',
        branchId: 'branch-X',
      );

      await expectLater(
        RealOwnerReportsRepository(
          null,
          scope: m,
          transport: t,
        ).loadReport(analyticsScope: foreign),
        throwsA(isA<OwnerReportsException>()),
      );
      await expectLater(
        RealOwnerSalesSeriesRepository(
          scope: m,
          transport: t,
        ).loadSeries(range: AnalyticsRange.last7, analyticsScope: foreign),
        throwsA(isA<OwnerSalesSeriesException>()),
      );
      expect(t.functions, isEmpty, reason: 'nothing reached the wire');
    });

    test('an ABSENT scope falls back to COVERAGE, never to the pin', () async {
      final t = _RecordingTransport();
      await RealOwnerReportsRepository(
        null,
        scope: _membership(),
        transport: t,
      ).loadReport();
      expect(t.lastTo('owner_report_range')!['p_restaurant_id'], isNull);
      expect(t.lastTo('owner_report_range')!['p_branch_id'], isNull);
    });

    test(
      'the key getter reconstructs the same scope the selection produced',
      () {
        const key = OwnerReportQueryKey(
          organizationId: 'org-1',
          restaurantId: 'rest-2',
          branchId: 'branch-2',
          range: ReportRange.today,
          isDemoMode: false,
        );
        final scope = key.analyticsScope!;
        expect(scope.organizationId, 'org-1');
        expect(scope.restaurantId, 'rest-2');
        expect(scope.branchId, 'branch-2');
        expect(scope.kind, DashboardAnalyticsScopeKind.singleBranch);

        const broad = OwnerSalesSeriesQueryKey(
          organizationId: 'org-1',
          restaurantId: null,
          branchId: null,
          range: AnalyticsRange.last7,
          isDemoMode: false,
        );
        expect(broad.analyticsScope!.kind, DashboardAnalyticsScopeKind.orgWide);
      },
    );
  });

  // =========================================================================
  // F-1C — single-branch coverage requires the restaurant too
  // =========================================================================
  group('F-1C: single-branch coverage compares the full triple', () {
    final fixed = DashboardAnalyticsScope.coveredBy(
      _membership(role: MembershipRole.manager),
    );

    test('same org + same branch + WRONG restaurant => false', () {
      expect(
        fixed.covers(
          const AuditBranchOption(
            organizationId: 'org-1',
            branchId: 'branch-1',
            restaurantId: 'rest-WRONG',
            label: 'x',
          ),
        ),
        isFalse,
      );
    });

    test('same org + same restaurant + same branch => true', () {
      expect(
        fixed.covers(
          const AuditBranchOption(
            organizationId: 'org-1',
            branchId: 'branch-1',
            restaurantId: 'rest-1',
            label: 'x',
          ),
        ),
        isTrue,
      );
    });

    test('different org => false', () {
      expect(fixed.covers(_orgAOption), isFalse);
    });

    test('different branch => false', () {
      expect(
        fixed.covers(
          const AuditBranchOption(
            organizationId: 'org-1',
            branchId: 'branch-OTHER',
            restaurantId: 'rest-1',
            label: 'x',
          ),
        ),
        isFalse,
      );
    });
  });

  // =========================================================================
  // F-1B — the selector's value against the CURRENT item set
  // =========================================================================
  group('F-1B: selector value/item invariant', () {
    Widget app({
      required MembershipContext membership,
      required AuditFilterOptionsRepository options,
      required _RecordingTransport transport,
      void Function(ProviderContainer)? capture,
    }) => ProviderScope(
      overrides: [
        dashboardMembershipProvider.overrideWithValue(membership),
        dashboardAuthTransportProvider.overrideWithValue(transport),
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        auditFilterOptionsRepositoryProvider.overrideWithValue(options),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          capture?.call(ProviderScope.containerOf(context));
          return MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: const DashboardHomeScreen(),
          );
        },
      ),
    );

    String? valueOf(WidgetTester tester) => tester
        .widget<DropdownButtonFormField<String?>>(
          find.byKey(const Key('overview-scope-selector')),
        )
        .initialValue;

    /// OPENS the dropdown and returns the item values it offers.
    ///
    /// A closed DropdownButtonFormField renders only its selected item, so
    /// reading the tree while shut would assert nothing about the item SET —
    /// which is precisely what F-1B is about.
    Future<Set<String?>> openItemValues(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();
      // DISTINCT values: while the menu is open the button still renders its
      // own copy of the selected item behind it, so raw counts double-count.
      return tester
          .widgetList<DropdownMenuItem<String?>>(
            find.byType(DropdownMenuItem<String?>),
          )
          .map((i) => i.value)
          .toSet();
    }

    void size(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    // CODEX F-1B-3 SUPERSEDES THE ORIGINAL EXPECTATION HERE. This case used to
    // assert that an in-flight option list shows the BROAD value. That kept the
    // dropdown assertion-safe but made the control claim a breadth the reports
    // did not have — the transport was already on branch B. The control now
    // offers the branch it is querying, so the value is present exactly once
    // AND the screen matches the figures. The invariant the case exists to
    // protect (never a value without an item) is asserted as before.
    testWidgets('a coverage-valid selection whose option has NOT loaded is '
        'shown as the branch being queried, with an item of its own', (
      tester,
    ) async {
      size(tester);
      late ProviderContainer c;
      await tester.pumpWidget(
        app(
          membership: _membership(),
          transport: _RecordingTransport(),
          options: const _FixedOptions([
            _branchB,
          ], delay: Duration(milliseconds: 200)),
          capture: (x) => c = x,
        ),
      );
      await tester.pump();
      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchB;
      await tester.pump();

      // Options still in flight: the branch IS authorized, still drives the
      // reports, and is offered as its own item rather than silently widened.
      expect(c.read(effectiveAnalyticsBranchProvider), _branchB);
      expect(valueOf(tester), 'branch-2');
      expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-2');
      // A value with no item throws on the very frame it is built, so a clean
      // frame here is the item's existence. (Opening the menu is avoided on
      // purpose: settling it would resolve the in-flight load under test.)
      expect(tester.takeException(), isNull);

      // ...and once they land, it resumes.
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(valueOf(tester), 'branch-2');
      expect(tester.takeException(), isNull);
    });

    // CODEX F-1B-3 — same supersession as the case above: a FAILED list is not
    // evidence that the branch is gone, so the scope stays on it AND the
    // control now says so.
    testWidgets(
      'a FAILED option load keeps the branch, in both the scope and the control',
      (tester) async {
        size(tester);
        late ProviderContainer c;
        await tester.pumpWidget(
          app(
            membership: _membership(),
            transport: _RecordingTransport(),
            options: const _FixedOptions([], fail: true),
            capture: (x) => c = x,
          ),
        );
        await tester.pumpAndSettle();
        c.read(selectedAnalyticsBranchProvider.notifier).state = _branchB;
        await tester.pumpAndSettle();

        expect(valueOf(tester), 'branch-2');
        expect(await openItemValues(tester), {null, 'branch-2'});
        expect(tester.takeException(), isNull);
        // The analytics scope still follows AUTHORIZED coverage — a failed
        // option list must not silently widen the financial query.
        expect(
          c.read(dashboardAnalyticsScopeProvider)!.branchId,
          'branch-2',
          reason: 'transport scope follows coverage, not the option list',
        );
      },
    );

    testWidgets('an EXACT duplicate option yields one item and one match', (
      tester,
    ) async {
      size(tester);
      late ProviderContainer c;
      await tester.pumpWidget(
        app(
          membership: _membership(),
          transport: _RecordingTransport(),
          options: const _FixedOptions([_branchB, _branchB]),
          capture: (x) => c = x,
        ),
      );
      await tester.pumpAndSettle();
      c.read(selectedAnalyticsBranchProvider.notifier).state = _branchB;
      await tester.pumpAndSettle();

      expect(valueOf(tester), 'branch-2');
      expect(await openItemValues(tester), {null, 'branch-2'});
      // The decisive proof: had the duplicate NOT collapsed there would be two
      // items carrying the same value, which DropdownButtonFormField asserts
      // on — so a clean frame is itself the evidence.
      expect(tester.takeException(), isNull);
    });

    // CODEX F-1B-2 SUPERSEDES THE ORIGINAL EXPECTATION HERE. This case used to
    // assert that the FIRST of two conflicting composites survives, which made
    // list order decide which restaurant a branch belongs to. Both are now
    // dropped: a branch id carrying two different composites is corrupt data,
    // and the client fails closed rather than picking a winner.
    testWidgets('the SAME branch id under a DIFFERENT restaurant is dropped '
        'ENTIRELY, not resolved by list order', (tester) async {
      size(tester);
      const conflicting = AuditBranchOption(
        organizationId: 'org-1',
        branchId: 'branch-2',
        restaurantId: 'rest-CONFLICT',
        label: 'Conflicting · Harbor',
      );
      await tester.pumpWidget(
        app(
          membership: _membership(),
          transport: _RecordingTransport(),
          options: const _FixedOptions([_branchB, conflicting]),
        ),
      );
      await tester.pumpAndSettle();

      expect(await openItemValues(tester), {null});
      // Decisive: NEITHER conflicting label reaches the menu. Keeping one would
      // be a guess about which restaurant owns branch-2, and the answer would
      // depend on which row the server happened to send first.
      expect(find.text('Conflicting · Harbor'), findsNothing);
      expect(find.text('Rest Two · Harbor'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A -> B -> A in ONE root: loading, then failed, then loaded', (
      tester,
    ) async {
      size(tester);
      late ProviderContainer c;

      Future<void> pump(
        MembershipContext m,
        AuditFilterOptionsRepository o,
      ) async {
        await tester.pumpWidget(
          app(
            membership: m,
            transport: _RecordingTransport(),
            options: o,
            capture: (x) => c = x,
          ),
        );
      }

      // 1-3: Org A, options loaded, A1 selected.
      await pump(
        _membership(organizationId: 'org-A', restaurantId: 'rest-A'),
        const _FixedOptions([_orgAOption]),
      );
      await tester.pumpAndSettle();
      c.read(selectedAnalyticsBranchProvider.notifier).state = _orgAOption;
      await tester.pumpAndSettle();
      expect(valueOf(tester), 'branch-A1');

      // 4: Org B.
      await pump(
        _membership(organizationId: 'org-B', restaurantId: 'rest-B'),
        const _FixedOptions([]),
      );
      await tester.pumpAndSettle();
      expect(valueOf(tester), isNull);
      expect(c.read(dashboardAnalyticsScopeProvider)!.organizationId, 'org-B');
      expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, isNull);
      expect(tester.takeException(), isNull);

      // 5-6a: back to Org A with options still LOADING.
      await pump(
        _membership(organizationId: 'org-A', restaurantId: 'rest-A'),
        const _FixedOptions([_orgAOption], delay: Duration(milliseconds: 200)),
      );
      await tester.pump();
      // CODEX F-1B-3: authorized and still driving the reports, so the control
      // says so rather than claiming the broad scope it is not using.
      expect(valueOf(tester), 'branch-A1', reason: 'authorized and in use');
      expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-A1');
      expect(tester.takeException(), isNull);

      // 6b: options FAIL — still not evidence the branch is gone.
      await pump(
        _membership(organizationId: 'org-A', restaurantId: 'rest-A'),
        const _FixedOptions([], fail: true),
      );
      await tester.pumpAndSettle();
      expect(valueOf(tester), 'branch-A1');
      expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-A1');
      expect(tester.takeException(), isNull);

      // 6c: options LOAD — exactly one A1 exists, so it may resume.
      await pump(
        _membership(organizationId: 'org-A', restaurantId: 'rest-A'),
        const _FixedOptions([_orgAOption]),
      );
      await tester.pumpAndSettle();
      expect(valueOf(tester), 'branch-A1');
      expect(c.read(dashboardAnalyticsScopeProvider)!.organizationId, 'org-A');
      expect(tester.takeException(), isNull);
    });
  });
}
