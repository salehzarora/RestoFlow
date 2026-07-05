import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:restoflow_admin/src/auth/admin_auth.dart';
import 'package:restoflow_admin/src/auth/admin_mfa_screen.dart';
import 'package:restoflow_admin/src/auth/admin_sign_in_screen.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'fake_admin_auth_service.dart';

/// DESIGN-002 Admin MFA trust polish:
///  * the MFA banner shows the CORRECT body (adminMfaRequiredBody), not the
///    generic "not the owner panel" copy;
///  * the enrolment otpauth:// URI renders as a scannable QR (locally) AND the
///    URI fallback is forced LTR;
///  * the operator's signed-in account is shown (MFA + overview);
///  * sign-in errors surface in a top-level danger banner (not under Password).
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _mfa(FakeAdminAuthService auth, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: AdminMfaScreen(
          authService: auth,
          onVerified: () {},
          onSignOut: () {},
        ),
      ),
    );

Widget _signIn(FakeAdminAuthService auth) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: AdminSignInScreen(authService: auth),
  ),
);

void main() {
  testWidgets('MFA enrol shows the correct body, a scannable QR, and the '
      'signed-in account', (tester) async {
    _tall(tester);
    final l10n = await _en();
    final auth = FakeAdminAuthService(signedIn: true); // enrol (no factor)
    addTearDown(auth.dispose);

    await tester.pumpWidget(_mfa(auth));
    await tester.pumpAndSettle();

    // The banner now explains WHY MFA is required (was adminGateNotOwner).
    expect(find.text(l10n.adminMfaRequiredBody), findsOneWidget);
    expect(find.text(l10n.adminGateNotOwner), findsNothing);

    // A real, locally-rendered QR for the otpauth URI (offline; no network).
    expect(find.byKey(const Key('admin-mfa-qr')), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);

    // The setup key is still shown exactly once (the code block, not the URI).
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);

    // The operator can confirm which account is being verified.
    expect(find.byKey(const Key('admin-signed-in-as')), findsOneWidget);
    expect(find.text(l10n.adminSignedInAs('op@example.test')), findsOneWidget);
  });

  testWidgets('the enrolment otpauth URI is forced LTR (RTL-safe)', (
    tester,
  ) async {
    _tall(tester);
    final auth = FakeAdminAuthService(signedIn: true);
    addTearDown(auth.dispose);

    await tester.pumpWidget(_mfa(auth, locale: const Locale('ar')));
    await tester.pumpAndSettle();

    // The URI SelectableText renders and is pinned to LTR so the machine string
    // keeps its order under Arabic. (find by the otpauth text.)
    final uri = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (w) =>
            w is SelectableText && (w.data?.startsWith('otpauth://') ?? false),
      ),
    );
    expect(uri.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sign-in failure surfaces in a top-level danger banner', (
    tester,
  ) async {
    _tall(tester);
    final l10n = await _en();
    final auth = FakeAdminAuthService(signInError: AdminSignInError.network);
    addTearDown(auth.dispose);

    await tester.pumpWidget(_signIn(auth));
    await tester.pumpAndSettle();

    // No error before a failed attempt.
    expect(find.byKey(const Key('admin-signin-error')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('admin-signin-email')),
      'op@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('admin-signin-password')),
      'whatever',
    );
    await tester.tap(find.byKey(const Key('admin-signin-submit')));
    await tester.pumpAndSettle();

    // The network error is a banner above the form — not hidden under Password.
    expect(find.byKey(const Key('admin-signin-error')), findsOneWidget);
    expect(find.text(l10n.authNetworkError), findsOneWidget);
  });

  testWidgets('the platform overview shows the signed-in operator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final l10n = await _en();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: PlatformAdminScreen(operatorEmail: 'op@example.test'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform-signed-in-as')), findsOneWidget);
    expect(find.text(l10n.adminSignedInAs('op@example.test')), findsOneWidget);
  });
}
