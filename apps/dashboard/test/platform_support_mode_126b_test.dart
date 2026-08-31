/// ADMIN-126B — the tenant-side half of platform support mode.
///
/// These tests are about HONESTY, not authorization. Whether a support operator
/// may read or write anything is settled in
/// `20260903090001_platform_support_sessions_126.sql` and proved by
/// `platform_support_sessions_126b_test.sql` (88 assertions, including an
/// eighteen-case write-denial matrix). Nothing here could grant access and
/// nothing here could take it away.
///
/// What they do prove is that the UI never MISLEADS: the handoff is spent once
/// and erased from the URL, the banner is unmissable and names the tenant, the
/// countdown is real, ending is immediate, and an expired or absent session
/// lands on a safe screen rather than a dashboard that quietly cannot load.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/support/platform_support.dart';
import 'package:restoflow_dashboard/src/support/support_mode_gate.dart';
import 'package:restoflow_dashboard/src/support/support_mode_scope.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> strings([String locale = 'en']) =>
    AppLocalizations.delegate.load(Locale(locale));

PlatformSupportSession _session({
  DateTime? expiresAt,
  String? restaurantName,
  String organizationName = 'Bistro Group',
}) => PlatformSupportSession(
  id: 'sup-1',
  organizationId: 'org-1',
  organizationName: organizationName,
  reason: 'investigating a reported missing sales figure',
  expiresAt: expiresAt ?? DateTime(2026, 9, 3, 12, 15),
  restaurantId: restaurantName == null ? null : 'rest-1',
  restaurantName: restaurantName,
);

/// A repository that answers from a script rather than a server, and RECORDS
/// what it was asked — the exchange count is the point of several tests.
class _FakeSupportRepository implements PlatformSupportRepository {
  _FakeSupportRepository({this.exchanged, this.live});

  /// What `exchange` resolves with.
  final PlatformSupportSession? exchanged;

  /// What `current` resolves with (the authoritative answer).
  final PlatformSupportSession? live;

  final List<String> exchangeCalls = [];
  int currentCalls = 0;
  int endCalls = 0;

  @override
  Future<PlatformSupportSession?> exchange(String token) async {
    exchangeCalls.add(token);
    return exchanged;
  }

  @override
  Future<PlatformSupportSession?> current() async {
    currentCalls++;
    return live;
  }

  @override
  Future<void> end() async => endCalls++;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String locale = 'en',
  Size size = const Size(1300, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _BuildCounter.builds = 0);

  group('A. the handoff token', () {
    test('is taken from the fragment and STRIPPED, once', () {
      var replacedWith = 'not called';
      final token = takeSupportHandoffToken('#support=abc123', (cleaned) {
        replacedWith = cleaned;
      });
      expect(token, 'abc123');
      // The address bar must not keep it: a screenshot or a copied URL then
      // carries nothing at all.
      expect(replacedWith, '');
    });

    test('leaves any OTHER fragment parameters intact', () {
      var replacedWith = '';
      final token = takeSupportHandoffToken('#tab=menu&support=xyz&lang=ar', (
        cleaned,
      ) {
        replacedWith = cleaned;
      });
      expect(token, 'xyz');
      expect(replacedWith, 'tab=menu&lang=ar');
    });

    test('an ordinary launch URL is untouched and yields nothing', () {
      var called = false;
      expect(
        takeSupportHandoffToken('#tab=menu', (_) => called = true),
        isNull,
      );
      // Critically: no history rewrite on a normal load.
      expect(called, isFalse);
      expect(takeSupportHandoffToken('', (_) => called = true), isNull);
      expect(called, isFalse);
    });

    test('an EMPTY support value is not a token', () {
      // `#support=` with nothing after it must not be exchanged: the server
      // would refuse it, and treating it as a handoff would show the operator a
      // failure where they had simply mistyped a URL.
      expect(takeSupportHandoffToken('#support=', (_) {}), isNull);
      expect(takeSupportHandoffToken('#support=   ', (_) {}), isNull);
    });
  });

  group('B. the gate', () {
    testWidgets(
      'with NO handoff and no session, renders the tenant dashboard',
      (tester) async {
        final repo = _FakeSupportRepository();
        await _pump(
          tester,
          SupportModeGate(
            repository: repo,
            handoffToken: null,
            onSupport: (_, _) => const Text('SUPPORT'),
            child: const Scaffold(body: Text('TENANT')),
          ),
        );
        expect(find.text('TENANT'), findsOneWidget);
        expect(find.text('SUPPORT'), findsNothing);
        // Nothing was spent, because there was nothing to spend.
        expect(repo.exchangeCalls, isEmpty);
      },
    );

    testWidgets('spends the handoff exactly ONCE, then asks the server', (
      tester,
    ) async {
      final session = _session();
      final repo = _FakeSupportRepository(exchanged: session, live: session);
      await _pump(
        tester,
        SupportModeGate(
          repository: repo,
          handoffToken: 'tok-1',
          clock: () => DateTime(2026, 9, 3, 12, 5),
          onSupport: (_, _) => const Scaffold(body: Text('SUPPORT')),
          child: const Scaffold(body: Text('TENANT')),
        ),
      );
      expect(repo.exchangeCalls, ['tok-1']);
      // The exchange RESPONSE is a courtesy; the status read is the truth, so
      // it is always made.
      expect(repo.currentCalls, 1);
      expect(find.text('SUPPORT'), findsOneWidget);
      expect(find.text('TENANT'), findsNothing);
    });

    testWidgets('a DEAD handoff lands on the safe screen, never the tenant '
        'dashboard', (tester) async {
      final l10n = await strings();
      // Already used, expired, or never valid — the server answers all three
      // identically, and so must this.
      final repo = _FakeSupportRepository(exchanged: null, live: null);
      await _pump(
        tester,
        SupportModeGate(
          repository: repo,
          handoffToken: 'spent',
          onSupport: (_, _) => const Text('SUPPORT'),
          child: const Scaffold(body: Text('TENANT')),
        ),
      );
      expect(find.byKey(const Key('support-session-closed')), findsOneWidget);
      expect(find.text(l10n.supportModeClosedTitle), findsOneWidget);
      expect(find.text('TENANT'), findsNothing);
      expect(find.text('SUPPORT'), findsNothing);
    });

    testWidgets('ending the session replaces the dashboard immediately', (
      tester,
    ) async {
      final session = _session();
      final repo = _FakeSupportRepository(exchanged: session, live: session);
      await _pump(
        tester,
        SupportModeGate(
          repository: repo,
          handoffToken: 'tok-1',
          clock: () => DateTime(2026, 9, 3, 12, 5),
          onSupport: (_, _) => const Scaffold(body: Text('SUPPORT')),
          child: const Scaffold(body: Text('TENANT')),
        ),
      );
      expect(find.text('SUPPORT'), findsOneWidget);

      await tester.tap(find.byKey(const Key('support-mode-end')));
      await tester.pumpAndSettle();

      expect(repo.endCalls, 1);
      expect(find.byKey(const Key('support-session-closed')), findsOneWidget);
      // And it does NOT fall through to the tenant dashboard.
      expect(find.text('TENANT'), findsNothing);
      expect(find.text('SUPPORT'), findsNothing);
    });
  });

  group('C. the banner', () {
    testWidgets('names the mode, the tenant and the time left', (tester) async {
      final l10n = await strings();
      await _pump(
        tester,
        SupportModeScaffold(
          session: _session(restaurantName: 'Main Street'),
          clock: () => DateTime(2026, 9, 3, 12, 3, 30),
          onEnd: () async {},
          child: const Scaffold(body: Text('SUPPORT')),
        ),
      );
      expect(find.text(l10n.supportModeBanner), findsOneWidget);
      // The person being supported must be able to see WHOSE data is open.
      expect(find.text('Bistro Group · Main Street'), findsOneWidget);
      expect(find.text(l10n.supportModeExpiresIn('11:30')), findsOneWidget);
      expect(find.text(l10n.supportModeEnd), findsOneWidget);
      expect(find.text('SUPPORT'), findsOneWidget);
    });

    testWidgets('falls back to the organization when the session is org-wide', (
      tester,
    ) async {
      await _pump(
        tester,
        SupportModeScaffold(
          session: _session(),
          clock: () => DateTime(2026, 9, 3, 12, 0),
          onEnd: () async {},
          child: const Scaffold(body: Text('SUPPORT')),
        ),
      );
      expect(find.text('Bistro Group'), findsOneWidget);
    });

    testWidgets('an EXPIRED session replaces the dashboard with the safe '
        'screen', (tester) async {
      final l10n = await strings();
      await _pump(
        tester,
        SupportModeScaffold(
          session: _session(),
          // One second past the server-set expiry.
          clock: () => DateTime(2026, 9, 3, 12, 15, 1),
          onEnd: () async {},
          child: const Scaffold(body: Text('SUPPORT')),
        ),
      );
      expect(find.text(l10n.supportModeExpired), findsOneWidget);
      expect(find.byKey(const Key('support-session-closed')), findsOneWidget);
      // Leaving stale content on screen would look live while every server read
      // behind it was already being refused.
      expect(find.text('SUPPORT'), findsNothing);
    });

    testWidgets('publishes the support scope to the dashboard below', (
      tester,
    ) async {
      bool? seen;
      await _pump(
        tester,
        SupportModeScaffold(
          session: _session(),
          clock: () => DateTime(2026, 9, 3, 12, 0),
          onEnd: () async {},
          child: Builder(
            builder: (context) {
              seen = SupportModeScope.of(context);
              return const Scaffold(body: Text('SUPPORT'));
            },
          ),
        ),
      );
      expect(seen, isTrue);
    });

    testWidgets('the countdown ticks WITHOUT rebuilding the dashboard beneath '
        'it', (tester) async {
      // The banner counts down every second. If that second lived in the state
      // holding the Dashboard, every tick would mark the whole shell dirty —
      // the exact one-second whole-shell rebuild PERF-110 had to hunt down in
      // the kiosk. The countdown must repaint; the Dashboard must not.
      var now = DateTime(2026, 9, 3, 12, 5);
      final l10n = await strings();
      await _pump(
        tester,
        SupportModeScaffold(
          session: _session(),
          clock: () => now,
          onEnd: () async {},
          child: const _BuildCounter(),
        ),
      );
      expect(_BuildCounter.builds, 1);
      expect(find.text(l10n.supportModeExpiresIn('10:00')), findsOneWidget);
      // The scope wrapping the Dashboard, as constructed on the first frame.
      final scopeBefore = tester.widget<SupportModeScope>(
        find.byType(SupportModeScope),
      );

      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }

      // The clock moved and the banner says so...
      expect(find.text(l10n.supportModeExpiresIn('09:57')), findsOneWidget);
      // ...while the Dashboard's own wrapper is the SAME OBJECT it was three
      // seconds ago. This is the discriminating assertion: if the seconds were
      // held in the state above it, that state would have rebuilt and produced
      // a fresh wrapper each tick.
      expect(
        identical(
          scopeBefore,
          tester.widget<SupportModeScope>(find.byType(SupportModeScope)),
        ),
        isTrue,
      );
      expect(_BuildCounter.builds, 1);
      // And the banner is a SIBLING of the Dashboard, not an ancestor of it.
      expect(
        find.descendant(
          of: find.byType(SupportModeScope),
          matching: find.byKey(const Key('support-mode-banner')),
        ),
        findsNothing,
      );
    });

    testWidgets('reads correctly in Arabic and Hebrew', (tester) async {
      for (final locale in ['ar', 'he']) {
        final l10n = await strings(locale);
        await _pump(
          tester,
          SupportModeScaffold(
            session: _session(restaurantName: 'Main Street'),
            clock: () => DateTime(2026, 9, 3, 12, 5),
            onEnd: () async {},
            child: const Scaffold(body: Text('SUPPORT')),
          ),
          locale: locale,
        );
        expect(
          find.text(l10n.supportModeBanner),
          findsOneWidget,
          reason: 'the banner must be translated in $locale',
        );
        expect(find.text(l10n.supportModeEnd), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('lays out without overflowing at every supported width', (
      tester,
    ) async {
      for (final width in [390.0, 768.0, 1024.0, 1440.0]) {
        await _pump(
          tester,
          SupportModeScaffold(
            session: _session(restaurantName: 'Main Street'),
            clock: () => DateTime(2026, 9, 3, 12, 5),
            onEnd: () async {},
            child: const Scaffold(body: Text('SUPPORT')),
          ),
          size: Size(width, 900),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'the banner overflowed at ${width}px',
        );
        expect(find.byKey(const Key('support-mode-banner')), findsOneWidget);
      }
    });
  });

  group('D. what support mode is allowed to show', () {
    test('drops exactly the destinations with no approved support read', () {
      final supportVisible = DashboardDestination.visibleFor(supportMode: true);
      // Overview (the reports), Menu, Devices, Tables and Settings are backed by
      // the fifteen reads the server approved.
      expect(supportVisible, [
        DashboardDestination.overview,
        DashboardDestination.menu,
        DashboardDestination.devices,
        DashboardDestination.tables,
        DashboardDestination.settings,
      ]);
      // Staff, Users, Orders and Activity carry staff or customer identity and
      // were deliberately WITHHELD from support sessions, so their tabs go too.
      for (final dropped in [
        DashboardDestination.staff,
        DashboardDestination.users,
        DashboardDestination.orders,
        DashboardDestination.activity,
      ]) {
        expect(
          supportVisible.contains(dropped),
          isFalse,
          reason: '${dropped.name} has no approved support read',
        );
        expect(dropped.readableInSupportMode, isFalse);
      }
    });

    test('the ORDINARY tenant navigation is completely unchanged', () {
      // The whole feature must be invisible to a tenant. This is the assertion
      // that would fail if support mode ever leaked into the normal path.
      expect(DashboardDestination.visible, [
        DashboardDestination.overview,
        DashboardDestination.menu,
        DashboardDestination.devices,
        DashboardDestination.staff,
        DashboardDestination.tables,
        DashboardDestination.users,
        DashboardDestination.orders,
        DashboardDestination.activity,
        DashboardDestination.settings,
      ]);
      expect(
        DashboardDestination.visibleFor(),
        DashboardDestination.visible,
        reason: 'the default mode IS the tenant mode',
      );
    });

    test('the compacted index space stays consistent within each mode', () {
      // The bottom bar has no notion of a hidden destination, so a mismatch
      // between the two spaces would silently navigate to the wrong tab.
      for (final supportMode in [false, true]) {
        final visible = DashboardDestination.visibleFor(
          supportMode: supportMode,
        );
        for (var i = 0; i < visible.length; i++) {
          expect(
            visible[i].visibleIndexIn(supportMode: supportMode),
            i,
            reason: '${visible[i].name} at $i (supportMode=$supportMode)',
          );
        }
      }
      // A withheld destination has no position in the support space at all.
      expect(
        DashboardDestination.orders.visibleIndexIn(supportMode: true),
        isNull,
      );
      expect(
        DashboardDestination.orders.visibleIndexIn(),
        isNotNull,
        reason: 'and it is still there for a tenant',
      );
    });
  });

  group('E. the synthesized scope', () {
    test('carries the session target and NEVER a real membership id', () {
      final membership = supportMembershipFor(
        _session(restaurantName: 'Main Street'),
      );
      expect(membership.organizationId, 'org-1');
      expect(membership.restaurantId, 'rest-1');
      // The id is marked as synthetic on its face. A support session creates no
      // membership row, so there is no real id this could ever collide with.
      expect(membership.id, startsWith('support:'));
      expect(membership.role, MembershipRole.orgOwner);
    });

    test('an org-wide session has no restaurant, and does not invent one', () {
      final membership = supportMembershipFor(_session());
      expect(membership.restaurantId, isNull);
      expect(membership.branchId, isNull);
    });
  });

  group('F. the session model', () {
    test('is built only from an ACTIVE server answer', () {
      // Anything short of an explicit active session is no session. Parsing
      // leniently here would let a malformed answer look like access.
      expect(PlatformSupportSession.fromJson(null), isNull);
      expect(PlatformSupportSession.fromJson('nope'), isNull);
      expect(PlatformSupportSession.fromJson({'ok': false}), isNull);
      expect(
        PlatformSupportSession.fromJson({'ok': true, 'active': false}),
        isNull,
      );
      expect(
        PlatformSupportSession.fromJson({
          'ok': true,
          'active': true,
          'organization': {'id': 'o', 'name': 'O'},
          // No expiry => not a session we are willing to display.
        }),
        isNull,
      );
    });

    test('reads a complete answer', () {
      final session = PlatformSupportSession.fromJson({
        'ok': true,
        'active': true,
        'support_session_id': 's1',
        'reason': 'why',
        'expires_at': '2026-09-03T12:15:00Z',
        'organization': {'id': 'o1', 'name': 'Bistro Group'},
        'restaurant': {'id': 'r1', 'name': 'Main Street'},
      });
      expect(session, isNotNull);
      expect(session!.organizationName, 'Bistro Group');
      expect(session.restaurantName, 'Main Street');
      expect(session.targetLabel, 'Bistro Group · Main Street');
    });

    test('never reports negative time remaining', () {
      final session = _session();
      expect(session.remaining(DateTime(2026, 9, 3, 12, 5)).inMinutes, 10);
      expect(session.remaining(DateTime(2026, 9, 3, 13, 0)), Duration.zero);
    });
  });

  group('G. the handoff token survives a parent rebuild (126B2)', () {
    testWidgets('a rebuild that drops widget.handoffToken mid-exchange does not '
        'lose the token or flip the branch', (tester) async {
      // Reproduce the production defect: main.dart reads the fragment lazily
      // inside the supportGate closure, so a rebuild during the exchange passes
      // handoffToken=null. The gate must keep exchanging and land on the
      // support scaffold, never on the tenant child or the closed view.
      final repo = _FakeSupportRepository(
        exchanged: _session(restaurantName: 'Downtown'),
        live: _session(restaurantName: 'Downtown'),
      );
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      String? tokenFor(int build) =>
          build == 0 ? 'tok-1' : null; // lazy re-read

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, build, _) => SupportModeGate(
              repository: repo,
              handoffToken: tokenFor(build),
              onSupport: (context, session) => const _BuildCounter(),
              child: const Scaffold(body: Text('TENANT')),
            ),
          ),
        ),
      );
      // First frame: exchange is in flight; force the parent rebuild that used
      // to pass null and swap the spinner for the tenant child.
      rebuild.value = 1;
      await tester.pump();
      expect(
        find.text('TENANT'),
        findsNothing,
        reason: 'the tenant dashboard must not flash during the exchange',
      );
      await tester.pumpAndSettle();
      // The exchange still ran exactly once, with the captured token, and the
      // support scaffold is shown.
      expect(repo.exchangeCalls, ['tok-1']);
      expect(find.text('SUPPORT'), findsOneWidget);
      expect(find.text('TENANT'), findsNothing);
    });

    testWidgets('a spent handoff whose parent later passes null still lands on '
        'the closed view, not the tenant dashboard', (tester) async {
      final repo = _FakeSupportRepository(exchanged: null, live: null);
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      final l10n = await strings();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, build, _) => SupportModeGate(
              repository: repo,
              handoffToken: build == 0 ? 'spent' : null,
              onSupport: (context, session) => const _BuildCounter(),
              child: const Scaffold(body: Text('TENANT')),
            ),
          ),
        ),
      );
      rebuild.value = 1;
      await tester.pumpAndSettle();
      expect(find.text(l10n.supportModeClosedTitle), findsOneWidget);
      expect(find.text('TENANT'), findsNothing);
    });
  });

  group('I. withheld destinations stay unreadable in support mode (126B2)', () {
    test('Orders and Activity are the drill-down targets support withholds', () {
      // The Overview KPI drill-downs target these; the shell suppresses a
      // support-mode drill-down by consulting exactly this flag (the same one
      // that drops their rail tiles), so a silent flip to readable would break
      // both the rail AND the drill-down guard together — and this pins it.
      expect(DashboardDestination.orders.readableInSupportMode, isFalse);
      expect(DashboardDestination.activity.readableInSupportMode, isFalse);
      expect(DashboardDestination.staff.readableInSupportMode, isFalse);
      expect(DashboardDestination.users.readableInSupportMode, isFalse);
      // Overview and the report/catalog surfaces stay reachable.
      expect(DashboardDestination.overview.readableInSupportMode, isTrue);
      expect(DashboardDestination.menu.readableInSupportMode, isTrue);
      expect(DashboardDestination.tables.readableInSupportMode, isTrue);
    });
  });

  group('H. the banner shows the typed reason (126B2)', () {
    testWidgets('the reason is rendered so tenant staff can see why', (
      tester,
    ) async {
      final l10n = await strings();
      await _pump(
        tester,
        SupportModeScaffold(
          session: _session(restaurantName: 'Downtown'),
          onEnd: () async {},
          clock: () => DateTime(2026, 9, 3, 12, 5),
          child: const _BuildCounter(),
        ),
      );
      expect(find.byKey(const Key('support-mode-reason')), findsOneWidget);
      expect(
        find.text(
          l10n.supportModeReason(
            'investigating a reported missing sales figure',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ar: the reason renders RTL without overflow', (tester) async {
      await _pump(
        tester,
        SupportModeScaffold(
          session: _session(restaurantName: 'وسط البلد'),
          onEnd: () async {},
          clock: () => DateTime(2026, 9, 3, 12, 5),
          child: const _BuildCounter(),
        ),
        locale: 'ar',
        size: const Size(430, 900),
      );
      expect(find.byKey(const Key('support-mode-reason')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Counts how many times the widget standing in for the Dashboard is built.
class _BuildCounter extends StatelessWidget {
  const _BuildCounter();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return const Scaffold(body: Text('SUPPORT'));
  }
}
