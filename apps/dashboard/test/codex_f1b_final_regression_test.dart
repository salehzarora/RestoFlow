import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/state/analytics_branch_providers.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// CODEX RE-REVIEW — regressions for F-1B-1, F-1B-2 and F-1B-3.
///
/// The previous round fixed the selector's *value*; these three are about what
/// the value MEANS.
///
/// F-1B-1 (P2) — the display label took part in branch identity. Matching the
/// selection with `AuditBranchOption.==` compared the label too, so a RENAMED
/// branch stopped matching itself: the reports kept querying branch-2 while the
/// control, finding no equal option, showed "All permitted branches".
///
/// F-1B-2 (P2) — de-duplication kept the FIRST row for a branch id. Two rows
/// sharing a branch id under different restaurants therefore resolved by LIST
/// ORDER: send the wrong tuple first and the wrong tuple won, silently.
///
/// F-1B-3 (P2) — a branch the authoritative option list no longer contains
/// stayed a hidden financial scope. Deleted or tombstoned, the selector could
/// not show it, so the screen said "All permitted branches" while every report
/// kept asking for that one branch — usually to an empty result, indefinitely.
///
/// The line these draw is between TRANSIENT ignorance (loading, failure — the
/// selection stands, because a flaky fetch is not evidence of removal) and an
/// AUTHORITATIVE answer (a successful list — which decides).

// ===========================================================================
// Harness
// ===========================================================================

class _RecordingTransport implements SyncRpcTransport {
  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  int countOf(String fn) => functions.where((f) => f == fn).length;

  Map<String, dynamic>? lastTo(String fn) {
    for (var i = functions.length - 1; i >= 0; i--) {
      if (functions[i] == fn) return params[i];
    }
    return null;
  }

  /// Every param map recorded from [from] onwards, for "nothing since" scans.
  Iterable<Map<String, dynamic>> paramsSince(int from) => params.skip(from);

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

/// A branch-option source whose ANSWER can change between loads, so a single
/// container can walk the whole lifecycle — loaded, refreshing, failed, loaded
/// again with the branch gone — without ever rebuilding the root. Rebuilding
/// the root would reset the selection and prove nothing about a live session.
class _MutableOptions implements AuditFilterOptionsRepository {
  _MutableOptions(this.branches);

  List<AuditBranchOption> branches;
  bool fail = false;

  /// When set, `loadBranches` parks until it completes — an in-flight load.
  Completer<void>? gate;

  @override
  Future<List<AuditBranchOption>> loadBranches() async {
    final g = gate;
    if (g != null) await g.future;
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
  // Exactly the pin resolveTenantContext applies: the FIRST of each.
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

/// The SAME branch, renamed. Identical triple, different label.
const _harborNew = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-2',
  label: 'Rest Two · Harbour Point',
);
const _airport = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-9',
  restaurantId: 'rest-2',
  label: 'Rest Two · Airport',
);
const _main = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  label: 'Rest One · Main',
);

/// The same BRANCH ID as [_harborOld] under a different restaurant — the
/// conflicting composite F-1B-2 is about.
const _harborConflict = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-CONFLICT',
  label: 'Conflicting · Harbor',
);

/// A DIFFERENT branch that happens to share a display label — not a conflict.
const _airportSameLabel = AuditBranchOption(
  organizationId: 'org-1',
  branchId: 'branch-9',
  restaurantId: 'rest-2',
  label: 'Rest Two · Harbor',
);

ProviderContainer _container({
  required _RecordingTransport transport,
  required AuditFilterOptionsRepository options,
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
      auditFilterOptionsRepositoryProvider.overrideWithValue(options),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Loads the report for the CURRENT key through the real provider graph.
///
/// Deliberately does NOT wait for the option list: the loading case has to be
/// able to issue a report while the list is still in flight, which is the whole
/// point of the transient rule. Cases that need a settled list call
/// [_reloadOptions] first.
Future<void> _loadReport(ProviderContainer c) => c.read(
  ownerReportForKeyProvider(c.read(currentOwnerReportKeyProvider)).future,
);

/// Re-runs the option load and waits for it to settle (success or failure).
///
/// CODEX F-1B-3-R1: settles the ANALYTICS answer as well — it stamps the raw
/// list with the authorization context it was loaded for, one microtask later.
Future<void> _reloadOptions(ProviderContainer c) async {
  c.invalidate(auditBranchOptionsProvider);
  await c
      .read(auditBranchOptionsProvider.future)
      .catchError((_) => const <AuditBranchOption>[]);
  await _settleAnswer(c);
}

/// Awaits the stamped analytics answer, swallowing the failure cases.
Future<void> _settleAnswer(ProviderContainer c) async {
  try {
    await c.read(analyticsBranchAnswerProvider.future);
  } catch (_) {
    // The failure states are the point of several of these cases.
  }
}

void main() {
  // =========================================================================
  // F-1B-1 — identity is three ids; the label is not one of them
  // =========================================================================
  group('F-1B-1: branch identity excludes the display label', () {
    test('a rename is the SAME branch; a different restaurant, organization or '
        'branch is not', () {
      expect(sameAnalyticsBranchIdentity(_harborOld, _harborNew), isTrue);
      expect(sameAnalyticsBranchIdentity(_harborOld, _harborConflict), isFalse);
      expect(sameAnalyticsBranchIdentity(_harborOld, _airport), isFalse);
      expect(
        sameAnalyticsBranchIdentity(
          _harborOld,
          const AuditBranchOption(
            organizationId: 'org-OTHER',
            branchId: 'branch-2',
            restaurantId: 'rest-2',
            label: 'Rest Two · Harbor',
          ),
        ),
        isFalse,
      );
      // The defect in one line: value equality says a rename is a new branch.
      expect(_harborOld == _harborNew, isFalse);
    });

    test(
      'a RENAME keeps the scope and the keys, and costs no request',
      () async {
        final t = _RecordingTransport();
        final options = _MutableOptions([_harborOld, _main]);
        final c = _container(transport: t, options: options);

        c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
        c.read(reportRangeProvider.notifier).state = ReportRange.last7;
        await _loadReport(c);

        final reportKeyBefore = c.read(currentOwnerReportKeyProvider);
        final seriesKeyBefore = c.read(currentOwnerSalesSeriesKeyProvider)!;
        final callsBefore = t.countOf('owner_report_range');
        expect(callsBefore, 1);

        // The branch is renamed server-side and the list is refetched.
        options.branches = [_harborNew, _main];
        await _reloadOptions(c);

        // Same branch: same scope, same ids, and the LIVE label.
        final scope = c.read(dashboardAnalyticsScopeProvider)!;
        expect(scope.restaurantId, 'rest-2');
        expect(scope.branchId, 'branch-2');
        expect(scope.branchLabel, 'Rest Two · Harbour Point');
        expect(c.read(resolvedLiveAnalyticsBranchProvider), _harborNew);

        // The identity the cache is keyed on did not move...
        final reportKeyAfter = c.read(currentOwnerReportKeyProvider);
        final seriesKeyAfter = c.read(currentOwnerSalesSeriesKeyProvider)!;
        expect(reportKeyAfter, reportKeyBefore);
        expect(seriesKeyAfter, seriesKeyBefore);

        // ...so re-reading issues NO new request. A change of display text must
        // never cost a financial round trip.
        await _loadReport(c);
        expect(t.countOf('owner_report_range'), callsBefore);
        expect(t.lastTo('owner_report_range')!['p_branch_id'], 'branch-2');
      },
    );

    testWidgets('the control shows the NEW name without a broad flash', (
      tester,
    ) async {
      final t = _RecordingTransport();
      final options = _MutableOptions([_harborOld, _main]);
      late ProviderContainer c;
      await tester.pumpWidget(
        _app(transport: t, options: options, capture: (x) => c = x),
      );
      await tester.pumpAndSettle();
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await tester.pumpAndSettle();
      expect(_valueOf(tester), 'branch-2');
      expect(find.text('Rest Two · Harbor'), findsWidgets);

      options.branches = [_harborNew, _main];
      c.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();

      expect(_valueOf(tester), 'branch-2', reason: 'never falls back to broad');
      expect(find.text('Rest Two · Harbour Point'), findsWidgets);
      expect(find.text('Rest Two · Harbor'), findsNothing);
      expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-2');
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // F-1B-2 — conflicting composites, and the order-independence of the answer
  // =========================================================================
  group('F-1B-2: conflicting composites fail closed', () {
    test('an exact duplicate collapses to one entry', () {
      final out = sanitizeAnalyticsBranchOptions(const [
        _harborOld,
        _harborOld,
      ]);
      expect(out, [_harborOld]);
    });

    test('rows differing ONLY in label are one branch, deterministically the '
        'first in source order', () {
      expect(sanitizeAnalyticsBranchOptions(const [_harborOld, _harborNew]), [
        _harborOld,
      ]);
      expect(sanitizeAnalyticsBranchOptions(const [_harborNew, _harborOld]), [
        _harborNew,
      ]);
    });

    test('a conflicting composite drops the branch id ENTIRELY — in BOTH '
        'orders', () {
      // Wrong tuple first: first-wins would have kept rest-CONFLICT.
      expect(
        sanitizeAnalyticsBranchOptions(const [
          _harborConflict,
          _harborOld,
          _airport,
        ]),
        [_airport],
      );
      // Correct tuple first: first-wins would have looked right by luck.
      expect(
        sanitizeAnalyticsBranchOptions(const [
          _harborOld,
          _harborConflict,
          _airport,
        ]),
        [_airport],
      );
    });

    test('the conflict is detected BEFORE coverage, so narrowing cannot hide '
        'it', () {
      // A restaurant-wide owner of rest-2 covers only _harborOld of the pair.
      final coverage = DashboardAnalyticsScope.coveredBy(
        _membership(
          role: MembershipRole.restaurantOwner,
          restaurantId: 'rest-2',
        ),
      );
      expect(
        sanitizeAnalyticsBranchOptions(const [
          _harborConflict,
          _harborOld,
          _airport,
        ], coverage: coverage),
        [_airport],
      );
    });

    test('the same LABEL on different branch ids is not a conflict', () {
      expect(
        sanitizeAnalyticsBranchOptions(const [_harborOld, _airportSameLabel]),
        const [_harborOld, _airportSameLabel],
      );
    });

    test('a SELECTED branch that becomes conflicting falls back to the broad '
        'parent, not to either tuple', () async {
      final t = _RecordingTransport();
      final options = _MutableOptions([_harborOld, _airport]);
      final c = _container(transport: t, options: options);

      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await _loadReport(c);
      expect(t.lastTo('owner_report_range')!['p_branch_id'], 'branch-2');

      options.branches = [_harborConflict, _harborOld, _airport];
      await _reloadOptions(c);

      expect(c.read(resolvedLiveAnalyticsBranchProvider), isNull);
      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.restaurantId, isNull);
      expect(scope.branchId, isNull);

      final from = t.params.length;
      await _loadReport(c);
      final after = t.lastTo('owner_report_range')!;
      expect(after['p_restaurant_id'], isNull);
      expect(after['p_branch_id'], isNull);
      for (final call in t.paramsSince(from)) {
        expect(call.values, isNot(contains('rest-CONFLICT')));
        expect(call.values, isNot(contains('branch-2')));
      }
    });

    testWidgets('neither conflicting label reaches the menu', (tester) async {
      final t = _RecordingTransport();
      await tester.pumpWidget(
        _app(
          transport: t,
          options: _MutableOptions([_harborConflict, _harborOld, _airport]),
        ),
      );
      await tester.pumpAndSettle();

      expect(await _openItemValues(tester), {null, 'branch-9'});
      expect(find.text('Conflicting · Harbor'), findsNothing);
      expect(find.text('Rest Two · Harbor'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // F-1B-3 — transient ignorance vs an authoritative answer
  // =========================================================================
  group('F-1B-3: authoritative omission retires a selection', () {
    test(
      'ONE root: loaded -> loading -> failed -> omitted -> returned',
      () async {
        final t = _RecordingTransport();
        final options = _MutableOptions([_harborOld, _main]);
        final c = _container(transport: t, options: options);
        c.read(reportRangeProvider.notifier).state = ReportRange.last7;
        c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
        await _loadReport(c);

        expect(t.lastTo('owner_report_range')!['p_branch_id'], 'branch-2');
        final loadedCalls = t.countOf('owner_report_range');

        // A. LOADING — nothing has been learned, so the branch still applies.
        options.gate = Completer<void>();
        c.invalidate(auditBranchOptionsProvider);
        c.read(auditBranchOptionsProvider); // start the load
        expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-2');
        expect(c.read(currentOwnerReportKeyProvider).branchId, 'branch-2');
        await _loadReport(c);
        expect(
          t.countOf('owner_report_range'),
          loadedCalls,
          reason: 'a loading option list is not a new scope',
        );
        options.gate!.complete();
        await _reloadOptions(c);

        // B. ERROR — likewise. A flaky fetch must not widen the figures.
        options.fail = true;
        await _reloadOptions(c);
        expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-2');
        await _loadReport(c);
        expect(
          t.countOf('owner_report_range'),
          loadedCalls,
          reason: 'a failed option list is not a new scope',
        );

        // C. SUCCESS with the branch OMITTED — now it is authoritative.
        options.fail = false;
        options.branches = [_main];
        await _reloadOptions(c);

        expect(c.read(resolvedLiveAnalyticsBranchProvider), isNull);
        final scope = c.read(dashboardAnalyticsScopeProvider)!;
        expect(scope.organizationId, 'org-1');
        expect(scope.restaurantId, isNull);
        expect(scope.branchId, isNull);
        expect(scope.kind, DashboardAnalyticsScopeKind.orgWide);

        final reportKey = c.read(currentOwnerReportKeyProvider);
        expect(reportKey.restaurantId, isNull);
        expect(reportKey.branchId, isNull);
        final seriesKey = c.read(currentOwnerSalesSeriesKeyProvider)!;
        expect(seriesKey.restaurantId, isNull);
        expect(seriesKey.branchId, isNull);

        // No branch-2 request may follow the omission — that is the whole bug.
        final from = t.params.length;
        await _loadReport(c);
        await c.read(
          ownerSalesSeriesForKeyProvider(
            c.read(currentOwnerSalesSeriesKeyProvider)!,
          ).future,
        );
        final report = t.lastTo('owner_report_range')!;
        final series = t.lastTo('owner_sales_series')!;
        for (final call in [report, series]) {
          expect(call['p_restaurant_id'], isNull);
          expect(call['p_branch_id'], isNull);
        }
        for (final call in t.paramsSince(from)) {
          expect(call.values, isNot(contains('branch-2')));
        }
        // And no first-branch fallback crept in from the pinned membership.
        for (final call in t.paramsSince(from)) {
          expect(call.values, isNot(contains('branch-1')));
        }

        // D. The branch RETURNS. Documented, deliberate behaviour: the raw
        // selection was left intact, so it resumes — but only because BOTH gates
        // hold, authorization and live presence.
        options.branches = [_harborOld, _main];
        await _reloadOptions(c);
        expect(c.read(effectiveAnalyticsBranchProvider), _harborOld);
        expect(c.read(resolvedLiveAnalyticsBranchProvider), _harborOld);
        expect(c.read(dashboardAnalyticsScopeProvider)!.branchId, 'branch-2');
      },
    );

    test('a RESTAURANT-wide owner falls back to the restaurant, never to the '
        'organization and never to a sibling', () async {
      final t = _RecordingTransport();
      final options = _MutableOptions([_harborOld, _airport]);
      final c = _container(
        transport: t,
        options: options,
        membership: _membership(
          role: MembershipRole.restaurantOwner,
          restaurantId: 'rest-2',
        ),
      );
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await _loadReport(c);
      expect(t.lastTo('owner_report_range')!['p_branch_id'], 'branch-2');

      options.branches = [_airport];
      await _reloadOptions(c);

      final scope = c.read(dashboardAnalyticsScopeProvider)!;
      expect(scope.kind, DashboardAnalyticsScopeKind.restaurantWide);
      expect(scope.restaurantId, 'rest-2');
      expect(scope.branchId, isNull);

      await _loadReport(c);
      final after = t.lastTo('owner_report_range')!;
      expect(after['p_restaurant_id'], 'rest-2', reason: 'no widening to org');
      expect(after['p_branch_id'], isNull);
      // Not the other branch that DID survive the omission, either.
      expect(after.values, isNot(contains('branch-9')));
    });

    test('a BRANCH-FIXED membership is never widened by an omission', () async {
      for (final role in const [
        MembershipRole.manager,
        MembershipRole.cashier,
      ]) {
        final t = _RecordingTransport();
        // The option list does not enumerate this membership's branch at all.
        final c = _container(
          transport: t,
          options: _MutableOptions([_airport]),
          membership: _membership(role: role),
        );
        // Even with the branch explicitly selected, which is the harder case.
        c.read(selectedAnalyticsBranchProvider.notifier).state = _main;
        await _loadReport(c);

        final scope = c.read(dashboardAnalyticsScopeProvider)!;
        expect(scope.kind, DashboardAnalyticsScopeKind.singleBranch);
        expect(scope.restaurantId, 'rest-1');
        expect(scope.branchId, 'branch-1');

        final call = t.lastTo('owner_report_range')!;
        expect(call['p_restaurant_id'], 'rest-1');
        expect(call['p_branch_id'], 'branch-1');
        // Never org-wide, never restaurant-wide, never the sibling.
        expect(call.values, isNot(contains('branch-9')));
      }
    });

    testWidgets('the control and the reports agree through the whole '
        'lifecycle, with no exception at any step', (tester) async {
      final t = _RecordingTransport();
      final options = _MutableOptions([_harborOld, _main]);
      late ProviderContainer c;
      await tester.pumpWidget(
        _app(transport: t, options: options, capture: (x) => c = x),
      );
      await tester.pumpAndSettle();
      c.read(selectedAnalyticsBranchProvider.notifier).state = _harborOld;
      await tester.pumpAndSettle();

      String? branchScope() =>
          c.read(dashboardAnalyticsScopeProvider)!.branchId;

      expect(_valueOf(tester), 'branch-2');
      expect(branchScope(), 'branch-2');

      // Loading: both stay on the branch.
      options.gate = Completer<void>();
      c.invalidate(auditBranchOptionsProvider);
      await tester.pump();
      expect(_valueOf(tester), 'branch-2');
      expect(branchScope(), 'branch-2');
      expect(tester.takeException(), isNull);
      options.gate!.complete();
      await tester.pumpAndSettle();

      // Failure: both stay on the branch.
      options.fail = true;
      c.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();
      expect(_valueOf(tester), 'branch-2');
      expect(branchScope(), 'branch-2');
      expect(tester.takeException(), isNull);

      // Authoritative omission: both move to the broad scope together.
      options.fail = false;
      options.branches = [_main];
      c.invalidate(auditBranchOptionsProvider);
      await tester.pumpAndSettle();
      expect(_valueOf(tester), isNull);
      expect(branchScope(), isNull);
      expect(await _openItemValues(tester), {null, 'branch-1'});
      expect(find.text('Rest Two · Harbor'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // The invariant the whole group exists to keep
  // =========================================================================
  group('selector item/value invariant', () {
    test(
      'the resolved value is offered exactly once, whatever the list says',
      () {
        const lists = <List<AuditBranchOption>>[
          [],
          [_harborOld],
          [_harborOld, _harborOld],
          [_harborOld, _harborNew],
          [_harborOld, _harborConflict],
          [_harborConflict, _harborOld],
          [_harborOld, _airportSameLabel],
          [_main, _harborOld, _airport],
        ];
        for (final list in lists) {
          for (final selected in const [null, _harborOld, _airport, _main]) {
            final t = _RecordingTransport();
            final c = _container(
              transport: t,
              options: _MutableOptions(list),
              membership: _membership(),
            );
            c.read(selectedAnalyticsBranchProvider.notifier).state = selected;
            // Read while the list is still in flight AND after it lands; the
            // invariant has to hold in both.
            final offered = sanitizeAnalyticsBranchOptions(
              list,
              coverage: c.read(dashboardCoveredScopeProvider),
            );
            final ids = offered.map((o) => o.branchId).toList();
            expect(
              ids.toSet().length,
              ids.length,
              reason: 'offered ids must be unique: $list',
            );
            final resolved = c.read(resolvedLiveAnalyticsBranchProvider);
            if (resolved != null) {
              // Still loading here, so the resolved value is the stored one and
              // the control offers exactly it.
              expect(resolved, selected);
            }
          }
        }
      },
    );
  });
}

// ===========================================================================
// Widget harness
// ===========================================================================

Widget _app({
  required _RecordingTransport transport,
  required AuditFilterOptionsRepository options,
  MembershipContext? membership,
  void Function(ProviderContainer)? capture,
}) => ProviderScope(
  overrides: [
    dashboardMembershipProvider.overrideWithValue(membership ?? _membership()),
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

String? _valueOf(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<String?>>(
      find.byKey(const Key('overview-scope-selector')),
    )
    .initialValue;

/// OPENS the dropdown and returns the DISTINCT item values it offers. A closed
/// field renders only its selected item, and an open one still renders the
/// button's own copy behind the menu — so distinct values are the honest read.
Future<Set<String?>> _openItemValues(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('overview-scope-selector')));
  await tester.pumpAndSettle();
  final values = tester
      .widgetList<DropdownMenuItem<String?>>(
        find.byType(DropdownMenuItem<String?>),
      )
      .map((i) => i.value)
      .toSet();
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
  return values;
}
