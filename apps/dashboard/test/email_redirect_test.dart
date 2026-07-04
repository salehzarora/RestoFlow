import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/auth/email_redirect.dart';

/// Verifies the sign-up email-confirmation redirect resolution (production
/// email-confirmation redirect fix): production must never redirect to
/// localhost, the configured app URL wins when provided, and local dev keeps
/// working.
void main() {
  const prodUrl = 'https://resto-flow-phi.vercel.app';

  group('resolveEmailRedirectUrl', () {
    test('uses RESTOFLOW_APP_URL (configured) when provided', () {
      final result = resolveEmailRedirectUrl(
        configuredAppUrl: prodUrl,
        base: Uri.parse('$prodUrl/login'),
      );
      expect(result, prodUrl);
      expect(result, isNot(contains('localhost')));
    });

    test(
      'configured app URL WINS over the base origin (production build never '
      'emits localhost even if served from an unexpected origin)',
      () {
        final result = resolveEmailRedirectUrl(
          configuredAppUrl: prodUrl,
          base: Uri.parse('http://localhost:3000'),
        );
        expect(result, prodUrl);
        expect(result, isNot(contains('localhost')));
      },
    );

    test(
      'falls back to the live web origin (production) when no app URL is '
      'configured — and that origin is NOT localhost',
      () {
        final result = resolveEmailRedirectUrl(
          configuredAppUrl: '',
          base: Uri.parse('$prodUrl/auth/callback?code=abc'),
        );
        expect(result, prodUrl);
        expect(result, isNot(contains('localhost')));
      },
    );

    test('local dev still works: an http localhost origin is preserved', () {
      final result = resolveEmailRedirectUrl(
        configuredAppUrl: '',
        base: Uri.parse('http://localhost:57026/'),
      );
      expect(result, 'http://localhost:57026');
    });

    test('blank/whitespace configured value is treated as unset', () {
      final result = resolveEmailRedirectUrl(
        configuredAppUrl: '   ',
        base: Uri.parse(prodUrl),
      );
      expect(result, prodUrl);
    });

    test('strips path/query, returning only the origin', () {
      final result = resolveEmailRedirectUrl(
        configuredAppUrl: '',
        base: Uri.parse('$prodUrl/x/y?z=1#frag'),
      );
      expect(result, prodUrl);
    });

    test(
      'non-http(s) base (e.g. flutter test file: URI) yields null so GoTrue '
      'uses its own configured Site URL — we never invent one',
      () {
        final result = resolveEmailRedirectUrl(
          configuredAppUrl: '',
          base: Uri.parse('file:///home/dev/project'),
        );
        expect(result, isNull);
      },
    );
  });
}
