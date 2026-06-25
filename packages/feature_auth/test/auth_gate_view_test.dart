import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

MembershipContext mem(String id, MembershipRole role) => MembershipContext(
  id: id,
  organizationId: 'org-$id',
  organizationName: 'Org $id',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: role,
  status: 'active',
);

/// Pumps [child] inside the shared l10n wiring and returns the active
/// localizations + text direction (the kds_rtl_ltr pattern).
Future<({AppLocalizations l10n, TextDirection dir})> pumpGate(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  late AppLocalizations l10n;
  late TextDirection dir;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            dir = Directionality.of(context);
            return child;
          },
        ),
      ),
    ),
  );
  // A single frame (NOT pumpAndSettle): the loading state shows a
  // CircularProgressIndicator that animates forever, which would never settle.
  await tester.pump();
  return (l10n: l10n, dir: dir);
}

Widget gate(AuthGateState state, {ValueChanged<String>? onSelect}) =>
    AuthGateView(
      state: state,
      onReady: (_, _) => const Text('READY-SENTINEL'),
      onSelectMembership: onSelect,
    );

void main() {
  testWidgets('loading renders the localized loading text + spinner', (
    tester,
  ) async {
    final r = await pumpGate(tester, gate(const AuthGateLoading()));
    expect(find.text(r.l10n.authLoadingAccount), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('unauthenticated renders the sign-in placeholder', (
    tester,
  ) async {
    final r = await pumpGate(tester, gate(const AuthGateUnauthenticated()));
    expect(find.text(r.l10n.authSignInRequired), findsOneWidget);
    expect(find.text(r.l10n.authContinue), findsOneWidget);
  });

  testWidgets('auth denied renders the access-denied state', (tester) async {
    final r = await pumpGate(tester, gate(const AuthGateAuthDenied()));
    expect(find.text(r.l10n.authAccessDenied), findsOneWidget);
  });

  testWidgets('invalid response renders the generic error state', (
    tester,
  ) async {
    final r = await pumpGate(tester, gate(const AuthGateInvalidResponse()));
    expect(find.text(r.l10n.authError), findsOneWidget);
  });

  testWidgets('no memberships renders the no-access state', (tester) async {
    final r = await pumpGate(tester, gate(const AuthGateNoMemberships()));
    expect(find.text(r.l10n.authNoAccess), findsOneWidget);
  });

  testWidgets('platform admin with zero memberships renders the admin state', (
    tester,
  ) async {
    final r = await pumpGate(
      tester,
      gate(const AuthGatePlatformAdminNoMemberships()),
    );
    expect(find.text(r.l10n.authPlatformAdmin), findsOneWidget);
  });

  testWidgets('wrong role renders the wrong-role state', (tester) async {
    final r = await pumpGate(
      tester,
      gate(const AuthGateWrongRole(MembershipRole.kitchenStaff)),
    );
    expect(find.text(r.l10n.authWrongRole), findsOneWidget);
  });

  testWidgets('deferred/accountant role renders the coming-soon state', (
    tester,
  ) async {
    final r = await pumpGate(
      tester,
      gate(const AuthGateDeferredRole(MembershipRole.accountant)),
    );
    expect(find.text(r.l10n.authComingSoon), findsOneWidget);
  });

  testWidgets('ready states delegate to onReady (app provides the screen)', (
    tester,
  ) async {
    await pumpGate(
      tester,
      gate(AuthGateReady(mem('a', MembershipRole.cashier))),
    );
    expect(find.text('READY-SENTINEL'), findsOneWidget);
  });

  testWidgets('Arabic renders RTL with localized (non-English) chrome', (
    tester,
  ) async {
    final r = await pumpGate(
      tester,
      gate(const AuthGateNoMemberships()),
      locale: const Locale('ar'),
    );
    expect(r.dir, TextDirection.rtl);
    expect(r.l10n.authNoAccess, isNot('No active access'));
    expect(find.text(r.l10n.authNoAccess), findsOneWidget);
  });

  testWidgets('Hebrew renders RTL', (tester) async {
    final r = await pumpGate(
      tester,
      gate(const AuthGateAuthDenied()),
      locale: const Locale('he'),
    );
    expect(r.dir, TextDirection.rtl);
    expect(find.text(r.l10n.authAccessDenied), findsOneWidget);
  });
}
