/// EGRESS-REMEDIATION-001 — the POS media image provider.
///
/// The egress audit proved menu images were re-downloaded whenever their
/// signed URL rotated (every menu refresh minted a fresh `?token=`), because
/// every cache layer in play keys on the URL STRING. This helper swaps the
/// plain [NetworkImage] under the existing `Image` widgets for a
/// [CachedNetworkImageProvider] whose **cache key is the stable storage
/// object path** (the URL minus its query), backed by a persistent disk cache
/// on io targets:
///
///  * the SAME logical object resolves to the SAME decoded-memory cache entry
///    and the SAME disk file across signed-token rotations, menu refreshes,
///    app resumes and restarts — unchanged images stop re-downloading;
///  * the grid, cart thumbnail and modifier sheet share one downloaded byte
///    file per object (decode sizes may differ; the transfer happens once);
///  * a REPLACED image has a new versioned object path (upload contract), so
///    its key changes and the new image downloads immediately — no restart,
///    no manual cache clearing;
///  * on web the cache manager is memory-backed and the browser HTTP cache
///    (now effective thanks to stable signed URLs) does the persistent work.
///
/// Rendering behavior is intentionally identical to `Image.network`: same
/// widgets, same `fit`/size/`errorBuilder`, no placeholder/fade changes.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The stable cache identity for a signed storage URL: host + URL path (the
/// path embeds the versioned object key) without the rotating token query.
/// The host is included so a device switched between Supabase environments
/// (which can share object paths via dump/restore) can never serve one
/// project's cached bytes for the other. Falls back to the full URL when
/// parsing fails — never throws.
String stableMediaCacheKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.path.isEmpty) return url;
  return '${uri.host}${uri.path}';
}

/// One shared cache manager for POS menu media. Long stale period bounded by
/// object count: the whole catalog is a few dozen small files, and replaced
/// images arrive under NEW keys, so old entries simply age out.
class PosMediaCache {
  PosMediaCache._();

  static const key = 'posMenuMediaCache';

  static CacheManager? _instance;

  static CacheManager get instance => _instance ??= CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 400,
    ),
  );

  /// EGRESS-REMEDIATION-001.1 — the PAIRING-BOUNDARY wipe. Empties the
  /// persistent byte cache IF one was ever created (a no-op otherwise, which
  /// also keeps widget tests off the platform channels). Best-effort: a file
  /// system failure is swallowed — an unpair must never hang or crash on
  /// cache cleanup, and a leftover file is retention-only (it can never be
  /// DISPLAYED again: the new pairing's menu references its own org's paths).
  static Future<void> clearIfCreated() async {
    final cache = _instance;
    if (cache == null) return;
    try {
      await cache.emptyCache();
    } catch (_) {
      // Best-effort by design.
    }
  }
}

/// Test seam: widget tests replace the provider factory (e.g. with plain
/// [NetworkImage]) so no cache manager/platform channels are exercised.
@visibleForTesting
ImageProvider Function(String url)? debugPosMediaImageProviderOverride;

/// Test seam: identity/equality tests build the REAL provider without
/// instantiating the platform-backed cache manager (whose construction needs
/// path_provider channels). Provider equality never involves the manager.
@visibleForTesting
bool debugPosMediaSkipCacheManager = false;

/// The image provider for a POS menu-media [url] (a signed storage URL).
///
/// `imageRenderMethodForWeb: HttpGet` keeps web decoding byte-based (exactly
/// like the previous `NetworkImage`, which also fetched bytes over CORS on
/// this deployment), so `cacheWidth`-style decode caps keep working on web —
/// the default HtmlImage path would silently ignore them.
ImageProvider posMediaImageProvider(String url) =>
    debugPosMediaImageProviderOverride?.call(url) ??
    CachedNetworkImageProvider(
      url,
      cacheKey: stableMediaCacheKey(url),
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      cacheManager: debugPosMediaSkipCacheManager
          ? null
          : PosMediaCache.instance,
    );
