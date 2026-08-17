import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/media/pos_media_image.dart';

/// EGRESS-REMEDIATION-001 — the stable-key provider contract.
///
/// The whole point of the media provider is that a ROTATED signed token does
/// not change the image identity: the decoded-memory cache key and the
/// persistent-cache key both derive from the stable object path, so a menu
/// refresh that re-signs URLs cannot force re-downloads or re-decodes of
/// unchanged images.
void main() {
  const pathA =
      '/storage/v1/object/sign/menu-images/org/rest/branch/item/imgA.png';
  const pathB =
      '/storage/v1/object/sign/menu-images/org/rest/branch/item/imgB.png';

  group('stableMediaCacheKey', () {
    test('strips the rotating token query, keeps host + object path', () {
      expect(
        stableMediaCacheKey('https://x.supabase.co$pathA?token=SECRET1'),
        'x.supabase.co$pathA',
      );
      expect(
        stableMediaCacheKey('https://x.supabase.co$pathA?token=SECRET2'),
        'x.supabase.co$pathA',
      );
    });

    test('different hosts (environments) never share a cache identity', () {
      expect(
        stableMediaCacheKey('https://a.supabase.co$pathA?token=t'),
        isNot(stableMediaCacheKey('https://b.supabase.co$pathA?token=t')),
      );
    });

    test('distinct object paths stay distinct (versioned replacement)', () {
      expect(
        stableMediaCacheKey('https://x.supabase.co$pathA?token=t'),
        isNot(stableMediaCacheKey('https://x.supabase.co$pathB?token=t')),
      );
    });

    test('falls back to the raw url when parsing yields no path', () {
      expect(stableMediaCacheKey(''), '');
    });
  });

  group('provider identity across token rotation', () {
    setUp(() {
      // These tests construct the REAL provider (the test-config override
      // must not intercept it); the platform-backed cache manager itself is
      // skipped — provider identity never involves it.
      debugPosMediaImageProviderOverride = null;
      debugPosMediaSkipCacheManager = true;
    });

    tearDown(() {
      debugPosMediaImageProviderOverride = NetworkImage.new;
      debugPosMediaSkipCacheManager = false;
    });

    test('two rotations of the same object are the SAME image identity', () {
      final gen1 =
          posMediaImageProvider('https://x.supabase.co$pathA?token=one')
              as CachedNetworkImageProvider;
      final gen2 =
          posMediaImageProvider('https://x.supabase.co$pathA?token=two')
              as CachedNetworkImageProvider;
      expect(
        gen1,
        gen2,
        reason:
            'equal providers share one decoded-memory cache entry '
            'across signing generations',
      );
      expect(gen1.hashCode, gen2.hashCode);
      expect(
        gen1.cacheKey,
        'x.supabase.co$pathA',
        reason:
            'the persistent byte cache is keyed by host + object path, '
            'never the token',
      );
    });

    test('a replaced (re-versioned) object is a DIFFERENT identity', () {
      final a = posMediaImageProvider('https://x.supabase.co$pathA?token=t');
      final b = posMediaImageProvider('https://x.supabase.co$pathB?token=t');
      expect(a, isNot(b));
    });

    test('ResizeImage wrapping (the grid/cart decode cap) preserves identity '
        'across rotation at the same width', () {
      ImageProvider wrapped(String url) =>
          ResizeImage.resizeIfNeeded(320, null, posMediaImageProvider(url));
      expect(
        wrapped('https://x.supabase.co$pathA?token=one'),
        wrapped('https://x.supabase.co$pathA?token=two'),
      );
    });
  });

  test('the widget-test override routes back to plain NetworkImage', () {
    debugPosMediaImageProviderOverride = NetworkImage.new;
    final provider = posMediaImageProvider('https://x.example/a.png');
    expect(provider, isA<NetworkImage>());
  });
}
