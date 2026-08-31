/// ADMIN-126B — the console's "Open Dashboard" action.
///
/// The property under test is that this button is what it says it is: a request
/// for a short, audited, read-only support session against ONE named tenant —
/// not a login, not an impersonation, and not something that can happen without
/// an operator typing a reason first.
///
/// The server is the authority on all of that (see
/// `platform_support_sessions_126b_test.sql`). These tests cover the half the
/// server cannot: that the console asks correctly, hands the one-time token
/// straight to the Dashboard without keeping or displaying it, and fails
/// honestly when the answer is no.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/support_access.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'console_test_harness.dart';

/// Records what the console asked for, and answers with a fixed handoff.
class _RecordingLauncher implements PlatformSupportLauncher {
  _RecordingLauncher({this.failure});

  final PlatformAdminException? failure;

  final List<String> organizationIds = [];
  final List<String?> restaurantIds = [];
  final List<String> reasons = [];

  @override
  Future<SupportHandoff> start({
    required String organizationId,
    String? restaurantId,
    required String reason,
  }) async {
    organizationIds.add(organizationId);
    restaurantIds.add(restaurantId);
    reasons.add(reason);
    final f = failure;
    if (f != null) throw f;
    return const SupportHandoff(
      supportSessionId: 'sup-1',
      handoffToken: 'TOKEN-abc123',
      organizationName: 'Bistro Group',
      restaurantName: 'Main Street',
    );
  }
}

/// Opens the Restaurants page and starts a session on its first row.
Future<void> _openFirstRestaurantSupport(
  WidgetTester tester, {
  String reason = 'checking a reported missing sales figure',
  bool confirm = true,
}) async {
  final l10n = await englishStrings();
  await goToSection(tester, l10n.adminNavRestaurants);
  await tester.tap(find.byIcon(Icons.open_in_new).first);
  await tester.pumpAndSettle();
  if (!confirm) return;
  await tester.enterText(find.byKey(const Key('support-reason-field')), reason);
  await tester.tap(find.byKey(const Key('support-reason-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the action is offered on every restaurant row', (tester) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp());
    await tester.pumpAndSettle();
    await goToSection(tester, l10n.adminNavRestaurants);

    expect(find.byIcon(Icons.open_in_new), findsWidgets);
    // It is an ACTION on a row, not a navigation destination of its own.
    expect(find.text(l10n.adminOpenDashboard), findsNothing);
  });

  testWidgets('nothing happens until a reason is typed', (tester) async {
    useSize(tester, kDesktop);
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(consoleApp(supportLauncher: launcher));
    await tester.pumpAndSettle();
    await _openFirstRestaurantSupport(tester, confirm: false);

    final l10n = await englishStrings();
    expect(find.byKey(const Key('support-reason-dialog')), findsOneWidget);
    expect(find.text(l10n.adminSupportDialogBody), findsOneWidget);

    // Confirming with an EMPTY reason must not open a session: the server would
    // refuse it, and the audit log would be the poorer for it either way.
    await tester.tap(find.byKey(const Key('support-reason-confirm')));
    await tester.pumpAndSettle();
    expect(launcher.reasons, isEmpty);
    expect(find.text(l10n.adminSupportReasonRequired), findsOneWidget);
    expect(find.byKey(const Key('support-reason-dialog')), findsOneWidget);

    // And cancelling closes it without asking for anything.
    await tester.tap(find.byKey(const Key('support-reason-cancel')));
    await tester.pumpAndSettle();
    expect(launcher.reasons, isEmpty);
    expect(find.byKey(const Key('support-reason-dialog')), findsNothing);
  });

  testWidgets('a confirmed start carries the typed reason and the exact '
      'target', (tester) async {
    useSize(tester, kDesktop);
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(consoleApp(supportLauncher: launcher));
    await tester.pumpAndSettle();
    await _openFirstRestaurantSupport(tester, reason: 'owner reported a gap');

    expect(launcher.reasons, hasLength(1));
    // The operator's own words survive into the request; the prefix only says
    // what kind of access it is.
    expect(launcher.reasons.single, contains('owner reported a gap'));
    expect(launcher.organizationIds, hasLength(1));
    // Scoped to ONE restaurant, not the whole organization, because that is
    // what the operator clicked.
    expect(launcher.restaurantIds.single, isNotNull);
  });

  testWidgets('the handoff goes into the URL FRAGMENT and is never displayed', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final opened = <String>[];
    await tester.pumpWidget(
      consoleApp(
        supportLauncher: _RecordingLauncher(),
        openUrl: opened.add,
        dashboardUrl: 'https://dashboard.test',
      ),
    );
    await tester.pumpAndSettle();
    await _openFirstRestaurantSupport(tester);

    expect(opened, hasLength(1));
    final url = opened.single;
    expect(url, 'https://dashboard.test/#support=TOKEN-abc123');
    // A fragment is never sent to a server: it cannot reach an access log, a
    // proxy trace, or a Referer header.
    expect(url.split('#').first, isNot(contains('TOKEN')));
    expect(Uri.parse(url).queryParameters, isEmpty);
    // And the token is nowhere on screen — not in a field, a label or a snack.
    expect(find.textContaining('TOKEN'), findsNothing);
    expect(find.textContaining('abc123'), findsNothing);

    final l10n = await englishStrings();
    expect(find.text(l10n.adminSupportStarted), findsOneWidget);
  });

  testWidgets('a trailing slash on the Dashboard URL is not doubled', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final opened = <String>[];
    await tester.pumpWidget(
      consoleApp(
        supportLauncher: _RecordingLauncher(),
        openUrl: opened.add,
        dashboardUrl: 'https://dashboard.test/',
      ),
    );
    await tester.pumpAndSettle();
    await _openFirstRestaurantSupport(tester);
    expect(opened.single, 'https://dashboard.test/#support=TOKEN-abc123');
  });

  testWidgets('a refused session says so, and opens nothing', (tester) async {
    useSize(tester, kDesktop);
    final opened = <String>[];
    final launcher = _RecordingLauncher(
      failure: const PlatformAdminException(
        'denied',
        kind: PlatformAdminErrorKind.accessDenied,
      ),
    );
    await tester.pumpWidget(
      consoleApp(supportLauncher: launcher, openUrl: opened.add),
    );
    await tester.pumpAndSettle();
    await _openFirstRestaurantSupport(tester);

    final l10n = await englishStrings();
    expect(find.text(l10n.adminSupportFailed), findsOneWidget);
    expect(opened, isEmpty, reason: 'a refused session must open no tab');
    // The developer-facing message never reaches the operator.
    expect(find.textContaining('denied'), findsNothing);
  });

  testWidgets('DEMO mode refuses honestly rather than fabricating a session', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final opened = <String>[];
    // The default launcher in demo mode is the one that refuses.
    await tester.pumpWidget(consoleApp(openUrl: opened.add));
    await tester.pumpAndSettle();
    await _openFirstRestaurantSupport(tester);

    final l10n = await englishStrings();
    expect(find.text(l10n.adminSupportUnavailable), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('the subscriber detail offers an ORGANIZATION-wide session', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(consoleApp(supportLauncher: launcher));
    await tester.pumpAndSettle();
    await goToSection(tester, l10n.adminNavSubscribers);
    await tester.tap(find.text('Bistro Group'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.adminOpenDashboard).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('support-reason-field')),
      'billing question',
    );
    await tester.tap(find.byKey(const Key('support-reason-confirm')));
    await tester.pumpAndSettle();

    expect(launcher.organizationIds, hasLength(1));
    // No restaurant: the operator asked for the organization.
    expect(launcher.restaurantIds.single, isNull);
  });

  testWidgets('the dialog states the target and that it is read-only', (
    tester,
  ) async {
    useSize(tester, kDesktop);
    final l10n = await englishStrings();
    await tester.pumpWidget(consoleApp(supportLauncher: _RecordingLauncher()));
    await tester.pumpAndSettle();
    await _openFirstRestaurantSupport(tester, confirm: false);

    expect(find.byKey(const Key('support-dialog-target')), findsOneWidget);
    expect(find.text(l10n.adminSupportDialogBody), findsOneWidget);
    // The word that must NEVER appear on this path.
    expect(find.textContaining('Impersonate'), findsNothing);
  });

  testWidgets('the action and its dialog survive every width and locale', (
    tester,
  ) async {
    for (final size in [kPhone, kTablet, kLaptop, kDesktop]) {
      for (final locale in ['en', 'ar', 'he']) {
        useSize(tester, size);
        await tester.pumpWidget(
          consoleApp(
            locale: Locale(locale),
            supportLauncher: _RecordingLauncher(),
          ),
        );
        await tester.pumpAndSettle();
        final strings = await AppLocalizations.delegate.load(Locale(locale));
        await goToSection(tester, strings.adminNavRestaurants);
        await tester.tap(find.byIcon(Icons.open_in_new).first);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('support-reason-dialog')),
          findsOneWidget,
          reason: 'dialog missing at ${size.width}px in $locale',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${size.width}px in $locale',
        );
        await tester.tap(find.byKey(const Key('support-reason-cancel')));
        await tester.pumpAndSettle();
      }
    }
  });
}
