import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-E1) — the Overview scope selector.
///
/// What these defend: a broad owner SEES that they are looking at everything
/// they are permitted to see, a scope-limited user is never shown a choice that
/// does not exist, and a failed option load never quietly picks a branch.

class _FixedOptions implements AuditFilterOptionsRepository {
  const _FixedOptions(this.branches);

  final List<AuditBranchOption> branches;

  @override
  Future<List<AuditBranchOption>> loadBranches() async => branches;

  @override
  Future<List<AuditActorOption>> loadActors() async => const [];
}

class _FailingOptions implements AuditFilterOptionsRepository {
  const _FailingOptions();

  // CODEX F-1B-3 FOLLOW-UP: a failure is a FAILURE. This fake used to return an
  // empty list "because the real repository fails soft", which is exactly the
  // conflation that let a failed enumeration widen the analytics scope. The
  // real repository now reports it, so the fake does too.
  @override
  Future<List<AuditBranchOption>> loadBranches() async =>
      throw const AuditFilterOptionsException('branch options unavailable');

  @override
  Future<List<AuditActorOption>> loadActors() async => const [];
}

const _branches = <AuditBranchOption>[
  AuditBranchOption(
    organizationId: 'org-1',
    branchId: 'branch-1',
    restaurantId: 'rest-1',
    label: 'Rest One · Main',
  ),
  AuditBranchOption(
    organizationId: 'org-1',
    branchId: 'branch-2',
    restaurantId: 'rest-1',
    label: 'Rest One · Harbor',
  ),
  AuditBranchOption(
    organizationId: 'org-1',
    branchId: 'branch-9',
    restaurantId: 'rest-2',
    label: 'Rest Two · Main',
  ),
];

MembershipContext _membership(MembershipRole role) => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest One',
  branchId: 'branch-1',
  branchName: 'Main',
  role: role,
  status: 'active',
);

Widget _wrap({
  required MembershipRole role,
  Locale locale = const Locale('en'),
  AuditFilterOptionsRepository options = const _FixedOptions(_branches),
  Widget? home,
}) => ProviderScope(
  overrides: [
    dashboardMembershipProvider.overrideWithValue(_membership(role)),
    auditFilterOptionsRepositoryProvider.overrideWithValue(options),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: home ?? const DashboardHomeScreen(),
  ),
);

void _size(WidgetTester tester, [Size size = const Size(1320, 3400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Opens the selector and returns the distinct option VALUES it offers.
///
/// The dropdown must be OPENED first: a closed DropdownButtonFormField renders
/// only its selected item, so reading the tree while it is shut would assert
/// nothing about what an owner can actually choose. The button keeps its own
/// copy of the selected item on screen behind the menu, so values are
/// de-duplicated.
Future<Set<String?>> _openOptions(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('overview-scope-selector')));
  await tester.pumpAndSettle();
  return tester
      .widgetList<DropdownMenuItem<String?>>(
        find.byType(DropdownMenuItem<String?>),
      )
      .map((i) => i.value)
      .toSet();
}

/// The value the selector is currently sitting on.
String? _selectedValue(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<String?>>(
      find.byKey(const Key('overview-scope-selector')),
    )
    .initialValue;

void main() {
  group('what each membership kind is offered', () {
    testWidgets('an ORG owner sees "All permitted branches" and every '
        'authorized branch, starting broad', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(role: MembershipRole.orgOwner));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overview-scope-selector')), findsOneWidget);
      expect(find.text('All permitted branches'), findsWidgets);
      // Broad by default — NOT the first branch.
      final field = tester.widget<DropdownButtonFormField<String?>>(
        find.byKey(const Key('overview-scope-selector')),
      );
      expect(field.initialValue, isNull);
      expect(await _openOptions(tester), {
        null,
        'branch-1',
        'branch-2',
        'branch-9',
      });
    });

    testWidgets('a RESTAURANT owner is offered only their own restaurant\'s '
        'branches', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(role: MembershipRole.restaurantOwner));
      await tester.pumpAndSettle();

      final options = await _openOptions(tester);
      expect(options, {null, 'branch-1', 'branch-2'});
      expect(
        options,
        isNot(contains('branch-9')),
        reason: 'branch-9 belongs to a sibling restaurant',
      );
    });

    testWidgets('a BRANCH-scoped user gets a read-only label — no dropdown and '
        'no fake "all" option', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(role: MembershipRole.manager));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overview-scope-selector')), findsNothing);
      expect(find.byKey(const Key('overview-scope-fixed')), findsOneWidget);
      expect(find.text('Branch: Main'), findsOneWidget);
      expect(find.text('All permitted branches'), findsNothing);
    });

    testWidgets('DEMO mode (no membership) shows no scope control at all', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: const DashboardHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overview-scope-selector')), findsNothing);
      expect(find.byKey(const Key('overview-scope-fixed')), findsNothing);
    });
  });

  group('selecting a scope', () {
    testWidgets('choosing a branch changes the report key, and choosing "all" '
        'returns to the broad scope', (tester) async {
      _size(tester);
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(
              _membership(MembershipRole.orgOwner),
            ),
            auditFilterOptionsRepositoryProvider.overrideWithValue(
              const _FixedOptions(_branches),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
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

      expect(container.read(currentOwnerReportKeyProvider).branchId, isNull);

      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest Two · Main').last);
      await tester.pumpAndSettle();

      final key = container.read(currentOwnerReportKeyProvider);
      expect(key.branchId, 'branch-9');
      expect(key.restaurantId, 'rest-2', reason: 'both ids, from the option');

      // ...and back to broad.
      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All permitted branches').last);
      await tester.pumpAndSettle();

      expect(container.read(currentOwnerReportKeyProvider).branchId, isNull);
    });

    testWidgets('no raw UUID-looking id is shown — options carry real names', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_wrap(role: MembershipRole.orgOwner));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('overview-scope-selector')));
      await tester.pumpAndSettle();

      for (final id in const ['branch-1', 'branch-2', 'branch-9', 'rest-1']) {
        expect(find.text(id), findsNothing, reason: '$id must not be shown');
      }
      // Identical branch names across restaurants stay distinguishable.
      expect(find.text('Rest One · Main'), findsWidgets);
      expect(find.text('Rest Two · Main'), findsWidgets);
    });

    testWidgets('a FAILED option load leaves the broad scope and offers no '
        'branches — it never picks one', (tester) async {
      _size(tester);
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardMembershipProvider.overrideWithValue(
              _membership(MembershipRole.orgOwner),
            ),
            auditFilterOptionsRepositoryProvider.overrideWithValue(
              const _FailingOptions(),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
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

      expect(await _openOptions(tester), {null});
      final key = container.read(currentOwnerReportKeyProvider);
      expect(key.branchId, isNull);
      expect(key.restaurantId, isNull);
    });
  });

  testWidgets('the chosen scope survives leaving Overview and coming back', (
    tester,
  ) async {
    // Phone width so the keyed bottom NavigationBar renders.
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Asserted through the UI rather than through an outer ProviderContainer:
    // the shell builds its OWN hoisted ProviderScope for the shared dashboard
    // providers, so the selection lives in THAT container. Reading an outer
    // one would test a copy nobody looks at. What matters to an owner is that
    // the control still shows their choice when they come back.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          auditFilterOptionsRepositoryProvider.overrideWithValue(
            const _FixedOptions(_branches),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          theme: restoflowBaseTheme(),
          home: DashboardShell(
            membership: _membership(MembershipRole.orgOwner),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_selectedValue(tester), isNull, reason: 'starts broad');

    await tester.tap(find.byKey(const Key('overview-scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rest One · Harbor').last);
    await tester.pumpAndSettle();
    expect(_selectedValue(tester), 'branch-2');

    final nav = () => tester.widget<NavigationBar>(
      find.byKey(const Key('dashboard-bottom-nav')),
    );
    nav().onDestinationSelected!(DashboardDestination.orders.visibleIndex!);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reports-heading')),
      findsNothing,
      reason: 'the Overview subtree really was torn down',
    );

    nav().onDestinationSelected!(DashboardDestination.overview.visibleIndex!);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reports-heading')), findsOneWidget);
    expect(
      _selectedValue(tester),
      'branch-2',
      reason: 'the chosen scope is session state, not subtree state',
    );
  });

  group('layout', () {
    testWidgets('renders at phone width without overflow', (tester) async {
      _size(tester, const Size(390, 4200));
      await tester.pumpWidget(_wrap(role: MembershipRole.orgOwner));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('overview-scope-selector')), findsOneWidget);
    });

    testWidgets('survives a 2x text scale at phone width', (tester) async {
      _size(tester, const Size(390, 5600));
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_wrap(role: MembershipRole.orgOwner));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('overview-scope-selector')), findsOneWidget);
    });

    for (final locale in const [Locale('ar'), Locale('he')]) {
      testWidgets('renders RTL (${locale.languageCode})', (tester) async {
        _size(tester, const Size(390, 4200));
        await tester.pumpWidget(
          _wrap(role: MembershipRole.orgOwner, locale: locale),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('overview-scope-selector'))),
          ),
          TextDirection.rtl,
        );
      });
    }
  });
}
