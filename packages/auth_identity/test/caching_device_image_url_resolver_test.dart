import 'dart:async';

import 'package:test/test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// EGRESS-REMEDIATION-001 — the POS signed-URL cache decorator.
///
/// The contract under test: menu/business refreshes may re-request URLs as
/// often as they like; the DECORATOR decides whether a network signing
/// actually happens. Unchanged paths inside the validity window reuse the
/// previous URL (so every URL-keyed image cache stays hot); near-expiry and
/// changed paths sign fresh; failures never poison the cache.
class _CountingResolver implements DeviceImageUrlResolver {
  int calls = 0;
  final List<List<String>> batches = [];
  int tokenCounter = 0;
  Set<String> deny = {};
  bool failAll = false;

  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    calls += 1;
    batches.add(List.of(objectKeys));
    if (failAll) throw StateError('transport down');
    tokenCounter += 1;
    return {
      for (final key in objectKeys)
        if (!deny.contains(key))
          key: 'https://s.example$key?token=t$tokenCounter',
    };
  }
}

void main() {
  late _CountingResolver inner;
  late DateTime now;
  late CachingDeviceImageUrlResolver cache;

  setUp(() {
    inner = _CountingResolver();
    now = DateTime.utc(2026, 8, 17, 12);
    cache = CachingDeviceImageUrlResolver(inner, now: () => now);
  });

  test('a second request inside the validity window signs NOTHING and '
      'returns the SAME url (menu refresh reuses; caches stay hot)', () async {
    final first = await cache.signedUrlsFor(['/a.png', '/b.png']);
    expect(inner.calls, 1);
    // Simulates the resume-invalidation: business data refreshed, resolver
    // asked again for the unchanged paths.
    final second = await cache.signedUrlsFor(['/a.png', '/b.png']);
    expect(inner.calls, 1, reason: 'no re-sign inside the window');
    expect(
      second,
      first,
      reason:
          'identical URL strings are what keep the '
          'ImageCache/browser/CDN keys stable',
    );
  });

  test('near expiry exactly one fresh signing happens', () async {
    await cache.signedUrlsFor(['/a.png']);
    expect(inner.calls, 1);
    // 24 minutes later: inside 30min validity but past the 25min refresh
    // horizon (30 - 5 margin).
    now = now.add(const Duration(minutes: 26));
    final refreshed = await cache.signedUrlsFor(['/a.png']);
    expect(inner.calls, 2);
    expect(refreshed['/a.png'], contains('token=t2'));
  });

  test(
    'a changed (versioned) path resolves immediately as a new identity',
    () async {
      await cache.signedUrlsFor(['/item/v1.png']);
      // The image was replaced: the menu now carries the NEW versioned path.
      final next = await cache.signedUrlsFor(['/item/v2.png']);
      expect(inner.calls, 2);
      expect(next.keys, ['/item/v2.png']);
    },
  );

  test(
    'concurrent requests for the same path share ONE signing call',
    () async {
      final results = await Future.wait([
        cache.signedUrlsFor(['/a.png']),
        cache.signedUrlsFor(['/a.png']),
        cache.signedUrlsFor(['/a.png', '/b.png']),
      ]);
      expect(
        inner.calls,
        2,
        reason:
            'one batch for /a.png shared by all three callers, plus one '
            'batch for the extra /b.png',
      );
      expect(results[0]['/a.png'], results[1]['/a.png']);
      expect(results[2]['/a.png'], results[0]['/a.png']);
    },
  );

  test('a failed signing is NOT cached; the next attempt succeeds', () async {
    inner.failAll = true;
    final failed = await cache.signedUrlsFor(['/a.png']);
    expect(failed, isEmpty, reason: 'fail-soft: caller renders imageless');
    inner.failAll = false;
    final ok = await cache.signedUrlsFor(['/a.png']);
    expect(ok['/a.png'], isNotNull);
    expect(inner.calls, 2);
  });

  test('a per-key denial is not cached and is re-attempted next load, while '
      'granted keys keep their cached URL', () async {
    inner.deny = {'/denied.png'};
    final first = await cache.signedUrlsFor(['/ok.png', '/denied.png']);
    expect(first.keys, ['/ok.png']);
    inner.deny = {};
    final second = await cache.signedUrlsFor(['/ok.png', '/denied.png']);
    expect(inner.calls, 2);
    expect(inner.batches.last, [
      '/denied.png',
    ], reason: 'only the previously-denied key re-signs');
    expect(second['/ok.png'], first['/ok.png']);
    expect(second['/denied.png'], isNotNull);
  });

  test('clear() drops the cache (authorization boundary)', () async {
    await cache.signedUrlsFor(['/a.png']);
    cache.clear();
    await cache.signedUrlsFor(['/a.png']);
    expect(inner.calls, 2);
  });

  test(
    'short validity windows clamp the margin instead of disabling reuse',
    () async {
      await cache.signedUrlsFor([
        '/a.png',
      ], expiresIn: const Duration(minutes: 2));
      now = now.add(const Duration(seconds: 30));
      await cache.signedUrlsFor([
        '/a.png',
      ], expiresIn: const Duration(minutes: 2));
      expect(inner.calls, 1, reason: 'margin clamps to validity/2 = 1min');
    },
  );

  test('a STALLED signing batch never hangs callers and a later refresh '
      'starts a fresh batch (reconnect recovery preserved)', () async {
    final stalled = _StalledOnceResolver();
    final bounded = CachingDeviceImageUrlResolver(
      stalled,
      now: () => now,
      inFlightTimeout: const Duration(milliseconds: 50),
    );
    // First call: the inner future never completes; the caller must get a
    // bounded, imageless answer instead of hanging the menu provider.
    final first = await bounded.signedUrlsFor(['/a.png']);
    expect(first, isEmpty);
    expect(stalled.calls, 1);
    // A later refresh (past the joinability horizon) must NOT join the
    // dead batch: it starts fresh and succeeds.
    now = now.add(const Duration(seconds: 1));
    final second = await bounded.signedUrlsFor(['/a.png']);
    expect(stalled.calls, 2);
    expect(second['/a.png'], isNotNull);
  });
}

/// Stalls forever on the FIRST call, succeeds afterwards.
class _StalledOnceResolver implements DeviceImageUrlResolver {
  int calls = 0;

  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) {
    calls += 1;
    if (calls == 1) {
      // Never completes — the stalled-socket failure mode.
      return Completer<Map<String, String>>().future;
    }
    return Future.value({
      for (final k in objectKeys) k: 'https://s.example$k?token=fresh',
    });
  }
}
