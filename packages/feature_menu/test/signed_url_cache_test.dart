import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

/// EGRESS-REMEDIATION-001 — the shared dashboard signed-URL cache.
void main() {
  late DateTime now;
  late SignedUrlCache cache;
  late int signs;

  Future<Uri> Function() signer(String tag) => () async {
    signs += 1;
    return Uri.parse('https://s.example/$tag?token=t$signs');
  };

  setUp(() {
    now = DateTime.utc(2026, 8, 17, 12);
    signs = 0;
    cache = SignedUrlCache(now: () => now);
  });

  test('reuses the SAME url future inside the validity window', () async {
    final a = await cache.resolve('p1', sign: signer('p1'));
    final b = await cache.resolve('p1', sign: signer('p1'));
    expect(signs, 1);
    expect(identical(a, b) || a == b, isTrue);
  });

  test(
    're-signs exactly once near expiry (30min validity, 5min margin)',
    () async {
      await cache.resolve('p1', sign: signer('p1'));
      now = now.add(const Duration(minutes: 26));
      final refreshed = await cache.resolve('p1', sign: signer('p1'));
      expect(signs, 2);
      expect(refreshed.query, 'token=t2');
    },
  );

  test(
    'a changed (versioned) path is a NEW identity and resolves fresh',
    () async {
      await cache.resolve('item/v1.png', sign: signer('v1'));
      await cache.resolve('item/v2.png', sign: signer('v2'));
      expect(signs, 2);
    },
  );

  test('concurrent same-path callers share ONE in-flight signing', () async {
    final results = await Future.wait([
      cache.resolve('p1', sign: signer('p1')),
      cache.resolve('p1', sign: signer('p1')),
    ]);
    expect(signs, 1);
    expect(results[0], results[1]);
  });

  test('a failed signing evicts itself so a later call retries', () async {
    Future<Uri> failing() async => throw StateError('down');
    await expectLater(cache.resolve('p1', sign: failing), throwsStateError);
    // Let the eviction hook run.
    await Future<void>.delayed(Duration.zero);
    final ok = await cache.resolve('p1', sign: signer('p1'));
    expect(ok.query, 'token=t1');
  });

  test('a stale failure completing late never drops a newer success', () async {
    // First sign fails but ONLY after a newer sign replaced it.
    late void Function() failNow;
    final slowFailure = Future<Uri>.delayed(
      const Duration(milliseconds: 1),
      () => throw StateError('late failure'),
    );
    // Swallow at source too: resolve() attaches its own observer.
    slowFailure.catchError((Object _) => Uri());
    failNow = () {};
    final first = cache.resolve('p1', sign: () => slowFailure);
    // Force-expire the failed entry, then succeed with a new sign.
    now = now.add(const Duration(minutes: 26));
    final second = cache.resolve('p1', sign: signer('p1'));
    await expectLater(first, throwsStateError);
    expect(await second, isNotNull);
    // The success must still be cached (the stale failure must not evict it).
    final third = await cache.resolve('p1', sign: signer('p1'));
    expect(third.query, 'token=t1');
    failNow();
  });

  test('clear() drops everything (session boundary)', () async {
    await cache.resolve('p1', sign: signer('p1'));
    cache.clear();
    await cache.resolve('p1', sign: signer('p1'));
    expect(signs, 2);
  });

  test('signedUrlCacheFor scopes caches per owner instance', () async {
    final ownerA = Object();
    final ownerB = Object();
    expect(
      identical(signedUrlCacheFor(ownerA), signedUrlCacheFor(ownerA)),
      isTrue,
    );
    expect(
      identical(signedUrlCacheFor(ownerA), signedUrlCacheFor(ownerB)),
      isFalse,
    );
  });
}
