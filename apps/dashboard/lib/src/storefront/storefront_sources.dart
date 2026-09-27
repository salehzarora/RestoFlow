import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show MenuReadSource, MenuScope;

import '../branding/restaurant_logo_repository.dart';

/// STOREFRONT-PUBLISH-001 — the read-only lookups the Settings "Storefront"
/// editor needs besides the profile itself: the restaurant's branches (the
/// storefront branch picker) and the PRIVATE originals a public derivative may
/// be made from (logo: the current receipt logo only; hero: the receipt logo
/// or a menu item's original image — owner decisions D3/D4).
///
/// Nothing here writes, and nothing here ever makes an original public: the
/// keys are handed to the `storefront-media-publish` function, which reads the
/// original AS THE CALLER and publishes only a transformed derivative.

/// One branch of the restaurant, as `list_org_structure` serves it.
class StorefrontBranchOption {
  const StorefrontBranchOption({
    required this.id,
    required this.name,
    this.timezone,
    this.restaurantTimezone,
    this.status,
  });

  final String id;
  final String name;

  /// The branch's lifecycle status as served (`active` | `suspended`), or
  /// null when the read did not say. The public read serves nothing for a
  /// suspended branch (READ-001: `b_status <> 'active'` is `not_found`), so
  /// the picker marks it (Q-035).
  final String? status;

  /// The read says this branch is not active (e.g. `suspended`).
  bool get isSuspended => status != null && status != 'active';

  /// The branch's OWN IANA timezone, or null when none is set.
  final String? timezone;

  /// The restaurant's IANA timezone (same read), or null when none is set.
  final String? restaurantTimezone;

  /// The zone the storefront would interpret the hours in with this branch:
  /// the server's `coalesce(branch.timezone, restaurant.timezone)`; null when
  /// neither is set (the `timezone_missing` blocker).
  String? get effectiveTimezone => timezone ?? restaurantTimezone;
}

/// The restaurant's branches for the storefront branch picker. Faked in
/// widget tests.
abstract interface class StorefrontBranchSource {
  /// The branches of THIS restaurant, or null when they cannot be read
  /// (fail-soft: the picker then says so instead of inventing options).
  Future<List<StorefrontBranchOption>?> list();
}

/// The real [StorefrontBranchSource] over `public.list_org_structure`
/// (manager+, GUC-free) — the same read the Settings prefill uses. Only the
/// branches of [restaurantId] are returned.
class SupabaseStorefrontBranchSource implements StorefrontBranchSource {
  SupabaseStorefrontBranchSource({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
  }) : _t = transport;

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;

  @override
  Future<List<StorefrontBranchOption>?> list() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_org_structure', <String, dynamic>{
        'p_organization_id': organizationId,
      });
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    final restaurants = raw['restaurants'];
    if (restaurants is! List) return null;
    for (final r in restaurants) {
      if (r is! Map) continue;
      final id = r['id'];
      if (id is! String || id.toLowerCase() != restaurantId.toLowerCase()) {
        continue;
      }
      final branches = r['branches'];
      if (branches is! List) return const <StorefrontBranchOption>[];
      final restaurantZone = _zone(r['timezone']);
      return List.unmodifiable([
        for (final b in branches)
          if (b is Map && b['id'] is String && (b['id'] as String).isNotEmpty)
            StorefrontBranchOption(
              id: b['id'] as String,
              name: b['name'] is String && (b['name'] as String).isNotEmpty
                  ? b['name'] as String
                  : b['id'] as String,
              timezone: _zone(b['timezone']),
              restaurantTimezone: restaurantZone,
              status:
                  b['status'] is String && (b['status'] as String).isNotEmpty
                  ? b['status'] as String
                  : null,
            ),
      ]);
    }
    // The restaurant is not in the caller's structure read: no options.
    return null;
  }

  static String? _zone(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// One menu item whose ORIGINAL image may become the storefront hero.
class StorefrontMenuImageOption {
  const StorefrontMenuImageOption({
    required this.itemId,
    required this.itemName,
    required this.imageKey,
  });

  final String itemId;
  final String itemName;

  /// The private `menu-images` object key of the item's current image.
  final String imageKey;
}

/// The candidate sources, each list independently fail-soft.
class StorefrontSourceOptions {
  const StorefrontSourceOptions({
    this.receiptLogoKey,
    this.receiptLogoUnavailable = false,
    this.menuImages = const <StorefrontMenuImageOption>[],
    this.menuImagesUnavailable = false,
  });

  /// The restaurant's CURRENT receipt logo key (`restaurant-logos`), or null
  /// when there is none (or it could not be read — see
  /// [receiptLogoUnavailable]).
  final String? receiptLogoKey;

  /// The receipt-logo read failed (not the same as "no logo").
  final bool receiptLogoUnavailable;

  /// The menu items with an original image (hero candidates), by name.
  final List<StorefrontMenuImageOption> menuImages;

  /// The menu read failed (not the same as "no images").
  final bool menuImagesUnavailable;
}

/// Loads the candidate sources. Faked in widget tests.
abstract interface class StorefrontSourceCatalog {
  /// Never throws: every failure is a flag on [StorefrontSourceOptions].
  Future<StorefrontSourceOptions> load();
}

/// The Dashboard's [StorefrontSourceCatalog]: the receipt logo through the
/// branding read (`get_restaurant_receipt_logo` -> `receipt_logo_path`) and
/// the menu originals through the Dashboard menu read (`list_menu` ->
/// `image_path`). Either seam may be absent (then that list is unavailable).
class DashboardStorefrontSourceCatalog implements StorefrontSourceCatalog {
  const DashboardStorefrontSourceCatalog({
    this.logoRepository,
    this.menuReadSource,
    this.menuScope,
  });

  final RestaurantLogoRepository? logoRepository;
  final MenuReadSource? menuReadSource;
  final MenuScope? menuScope;

  @override
  Future<StorefrontSourceOptions> load() async {
    final results = await Future.wait<Object?>([_receiptLogo(), _menuImages()]);
    final logo = results[0] as _LogoLookup;
    final menu = results[1] as List<StorefrontMenuImageOption>?;
    return StorefrontSourceOptions(
      receiptLogoKey: logo.key,
      receiptLogoUnavailable: logo.unavailable,
      menuImages: menu ?? const <StorefrontMenuImageOption>[],
      menuImagesUnavailable: menu == null,
    );
  }

  Future<_LogoLookup> _receiptLogo() async {
    final repo = logoRepository;
    if (repo == null) return const _LogoLookup(null, unavailable: true);
    try {
      final settings = await repo.read();
      if (settings == null) return const _LogoLookup(null, unavailable: true);
      // The CURRENT logo is a source whether or not it prints on receipts.
      return _LogoLookup(settings.hasLogo ? settings.path : null);
    } catch (_) {
      return const _LogoLookup(null, unavailable: true);
    }
  }

  Future<List<StorefrontMenuImageOption>?> _menuImages() async {
    final source = menuReadSource;
    final scope = menuScope;
    if (source == null || scope == null) return null;
    try {
      final snapshot = await source.load(scope);
      final seen = <String>{};
      final out = <StorefrontMenuImageOption>[];
      for (final item in snapshot.items) {
        final key = item.imagePath;
        if (item.isDeleted || key == null || key.isEmpty) continue;
        if (!seen.add(key)) continue;
        out.add(
          StorefrontMenuImageOption(
            itemId: item.id,
            itemName: item.name,
            imageKey: key,
          ),
        );
      }
      out.sort((a, b) => a.itemName.compareTo(b.itemName));
      return List.unmodifiable(out);
    } catch (_) {
      return null;
    }
  }
}

class _LogoLookup {
  const _LogoLookup(this.key, {this.unavailable = false});

  final String? key;
  final bool unavailable;
}
