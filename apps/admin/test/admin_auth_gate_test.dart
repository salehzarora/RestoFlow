import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/main.dart';
import 'package:restoflow_admin/src/admin_platform_gate.dart';
import 'package:restoflow_admin/src/auth/admin_auth.dart';
import 'package:restoflow_admin/src/auth/admin_mfa_screen.dart';
import 'package:restoflow_admin/src/auth/admin_sign_in_screen.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show AuthContextFetcher, RealModeUnconfiguredView;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'fake_admin_auth_service.dart';

MembershipContext mem(MembershipRole role) => MembershipContext(
  id: 'a',
  organizationId: 'org-a',
  organizationName: 'Org A',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: role,
  status: 'active',
);

MyContext ctx({
  bool admin = false,
  bool mfa = false,
  List<MembershipContext> memberships = const [],
}) => MyContext(
  appUser: const AppUserContext(
    id: 'u',
    email: 'op@example.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: admin,
  hasMfaAal2: mfa,
  memberships: memberships,
);

/// A context fetcher that reflects the fake's evolving server assurance: the
/// platform admin gains aal2 only after a successful TOTP verify.
AuthContextFetcher fetcherFor(
  FakeAdminAuthService auth, {
  bool admin = true,
  List<MembershipContext> memberships = const [],
}) =>
    () async => Success<MyContext, AuthFailure>(
      ctx(admin: admin, mfa: auth.serverAal2, memberships: memberships),
    );

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(child: app));
  await tester.pumpAndSettle();
}

Future<FakeAdminAuthService> _pumpApp(
  WidgetTester tester, {
  required FakeAdminAuthService auth,
  AuthContextFetcher? fetchContext,
}) async {
  addTearDown(auth.dispose);
  await _pump(
    tester,
    AdminApp(
      demoMode: false,
      authService: auth,
      fetchContext: fetchContext ?? fetcherFor(auth),
    ),
  );
  return auth;
}

void main() {
  testWidgets('demo mode renders the platform overview (no session)', (
    tester,
  ) async {
    await _pump(tester, const AdminApp(demoMode: true));
    final l10n = await en();
    expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
  });

  testWidgets('real mode with no wired auth fails closed to the unconfigured '
      'help page (never a bypass)', (tester) async {
    await _pump(tester, const AdminApp(demoMode: false));
    expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
    expect(find.byType(AdminSignInScreen), findsNothing);
  });

  testWidgets('RF-119-b no session -> the platform-operator sign-in screen '
      '(not the explainer, not the overview)', (tester) async {
    await _pumpApp(tester, auth: FakeAdminAuthService());
    expect(find.byType(AdminSignInScreen), findsOneWidget);
    expect(find.byKey(const Key('admin-signin-email')), findsOneWidget);
    expect(find.byKey(const Key('admin-signin-password')), findsOneWidget);
    final l10n = await en();
    expect(find.text(l10n.adminOverviewTitle), findsNothing);
  });

  testWidgets('RF-119-b sign-in with wrong credentials -> safe error, no '
      'session', (tester) async {
    final l10n = await en();
    await _pumpApp(
      tester,
      auth: FakeAdminAuthService(
        signInError: AdminSignInError.invalidCredentials,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('admin-signin-email')),
      'op@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('admin-signin-password')),
      'wrong',
    );
    await tester.tap(find.byKey(const Key('admin-signin-submit')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminSignInInvalid), findsOneWidget);
    expect(find.text(l10n.adminOverviewTitle), findsNothing);
    expect(find.byType(AdminSignInScreen), findsOneWidget);
  });

  testWidgets('a platform admin WITH an aal2 session reaches the overview '
      '(with a sign-out action)', (tester) async {
    final auth = FakeAdminAuthService(signedIn: true)..serverAal2 = true;
    await _pumpApp(tester, auth: auth);
    final l10n = await en();
    expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
    expect(find.byKey(const Key('platform-signout-button')), findsOneWidget);
  });

  testWidgets('a signed-in restaurant owner gets the platform-panel explainer, '
      'never the overview', (tester) async {
    final auth = FakeAdminAuthService(signedIn: true);
    await _pumpApp(
      tester,
      auth: auth,
      fetchContext: fetcherFor(
        auth,
        admin: false,
        memberships: [mem(MembershipRole.orgOwner)],
      ),
    );
    final l10n = await en();
    expect(find.byType(AdminGateExplainer), findsOneWidget);
    expect(find.text(l10n.adminGateNotOwner), findsOneWidget);
    expect(find.text(l10n.adminGateNotAdminAccount), findsOneWidget);
    expect(find.text(l10n.adminOverviewTitle), findsNothing);
  });

  testWidgets('RF-119-b platform admin WITHOUT aal2 and NO factor -> TOTP '
      'ENROL screen (setup key shown), never platform data', (tester) async {
    final l10n = await en();
    final auth = FakeAdminAuthService(signedIn: true); // assurance: no factor
    await _pumpApp(tester, auth: auth);
    expect(find.byType(AdminMfaScreen), findsOneWidget);
    expect(auth.enrollCalls, 1, reason: 'no verified factor -> enrol');
    expect(find.text(l10n.adminMfaEnrollTitle), findsOneWidget);
    // The one-time setup key (secret) is shown for enrolment (exact match, so it
    // is the code block — not the same secret embedded in the longer otpauth URI).
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
    expect(find.byKey(const Key('admin-mfa-code')), findsOneWidget);
    // No platform data before aal2.
    expect(find.text(l10n.adminOverviewTitle), findsNothing);
  });

  testWidgets(
    'RF-119-b enrol + verify success -> context refetch -> overview',
    (tester) async {
      final l10n = await en();
      final auth = FakeAdminAuthService(signedIn: true);
      await _pumpApp(tester, auth: auth);
      expect(find.byType(AdminMfaScreen), findsOneWidget);

      await tester.enterText(find.byKey(const Key('admin-mfa-code')), '123456');
      await tester.tap(find.byKey(const Key('admin-mfa-verify')));
      await tester.pumpAndSettle();

      expect(auth.verifyCalls, 1);
      expect(auth.lastVerifiedCode, '123456');
      // Entry is gated on the SERVER-derived assurance (the refetched context).
      expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
      expect(find.byType(AdminMfaScreen), findsNothing);
    },
  );

  testWidgets('RF-119-b platform admin WITHOUT aal2 WITH a verified factor -> '
      'CHALLENGE screen (no enrol, no setup key)', (tester) async {
    final l10n = await en();
    final auth = FakeAdminAuthService(
      signedIn: true,
      assurance: const AdminMfaAssurance(
        isAal2: false,
        hasVerifiedFactor: true,
        verifiedFactorId: 'factor-existing',
      ),
    );
    await _pumpApp(tester, auth: auth);
    expect(find.byType(AdminMfaScreen), findsOneWidget);
    expect(
      auth.enrollCalls,
      0,
      reason: 'a verified factor -> challenge, no enrol',
    );
    expect(find.text(l10n.adminMfaChallengeTitle), findsOneWidget);
    // The setup key is NOT shown in challenge mode.
    expect(find.textContaining('JBSWY3DPEHPK3PXP'), findsNothing);
  });

  testWidgets('RF-119-b a wrong TOTP code shows a safe error and NO platform '
      'data', (tester) async {
    final l10n = await en();
    final auth = FakeAdminAuthService(
      signedIn: true,
      verifyError: AdminMfaVerifyError.invalidCode,
    );
    await _pumpApp(tester, auth: auth);
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '000000');
    await tester.tap(find.byKey(const Key('admin-mfa-verify')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminMfaVerifyFailed), findsOneWidget);
    expect(auth.serverAal2, isFalse);
    expect(find.text(l10n.adminOverviewTitle), findsNothing);
    expect(find.byType(AdminMfaScreen), findsOneWidget);
  });

  testWidgets('RF-119-b sign out from the MFA screen -> back to sign-in', (
    tester,
  ) async {
    final auth = FakeAdminAuthService(signedIn: true);
    await _pumpApp(tester, auth: auth);
    expect(find.byType(AdminMfaScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-mfa-signout')));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.byType(AdminSignInScreen), findsOneWidget);
    expect(find.byType(AdminMfaScreen), findsNothing);
  });

  testWidgets('RF-119-b SERVER-GATED: a client verify that the server does NOT '
      'confirm as aal2 stays on MFA, never reaches the overview', (
    tester,
  ) async {
    final l10n = await en();
    // The client verify succeeds, but the server session stays non-aal2 (a
    // client-trust bypass would wrongly enter the overview here).
    final auth = FakeAdminAuthService(
      signedIn: true,
      serverAal2AfterVerify: false,
    );
    await _pumpApp(tester, auth: auth);
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '123456');
    await tester.tap(find.byKey(const Key('admin-mfa-verify')));
    await tester.pumpAndSettle();
    expect(auth.verifyCalls, 1);
    // Entry is gated on the SERVER-derived get_my_context.is_mfa_aal2 (still
    // false) — NOT the client's verify result.
    expect(find.text(l10n.adminOverviewTitle), findsNothing);
    expect(find.byType(AdminMfaScreen), findsOneWidget);
  });

  testWidgets('RF-119-b sign-in SUCCESS drives the session stream and advances '
      'off the sign-in screen', (tester) async {
    // Signed out, valid credentials, a platform admin with no factor.
    final auth = FakeAdminAuthService();
    await _pumpApp(tester, auth: auth);
    expect(find.byType(AdminSignInScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin-signin-email')),
      'op@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('admin-signin-password')),
      'correct-horse',
    );
    await tester.tap(find.byKey(const Key('admin-signin-submit')));
    await tester.pumpAndSettle();
    // The session stream transition drives the flow to resolve context -> MFA.
    expect(find.byType(AdminSignInScreen), findsNothing);
    expect(find.byType(AdminMfaScreen), findsOneWidget);
  });

  testWidgets(
    'RF-119-b a denied get_my_context (signed in, not a linked admin) '
    '-> the explainer, never the overview',
    (tester) async {
      final l10n = await en();
      final auth = FakeAdminAuthService(signedIn: true);
      addTearDown(auth.dispose);
      await _pump(
        tester,
        AdminApp(
          demoMode: false,
          authService: auth,
          fetchContext: () async =>
              const Failure<MyContext, AuthFailure>(AuthDeniedFailure()),
        ),
      );
      expect(find.byType(AdminGateExplainer), findsOneWidget);
      expect(find.text(l10n.adminOverviewTitle), findsNothing);
    },
  );

  testWidgets('RF-119-b a transport error on get_my_context -> the retryable '
      'error state, never the overview', (tester) async {
    final l10n = await en();
    final auth = FakeAdminAuthService(signedIn: true);
    addTearDown(auth.dispose);
    await _pump(
      tester,
      AdminApp(
        demoMode: false,
        authService: auth,
        fetchContext: () async =>
            const Failure<MyContext, AuthFailure>(AuthNetworkFailure()),
      ),
    );
    expect(find.text(l10n.authError), findsOneWidget);
    expect(find.text(l10n.authTryAgain), findsOneWidget);
    expect(find.text(l10n.adminOverviewTitle), findsNothing);
  });

  testWidgets('RF-119-b the MFA screen renders in Arabic (RTL) safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAdminAuthService(signedIn: true);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: AdminMfaScreen(
            authService: auth,
            onVerified: () {},
            onSignOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(AdminMfaScreen))),
      TextDirection.rtl,
    );
    expect(find.text('مطلوب مصادقة متعددة العوامل'), findsOneWidget);
  });
}
