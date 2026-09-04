/// AUTH-FLOW-256 — confirmation continuation, password recovery, and telling
/// the truth about why sign-in failed.
///
/// The incident these cover: a new tenant confirmed their email, was dropped on
/// a broken page, was then told "Incorrect email or password" for a password
/// that was never checked, and finally received a reset email whose link led to
/// a Dashboard with no way to set a password. Three separate defects, each of
/// which independently ends the sign-up journey.
///
/// The classifier and the callback parser are pure functions on purpose — a
/// 402 must be provably distinguishable from a wrong password without a browser,
/// a network, or an SDK in the way.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/auth/auth_callback.dart';
import 'package:restoflow_dashboard/src/auth/auth_failure_classifier.dart';
import 'package:restoflow_dashboard/src/auth/dashboard_auth_repository.dart';
import 'package:restoflow_dashboard/src/auth/login_signup_screen.dart';
import 'package:restoflow_dashboard/src/auth/password_recovery_screen.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

/// A scriptable auth repository. Records what it was asked so a test can prove
/// the flow called the RIGHT thing, not merely that a screen rendered.
class _FakeAuth implements DashboardAuthRepository {
  _FakeAuth({
    AuthSessionStatus initialStatus = AuthSessionStatus.signedOut,
    this.signInOutcome = const AuthSignedIn(),
    this.signUpOutcome = const AuthConfirmationRequired(),
    this.resetOutcome = const AuthPasswordResetRequested(),
    this.recoveryOutcome = const AuthPasswordUpdated(),
    bool recovering = false,
  }) : _status = initialStatus,
       _recovering = recovering;

  AuthSessionStatus _status;
  bool _recovering;
  AuthOutcome signInOutcome;
  AuthOutcome signUpOutcome;
  AuthOutcome resetOutcome;
  AuthOutcome recoveryOutcome;

  final _status$ = StreamController<AuthSessionStatus>.broadcast();
  final _recovery$ = StreamController<bool>.broadcast();

  final List<String> resetEmails = [];
  final List<String> newPasswords = [];
  int signOutCount = 0;
  int cancelCount = 0;

  @override
  AuthSessionStatus get status => _status;

  @override
  Stream<AuthSessionStatus> get statusChanges => _status$.stream;

  @override
  bool get isPasswordRecovery => _recovering;

  @override
  Stream<bool> get passwordRecoveryChanges => _recovery$.stream;

  void emitStatus(AuthSessionStatus s) {
    _status = s;
    _status$.add(s);
  }

  void emitRecovery(bool r) {
    _recovering = r;
    _recovery$.add(r);
  }

  @override
  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async => signInOutcome;

  @override
  Future<AuthOutcome> signUp({
    required String email,
    required String password,
  }) async => signUpOutcome;

  @override
  Future<void> signOut() async {
    signOutCount++;
    emitStatus(AuthSessionStatus.signedOut);
  }

  @override
  Future<AuthOutcome> requestPasswordReset({required String email}) async {
    resetEmails.add(email);
    return resetOutcome;
  }

  @override
  Future<AuthOutcome> completePasswordRecovery({
    required String newPassword,
  }) async {
    newPasswords.add(newPassword);
    if (recoveryOutcome is AuthPasswordUpdated) emitRecovery(false);
    return recoveryOutcome;
  }

  @override
  Future<void> cancelPasswordRecovery() async {
    cancelCount++;
    emitRecovery(false);
    await signOut();
  }

  void dispose() {
    _status$.close();
    _recovery$.close();
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  String code = 'en',
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    // The auth screens carry a LanguageSelector, which is a Riverpod consumer.
    ProviderScope(
      child: MaterialApp(
        locale: Locale(code),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('A. why sign-in said the wrong thing', () {
    test('402, 429 and 5xx are NEVER a wrong password', () {
      // This is the whole point of the phase. Each of these used to render as
      // "Incorrect email or password", sending the owner to re-type a
      // credential that had never been rejected.
      expect(
        classifyAuthFailure(statusCode: 402),
        AuthErrorKind.serviceUnavailable,
      );
      expect(classifyAuthFailure(statusCode: 429), AuthErrorKind.rateLimited);
      for (final code in [500, 502, 503, 504]) {
        expect(
          classifyAuthFailure(statusCode: code),
          AuthErrorKind.serviceUnavailable,
          reason: '$code is the service failing, not the operator',
        );
      }
      for (final code in [402, 429, 500, 503]) {
        expect(
          classifyAuthFailure(statusCode: code),
          isNot(AuthErrorKind.invalidCredentials),
        );
      }
    });

    test('an unconfirmed email is reported as such, not as a bad password', () {
      expect(
        classifyAuthFailure(statusCode: 400, errorCode: 'email_not_confirmed'),
        AuthErrorKind.emailNotConfirmed,
      );
      // Even when the server sends no code, the phrase is recognised.
      expect(
        classifyAuthFailure(statusCode: 400, message: 'Email not confirmed'),
        AuthErrorKind.emailNotConfirmed,
      );
    });

    test('a genuinely wrong credential still says so', () {
      expect(
        classifyAuthFailure(statusCode: 400, errorCode: 'invalid_credentials'),
        AuthErrorKind.invalidCredentials,
      );
      expect(
        classifyAuthFailure(statusCode: 401),
        AuthErrorKind.invalidCredentials,
      );
    });

    test('rate limiting is recognised by code as well as by status', () {
      for (final code in [
        'over_request_rate_limit',
        'over_email_send_rate_limit',
      ]) {
        expect(
          classifyAuthFailure(statusCode: 400, errorCode: code),
          AuthErrorKind.rateLimited,
          reason: '$code is a throttle, not a credential',
        );
      }
    });

    test('password-policy and link failures are distinct kinds', () {
      expect(
        classifyAuthFailure(statusCode: 422, errorCode: 'weak_password'),
        AuthErrorKind.weakPassword,
      );
      expect(
        classifyAuthFailure(statusCode: 422, errorCode: 'same_password'),
        AuthErrorKind.samePassword,
      );
      expect(
        classifyAuthFailure(statusCode: 403, errorCode: 'otp_expired'),
        AuthErrorKind.linkExpired,
      );
      // The PKCE "opened in another browser" failure is a LINK problem, not an
      // account problem — this is the confirmation defect from the incident.
      expect(
        classifyAuthFailure(
          statusCode: 400,
          message: 'Code verifier could not be found in local storage.',
        ),
        AuthErrorKind.linkExpired,
      );
    });

    test('an unclassifiable failure is unknown, never a guess', () {
      expect(classifyAuthFailure(), AuthErrorKind.unknown);
      expect(
        classifyAuthFailure(statusCode: 418, message: 'teapot'),
        AuthErrorKind.unknown,
      );
    });
  });

  group('B. reading the callback URL', () {
    test('every shape a Supabase email can arrive in is recognised', () {
      expect(
        resolveCallbackKind(Uri.parse('https://x.test/?code=abc')),
        AuthCallbackKind.confirmation,
      );
      expect(
        resolveCallbackKind(
          Uri.parse('https://x.test/?token_hash=h&type=recovery'),
        ),
        AuthCallbackKind.recovery,
      );
      expect(
        resolveCallbackKind(
          Uri.parse('https://x.test/#access_token=t&type=recovery'),
        ),
        AuthCallbackKind.recovery,
      );
      // A bare PKCE code carries no `type`, so the PATH is what distinguishes
      // "reset my password" from "confirm my email".
      expect(
        resolveCallbackKind(Uri.parse('https://x.test/auth/recovery?code=abc')),
        AuthCallbackKind.recovery,
      );
      expect(
        resolveCallbackKind(Uri.parse('https://x.test/')),
        AuthCallbackKind.none,
      );
    });

    test('a failed link is a failure, never something to exchange', () {
      final cb = parseAuthCallback(
        Uri.parse(
          'https://x.test/?error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired',
        ),
      );
      expect(cb.kind, AuthCallbackKind.failure);
      expect(cb.errorCode, 'otp_expired');
      expect(
        classifyAuthFailure(errorCode: cb.errorCode),
        AuthErrorKind.linkExpired,
      );
    });

    test('scrubbing removes every token and keeps everything else', () {
      final cleaned = scrubbedUrl(
        Uri.parse(
          'https://x.test/auth/recovery?token_hash=SECRET&type=recovery&tab=menu'
          '#access_token=SECRET2&refresh_token=SECRET3&lang=ar',
        ),
      );
      final s = cleaned.toString();
      // A recovery link left in history is a replayable credential.
      for (final secret in ['SECRET', 'SECRET2', 'SECRET3']) {
        expect(
          s,
          isNot(contains(secret)),
          reason: '$secret survived scrubbing',
        );
      }
      for (final key in [
        'token_hash',
        'access_token',
        'refresh_token',
        'type',
      ]) {
        expect(s, isNot(contains(key)));
      }
      // Unrelated parameters are not collateral damage.
      expect(cleaned.queryParameters['tab'], 'menu');
      expect(s, contains('lang=ar'));
    });

    test('an ordinary load is left completely alone', () {
      final uri = Uri.parse('https://x.test/?tab=menu#lang=ar');
      expect(parseAuthCallback(uri).isAuthCallback, isFalse);
      expect(scrubbedUrl(uri).queryParameters['tab'], 'menu');
    });
  });

  group('C. redirect resolution', () {
    test(
      'recovery and confirmation get their own paths on the live origin',
      () {
        final origin = resolveAuthRedirectUrl(
          isWeb: true,
          currentUri: Uri.parse('https://resto-flow-phi.vercel.app/'),
        );
        expect(
          recoveryRedirectUrl(origin),
          'https://resto-flow-phi.vercel.app/auth/recovery',
        );
        expect(
          confirmationRedirectUrl(origin),
          'https://resto-flow-phi.vercel.app/auth/confirmed',
        );
      },
    );

    test('an explicit override wins, and a trailing slash is not doubled', () {
      final origin = resolveAuthRedirectUrl(
        isWeb: true,
        currentUri: Uri.parse('https://ignored.test/'),
        configuredOverride: 'https://veyro.example/',
      );
      expect(
        recoveryRedirectUrl(origin),
        'https://veyro.example/auth/recovery',
      );
    });

    test('a non-web build fabricates no link', () {
      final origin = resolveAuthRedirectUrl(isWeb: false);
      expect(origin, isNull);
      expect(recoveryRedirectUrl(origin), isNull);
      expect(confirmationRedirectUrl(origin), isNull);
      // Specifically: it never falls back to a localhost value on a hosted app.
      expect(recoveryRedirectUrl(''), isNull);
    });
  });

  group('D. forgot password, from the sign-in screen', () {
    testWidgets('the entry point exists in sign-in and not in sign-up', (
      tester,
    ) async {
      final auth = _FakeAuth();
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, LoginSignupScreen(authRepository: auth));

      expect(find.byKey(const Key('auth-forgot-password')), findsOneWidget);
      await tester.tap(find.text(l10n.authCreateAccountTab));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-forgot-password')), findsNothing);
    });

    testWidgets('requesting a reset asks for the email and nothing else', (
      tester,
    ) async {
      final auth = _FakeAuth();
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, LoginSignupScreen(authRepository: auth));

      await tester.tap(find.byKey(const Key('auth-forgot-password')));
      await tester.pumpAndSettle();
      // No password is asked for to send a reset link.
      expect(find.byKey(const Key('auth-password')), findsNothing);
      expect(find.byKey(const Key('auth-reset-body')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'owner@veyro.test',
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(auth.resetEmails, ['owner@veyro.test']);
      expect(find.text(l10n.authResetSent), findsOneWidget);
    });

    testWidgets('the confirmation does NOT reveal whether the account exists', (
      tester,
    ) async {
      // Non-enumeration: an unknown address and a real one must produce the
      // same words, or the form becomes an account-existence oracle.
      final seen = <String>{};
      for (final email in ['real@veyro.test', 'nobody@nowhere.test']) {
        final auth = _FakeAuth();
        addTearDown(auth.dispose);
        // A distinct key per iteration: pumping the same widget TYPE reuses the
        // existing State, so the second pass would still be in reset mode.
        await _pump(
          tester,
          LoginSignupScreen(key: ValueKey(email), authRepository: auth),
        );
        await tester.tap(find.byKey(const Key('auth-forgot-password')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('auth-email')), email);
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();

        final banner = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(const Key('auth-reset-sent')),
                matching: find.byType(Text),
              )
              .first,
        );
        seen.add(banner.data ?? '');
      }
      expect(seen, hasLength(1), reason: 'the two answers must be identical');
    });

    testWidgets('a rate-limited reset is reported honestly', (tester) async {
      final auth = _FakeAuth(
        resetOutcome: const AuthError(AuthErrorKind.rateLimited),
      );
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, LoginSignupScreen(authRepository: auth));
      await tester.tap(find.byKey(const Key('auth-forgot-password')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('auth-email')), 'a@b.test');
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.authRateLimited), findsOneWidget);
      expect(find.text(l10n.authInvalidCredentials), findsNothing);
    });

    testWidgets('you can get back to sign in', (tester) async {
      final auth = _FakeAuth();
      addTearDown(auth.dispose);
      await _pump(tester, LoginSignupScreen(authRepository: auth));
      await tester.tap(find.byKey(const Key('auth-forgot-password')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth-back-to-sign-in')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-password')), findsOneWidget);
    });
  });

  group('E. the sign-in screen speaks each failure plainly', () {
    testWidgets('each kind renders its own message', (tester) async {
      final l10n = await _l10n();
      final cases = <AuthErrorKind, String>{
        AuthErrorKind.invalidCredentials: l10n.authInvalidCredentials,
        AuthErrorKind.emailNotConfirmed: l10n.authEmailNotConfirmed,
        AuthErrorKind.rateLimited: l10n.authRateLimited,
        AuthErrorKind.serviceUnavailable: l10n.authServiceUnavailable,
        AuthErrorKind.accountUnavailable: l10n.authAccountUnavailable,
      };
      for (final entry in cases.entries) {
        final auth = _FakeAuth(signInOutcome: AuthError(entry.key));
        addTearDown(auth.dispose);
        await _pump(tester, LoginSignupScreen(authRepository: auth));
        await tester.enterText(find.byKey(const Key('auth-email')), 'a@b.test');
        await tester.enterText(find.byKey(const Key('auth-password')), 'pw');
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
        if (entry.key != AuthErrorKind.invalidCredentials) {
          expect(
            find.text(l10n.authInvalidCredentials),
            findsNothing,
            reason: '${entry.key} must not read as a wrong password',
          );
        }
      }
    });

    testWidgets('sign-up that needs confirmation says so', (tester) async {
      final auth = _FakeAuth();
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, LoginSignupScreen(authRepository: auth));
      await tester.tap(find.text(l10n.authCreateAccountTab));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('auth-email')), 'a@b.test');
      await tester.enterText(
        find.byKey(const Key('auth-password')),
        'longenough',
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-confirmation-sent')), findsOneWidget);
      expect(find.text(l10n.authEmailConfirmationSent), findsOneWidget);
    });

    testWidgets('a project that auto-confirms shows NO check-your-email note', (
      tester,
    ) async {
      // With auto-confirm on, sign-up returns a session immediately. Telling
      // that operator to go and check their inbox would send them looking for
      // an email that was never sent.
      final auth = _FakeAuth(signUpOutcome: const AuthSignedIn());
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, LoginSignupScreen(authRepository: auth));
      await tester.tap(find.text(l10n.authCreateAccountTab));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('auth-email')), 'a@b.test');
      await tester.enterText(
        find.byKey(const Key('auth-password')),
        'longenough',
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-confirmation-sent')), findsNothing);
    });
  });

  group('F. the recovery screen', () {
    testWidgets('asks for a new password twice and validates both', (
      tester,
    ) async {
      final auth = _FakeAuth(recovering: true);
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, PasswordRecoveryScreen(authRepository: auth));

      expect(find.text(l10n.authNewPasswordTitle), findsOneWidget);

      // Too short.
      await tester.enterText(find.byKey(const Key('recovery-password')), 'abc');
      await tester.enterText(find.byKey(const Key('recovery-confirm')), 'abc');
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await tester.pumpAndSettle();
      expect(auth.newPasswords, isEmpty);
      expect(find.text(l10n.authWeakPassword), findsWidgets);

      // Mismatched.
      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'a-good-password',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm')),
        'a-different-one',
      );
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await tester.pumpAndSettle();
      expect(auth.newPasswords, isEmpty);
      expect(find.text(l10n.authPasswordsDoNotMatch), findsOneWidget);
    });

    testWidgets('a matching, long-enough password is submitted once', (
      tester,
    ) async {
      final auth = _FakeAuth(recovering: true);
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, PasswordRecoveryScreen(authRepository: auth));

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'a-good-password',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm')),
        'a-good-password',
      );
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await tester.pumpAndSettle();

      expect(auth.newPasswords, ['a-good-password']);
      expect(find.text(l10n.authPasswordUpdated), findsOneWidget);
    });

    testWidgets('an expired link offers a new one instead of a dead form', (
      tester,
    ) async {
      final auth = _FakeAuth(
        recovering: true,
        recoveryOutcome: const AuthError(AuthErrorKind.linkExpired),
      );
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, PasswordRecoveryScreen(authRepository: auth));

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'a-good-password',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm')),
        'a-good-password',
      );
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recovery-expired-card')), findsOneWidget);
      expect(find.text(l10n.authLinkExpiredTitle), findsOneWidget);
      // The form is gone: retrying it could never succeed.
      expect(find.byKey(const Key('recovery-submit')), findsNothing);
    });

    testWidgets('a rejected password is reported without losing the form', (
      tester,
    ) async {
      final auth = _FakeAuth(
        recovering: true,
        recoveryOutcome: const AuthError(AuthErrorKind.weakPassword),
      );
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(tester, PasswordRecoveryScreen(authRepository: auth));
      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'a-good-password',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm')),
        'a-good-password',
      );
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recovery-error')), findsOneWidget);
      expect(find.text(l10n.authWeakPassword), findsWidgets);
      expect(find.byKey(const Key('recovery-submit')), findsOneWidget);
    });

    testWidgets('abandoning recovery signs the recovery session OUT', (
      tester,
    ) async {
      // A recovery session that is merely navigated away from would still be a
      // usable session whose password was never replaced.
      final auth = _FakeAuth(recovering: true);
      addTearDown(auth.dispose);
      await _pump(tester, PasswordRecoveryScreen(authRepository: auth));
      await tester.tap(find.byKey(const Key('recovery-cancel')));
      await tester.pumpAndSettle();

      expect(auth.cancelCount, 1);
      expect(auth.signOutCount, 1);
    });

    testWidgets('renders in ar and he without overflowing', (tester) async {
      for (final code in ['ar', 'he']) {
        final auth = _FakeAuth(recovering: true);
        addTearDown(auth.dispose);
        final l10n = await _l10n(code);
        await _pump(
          tester,
          PasswordRecoveryScreen(authRepository: auth),
          code: code,
        );
        expect(find.text(l10n.authNewPasswordTitle), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'overflow in $code');
      }
    });
  });

  group('G. the flow routes a recovery session to the recovery screen', () {
    testWidgets('a recovery session never lands on the dashboard', (
      tester,
    ) async {
      // The incident: the reset link DOES create a session, so a flow that only
      // checks "signed in?" strands the operator with their old password.
      final auth = _FakeAuth(
        initialStatus: AuthSessionStatus.signedIn,
        recovering: true,
      );
      addTearDown(auth.dispose);
      final l10n = await _l10n();
      await _pump(
        tester,
        DashboardApp(
          demoMode: false,
          authRepository: auth,
          fetchContext: () async => throw StateError('must not be called'),
        ),
      );

      expect(find.text(l10n.authNewPasswordTitle), findsOneWidget);
      expect(find.byKey(const Key('recovery-form-card')), findsOneWidget);
    });

    testWidgets('a normal signed-out load still shows sign-in', (tester) async {
      final auth = _FakeAuth();
      addTearDown(auth.dispose);
      await _pump(
        tester,
        DashboardApp(
          demoMode: false,
          authRepository: auth,
          fetchContext: () async => throw StateError('must not be called'),
        ),
      );
      expect(find.byKey(const Key('auth-password')), findsOneWidget);
      expect(find.byKey(const Key('recovery-form-card')), findsNothing);
    });
  });

  group('H. localization completeness', () {
    test('every new AUTH-256 string exists in all three locales', () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l10n(code);
        final strings = <String, String>{
          'authForgotPassword': l10n.authForgotPassword,
          'authResetTitle': l10n.authResetTitle,
          'authResetBody': l10n.authResetBody,
          'authResetSend': l10n.authResetSend,
          'authResetSent': l10n.authResetSent,
          'authBackToSignIn': l10n.authBackToSignIn,
          'authNewPasswordTitle': l10n.authNewPasswordTitle,
          'authNewPasswordBody': l10n.authNewPasswordBody,
          'authNewPasswordLabel': l10n.authNewPasswordLabel,
          'authConfirmPasswordLabel': l10n.authConfirmPasswordLabel,
          'authPasswordsDoNotMatch': l10n.authPasswordsDoNotMatch,
          'authUpdatePasswordAction': l10n.authUpdatePasswordAction,
          'authPasswordUpdated': l10n.authPasswordUpdated,
          'authLinkExpiredTitle': l10n.authLinkExpiredTitle,
          'authLinkExpiredBody': l10n.authLinkExpiredBody,
          'authRequestNewLink': l10n.authRequestNewLink,
          'authEmailConfirmedTitle': l10n.authEmailConfirmedTitle,
          'authEmailConfirmedBody': l10n.authEmailConfirmedBody,
          'authEmailNotConfirmed': l10n.authEmailNotConfirmed,
          'authRateLimited': l10n.authRateLimited,
          'authServiceUnavailable': l10n.authServiceUnavailable,
          'authAccountUnavailable': l10n.authAccountUnavailable,
          'authWeakPassword': l10n.authWeakPassword,
          'authSamePassword': l10n.authSamePassword,
        };
        strings.forEach((key, value) {
          expect(value, isNotEmpty, reason: '$key missing in $code');
        });
      }
    });

    test('ar and he are genuinely translated, not English copies', () async {
      final en = await _l10n('en');
      for (final code in ['ar', 'he']) {
        final other = await _l10n(code);
        expect(other.authNewPasswordTitle, isNot(en.authNewPasswordTitle));
        expect(other.authForgotPassword, isNot(en.authForgotPassword));
        expect(other.authRateLimited, isNot(en.authRateLimited));
      }
    });
  });
}
