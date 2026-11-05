import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// KIOSK-001-WEB-087 — deterministic guards for the hosted /kiosk route:
/// the Vercel rewrites and the four-app web assembly script. Source scans in
/// the repo's guard-test idiom (CWD-agnostic for `flutter test apps/kiosk`
/// from the repo root or the app dir); no network, no build execution.
File _repoFile(String relative) {
  for (final prefix in ['', '../../']) {
    final f = File('$prefix$relative');
    if (f.existsSync()) return f;
  }
  throw StateError('$relative not found from ${Directory.current.path}');
}

void main() {
  test(
    'vercel.json routes /kiosk and /kiosk/* BEFORE the dashboard catch-all',
    () {
      final config =
          jsonDecode(_repoFile('vercel.json').readAsStringSync())
              as Map<String, dynamic>;
      final rewrites = (config['rewrites'] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (r) => (
              source: r['source'] as String,
              dest: r['destination'] as String,
            ),
          )
          .toList();
      final sources = rewrites.map((r) => r.source).toList();

      // The kiosk pair exists and lands on the kiosk SPA entry.
      expect(sources, contains('/kiosk'));
      expect(sources, contains('/kiosk/(.*)'));
      for (final r in rewrites.where((r) => r.source.startsWith('/kiosk'))) {
        expect(r.dest, '/kiosk/index.html', reason: r.source);
      }

      // The final Dashboard fallback leaves processor paths to static serving
      // (including a real 404 for absent assets), after all device-app routes.
      const dashboardFallback = r'/((?!product-cutout(?:/|$)).*)';
      expect(sources.last, dashboardFallback);
      expect(rewrites.last.dest, '/index.html');
      expect(
        sources.indexOf('/kiosk/(.*)'),
        lessThan(sources.indexOf('/kiosk')),
        reason: 'deep-link rewrite must precede the exact match',
      );
      expect(
        sources.indexOf('/kiosk'),
        lessThan(sources.indexOf(dashboardFallback)),
      );

      // The existing three-app surface is preserved untouched.
      expect(sources, containsAll(['/pos', '/pos/(.*)', '/kds', '/kds/(.*)']));
      for (final app in ['kiosk', 'pos', 'kds']) {
        for (final path in ['/$app', '/$app/', '/$app/orders/123']) {
          final route = rewrites.firstWhere(
            (r) => RegExp('^${r.source}\$').hasMatch(path),
          );
          expect(route.dest, '/$app/index.html', reason: path);
        }
      }

      final fallback = RegExp('^${sources.last}\$');
      for (final path in [
        '/product-cutout',
        '/product-cutout/',
        '/product-cutout/worker.mjs',
        '/product-cutout/assets/${'a' * 64}/u2net-00.bin',
        '/product-cutout/missing.mjs',
      ]) {
        expect(fallback.hasMatch(path), isFalse, reason: path);
      }
      for (final path in [
        '/',
        '/settings',
        '/products/123',
        '/product-cutout-help',
      ]) {
        expect(fallback.hasMatch(path), isTrue, reason: path);
      }
      expect(config['outputDirectory'], 'apps/dashboard/build/web');
    },
  );

  test('the Vercel build script builds and assembles the kiosk at /kiosk/', () {
    final script = _repoFile('tools/vercel_build_web.sh').readAsStringSync();

    // Kiosk is built from its own app dir with EXACTLY the /kiosk/ base-href
    // and the same shared public defines as the other apps.
    expect(script, contains('cd apps/kiosk'));
    expect(script, contains('--base-href=/kiosk/'));
    expect(
      RegExp(r'cd apps/kiosk[^\n]*\$\{DEFINES\[@\]\}').hasMatch(script),
      isTrue,
      reason: 'the kiosk build must reuse the shared DEFINES array',
    );

    // Deterministic assembly: stale output removed, fresh copy under the
    // dashboard output the /kiosk rewrites serve from.
    expect(script, contains('apps/dashboard/build/web/kiosk'));
    final rmLine = script
        .split('\n')
        .firstWhere((l) => l.trimLeft().startsWith('rm -rf'), orElse: () => '');
    expect(
      rmLine,
      contains('apps/dashboard/build/web/kiosk'),
      reason: 'stale kiosk output must be removed before copy',
    );
    expect(
      script.contains(
        'cp -r apps/kiosk/build/web apps/dashboard/build/web/kiosk',
      ),
      isTrue,
    );
    expect(
      script.indexOf('rm -rf'),
      lessThan(script.indexOf('cp -r apps/kiosk/build/web')),
    );

    // The existing three-app assembly is preserved.
    expect(script, contains('--base-href=/pos/'));
    expect(script, contains('--base-href=/kds/'));
    expect(
      script,
      contains('cp -r apps/pos/build/web apps/dashboard/build/web/pos'),
    );
    expect(
      script,
      contains('cp -r apps/kds/build/web apps/dashboard/build/web/kds'),
    );

    // No secret material: public env-var NAMES only.
    expect(script.contains('service_role'), isFalse);
    expect(script.contains('sb_secret_'), isFalse);
    expect(
      script.contains('sb_publishable_'),
      isFalse,
      reason: 'keys travel by env NAME, never as literals',
    );
  });

  test('the kiosk web entry keeps the substitutable base href', () {
    final index = _repoFile('apps/kiosk/web/index.html').readAsStringSync();
    expect(index, contains(r'<base href="$FLUTTER_BASE_HREF">'));
  });
}
