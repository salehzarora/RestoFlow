import 'device_image_url_resolver.dart';

/// EGRESS-REMEDIATION-001 — the path-keyed, expiry-aware signed-URL cache in
/// front of a real [DeviceImageUrlResolver].
///
/// The egress audit proved the POS re-signed EVERY menu image on EVERY menu
/// provider rebuild (app resume, reconnect recovery, PIN/session transitions,
/// availability edits, staleness refusals). Each re-sign minted a fresh
/// `?token=`, which changed the URL string and therefore busted Flutter's
/// URL-keyed [ImageCache], the browser HTTP cache, and the CDN cache key at
/// once — an unchanged 2MB product photo re-downloaded on every wake of the
/// till.
///
/// This decorator decouples "menu/business data refreshed" from "image URL
/// changed": the menu provider keeps refreshing exactly as before, but an
/// object path that is still inside its signing validity window (minus a
/// conservative refresh margin) reuses the PREVIOUS signed URL, so every
/// cache layer stays hot. Near expiry the path is re-signed as before — the
/// 30-minute authorization window itself is unchanged in this phase.
///
/// Contract details:
///  * keyed by the storage OBJECT PATH — a replaced image has a new versioned
///    path (upload contract) and therefore resolves immediately as a new
///    identity: no restart needed for edited images;
///  * concurrent requests for overlapping path sets share the in-flight
///    signing batch (at most one signing call per path at a time);
///  * only successful signs are cached; per-key failures (policy-denied /
///    missing objects) and transport errors stay uncached so a later menu
///    load retries them — transient failures never poison the cache;
///  * the cache lives inside the resolver instance. The POS wires ONE
///    resolver per device bootstrap (the same anonymously-authenticated
///    device client as the transport), so the cache's lifetime equals the
///    authorization principal's lifetime — there is no cross-device or
///    cross-tenant reuse surface. PIN users on the same paired device already
///    share the device-scoped SELECT policy, so reuse across PIN sessions is
///    exactly as safe as the signing itself.
class CachingDeviceImageUrlResolver implements DeviceImageUrlResolver {
  CachingDeviceImageUrlResolver(
    this._inner, {
    DateTime Function()? now,
    this.refreshMargin = const Duration(minutes: 5),
    this.inFlightTimeout = const Duration(seconds: 20),
  }) : _now = now ?? DateTime.now;

  final DeviceImageUrlResolver _inner;
  final DateTime Function() _now;

  /// How long before actual expiry a cached URL is considered stale (clamped
  /// to half the validity for short windows).
  final Duration refreshMargin;

  /// How long an in-flight signing batch stays JOINABLE, and how long a
  /// caller waits on a joined batch. A stalled socket (no default HTTP
  /// timeout on mobile) must degrade to "imageless this load, retry next
  /// load" — pre-change every menu refresh got a fresh signing attempt, and
  /// this bound preserves that recovery: a later refresh finding a
  /// stale-in-flight batch starts a NEW one instead of joining the dead one,
  /// and no caller ever hangs the menu provider on a signing that never
  /// completes.
  final Duration inFlightTimeout;

  final Map<String, _CachedSignedUrl> _cache = <String, _CachedSignedUrl>{};
  final Map<String, _InFlightBatch> _inFlight = <String, _InFlightBatch>{};

  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    if (objectKeys.isEmpty) return const {};
    final now = _now();
    final result = <String, String>{};
    final missing = <String>[];
    for (final key in objectKeys) {
      final cached = _cache[key];
      if (cached != null && now.isBefore(cached.refreshAfter)) {
        result[key] = cached.url;
      } else if (!missing.contains(key)) {
        missing.add(key);
      }
    }
    if (missing.isEmpty) return result;

    // Split the misses into paths already being signed by a concurrent call
    // (join their batch — but ONLY while it is fresh enough to still be
    // believed alive) and paths nobody is usefully signing (one new batch).
    final joins = <Future<Map<String, String>>>{};
    final toSign = <String>[];
    for (final key in missing) {
      final pending = _inFlight[key];
      if (pending != null &&
          now.difference(pending.startedAt) < inFlightTimeout) {
        joins.add(pending.future);
      } else {
        toSign.add(key);
      }
    }
    if (toSign.isNotEmpty) {
      final margin = refreshMargin >= expiresIn
          ? expiresIn ~/ 2
          : refreshMargin;
      final refreshAfter = now.add(expiresIn - margin);
      final generationAtStart = _generation;
      final batch = _inner.signedUrlsFor(toSign, expiresIn: expiresIn).then((
        urls,
      ) {
        // Cache ONLY the successful keys; absent keys (denied/missing) and
        // thrown transport errors stay uncached so a later load can retry.
        // A batch that crossed a clear() (generation bump) returns its URLs
        // to its own callers but must not repopulate the wiped cache.
        if (generationAtStart == _generation) {
          for (final entry in urls.entries) {
            _cache[entry.key] = _CachedSignedUrl(entry.value, refreshAfter);
          }
        }
        return urls;
      });
      final entry = _InFlightBatch(batch, now);
      final guarded = batch.whenComplete(() {
        for (final key in toSign) {
          if (identical(_inFlight[key], entry)) _inFlight.remove(key);
        }
      });
      for (final key in toSign) {
        _inFlight[key] = entry;
      }
      joins.add(guarded);
    }
    for (final batch in joins) {
      Map<String, String> urls;
      try {
        // The wait itself is BOUNDED: a hung signing yields "imageless this
        // load" instead of hanging the caller (the menu provider awaits us).
        urls = await batch.timeout(inFlightTimeout, onTimeout: () => const {});
      } catch (_) {
        // The caller treats a failed resolution as "imageless" (fail-soft);
        // a shared batch failure must not break the merged result of the
        // paths that DID resolve from cache.
        continue;
      }
      for (final key in missing) {
        final url = urls[key];
        if (url != null) result[key] = url;
      }
    }
    return result;
  }

  /// Drops every cached URL AND forgets in-flight batches (authorization
  /// boundary — e.g. a re-bootstrap). The generation bump makes a batch that
  /// was still in flight across the wipe unable to write stale entries into
  /// the fresh cache (its write closure checks the generation it started in).
  void clear() {
    _generation += 1;
    _cache.clear();
    _inFlight.clear();
  }

  /// Bumped by [clear]; see [clear].
  int _generation = 0;
}

class _CachedSignedUrl {
  _CachedSignedUrl(this.url, this.refreshAfter);

  final String url;
  final DateTime refreshAfter;
}

class _InFlightBatch {
  _InFlightBatch(this.future, this.startedAt);

  final Future<Map<String, String>> future;
  final DateTime startedAt;
}
