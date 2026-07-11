import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/activity/activity_log_screen.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_repository.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// AUDIT-LOG-DASHBOARD-001 — the Activity-log surface: rows / empty / error /
/// loading, range + category + sensitive filters, "load more", the read-only
/// detail dialog (safe fields, NO edit/delete/retry, no raw secret), and RTL.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

DemoAuditEvent _ev(
  String id, {
  required String action,
  required String category,
  int daysAgo = 0,
  String? reason,
  Map<String, Object?> newValues = const {},
}) => DemoAuditEvent(
  daysAgo: daysAgo,
  event: AuditEvent(
    eventId: id,
    action: action,
    category: category,
    occurredAtLabel: '14:00',
    actorName: 'Amira',
    restaurantName: 'Rest 1',
    branchName: 'Downtown',
    reason: reason,
    newValues: newValues,
  ),
);

Widget _wrap(
  AuditLogRepository repo, {
  bool demo = true,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: demo),
    ),
    auditLogRepositoryProvider.overrideWithValue(repo),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: ActivityLogScreen()),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ActivityLogScreen)));

void main() {
  testWidgets('D45 renders demo events and the demo banner', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(_wrap(DemoAuditLogRepository()));
    await tester.pumpAndSettle();

    expect(find.text(l10n.activityLogDemoNotice), findsOneWidget);
    expect(find.byKey(const Key('activity-card-demo-ae-1')), findsOneWidget);
    expect(find.text(l10n.activityLogTitleOrderVoided), findsWidgets);
    expect(find.byKey(const Key('activity-empty')), findsNothing);
  });

  testWidgets('D46 empty state when no events match', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(_wrap(DemoAuditLogRepository(events: const [])));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-empty')), findsOneWidget);
    expect(find.text(l10n.activityLogEmpty), findsOneWidget);
  });

  testWidgets('D47 error state on a failing repository', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(DemoAuditLogRepository(failureMessage: 'boom')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-error')), findsOneWidget);
  });

  testWidgets('D48 range chip switches the window', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(DemoAuditLogRepository()));
    await tester.pumpAndSettle();
    // Today shows the void; yesterday's shift-close is hidden.
    expect(find.byKey(const Key('activity-card-demo-ae-1')), findsOneWidget);
    expect(find.byKey(const Key('activity-card-demo-ae-6')), findsNothing);

    await tester.tap(find.byKey(const Key('activity-range-yesterday')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-card-demo-ae-1')), findsNothing);
    expect(find.byKey(const Key('activity-card-demo-ae-6')), findsOneWidget);
  });

  testWidgets('D49 category filter narrows the list', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(DemoAuditLogRepository()));
    await tester.pumpAndSettle();
    // Default today: both a void (ae-1) and a discount (ae-2) show.
    expect(find.byKey(const Key('activity-card-demo-ae-1')), findsOneWidget);
    expect(find.byKey(const Key('activity-card-demo-ae-2')), findsOneWidget);

    _container(tester).read(auditLogQueryProvider.notifier).state =
        const AuditQuery(category: AuditCategory.voids);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activity-card-demo-ae-1')), findsOneWidget);
    expect(find.byKey(const Key('activity-card-demo-ae-2')), findsNothing);
  });

  testWidgets('D50 sensitive-only toggle hides non-sensitive events', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(
        DemoAuditLogRepository(
          events: [
            _ev('sens', action: 'order.voided', category: 'voids'),
            _ev('plain', action: 'order.submitted', category: 'orders'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-card-sens')), findsOneWidget);
    expect(find.byKey(const Key('activity-card-plain')), findsOneWidget);

    await tester.tap(find.byKey(const Key('activity-sensitive-only')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activity-card-sens')), findsOneWidget);
    expect(find.byKey(const Key('activity-card-plain')), findsNothing);
  });

  testWidgets('D51 load-more appends the next keyset page', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(
        DemoAuditLogRepository(
          pageSize: 1,
          events: [
            _ev('a', action: 'order.voided', category: 'voids'),
            _ev('b', action: 'order.voided', category: 'voids'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-card-a')), findsOneWidget);
    expect(find.byKey(const Key('activity-card-b')), findsNothing);
    expect(find.byKey(const Key('activity-load-more')), findsOneWidget);

    await tester.tap(find.byKey(const Key('activity-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-card-b')), findsOneWidget);
    expect(l10n.activityLogLoadMore, isNotEmpty);
  });

  testWidgets('D52 detail dialog shows safe fields, NO edit/delete, no secret', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(
        DemoAuditLogRepository(
          events: [
            _ev(
              'x',
              action: 'staff.pin_set',
              category: 'staff',
              reason: 'Onboarding',
              // A smuggled secret must never render in the dialog.
              newValues: {'pin_set': true, 'pin_hash': r'$2b$SUPERSECRET'},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('activity-card-x')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const Key('activity-detail-dialog'));
    expect(dialog, findsOneWidget);
    expect(find.text('Onboarding'), findsOneWidget); // reason surfaced
    // Read-only: the dialog has NO edit / delete / retry affordances (its only
    // action is close). The list "refresh" behind it is a re-fetch, not a
    // mutation, so it is deliberately not asserted against here.
    expect(
      find.descendant(of: dialog, matching: find.byIcon(Icons.delete)),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.byIcon(Icons.edit)),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.byIcon(Icons.refresh)),
      findsNothing,
    );
    expect(find.byKey(const Key('activity-detail-close')), findsOneWidget);
    // No raw secret leaks into the dialog.
    expect(find.textContaining('SUPERSECRET'), findsNothing);
    expect(l10n.activityLogClose, isNotEmpty);
  });

  testWidgets('D53 RTL: Arabic renders right-to-left with localized chrome', (
    tester,
  ) async {
    _wide(tester);
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    await tester.pumpWidget(
      _wrap(DemoAuditLogRepository(), locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();

    final dir = Directionality.of(
      tester.element(find.byType(ActivityLogScreen)),
    );
    expect(dir, TextDirection.rtl);
    expect(find.text(ar.activityLogTitle), findsWidgets);
  });

  testWidgets('D66 branch filter renders "All permitted branches" + options', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(_wrap(DemoAuditLogRepository()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-branch-filter')), findsOneWidget);
    expect(find.text(l10n.activityLogBranchAll), findsWidgets);
  });

  testWidgets('D67 actor filter renders "All staff" + demo staff options', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(_wrap(DemoAuditLogRepository()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-actor-filter')), findsOneWidget);
    expect(find.text(l10n.activityLogActorAll), findsWidgets);
    // Open the actor dropdown; a demo staff name is offered as an option.
    await tester.tap(find.byKey(const Key('activity-actor-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Amira'), findsWidgets);
  });

  testWidgets('D68 selecting a branch preserves other filters and reloads', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(DemoAuditLogRepository()));
    await tester.pumpAndSettle();
    final container = _container(tester);
    // Set a category filter first, then a branch.
    container.read(auditLogQueryProvider.notifier).state = const AuditQuery(
      category: AuditCategory.voids,
    );
    await tester.pumpAndSettle();
    container.read(auditLogQueryProvider.notifier).state = container
        .read(auditLogQueryProvider)
        .copyWith(
          branch: const AuditBranchOption(
            branchId: 'demo-branch-harbor',
            restaurantId: 'demo-rest-1',
            label: 'RestoFlow · Harbor',
          ),
        );
    await tester.pumpAndSettle();
    final q = container.read(auditLogQueryProvider);
    // Both filters coexist; the list re-loaded (not in error/loading).
    expect(q.category, AuditCategory.voids);
    expect(q.branch?.branchId, 'demo-branch-harbor');
    final state = container.read(auditLogControllerProvider);
    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.cursor, isNull); // pagination reset for the new query
  });

  testWidgets('D69 RTL narrow width: filter bar wraps without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrap(DemoAuditLogRepository(), locale: const Locale('he')),
    );
    await tester.pumpAndSettle();
    // A RenderFlex overflow would have thrown during layout/settle.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('activity-branch-filter')), findsOneWidget);
  });
}
