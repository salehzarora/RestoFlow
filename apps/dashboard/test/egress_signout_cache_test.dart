import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/auth/supabase_dashboard_auth.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show signedUrlCacheFor;
import 'package:supabase/supabase.dart';

/// EGRESS-REMEDIATION-001.1 — the dashboard SIGN-OUT auth boundary.
///
/// The real wiring (buildDashboardRealAuth) builds both media storages and
/// hooks their signed-URL caches to the auth repository's sign-out. This test
/// exercises that EXACT wiring — no network is needed because the caches
/// accept injected sign closures, and the GoTrue sign-out against an
/// unreachable host still runs the cleanup (finally semantics).
void main() {
  test(
    'sign-out clears BOTH media URL caches; ordinary re-resolves do not',
    () async {
      final real = buildDashboardRealAuth(
        SupabaseClient('http://127.0.0.1:9', 'test-anon-key'),
      );
      var menuSigns = 0;
      var logoSigns = 0;
      Future<Uri> signMenu() async {
        menuSigns += 1;
        return Uri.parse('https://s.example/menu?token=m$menuSigns');
      }

      Future<Uri> signLogo() async {
        logoSigns += 1;
        return Uri.parse('https://s.example/logo?token=l$logoSigns');
      }

      // Warm both caches exactly as the thumbnails/logo surfaces do.
      await signedUrlCacheFor(
        real.menuImageStorage,
      ).resolve('org/item/img.png', sign: signMenu);
      await signedUrlCacheFor(
        real.brandingLogoStorage,
      ).resolve('org/logo.png', sign: signLogo);
      expect(menuSigns, 1);
      expect(logoSigns, 1);

      // ORDINARY operation (rebuilds, tab revisits) re-resolves WITHOUT
      // clearing: still one sign each.
      await signedUrlCacheFor(
        real.menuImageStorage,
      ).resolve('org/item/img.png', sign: signMenu);
      await signedUrlCacheFor(
        real.brandingLogoStorage,
      ).resolve('org/logo.png', sign: signLogo);
      expect(menuSigns, 1, reason: 'normal usage keeps the cache');
      expect(logoSigns, 1);

      // The AUTH BOUNDARY: sign-out. The GoTrue call may fail (unreachable
      // host) — the cleanup must run regardless and sign-out must not hang.
      try {
        await real.auth.signOut().timeout(const Duration(seconds: 10));
      } catch (_) {
        // Network failure is fine; the local teardown still happened.
      }

      // Both caches are gone: the next resolves sign fresh (a re-signed-in
      // operator resolves their media normally through the same path).
      await signedUrlCacheFor(
        real.menuImageStorage,
      ).resolve('org/item/img.png', sign: signMenu);
      await signedUrlCacheFor(
        real.brandingLogoStorage,
      ).resolve('org/logo.png', sign: signLogo);
      expect(menuSigns, 2, reason: 'sign-out cleared the menu URL cache');
      expect(logoSigns, 2, reason: 'sign-out cleared the logo URL cache');
    },
  );

  test('signOut invokes the cleanup callback even when the network call '
      'throws, and never converts cleanup failure into an error', () async {
    var cleaned = 0;
    final repo = SupabaseDashboardAuthRepository(
      SupabaseClient('http://127.0.0.1:9', 'test-anon-key'),
      onSignedOut: () {
        cleaned += 1;
        throw StateError('cleanup hiccup — must be swallowed');
      },
    );
    try {
      await repo.signOut().timeout(const Duration(seconds: 10));
    } on StateError {
      fail('cleanup failure must never surface from signOut');
    } catch (_) {
      // A GoTrue/network error is acceptable and matches pre-change behavior.
    }
    expect(cleaned, 1);
  });
}
