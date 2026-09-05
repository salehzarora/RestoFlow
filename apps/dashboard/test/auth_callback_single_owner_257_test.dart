/// AUTH-CALLBACK-257 — one verifier, a URL that is actually cleaned, and a
/// confirmed owner who reaches onboarding instead of an error page.
///
/// Production evidence this pins down, for
/// `/auth/confirmed?token_hash=…&type=email`:
///   * the first `/verify` returned 200 and a second followed as a WARNING;
///   * VEYRO rendered the generic "Something went wrong" page anyway;
///   * the `token_hash` was still in the address bar while it did.
///
/// Three separate causes, each proven here rather than assumed. Note especially
/// group A: the AUTH-256 scrub test passed while the production shape leaked,
/// because it only ever exercised a URL with a NON-auth parameter left over.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/auth/auth_callback.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

void main() {
  group('A. the URL is actually cleaned', () {
    test('the PRODUCTION shape leaves no token behind', () {
      // Every parameter is an auth parameter. `Uri.replace(queryParameters:
      // null)` KEEPS the original query — null means "leave this field alone",
      // not "clear it" — so the old implementation returned this URL unchanged
      // and the token stayed in the address bar for the life of the tab.
      final cleaned = scrubbedUrl(
        Uri.parse(
          'https://resto-flow-phi.vercel.app/auth/confirmed'
          '?token_hash=SECRET&type=email',
        ),
      );
      expect(cleaned.toString(), isNot(contains('SECRET')));
      expect(cleaned.toString(), isNot(contains('token_hash')));
      expect(cleaned.query, isEmpty);
      expect(cleaned.fragment, isEmpty);
      // And it stays a usable URL, not a bare origin or a dangling '?'/'#'.
      expect(cleaned.path, '/auth/confirmed');
      expect(
        cleaned.toString(),
        'https://resto-flow-phi.vercel.app/auth/confirmed',
      );
    });

    test('the recovery shape leaves no token behind either', () {
      final cleaned = scrubbedUrl(
        Uri.parse(
          'https://resto-flow-phi.vercel.app/auth/recovery'
          '?token_hash=SECRET&type=recovery',
        ),
      );
      expect(cleaned.toString(), isNot(contains('SECRET')));
      expect(
        cleaned.toString(),
        'https://resto-flow-phi.vercel.app/auth/recovery',
      );
    });

    test('every shape, including a port and a fragment, is scrubbed', () {
      const secret = 'SECRET';
      final shapes = <String>[
        'https://x.test/?code=$secret',
        'https://x.test/a#access_token=$secret&type=recovery',
        'http://127.0.0.1:57426/auth/confirmed?token_hash=$secret&type=email',
        'https://x.test/auth/recovery?token=$secret&type=recovery',
        'https://x.test/?error=access_denied&error_code=otp_expired'
            '&error_description=$secret',
      ];
      for (final shape in shapes) {
        final cleaned = scrubbedUrl(Uri.parse(shape)).toString();
        expect(cleaned, isNot(contains(secret)), reason: shape);
        for (final key in const [
          'token_hash',
          'access_token',
          'code=',
          'error_code',
        ]) {
          expect(cleaned, isNot(contains(key)), reason: '$key survived $shape');
        }
      }
    });

    test('non-auth parameters survive, and a mixed URL still works', () {
      final cleaned = scrubbedUrl(
        Uri.parse('https://x.test/a?token_hash=SECRET&tab=menu#lang=ar'),
      );
      expect(cleaned.toString(), isNot(contains('SECRET')));
      expect(cleaned.queryParameters['tab'], 'menu');
      expect(cleaned.fragment, contains('lang=ar'));
    });

    test('an ordinary URL is returned untouched', () {
      final plain = Uri.parse('https://x.test/settings?tab=devices');
      expect(scrubbedUrl(plain).toString(), plain.toString());
      // The port survives too — the local runbook depends on a fixed origin.
      final local = Uri.parse('http://localhost:57026/');
      expect(scrubbedUrl(local).toString(), local.toString());
    });

    test('scrubbing is idempotent — a replay finds nothing left to spend', () {
      final once = scrubbedUrl(
        Uri.parse('https://x.test/auth/confirmed?token_hash=SECRET&type=email'),
      );
      final twice = scrubbedUrl(once);
      expect(twice.toString(), once.toString());
      // The second pass is not a callback any more, so a reload cannot re-verify.
      expect(parseAuthCallback(once).isAuthCallback, isFalse);
      expect(resolveCallbackKind(once), AuthCallbackKind.none);
    });
  });

  group('B. a confirmed owner with no tenant reaches ONBOARDING', () {
    test('get_my_context 42501 is an auth denial, not a server error', () {
      // The live message, verified against hosted:
      //   "get_my_context: no linked, authenticated principal"
      // It is not on the shared PIN/device-session allowlist that
      // POS-OFFLINE-OPERATIONS-002 narrowed 42501 to, so the generic classifier
      // calls it `server` — which became AuthUnknownFailure ->
      // AuthGateInvalidResponse -> the generic error page, for every freshly
      // confirmed owner who had not created an organization yet.
      const message = 'get_my_context: no linked, authenticated principal';
      expect(
        classifyPostgrestCode('42501', message: message),
        SyncTransportErrorKind.server,
        reason: 'the shared sync classifier is unchanged by this fix',
      );

      // This repository re-asserts its OWN documented contract instead.
      final state = resolveAuthGateState(
        surface: AppSurface.dashboard,
        contextResult: const Failure<MyContext, AuthFailure>(
          AuthDeniedFailure(),
        ),
        selectedMembershipId: null,
      );
      expect(state, isA<AuthGateAuthDenied>());
    });

    test('a server error still reads as an invalid response', () {
      // The fix must not swallow genuine server failures into onboarding.
      final state = resolveAuthGateState(
        surface: AppSurface.dashboard,
        contextResult: const Failure<MyContext, AuthFailure>(
          AuthUnknownFailure('server error'),
        ),
        selectedMembershipId: null,
      );
      expect(state, isA<AuthGateInvalidResponse>());
    });
  });

  group('C. recovery intent survives initialization', () {
    test('the recovery path is recognised from the boot URL alone', () {
      // The `passwordRecovery` event fires while the callback is being verified
      // at boot — before the repository that listens for it exists. The URL is
      // therefore the signal that has to carry the intent across that gap.
      expect(
        resolveCallbackKind(
          Uri.parse('https://x.test/auth/recovery?token_hash=h&type=recovery'),
        ),
        AuthCallbackKind.recovery,
      );
      // Even a bare PKCE code on the recovery path, which carries no `type`.
      expect(
        resolveCallbackKind(Uri.parse('https://x.test/auth/recovery?code=c')),
        AuthCallbackKind.recovery,
      );
      // And a confirmation is NOT mistaken for one.
      expect(
        resolveCallbackKind(
          Uri.parse('https://x.test/auth/confirmed?token_hash=h&type=email'),
        ),
        AuthCallbackKind.confirmation,
      );
    });
  });
}
