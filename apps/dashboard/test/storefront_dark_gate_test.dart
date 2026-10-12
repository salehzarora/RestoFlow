/// STOREFRONT-INTEGRATE-001 - the Storefront editor's DARK gate.
///
/// A stock build (CI passes no `--dart-define`) has the gate CLOSED: the real
/// shell builds no Storefront seams, sends no Storefront RPC and never invokes
/// the media function, and the Settings card shows the honest "not connected"
/// note. Opening the gate (the constructor seam) wires the SAME shell, which
/// proves the closed case is not vacuous. The production web build never sets
/// the define.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_dark_gate.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const Set<String> _storefrontRpcs = <String>{
  SupabaseStorefrontProfileRepository.readFunction,
  SupabaseStorefrontProfileRepository.writeFunction,
  SupabaseStorefrontMediaRepository.listFunction,
  SupabaseStorefrontMediaRepository.retractFunction,
  SupabaseStorefrontMediaRepository.cancelFunction,
};

/// Every RPC answers "transient"; only WHICH functions were asked matters.
class _OfflineTransport implements SyncRpcTransport {
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    throw const SyncTransportException(
      SyncTransportErrorKind.transient,
      code: '503',
      message: 'not under test',
    );
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

const MembershipContext _owner = MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Restaurant 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: MembershipRole.orgOwner,
  status: 'active',
);

Widget _app(
  SyncRpcTransport transport,
  StorefrontFunctionInvoker invoker, {
  bool? enabled,
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: false),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: enabled == null
        // The production shape: the gate keeps its compile-time default.
        ? DashboardShell(
            membership: _owner,
            currencyCode: 'ILS',
            reportsTransport: transport,
            storefrontFunctionInvoker: invoker,
          )
        : DashboardShell(
            membership: _owner,
            currencyCode: 'ILS',
            reportsTransport: transport,
            storefrontFunctionInvoker: invoker,
            storefrontEditorEnabled: enabled,
          ),
  ),
);

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

File _repoFile(String rel) {
  for (final prefix in ['', '../../', '../']) {
    final f = File('$prefix$rel');
    if (f.existsSync()) return f;
  }
  fail('cannot find $rel (cwd: ${Directory.current.path})');
}

void main() {
  test('the gate is compile-time FALSE in a stock build', () {
    expect(kStorefrontEditorEnabled, isFalse);
  });

  testWidgets('CLOSED by default: no seams, no Storefront RPC, no function '
      'call, and the honest "not connected" note', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final transport = _OfflineTransport();
    final invoker = _CountingInvoker();

    await tester.pumpWidget(_app(transport, invoker));
    await tester.pumpAndSettle();
    await _openSettings(tester, l10n);
    expect(
      tester
          .widget<RealSettingsView>(find.byType(RealSettingsView))
          .storefrontSeams,
      isNull,
    );
    await _revealStorefront(tester);

    expect(find.byKey(const Key('storefront-unavailable')), findsOneWidget);
    expect(find.text(l10n.storefrontUnavailableNote), findsOneWidget);
    expect(find.byKey(const Key('storefront-publish')), findsNothing);
    expect(find.byKey(const Key('storefront-unpublish')), findsNothing);
    expect(find.byKey(const Key('storefront-save')), findsNothing);
    expect(transport.calls.where(_storefrontRpcs.contains), isEmpty);
    expect(invoker.calls, 0);
  });

  testWidgets('OPEN (test seam): the same shell wires the editor', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final transport = _OfflineTransport();
    final invoker = _CountingInvoker();

    await tester.pumpWidget(_app(transport, invoker, enabled: true));
    await tester.pumpAndSettle();
    await _openSettings(tester, l10n);
    final seams = tester
        .widget<RealSettingsView>(find.byType(RealSettingsView))
        .storefrontSeams;
    expect(seams, isNotNull);
    expect(seams!.publisher, isNotNull);
    await _revealStorefront(tester);

    expect(find.byKey(const Key('storefront-unavailable')), findsNothing);
    expect(
      transport.calls,
      contains(SupabaseStorefrontProfileRepository.readFunction),
    );
  });

  test('the production web build never sets the define', () {
    for (final rel in ['tools/vercel_build_web.sh', 'vercel.json']) {
      expect(
        _repoFile(rel).readAsStringSync(),
        isNot(contains('RESTOFLOW_STOREFRONT_EDITOR')),
        reason: rel,
      );
    }
  });
}
