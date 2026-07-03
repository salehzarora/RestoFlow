import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import '../data/menu_image_storage.dart';
import '../models/menu_item.dart';
import '../state/menu_providers.dart';

/// Session-lived signed-URL futures, cached PER storage backend (an [Expando],
/// so one surface's storage never serves another's URLs and a torn-down
/// backend stays garbage-collectable). Signed URLs are short-lived by design
/// (private bucket — DECISION D-032); a cache entry outliving its URL is
/// harmless here: already-rendered thumbnails keep their decoded bytes, and a
/// stale-URL load failure just falls back to the placeholder icon.
final Expando<Map<String, Future<Uri>>> _signedUrlCache =
    Expando<Map<String, Future<Uri>>>('menu thumbnail signed-url cache');

/// Resolves (and memoizes) the signed URL for [path] so a list rebuild never
/// re-signs every visible row. FAIL-SOFT: a failed resolution is observed
/// (never an unhandled async error), evicted so a later rebuild may retry,
/// and surfaces only as the placeholder icon — never error chrome or spam.
Future<Uri> _cachedSignedUrl(MenuImageStorage storage, String path) {
  final cache = _signedUrlCache[storage] ??= <String, Future<Uri>>{};
  final existing = cache[path];
  if (existing != null) return existing;
  final future = storage.createSignedUrl(path);
  cache[path] = future;
  future.then<void>((_) {}, onError: (Object _) => cache.remove(path));
  return future;
}

/// A small rounded product thumbnail for catalog rows and the editor's summary
/// strip (menu/media sprint, Part F): the item's image — fetched via a
/// short-lived signed URL from the surface's wired [MenuImageStorage]
/// (private bucket, DECISION D-032) — or the quiet placeholder icon when this
/// surface has no storage wired, the item has no image, or ANY resolution /
/// load step fails. Images are never load-bearing: no spinner, no error text.
class MenuItemThumbnail extends ConsumerWidget {
  const MenuItemThumbnail({required this.item, this.size = 44, super.key});

  final MenuItem item;

  /// The square edge in logical pixels (44–56 keeps rows compact).
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final storage = ref.watch(menuImageStorageProvider)?.storage;
    final imagePath = item.imagePath;

    Widget placeholder() => Icon(
      Icons.image_outlined,
      size: size / 2,
      color: scheme.onSurfaceVariant,
    );

    final Widget content;
    if (storage == null || imagePath == null) {
      content = placeholder();
    } else {
      content = FutureBuilder<Uri>(
        future: _cachedSignedUrl(storage, imagePath),
        builder: (context, snapshot) {
          final url = snapshot.data;
          // Pending AND failed both render the placeholder (fail-soft).
          if (url == null) return placeholder();
          return Image.network(
            url.toString(),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => placeholder(),
          );
        },
      );
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
      ),
      child: content,
    );
  }
}
