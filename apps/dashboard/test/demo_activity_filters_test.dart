import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/activity/activity_log_screen.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_repository.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// STATIC-97CDEE8-DEMO-ACTIVITY-01 — the demo Activity timeline honours its own
/// branch and actor filters.
///
/// Every layer above the repository was already right: the control offered the
/// options, the effective query carried the selection, the controller passed it
/// down. `DemoAuditLogRepository._matches` then checked range, category and
/// sensitive-only and stopped — so picking "Harbor" or "Amira" changed the
/// dropdown and nothing else, and the timeline went on showing other branches'
/// and other people's events. A filter that visibly does nothing is worse than
/// no filter: it answers a question the owner asked, wrongly.
///
/// These drive the REAL demo path — the actual screen, the actual controller,
/// the actual repository — and assert the RESULT, because asserting the
/// effective query is exactly what would have passed while the bug was live.

Widget _app() => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: true),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const Scaffold(body: ActivityLogScreen()),
  ),
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Picks an option out of a real dropdown by its visible label.
Future<void> _pick(WidgetTester tester, String key, String label) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The event ids the REPOSITORY actually returned, through the controller.
List<String> _resultIds(ProviderContainer c) =>
    c.read(auditLogControllerProvider).events.map((e) => e.eventId).toList();

void main() {
  // The fixture's shape, asserted rather than assumed — every case below reads
  // as a claim about these rows.
  group('the demo fixtures carry filterable identities', () {
    test('every event names a branch option or is org-level, and every event '
        'names an actor option', () async {
      const options = DemoAuditFilterOptionsRepository();
      final branchIds = (await options.loadBranches())
          .map((b) => b.branchId)
          .toSet();
      final actorIds = (await options.loadActors())
          .map((a) => a.employeeProfileId)
          .toSet();

      final events = demoAuditEvents();
      for (final e in events) {
        if (e.branchId != null) {
          expect(
            branchIds,
            contains(e.branchId),
            reason: '${e.event.eventId} names a branch nobody can select',
          );
        }
        expect(
          actorIds,
          contains(e.actorId),
          reason: '${e.event.eventId} names an actor nobody can select',
        );
      }

      // Enough diversity that the cases below can actually discriminate.
      expect(
        events.map((e) => e.branchId).whereType<String>().toSet().length,
        greaterThanOrEqualTo(2),
      );
      expect(
        events.map((e) => e.actorId).toSet().length,
        greaterThanOrEqualTo(2),
      );
      bool has(String? branch, String actor) => events.any(
        (e) => e.branchId == branch && e.actorId == actor && e.daysAgo == 0,
      );
      expect(has(demoBranchHarbor, demoActorAmira), isTrue);
      expect(has(demoBranchHarbor, demoActorSami), isTrue);
      expect(has(demoBranchDowntown, demoActorAmira), isTrue);
    });
  });

  group('the demo repository honours branch and actor', () {
    test(
      'BRANCH only: Harbor returns Harbor events and nothing else',
      () async {
        final page = await DemoAuditLogRepository().loadEvents(
          const AuditQuery(
            branch: AuditBranchOption(
              organizationId: 'demo-org-1',
              branchId: demoBranchHarbor,
              restaurantId: 'demo-rest-1',
              label: 'RestoFlow · Harbor',
            ),
          ),
        );
        expect(page.events, isNotEmpty);
        expect(
          page.events.every((e) => e.branchName == 'Harbor'),
          isTrue,
          reason: 'a Downtown or org-level event leaked through',
        );
      },
    );

    test('ACTOR only: Amira returns Amira events and nothing else', () async {
      final page = await DemoAuditLogRepository().loadEvents(
        const AuditQuery(
          actor: AuditActorOption(
            employeeProfileId: demoActorAmira,
            label: 'Amira',
          ),
        ),
      );
      expect(page.events, isNotEmpty);
      expect(page.events.every((e) => e.actorName == 'Amira'), isTrue);
    });

    test('an ORG-level event is excluded by any branch filter', () async {
      final orgLevel = demoAuditEvents()
          .where((e) => e.branchId == null && e.daysAgo == 0)
          .map((e) => e.event.eventId)
          .toSet();
      expect(orgLevel, isNotEmpty, reason: 'the fixture has org-level rows');

      final page = await DemoAuditLogRepository().loadEvents(
        const AuditQuery(
          branch: AuditBranchOption(
            organizationId: 'demo-org-1',
            branchId: demoBranchDowntown,
            restaurantId: 'demo-rest-1',
            label: 'RestoFlow · Downtown',
          ),
        ),
      );
      expect(
        page.events.map((e) => e.eventId).toSet().intersection(orgLevel),
        isEmpty,
      );
    });

    test('the OTHER filters still apply alongside', () async {
      final page = await DemoAuditLogRepository().loadEvents(
        const AuditQuery(
          category: AuditCategory.voids,
          branch: AuditBranchOption(
            organizationId: 'demo-org-1',
            branchId: demoBranchHarbor,
            restaurantId: 'demo-rest-1',
            label: 'RestoFlow · Harbor',
          ),
        ),
      );
      expect(page.events, isNotEmpty);
      expect(page.events.every((e) => e.category == 'voids'), isTrue);
      expect(page.events.every((e) => e.branchName == 'Harbor'), isTrue);
    });
  });

  group('the real demo Activity screen filters its timeline', () {
    testWidgets('BRANCH + ACTOR: only Harbor events by Amira survive', (
      tester,
    ) async {
      _size(tester);
      late ProviderContainer c;
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      c = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('activity-branch-filter'))),
        listen: false,
      );

      // Both filters really are offered before anything is selected.
      final all = _resultIds(c);
      expect(all.length, greaterThan(2));

      await _pick(tester, 'activity-branch-filter', 'RestoFlow · Harbor');
      await _pick(tester, 'activity-actor-filter', 'Amira');

      final ids = _resultIds(c);
      expect(ids, isNotEmpty, reason: 'a matching event must remain');

      final byId = {for (final e in demoAuditEvents()) e.event.eventId: e};
      for (final id in ids) {
        final e = byId[id]!;
        expect(e.branchId, demoBranchHarbor, reason: '$id is the wrong branch');
        expect(e.actorId, demoActorAmira, reason: '$id is the wrong actor');
      }

      // The two near misses are decisive: same branch/other actor, and same
      // actor/other branch. Either surviving means a filter did nothing.
      final otherActorSameBranch = byId.values.firstWhere(
        (e) => e.branchId == demoBranchHarbor && e.actorId != demoActorAmira,
      );
      final sameActorOtherBranch = byId.values.firstWhere(
        (e) => e.actorId == demoActorAmira && e.branchId == demoBranchDowntown,
      );
      expect(ids, isNot(contains(otherActorSameBranch.event.eventId)));
      expect(ids, isNot(contains(sameActorOtherBranch.event.eventId)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('clearing both restores the full applicable timeline', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('activity-branch-filter'))),
        listen: false,
      );
      final before = _resultIds(c);

      await _pick(tester, 'activity-branch-filter', 'RestoFlow · Harbor');
      await _pick(tester, 'activity-actor-filter', 'Amira');
      expect(_resultIds(c).length, lessThan(before.length));

      // "All" is the first item in each control.
      await tester.tap(find.byKey(const Key('activity-branch-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              AppLocalizations.of(
                tester.element(find.byKey(const Key('activity-branch-filter'))),
              ).activityLogBranchAll,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activity-actor-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              AppLocalizations.of(
                tester.element(find.byKey(const Key('activity-actor-filter'))),
              ).activityLogActorAll,
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(_resultIds(c), before);
      expect(tester.takeException(), isNull);
    });
  });
}
