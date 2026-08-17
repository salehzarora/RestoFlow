/// EGRESS-REMEDIATION-001 — the shared, expiry-aware signed-URL cache.
///
/// The egress audit proved the dominant Storage cost is URL CHURN: logically
/// identical private objects were re-signed on every surface visit, and every
/// fresh `?token=` busts the browser HTTP cache, Flutter's URL-keyed
/// [ImageCache], and the CDN cache key at once — so unchanged images
/// re-downloaded at full byte size.
///
/// This cache decouples "the surface refreshed" from "the URL changed": one
/// signed URL per OBJECT PATH is reused while safely inside its validity
/// window and re-signed only near expiry (a conservative refresh margin keeps
/// the current 30-minute authorization window — this phase never extends it).
///
/// Semantics:
///  * keyed by the stable storage object path — a REPLACED image gets a new
///    versioned path (upload contract), so it is a new cache identity and
///    resolves immediately: no restart, no manual cache clearing;
///  * the future is stored synchronously, so concurrent requests for the same
///    path share ONE in-flight signing call;
///  * only successful signs stay cached: a failed future evicts itself (if
///    still current) so a later rebuild can retry — transient errors never
///    poison the cache;
///  * instances are scoped to one storage backend via [signedUrlCacheFor]
///    (an [Expando]), which preserves the existing session/authorization
///    boundary: a torn-down backend takes its URLs with it, and one surface's
///    storage never serves another's URLs.
library;

/// The ONE signing validity used by every dashboard media surface — passed
/// BOTH to `createSignedUrl(expiresIn:)` and to [SignedUrlCache.resolve]'s
/// `validity`, so the cache's reuse horizon can never silently diverge from
/// the URL's actual lifetime.
const Duration kSignedUrlValidity = Duration(minutes: 30);

/// One cached signing: the shared future plus the moment it stops being safe
/// to reuse (expiry minus the refresh margin).
class _SignedUrlEntry {
  _SignedUrlEntry(this.future, this.refreshAfter);

  final Future<Uri> future;
  final DateTime refreshAfter;
}

/// A path-keyed signed-URL cache with a conservative pre-expiry refresh.
class SignedUrlCache {
  SignedUrlCache({
    DateTime Function()? now,
    this.refreshMargin = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// How long before the URL's actual expiry it is treated as stale. Clamped
  /// to half the validity so short-lived test windows still get reuse.
  final Duration refreshMargin;

  final Map<String, _SignedUrlEntry> _entries = <String, _SignedUrlEntry>{};

  /// Returns the cached signed URL for [path] while safely valid; otherwise
  /// calls [sign] exactly once (shared by concurrent callers) and caches the
  /// result for `validity - margin`.
  Future<Uri> resolve(
    String path, {
    Duration validity = kSignedUrlValidity,
    required Future<Uri> Function() sign,
  }) {
    final now = _now();
    final existing = _entries[path];
    if (existing != null && now.isBefore(existing.refreshAfter)) {
      return existing.future;
    }
    final margin = refreshMargin >= validity ? validity ~/ 2 : refreshMargin;
    final future = sign();
    final entry = _SignedUrlEntry(future, now.add(validity - margin));
    _entries[path] = entry;
    future.then<void>(
      (_) {},
      onError: (Object _) {
        // Evict ONLY if this entry is still the current one — a newer
        // successful sign for the same path must never be dropped by a stale
        // failure completing late.
        if (identical(_entries[path], entry)) _entries.remove(path);
      },
    );
    return future;
  }

  /// Drops every cached URL (session/authorization boundary).
  void clear() => _entries.clear();
}

final Expando<SignedUrlCache> _perOwner = Expando<SignedUrlCache>(
  'signed-url cache per storage backend',
);

/// The [SignedUrlCache] owned by [owner] (typically a storage backend
/// instance), created on first use. Keying on the backend instance preserves
/// the existing auth boundary: caches die with their backend and are never
/// shared across surfaces with different storage wiring.
SignedUrlCache signedUrlCacheFor(Object owner) =>
    _perOwner[owner] ??= SignedUrlCache();
