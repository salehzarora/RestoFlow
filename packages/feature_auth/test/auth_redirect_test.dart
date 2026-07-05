import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// RF-LIVE-002 — [resolveAuthRedirectUrl] must produce a correct
/// `emailRedirectTo` for localhost dev, Vercel preview/production, and custom
/// domains, WITHOUT hardcoding a single production URL, and must never leak a
/// secret. Non-web returns null (SDK default). The env-reading wrapper is a thin
/// shim over this pure decision.
void main() {
  group('resolveAuthRedirectUrl', () {
    test(
      'web: derives the origin from the current URL (localhost dev keeps the '
      'port)',
      () {
        final url = resolveAuthRedirectUrl(
          isWeb: true,
          currentUri: Uri.parse('http://localhost:57026/#/signup'),
        );
        expect(url, 'http://localhost:57026');
      },
    );

    test('web: a Vercel production origin (default https port is omitted)', () {
      final url = resolveAuthRedirectUrl(
        isWeb: true,
        currentUri: Uri.parse('https://restoflow.vercel.app/#/signup?x=1'),
      );
      expect(url, 'https://restoflow.vercel.app');
    });

    test('web: a Vercel PREVIEW deploy origin is followed automatically', () {
      final url = resolveAuthRedirectUrl(
        isWeb: true,
        currentUri: Uri.parse('https://restoflow-git-feat-abc.vercel.app/'),
      );
      expect(url, 'https://restoflow-git-feat-abc.vercel.app');
    });

    test('an explicit override wins over the origin (custom domain later)', () {
      final url = resolveAuthRedirectUrl(
        isWeb: true,
        currentUri: Uri.parse('https://restoflow.vercel.app/'),
        configuredOverride: 'https://app.myrestaurant.com',
      );
      expect(url, 'https://app.myrestaurant.com');
    });

    test('override is honored even on a non-web build', () {
      final url = resolveAuthRedirectUrl(
        isWeb: false,
        configuredOverride: 'https://app.myrestaurant.com',
      );
      expect(url, 'https://app.myrestaurant.com');
    });

    test('blank/whitespace override is ignored (falls through to origin)', () {
      final url = resolveAuthRedirectUrl(
        isWeb: true,
        currentUri: Uri.parse('http://localhost:57026/'),
        configuredOverride: '   ',
      );
      expect(url, 'http://localhost:57026');
    });

    test('non-web with no override returns null (uses the SDK default; never a '
        'localhost fallback)', () {
      expect(resolveAuthRedirectUrl(isWeb: false), isNull);
    });

    test('web but a non-http(s) origin (e.g. file://) returns null, not a bad '
        'redirect', () {
      final url = resolveAuthRedirectUrl(
        isWeb: true,
        currentUri: Uri.parse('file:///C:/app/index.html'),
      );
      expect(url, isNull);
    });

    test('never emits a secret-shaped value — it only echoes the given origin/'
        'override', () {
      final url = resolveAuthRedirectUrl(
        isWeb: true,
        currentUri: Uri.parse('https://restoflow.vercel.app/'),
      );
      expect(url, isNotNull);
      expect(url, isNot(contains('eyJ')));
      expect(url, isNot(contains('sb_secret')));
    });
  });

  group('authRedirectUrlFromEnvironment', () {
    test('in a (non-web) unit test with no override, returns null — never a '
        'localhost/dev value', () {
      // The test VM is non-web and no RESTOFLOW_AUTH_REDIRECT_URL dart-define is
      // set, so the wrapper must fall through to the SDK default (null).
      expect(authRedirectUrlFromEnvironment(), isNull);
    });
  });
}
