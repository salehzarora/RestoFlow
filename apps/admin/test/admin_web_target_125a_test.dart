import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PLATFORM-ADMIN-125A — the Web target, and the fence around it.
///
/// Until this phase `apps/admin` was the only app of the five with no platform
/// runner at all: the Dart was complete and tested, but `flutter build web`
/// answered "This project is not configured for the web", so the console could
/// not be opened and `_run_admin_real.bat` (tracked since RF-119-b) could never
/// have worked. These tests pin the shell that fixes that.
///
/// They also pin the FENCE. Admin is the internal platform plane (D-026): it is
/// deliberately absent from `tools/vercel_build_web.sh` and from the public
/// `vercel.json` routes, and adding a web target is exactly the change that
/// could let it drift into the public bundle by accident. Group B fails if it
/// ever does.

/// Resolves a repo path whether the test runs with cwd = `apps/admin`
/// (`flutter test apps/admin`) or cwd = repo root — the both-cwd probe the
/// repo's other file-reading tests use.
File _repoFile(String fromAdmin, String fromRoot) {
  final local = File(fromAdmin);
  return local.existsSync() ? local : File(fromRoot);
}

File _web(String name) => _repoFile('web/$name', 'apps/admin/web/$name');

void main() {
  group('A. the Admin web target exists and identifies itself honestly', () {
    test('A1. every bootstrap file the other apps ship is present', () {
      for (final name in const [
        'index.html',
        'manifest.json',
        'favicon.png',
        'icons/Icon-192.png',
        'icons/Icon-512.png',
        'icons/Icon-maskable-192.png',
        'icons/Icon-maskable-512.png',
      ]) {
        expect(
          _web(name).existsSync(),
          isTrue,
          reason: 'apps/admin/web/$name is missing',
        );
      }
    });

    test('A2. the base-href placeholder survives', () {
      // `flutter build` substitutes this. Keeping it is what lets a future
      // internal deployment serve Admin from a sub-path without editing source.
      expect(
        _web('index.html').readAsStringSync(),
        contains(r'$FLUTTER_BASE_HREF'),
      );
    });

    test('A3. the title says Admin — never a tenant surface', () {
      final html = _web('index.html').readAsStringSync();
      expect(html, contains('<title>BIZBOT Admin</title>'));
      // The whole point of the app is that it is NOT the restaurant console.
      // A copy-paste from apps/dashboard/web would silently mislabel it.
      for (final wrong in const [
        'BIZBOT Dashboard',
        'BIZBOT POS',
        'BIZBOT KDS',
        'BIZBOT Kiosk',
      ]) {
        expect(
          html,
          isNot(contains(wrong)),
          reason: '$wrong leaked into Admin',
        );
      }
    });

    test('A4. the shell describes an internal platform console', () {
      final html = _web('index.html').readAsStringSync();
      expect(html, contains('BIZBOT Admin — internal platform'));
      expect(
        html,
        contains('apple-mobile-web-app-title" content="BIZBOT Admin"'),
      );
    });

    test('A5. it is marked noindex — this is not a public product surface', () {
      final html = _web('index.html').readAsStringSync();
      expect(html, contains('name="robots"'));
      expect(html, contains('noindex'));
    });

    test('A6. the manifest names Admin and points at icons that exist', () {
      final manifest =
          jsonDecode(_web('manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['name'], 'BIZBOT Admin');
      expect(manifest['short_name'], 'BIZBOT Admin');
      expect(manifest['description'], contains('internal platform'));
      expect(manifest['prefer_related_applications'], isFalse);
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      expect(icons, hasLength(4));
      for (final icon in icons) {
        expect(
          _web(icon['src'] as String).existsSync(),
          isTrue,
          reason: 'manifest references a missing icon: ${icon['src']}',
        );
      }
    });

    test('A7. the static shell carries NO configuration or credential', () {
      // Backend config reaches the app only through --dart-define at build time
      // (D-011). Anything credential-shaped baked into the HTML/manifest would
      // be committed to source and served to every visitor.
      for (final name in const ['index.html', 'manifest.json']) {
        final text = _web(name).readAsStringSync();
        for (final forbidden in const [
          'sb_secret_',
          'sb_publishable_',
          'service_role',
          'eyJ',
          'RESTOFLOW_SUPABASE_ANON_KEY',
          'supabase.co',
          'localhost:54321',
        ]) {
          expect(
            text,
            isNot(contains(forbidden)),
            reason: '$forbidden must not appear in apps/admin/web/$name',
          );
        }
      }
    });
  });

  group('B. Admin stays OUT of the public web bundle (D-026 platform plane)', () {
    File script() => _repoFile(
      '../../tools/vercel_build_web.sh',
      'tools/vercel_build_web.sh',
    );
    File vercelJson() => _repoFile('../../vercel.json', 'vercel.json');

    test(
      'B1. the public build script builds the four tenant apps, not Admin',
      () {
        final text = script().readAsStringSync();
        for (final app in const ['dashboard', 'pos', 'kds', 'kiosk']) {
          expect(
            text,
            contains('cd apps/$app'),
            reason: 'the public build should still build $app',
          );
        }
        // The assertion that matters: no BUILD step for admin. Matched on the
        // build invocation, not on the word "admin" — the script's own comment
        // explains why Admin is excluded and must be allowed to stay.
        expect(
          text,
          isNot(contains('cd apps/admin')),
          reason: 'Admin must never be built into the public bundle',
        );
      },
    );

    test('B2. no public route serves Admin', () {
      final json = vercelJson().readAsStringSync();
      expect(json.toLowerCase(), isNot(contains('admin')));
      // And the public output stays the Dashboard build, so nothing can ride in.
      final config = jsonDecode(json) as Map<String, dynamic>;
      expect(config['outputDirectory'], 'apps/dashboard/build/web');
    });

    test('B3. the script still states WHY Admin is excluded', () {
      // A comment is not enforcement, but losing it is how the next person
      // "helpfully" adds Admin to the public build.
      expect(
        script().readAsStringSync(),
        contains('Admin is intentionally NOT built'),
      );
    });
  });
}
