/// STOREFRONT-INTEGRATE-001 + STOREFRONT-PRODUCTION-ENABLE-001 - the
/// Storefront editor's build gate and its activation guard.
///
/// A stock build (CI passes no `--dart-define`) has the gate CLOSED: the real
/// shell builds no Storefront seams, sends no Storefront RPC, never invokes the
/// media function, and Settings shows NO Storefront card (the old "not
/// connected" card is gone). Opening the gate (the constructor seam) wires the
/// SAME shell and shows the editor to an org owner, a restaurant owner and a
/// manager, which proves the closed case is not vacuous. Platform support mode
/// gets no seams and no card even with the gate open, a role the server
/// refuses gets no editor, and every Dashboard destination still navigates and
/// renders either way. The production web build passes the gate to the
/// Dashboard only, `true` only in a Vercel Production build whose variable is
/// exactly `true`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_dark_gate.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_section.dart';
import 'package:restoflow_dashboard/src/support/support_mode_scope.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const String _rest = 'rest-1';

const Set<String> _storefrontRpcs = <String>{
  SupabaseStorefrontProfileRepository.readFunction,
  SupabaseStorefrontProfileRepository.writeFunction,
  SupabaseStorefrontMediaRepository.listFunction,
  SupabaseStorefrontMediaRepository.retractFunction,
  SupabaseStorefrontMediaRepository.cancelFunction,
};

const SyncTransportException _offline = SyncTransportException(
  SyncTransportErrorKind.transient,
  code: '503',
  message: 'not under test',
);

/// Every RPC answers "transient"; only WHICH functions were asked matters.
class _OfflineTransport implements SyncRpcTransport {
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    throw _offline;
  }
}

/// A manager-rank caller of a restaurant with no storefront profile yet: the
/// profile read answers the real "no profile yet" envelope (API_CONTRACT
/// §4.42.3), everything else is offline. The editor then shows its create
/// form.
class _ManagerTransport implements SyncRpcTransport {
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    if (function == SupabaseStorefrontProfileRepository.readFunction) {
      return const {
        'ok': true,
        'entity': 'restaurant_storefront_profile',
        'restaurant_id': _rest,
        'exists': false,
        'version': 0,
        'profile': null,
        'derived': {
          'timezone': 'Asia/Jerusalem',
          'currency_code': 'ILS',
          'tax': {'enabled': false, 'rate_bp': 0, 'mode': 'exclusive'},
          'publish_ready': false,
          'publish_blockers': ['slug_missing', 'branch_missing'],
          'media_prefix': '0123456789abcdef0123456789abcdef',
        },
      };
    }
    throw _offline;
  }
}

/// The server's verdict for a caller below manager rank: the profile read and
/// the media list answer the uniform `not_found` (API_CONTRACT §4.42.3 /
/// §4.43.5); everything else is offline.
class _RefusingTransport implements SyncRpcTransport {
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    if (function == SupabaseStorefrontProfileRepository.readFunction) {
      return const {
        'ok': false,
        'error': 'not_found',
        'entity': 'restaurant_storefront_profile',
      };
    }
    if (function == SupabaseStorefrontMediaRepository.listFunction) {
      return const {
        'ok': false,
        'error': 'not_found',
        'entity': 'storefront_media',
      };
    }
    throw _offline;
  }
}

/// Counts every attempt to reach `storefront-media-publish`.
class _CountingInvoker implements StorefrontFunctionInvoker {
  int calls = 0;

  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    calls++;
    return const StorefrontFunctionReply.transportFailure();
  }
}

MembershipContext _member(MembershipRole role) => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: _rest,
  restaurantName: 'Restaurant 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: role,
  status: 'active',
);

Widget _app(
  SyncRpcTransport transport,
  StorefrontFunctionInvoker invoker, {
  bool? enabled,
  bool supportMode = false,
  MembershipRole role = MembershipRole.orgOwner,
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: false),
    ),
  ],
  child: SupportModeScope(
    active: supportMode,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      theme: restoflowBaseTheme(),
      home: enabled == null
          // The production shape: the gate keeps its compile-time default.
          ? DashboardShell(
              membership: _member(role),
              currencyCode: 'ILS',
              reportsTransport: transport,
              storefrontFunctionInvoker: invoker,
            )
          : DashboardShell(
              membership: _member(role),
              currencyCode: 'ILS',
              reportsTransport: transport,
              storefrontFunctionInvoker: invoker,
              storefrontEditorEnabled: enabled,
            ),
    ),
  ),
);

Future<void> _pumpShell(
  WidgetTester tester,
  Widget app, {
  Size size = const Size(1400, 2200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('dashboard-side-rail')),
      matching: find.text(l10n.dashboardNavSettings),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(RealSettingsView), findsOneWidget);
}

/// Scrolls the lazy Settings list until the Storefront card is built.
Future<void> _revealStorefront(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('storefront-section')),
    300,
    scrollable: find
        .descendant(
          of: find.byType(RealSettingsView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// The Storefront card's place in Settings is between the receipt-branding
/// card and the kitchen-workflow card. With BOTH neighbours built (including
/// offstage), the lazy list has built that place too, so an absent card is a
/// real absence and not an unbuilt part of the list.
void _expectNoStorefrontCardWithNeighboursBuilt(AppLocalizations l10n) {
  expect(
    find.text(l10n.brandingSectionTitle, skipOffstage: false),
    findsOneWidget,
  );
  expect(
    find.text(l10n.dashboardKitchenWorkflowSectionTitle, skipOffstage: false),
    findsOneWidget,
  );
  expect(find.byType(StorefrontSection, skipOffstage: false), findsNothing);
  expect(
    find.byKey(const Key('storefront-section'), skipOffstage: false),
    findsNothing,
  );
  expect(
    find.byKey(const Key('storefront-unavailable'), skipOffstage: false),
    findsNothing,
  );
  expect(
    find.text(l10n.storefrontUnavailableNote, skipOffstage: false),
    findsNothing,
  );
}

File _repoFile(String rel) {
  for (final prefix in ['', '../../', '../']) {
    final f = File('$prefix$rel');
    if (f.existsSync()) return f;
  }
  fail('cannot find $rel (cwd: ${Directory.current.path})');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('the gate is compile-time FALSE in a stock build', () {
    expect(kStorefrontEditorEnabled, isFalse);
  });

  testWidgets('CLOSED by default: no Storefront card at all, no seams, no '
      'Storefront RPC and no function call', (tester) async {
    final transport = _OfflineTransport();
    final invoker = _CountingInvoker();

    // A tall view: the whole Settings list is built without scrolling.
    await _pumpShell(
      tester,
      _app(transport, invoker),
      size: const Size(1400, 4000),
    );
    await _openSettings(tester, l10n);
    expect(
      tester
          .widget<RealSettingsView>(find.byType(RealSettingsView))
          .storefrontSeams,
      isNull,
    );

    _expectNoStorefrontCardWithNeighboursBuilt(l10n);
    expect(transport.calls.where(_storefrontRpcs.contains), isEmpty);
    expect(invoker.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final role in const [
    MembershipRole.orgOwner,
    MembershipRole.restaurantOwner,
    MembershipRole.manager,
  ]) {
    testWidgets('OPEN for a normal ${role.name}: the same shell shows the '
        'editor', (tester) async {
      final transport = _ManagerTransport();
      final invoker = _CountingInvoker();

      await _pumpShell(
        tester,
        _app(transport, invoker, enabled: true, role: role),
      );
      await _openSettings(tester, l10n);
      final seams = tester
          .widget<RealSettingsView>(find.byType(RealSettingsView))
          .storefrontSeams;
      expect(seams, isNotNull);
      expect(seams!.publisher, isNotNull);
      await _revealStorefront(tester);

      // The editor itself: the create form of a restaurant with no profile.
      expect(
        transport.calls,
        contains(SupabaseStorefrontProfileRepository.readFunction),
      );
      expect(find.byKey(const Key('storefront-slug')), findsOneWidget);
      expect(find.byKey(const Key('storefront-display-name')), findsOneWidget);
      for (final key in const [
        'storefront-unavailable',
        'storefront-denied',
        'storefront-load-failed',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('OPEN in platform support mode: the editor cannot be reached - '
      'no card, no seams, no Storefront RPC and no function call', (
    tester,
  ) async {
    final transport = _ManagerTransport();
    final invoker = _CountingInvoker();

    await _pumpShell(
      tester,
      _app(transport, invoker, enabled: true, supportMode: true),
      size: const Size(1400, 4000),
    );
    // Settings is a support-readable destination; the editor exists only as
    // its Storefront card (there is no separate editor route), so the card is
    // the one way in - and it is not built.
    await _openSettings(tester, l10n);
    expect(
      tester
          .widget<RealSettingsView>(find.byType(RealSettingsView))
          .storefrontSeams,
      isNull,
    );

    _expectNoStorefrontCardWithNeighboursBuilt(l10n);
    expect(transport.calls.where(_storefrontRpcs.contains), isEmpty);
    expect(invoker.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OPEN for a role the server refuses: no editable field, no '
      'publish control and no function call', (tester) async {
    final transport = _RefusingTransport();
    final invoker = _CountingInvoker();

    await _pumpShell(
      tester,
      _app(transport, invoker, enabled: true, role: MembershipRole.cashier),
    );
    await _openSettings(tester, l10n);
    await _revealStorefront(tester);

    // The server was asked and refused (rank < manager): the card says so and
    // offers nothing to edit or publish.
    expect(
      transport.calls,
      contains(SupabaseStorefrontProfileRepository.readFunction),
    );
    expect(find.byKey(const Key('storefront-denied')), findsOneWidget);
    for (final key in const [
      'storefront-save',
      'storefront-publish',
      'storefront-slug',
      'storefront-display-name',
      'storefront-branch',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(
      transport.calls,
      isNot(contains(SupabaseStorefrontProfileRepository.writeFunction)),
    );
    expect(invoker.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final enabled in const [false, true]) {
    testWidgets('every Dashboard destination still navigates and renders with '
        'the gate ${enabled ? 'OPEN' : 'CLOSED'}', (tester) async {
      final transport = _OfflineTransport();
      final invoker = _CountingInvoker();

      await _pumpShell(tester, _app(transport, invoker, enabled: enabled));
      final visited = <int>[];
      for (var i = 0; i < 10; i++) {
        final nav = find.byKey(Key('dashboard-nav-$i'));
        if (nav.evaluate().isEmpty) continue;
        await tester.tap(nav.first);
        for (var k = 0; k < 5; k++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        // The tap really switched the content to destination i.
        expect(
          find.byKey(ValueKey('dashboard-tab-$i')),
          findsOneWidget,
          reason: 'destination $i',
        );
        expect(tester.takeException(), isNull, reason: 'destination $i');
        visited.add(i);
      }
      expect(visited, containsAll(const [0, 9]));
      expect(visited, hasLength(greaterThanOrEqualTo(8)));
      expect(invoker.calls, 0);
    });
  }

  test('the production web build passes the gate to the Dashboard only, '
      'true only in a Vercel Production build with the exact value', () {
    final script = _repoFile(
      'tools/vercel_build_web.sh',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final lines = script.split('\n');
    final flagged = lines
        .where((l) => l.contains('--dart-define=RESTOFLOW_STOREFRONT_EDITOR='))
        .toList();
    expect(flagged, hasLength(1));
    expect(
      flagged.single,
      startsWith(r'(cd apps/dashboard && "$FLUTTER" build web '),
    );
    expect(
      flagged.single,
      endsWith(
        r'--dart-define=RESTOFLOW_STOREFRONT_EDITOR="$STOREFRONT_EDITOR")',
      ),
    );
    for (final app in const ['pos', 'kds', 'kiosk']) {
      final build = lines.singleWhere(
        (l) => l.startsWith('(cd apps/$app && "\$FLUTTER" build web '),
      );
      expect(
        build,
        isNot(contains('RESTOFLOW_STOREFRONT_EDITOR')),
        reason: app,
      );
    }
    // Closed by default; open ONLY on the exact value in a Production build.
    final setters = lines
        .where((l) => RegExp(r'\bSTOREFRONT_EDITOR=').hasMatch(l))
        .where((l) => !l.contains('--dart-define='))
        .toList();
    expect(setters, [
      'STOREFRONT_EDITOR=false',
      r'if [ "${RESTOFLOW_STOREFRONT_EDITOR:-}" = "true" ] && '
          r'[ "${VERCEL_ENV:-}" = "production" ]; then '
          'STOREFRONT_EDITOR=true; fi',
    ]);
    // No checked-in file hard-codes the gate open.
    expect(
      _repoFile('vercel.json').readAsStringSync(),
      isNot(contains('RESTOFLOW_STOREFRONT_EDITOR')),
    );
  });
}
