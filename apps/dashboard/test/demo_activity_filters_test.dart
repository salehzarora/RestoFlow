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

const _harborOption = AuditBranchOption(
  organizationId: 'demo-org-1',
  branchId: demoBranchHarbor,
  restaurantId: 'demo-rest-1',
  label: 'RestoFlow · Harbor',
);

/// Whether [part] appears inside [whole] in the same relative order.
bool _isSubsequence(List<String> part, List<String> whole) {
  var i = 0;
  for (final id in whole) {
    if (i < part.length && part[i] == id) i++;
  }
  return i == part.length;
}

bool _inRange(DemoAuditEvent e, AuditRange range) => switch (range) {
  AuditRange.today => e.daysAgo == 0,
  AuditRange.yesterday => e.daysAgo == 1,
  AuditRange.last7 => e.daysAgo >= 0 && e.daysAgo <= 6,
  AuditRange.last30 => e.daysAgo >= 0 && e.daysAgo <= 29,
};

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

  // =========================================================================
  // STATIC-C548C0E-DEMO-ACTIVITY-ORDER-01 — an audit timeline is newest-first
  // =========================================================================
  group('the demo timeline is newest-first', () {
    /// The order the fixture set SHOULD come back in for [query], derived
    /// independently of the repository so the expectation is not the code
    /// under test restated.
    List<String> expectedOrder(AuditQuery query) {
      final rows = [
        for (final e in demoAuditEvents())
          if (_inRange(e, query.range) &&
              (query.branch == null || e.branchId == query.branch!.branchId) &&
              (query.actor == null ||
                  e.actorId == query.actor!.employeeProfileId))
            e,
      ];
      rows.sort((a, b) {
        final byDay = a.daysAgo.compareTo(b.daysAgo);
        if (byDay != 0) return byDay;
        return b.minuteOfDay.compareTo(a.minuteOfDay);
      });
      return [for (final e in rows) e.event.eventId];
    }

    Future<List<String>> idsFor(AuditQuery query, {int pageSize = 25}) async {
      final page = await DemoAuditLogRepository(
        pageSize: pageSize,
      ).loadEvents(query);
      return page.events.map((e) => e.eventId).toList();
    }

    test('A. the default today timeline is in descending time order', () async {
      const q = AuditQuery();
      final ids = await idsFor(q);
      expect(ids, expectedOrder(q));
      // The defect in one assertion: 15:40 was appended after 09:40.
      expect(
        ids.indexOf('demo-ae-9'),
        lessThan(ids.indexOf('demo-ae-1')),
        reason: '15:40 must precede 14:05',
      );
      expect(ids.first, 'demo-ae-9');
    });

    test('B. ACTOR only: Amira newest-first', () async {
      const q = AuditQuery(
        actor: AuditActorOption(
          employeeProfileId: demoActorAmira,
          label: 'Amira',
        ),
      );
      final ids = await idsFor(q);
      expect(ids, expectedOrder(q));
      expect(ids.indexOf('demo-ae-9'), lessThan(ids.indexOf('demo-ae-1')));
    });

    test('C. BRANCH only: Harbor newest-first', () async {
      const q = AuditQuery(branch: _harborOption);
      final ids = await idsFor(q);
      expect(ids, expectedOrder(q));
      expect(ids, ['demo-ae-9', 'demo-ae-10']);
    });

    test('D. BRANCH + ACTOR: the matching set, in order', () async {
      const q = AuditQuery(
        branch: _harborOption,
        actor: AuditActorOption(
          employeeProfileId: demoActorAmira,
          label: 'Amira',
        ),
      );
      final ids = await idsFor(q);
      expect(ids, expectedOrder(q));
      expect(ids, ['demo-ae-9']);
    });

    test('E. a small page size puts the NEWEST rows on page 1, and the rest '
        'follow with no gap or repeat', () async {
      const q = AuditQuery(range: AuditRange.last7);
      final expected = expectedOrder(q);
      expect(expected.length, greaterThan(4), reason: 'enough rows to page');

      final repo = DemoAuditLogRepository(pageSize: 2);
      final collected = <String>[];
      String? cursor;
      var guard = 0;
      do {
        final page = await repo.loadEvents(q, cursor: cursor);
        collected.addAll(page.events.map((e) => e.eventId));
        cursor = page.nextCursor;
        expect(++guard, lessThan(20), reason: 'pagination must terminate');
      } while (cursor != null);

      expect(collected, expected, reason: 'no gap, no repeat, right order');
      expect(
        collected.toSet().length,
        collected.length,
        reason: 'no duplicate',
      );
      // Page 1 alone must already hold the two newest.
      final first = await repo.loadEvents(q);
      expect(first.events.map((e) => e.eventId), expected.take(2));
    });

    test('F. ordering survives the other filters', () async {
      // For CATEGORY and SENSITIVE-ONLY the expectation is stated as a
      // SUBSEQUENCE of the full ordered timeline rather than as a list of ids.
      // Reproducing those two predicates here would mean copying the code under
      // test into its own test; "filtering removes rows and never reorders the
      // ones it keeps" is both the stronger claim and the one that stays true
      // when the predicates change.
      final full = expectedOrder(const AuditQuery(range: AuditRange.last7));

      final voids = await idsFor(
        const AuditQuery(
          range: AuditRange.last7,
          category: AuditCategory.voids,
        ),
      );
      expect(
        voids.length,
        greaterThan(1),
        reason: 'more than one void to order',
      );
      expect(_isSubsequence(voids, full), isTrue, reason: '$voids vs $full');

      final sensitive = await idsFor(
        const AuditQuery(range: AuditRange.last7, sensitiveOnly: true),
      );
      expect(sensitive.length, greaterThan(1));
      expect(_isSubsequence(sensitive, full), isTrue);
    });

    test(
      'a tie at the same minute resolves by source order, deterministically',
      () async {
        const a = AuditEvent(
          eventId: 'tie-a',
          action: 'order.voided',
          category: 'voids',
          occurredAtLabel: '12:00',
        );
        const b = AuditEvent(
          eventId: 'tie-b',
          action: 'order.voided',
          category: 'voids',
          occurredAtLabel: '12:00',
        );
        final repo = DemoAuditLogRepository(
          events: const [
            DemoAuditEvent(daysAgo: 0, minuteOfDay: 720, event: a),
            DemoAuditEvent(daysAgo: 0, minuteOfDay: 720, event: b),
          ],
        );
        for (var i = 0; i < 3; i++) {
          final page = await repo.loadEvents(const AuditQuery());
          expect(page.events.map((e) => e.eventId), ['tie-a', 'tie-b']);
        }
      },
    );

    test('every fixture minute matches the time in its own label', () {
      for (final e in demoAuditEvents()) {
        final match = RegExp(
          r'(\d{2}):(\d{2})',
        ).firstMatch(e.event.occurredAtLabel);
        expect(match, isNotNull, reason: e.event.eventId);
        final expected =
            int.parse(match!.group(1)!) * 60 + int.parse(match.group(2)!);
        expect(
          e.minuteOfDay,
          expected,
          reason:
              '${e.event.eventId} says "${e.event.occurredAtLabel}" but '
              'sorts at ${e.minuteOfDay}',
        );
      }
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

    testWidgets('the rendered timeline itself is newest-first', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('activity-branch-filter'))),
        listen: false,
      );

      // Through the REAL controller and repository, not a sorting helper.
      final ids = _resultIds(c);
      final byId = {for (final e in demoAuditEvents()) e.event.eventId: e};
      for (var i = 1; i < ids.length; i++) {
        final prev = byId[ids[i - 1]]!;
        final next = byId[ids[i]]!;
        final ordered =
            prev.daysAgo < next.daysAgo ||
            (prev.daysAgo == next.daysAgo &&
                prev.minuteOfDay >= next.minuteOfDay);
        expect(
          ordered,
          isTrue,
          reason: '${ids[i - 1]} then ${ids[i]} is out of order',
        );
      }
      expect(ids.first, 'demo-ae-9', reason: 'the newest event leads');
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
